local Matrix = {}

Matrix.DEFAULT_HOMESERVER = "https://opus.quadigen.com/_matrix/static/"
Matrix.DEVICE_NAME = "Studio"

local STAGE_NAMES = {
	["m.login.recaptcha"] = "a captcha",
	["m.login.email.identity"] = "email verification",
	["m.login.msisdn"] = "phone verification",
	["m.login.sso"] = "single sign-on",
	["m.login.terms"] = "accepting terms of service",
	["m.login.registration_token"] = "a registration token",
	["org.matrix.msc3231.login.registration_token"] = "a registration token",
}

local TOKEN_STAGES = {
	["m.login.registration_token"] = true,
	["org.matrix.msc3231.login.registration_token"] = true,
}

local http: any = game:GetService("HttpService")

local function trim(text: any): string
	return (tostring(text or ""):match("^%s*(.-)%s*$")) :: string
end

local function urlEncode(text: string): string
	return (text:gsub("[^%w%-_%.~]", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end

function Matrix.normalizeHomeserver(input: any): string
	local url = trim(input)

	if url == "" then
		url = Matrix.DEFAULT_HOMESERVER
	end

	if not url:find("^%a[%w+.-]*://") then
		url = "https://" .. url
	end

	local matrixAt = url:find("/_matrix", 1, true)

	if matrixAt then
		url = url:sub(1, matrixAt - 1)
	end

	return (url:gsub("/+$", ""))
end

function Matrix.normalizeUsername(input: any): string
	local name = trim(input):lower()

	name = name:gsub("^@", "")
	name = name:gsub(":.*$", "")

	return name
end

function Matrix.describeError(status: number, data: any): string
	if type(data) == "table" then
		local code, message = data.errcode, data.error

		if code == "M_LIMIT_EXCEEDED" then
			local seconds = math.ceil((tonumber(data.retry_after_ms) or 2000) / 1000)
			return `Too many attempts. Try again in {seconds}s.`
		elseif code == "M_USER_IN_USE" then
			return "That username is already taken."
		elseif code == "M_INVALID_USERNAME" then
			return message or "That username is not valid."
		elseif code == "M_WEAK_PASSWORD" then
			return message or "That password is too weak."
		elseif code == "M_FORBIDDEN" then
			return message or "Forbidden (wrong credentials, or registration is disabled)."
		elseif code == "M_USER_DEACTIVATED" then
			return "This account has been deactivated."
		elseif code == "M_EXCLUSIVE" then
			return "That username is reserved."
		elseif message then
			return message
		end
	end

	return `Request failed (HTTP {status}).`
end

export type Result = {
	ok: boolean,
	status: number,
	data: any?,
	error: string?,
}

function Matrix.request(base: string, method: string, path: string, body: any?, token: string?): Result
	local headers: { [string]: string } = { ["Accept"] = "application/json" }
	local encoded = nil

	if body ~= nil then
		headers["Content-Type"] = "application/json"
		encoded = http:JSONEncode(body)
	end

	if token then
		headers["Authorization"] = "Bearer " .. token
	end

	local ok, response = pcall(function()
		return http:RequestAsync({
			Url = base .. path,
			Method = method,
			Headers = headers,
			Body = encoded,
		})
	end)

	if not ok then
		return { ok = false, status = 0, error = "Network error: " .. tostring(response) }
	end

	local data = nil

	if response.Body and response.Body ~= "" then
		local decodedOk, decoded = pcall(function()
			return http:JSONDecode(response.Body)
		end)

		if decodedOk then
			data = decoded
		end
	end

	local status = response.StatusCode or 0
	local success = status >= 200 and status < 300

	return {
		ok = success,
		status = status,
		data = data,
		error = (not success) and Matrix.describeError(status, data) or nil,
	}
end

local function speaksMatrix(base: string): boolean
	local result = Matrix.request(base, "GET", "/_matrix/client/versions")

	return result.ok and type(result.data) == "table" and result.data.versions ~= nil
end

function Matrix.resolveHomeserver(input: any): (boolean, string)
	local base = Matrix.normalizeHomeserver(input)

	if speaksMatrix(base) then
		return true, base
	end

	local wellKnown = Matrix.request(base, "GET", "/.well-known/matrix/client")

	if wellKnown.ok and type(wellKnown.data) == "table" then
		local hs = wellKnown.data["m.homeserver"]
		local delegated = type(hs) == "table" and hs.base_url

		if type(delegated) == "string" then
			delegated = Matrix.normalizeHomeserver(delegated)

			if speaksMatrix(delegated) then
				return true, delegated
			end
		end
	end

	return false, "Could not find a Matrix homeserver at " .. base
end

export type Session = {
	homeserver: string,
	userId: string,
	accessToken: string,
	deviceId: string?,
}

local currentSession: Session? = nil
local listeners: { (Session?) -> () } = {}

local function sessionFrom(base: string, data: any): Session?
	if type(data) ~= "table" or not data.access_token then
		return nil
	end

	return {
		homeserver = base,
		userId = data.user_id,
		accessToken = data.access_token,
		deviceId = data.device_id,
	}
end

function Matrix.getSession(): Session?
	return currentSession
end

function Matrix.setSession(session: Session?)
	currentSession = session

	for _, listener in ipairs(table.clone(listeners)) do
		task.spawn(listener, session)
	end
end

function Matrix.onSessionChanged(listener: (Session?) -> ()): () -> ()
	table.insert(listeners, listener)

	return function()
		local index = table.find(listeners, listener)

		if index then
			table.remove(listeners, index)
		end
	end
end

function Matrix.login(base: string, username: string, password: string): (boolean, any)
	local result = Matrix.request(base, "POST", "/_matrix/client/v3/login", {
		type = "m.login.password",
		identifier = { type = "m.id.user", user = username },
		password = password,
		initial_device_display_name = Matrix.DEVICE_NAME,
	})

	if not result.ok then
		return false, result.error
	end

	local session = sessionFrom(base, result.data)

	if not session then
		return false, "The server returned no access token."
	end

	return true, session
end

function Matrix.logout(session: Session?): (boolean, string?)
	session = session or currentSession

	if not session then
		return false, "Not logged in."
	end

	local result = Matrix.request(session.homeserver, "POST", "/_matrix/client/v3/logout", {}, session.accessToken)

	if result.ok or result.status == 401 then
		if session == currentSession then
			Matrix.setSession(nil)
		end

		return true, nil
	end

	return false, result.error
end

function Matrix.whoami(session: Session?): (boolean, any)
	session = session or currentSession

	if not session then
		return false, "Not logged in."
	end

	local result =
		Matrix.request(session.homeserver, "GET", "/_matrix/client/v3/account/whoami", nil, session.accessToken)

	if not result.ok then
		return false, result.error
	end

	return true, result.data
end

function Matrix.checkUsername(base: string, username: string): (boolean, string?)
	local result = Matrix.request(base, "GET", "/_matrix/client/v3/register/available?username=" .. urlEncode(username))

	if result.ok then
		return true, nil
	end

	return false, result.error
end

export type RegisterOptions = {
	registrationToken: string?,
}

function Matrix.register(base: string, username: string, password: string, options: RegisterOptions?): (boolean, any)
	local token = trim(options and options.registrationToken)

	local function body(auth: any?)
		return {
			username = username,
			password = password,
			initial_device_display_name = Matrix.DEVICE_NAME,
			auth = auth,
		}
	end

	local path = "/_matrix/client/v3/register?kind=user"

	local result = Matrix.request(base, "POST", path, body(nil))

	if not result.ok then
		local data = result.data

		if result.status ~= 401 or type(data) ~= "table" or type(data.flows) ~= "table" then
			return false, result.error
		end

		local sessionId = data.session

		local supported: { [string]: boolean } = { ["m.login.dummy"] = true }

		if token ~= "" then
			for stage in pairs(TOKEN_STAGES) do
				supported[stage] = true
			end
		end

		local chosen: { string }? = nil

		for _, flow in ipairs(data.flows) do
			local usable = true

			for _, stage in ipairs(flow.stages or {}) do
				if not supported[stage] then
					usable = false
					break
				end
			end

			if usable then
				chosen = flow.stages
				break
			end
		end

		if not chosen then
			local needs = {}
			local firstFlow = data.flows[1]

			for _, stage in ipairs(firstFlow and firstFlow.stages or {}) do
				if not supported[stage] then
					table.insert(needs, STAGE_NAMES[stage] or stage)
				end
			end

			if #needs == 0 then
				return false, "This server's sign-up requirements are not supported."
			end

			return false, "This server requires " .. table.concat(needs, ", ") .. " to sign up."
		end

		for _, stage in ipairs(chosen) do
			local auth: any = { type = stage, session = sessionId }

			if TOKEN_STAGES[stage] then
				auth.token = token
			end

			result = Matrix.request(base, "POST", path, body(auth))

			if result.ok then
				break
			end

			local data2 = result.data
			local interim = result.status == 401 and type(data2) == "table" and data2.errcode == nil

			if not interim then
				return false, result.error
			end
		end

		if not result.ok then
			return false, "Registration did not complete."
		end
	end

	local session = sessionFrom(base, result.data)

	if not session then
		return false, "Account created, but the server returned no access token. Try logging in."
	end

	return true, session
end

local function enc(value: any): string
	return urlEncode(tostring(value))
end

local function query(params: { [string]: any }): string
	local keys = {}

	for key, value in pairs(params) do
		if value ~= nil then
			table.insert(keys, key)
		end
	end

	if #keys == 0 then
		return ""
	end

	table.sort(keys)

	local parts = {}

	for _, key in ipairs(keys) do
		local value = params[key]

		if type(value) == "boolean" then
			value = value and "true" or "false"
		end

		table.insert(parts, urlEncode(key) .. "=" .. urlEncode(tostring(value)))
	end

	return "?" .. table.concat(parts, "&")
end

local function authed(session: Session?, method: string, path: string, body: any?): Result
	session = session or currentSession

	if not session then
		return { ok = false, status = 0, error = "Not logged in." }
	end

	local result = Matrix.request(session.homeserver, method, path, body, session.accessToken)

	if result.status == 401 and type(result.data) == "table" and result.data.errcode == "M_UNKNOWN_TOKEN" then
		result.error = "Your session has expired. Please log in again."

		if session == currentSession then
			Matrix.setSession(nil)
		end
	end

	return result
end

Matrix.authedRequest = authed

local txnCounter = 0

function Matrix.newTxnId(): string
	txnCounter += 1

	return `studio-{http:GenerateGUID(false)}-{txnCounter}`
end

export type Message = {
	eventId: string?,
	sender: string?,
	type: string?,
	msgtype: string?,
	body: string?,
	timestampMs: number,
	timestamp: number,
	stateKey: string?,
	content: any,
	raw: any,
}

function Matrix.parseEvent(event: any): Message
	local content = type(event.content) == "table" and event.content or {}
	local ms = tonumber(event.origin_server_ts) or 0

	return {
		eventId = event.event_id,
		sender = event.sender,
		type = event.type,
		msgtype = content.msgtype,
		body = content.body,
		timestampMs = ms,
		timestamp = ms / 1000,
		stateKey = event.state_key,
		content = content,
		raw = event,
	}
end

function Matrix.mxcToHttp(base: string, mxc: string?, options: any?): string?
	if type(mxc) ~= "string" then
		return nil
	end

	local server, mediaId = mxc:match("^mxc://([^/]+)/([^/?#]+)")

	if not server then
		return nil
	end

	options = options or {}

	local prefix = options.authenticated and "/_matrix/client/v1/media" or "/_matrix/media/v3"

	if options.width or options.height then
		return base
			.. `{prefix}/thumbnail/{server}/{mediaId}`
			.. query({ width = options.width or 64, height = options.height or 64, method = options.method or "crop" })
	end

	return base .. `{prefix}/download/{server}/{mediaId}`
end

function Matrix.getJoinedRooms(session: Session?): (boolean, any)
	local result = authed(session, "GET", "/_matrix/client/v3/joined_rooms")

	if not result.ok then
		return false, result.error
	end

	return true, (type(result.data) == "table" and result.data.joined_rooms) or {}
end

function Matrix.sync(session: Session?, options: any?): (boolean, any, number?)
	options = options or {}

	local filter = options.filter

	if type(filter) == "table" then
		filter = http:JSONEncode(filter)
	end

	local result = authed(session, "GET", "/_matrix/client/v3/sync" .. query({
		since = options.since,
		timeout = options.timeout,
		filter = filter,
		full_state = options.fullState,
		set_presence = options.setPresence,
	}))

	if not result.ok then
		return false, result.error, result.status
	end

	return true, result.data, result.status
end

local ROOM_LIST_FILTER = {
	presence = { not_types = { "*" } },
	account_data = { types = { "m.direct" } },
	room = {
		timeline = { limit = 1 },
		ephemeral = { not_types = { "*" } },
		account_data = { not_types = { "*" } },
		state = {
			lazy_load_members = true,
			types = { "m.room.name", "m.room.topic", "m.room.canonical_alias", "m.room.avatar", "m.room.create" },
		},
	},
}

local LIVE_FILTER = {
	presence = { not_types = { "*" } },
	room = {
		timeline = { limit = 20 },
		account_data = { not_types = { "*" } },
		state = { lazy_load_members = true },
	},
}

export type RoomInfo = {
	roomId: string,
	membership: string,
	displayName: string,
	name: string?,
	topic: string?,
	alias: string?,
	avatarUrl: string?,
	roomType: string?,
	heroes: { string },
	memberCount: number?,
	unread: number,
	highlights: number,
	lastMessage: Message?,
	isDirect: boolean,
	directUserId: string?,
	invitedBy: string?,
}

local function newRoomInfo(roomId: string, membership: string): any
	return {
		roomId = roomId,
		membership = membership,
		displayName = roomId,
		heroes = {},
		unread = 0,
		highlights = 0,
		isDirect = false,
	}
end

local function applyStateEvents(info: any, events: any, selfId: string?)
	for _, event in ipairs(events or {}) do
		local content = type(event.content) == "table" and event.content or nil

		if content and event.state_key ~= nil then
			local kind = event.type

			if kind == "m.room.name" and event.state_key == "" then
				info.name = (content.name ~= "" and content.name) or nil
			elseif kind == "m.room.topic" and event.state_key == "" then
				info.topic = (content.topic ~= "" and content.topic) or nil
			elseif kind == "m.room.canonical_alias" and event.state_key == "" then
				info.alias = content.alias
			elseif kind == "m.room.avatar" and event.state_key == "" then
				info.avatarUrl = content.url
			elseif kind == "m.room.create" then
				info.roomType = content.type
			elseif
				kind == "m.room.member"
				and selfId
				and event.state_key == selfId
				and content.membership == "invite"
			then
				info.invitedBy = event.sender
			end
		end
	end
end

local function finishRoomInfo(info: any, direct: { [string]: string })
	info.directUserId = direct[info.roomId]
	info.isDirect = info.directUserId ~= nil

	if info.name then
		info.displayName = info.name
	elseif info.alias then
		info.displayName = info.alias
	elseif info.isDirect then
		info.displayName = info.directUserId
	elseif #info.heroes > 0 then
		info.displayName = table.concat(info.heroes, ", ")
	elseif info.invitedBy then
		info.displayName = `Invite from {info.invitedBy}`
	end
end

function Matrix.summarizeSync(data: any, selfId: string?): { RoomInfo }
	local rooms = {}
	local direct: { [string]: string } = {}

	local accountEvents = type(data.account_data) == "table" and data.account_data.events or {}

	for _, event in ipairs(accountEvents) do
		if event.type == "m.direct" and type(event.content) == "table" then
			for userId, roomIds in pairs(event.content) do
				if type(roomIds) == "table" then
					for _, roomId in ipairs(roomIds) do
						direct[roomId] = userId
					end
				end
			end
		end
	end

	local roomsData = type(data.rooms) == "table" and data.rooms or {}

	for roomId, room in pairs(roomsData.join or {}) do
		local info = newRoomInfo(roomId, "join")
		local timeline = type(room.timeline) == "table" and room.timeline.events or {}

		applyStateEvents(info, type(room.state) == "table" and room.state.events or {}, selfId)
		applyStateEvents(info, timeline, selfId)

		for index = #timeline, 1, -1 do
			if timeline[index].type == "m.room.message" then
				info.lastMessage = Matrix.parseEvent(timeline[index])
				break
			end
		end

		local summary = type(room.summary) == "table" and room.summary or {}

		info.heroes = summary["m.heroes"] or {}
		info.memberCount = summary["m.joined_member_count"]

		local unread = type(room.unread_notifications) == "table" and room.unread_notifications or {}

		info.unread = unread.notification_count or 0
		info.highlights = unread.highlight_count or 0

		finishRoomInfo(info, direct)
		table.insert(rooms, info)
	end

	for roomId, room in pairs(roomsData.invite or {}) do
		local info = newRoomInfo(roomId, "invite")

		applyStateEvents(info, type(room.invite_state) == "table" and room.invite_state.events or {}, selfId)

		finishRoomInfo(info, direct)
		table.insert(rooms, info)
	end

	table.sort(rooms, function(a, b)
		local aInvite, bInvite = a.membership == "invite", b.membership == "invite"

		if aInvite ~= bInvite then
			return aInvite
		end

		local aTime = a.lastMessage and a.lastMessage.timestampMs or 0
		local bTime = b.lastMessage and b.lastMessage.timestampMs or 0

		if aTime ~= bTime then
			return aTime > bTime
		end

		return a.displayName:lower() < b.displayName:lower()
	end)

	return rooms
end

function Matrix.getRooms(session: Session?): (boolean, any, string?)
	session = session or currentSession

	if not session then
		return false, "Not logged in."
	end

	local ok, data = Matrix.sync(session, { filter = ROOM_LIST_FILTER, timeout = 0 })

	if not ok then
		return false, data
	end

	return true, Matrix.summarizeSync(data, session.userId), data.next_batch
end

function Matrix.getRoomState(session: Session?, roomId: string, eventType: string, stateKey: string?): (boolean, any)
	local path = `/_matrix/client/v3/rooms/{enc(roomId)}/state/{enc(eventType)}`

	if stateKey and stateKey ~= "" then
		path ..= "/" .. enc(stateKey)
	end

	local result = authed(session, "GET", path)

	if not result.ok then
		return false, result.error
	end

	return true, result.data
end

function Matrix.getRoomInfo(session: Session?, roomId: string): (boolean, any)
	local info = { roomId = roomId }

	local function fetch(eventType: string, field: string, target: string)
		local ok, content = Matrix.getRoomState(session, roomId, eventType)

		if ok and type(content) == "table" then
			info[target] = content[field]
		end
	end

	fetch("m.room.name", "name", "name")
	fetch("m.room.topic", "topic", "topic")
	fetch("m.room.canonical_alias", "alias", "alias")
	fetch("m.room.avatar", "url", "avatarUrl")

	info.displayName = info.name or info.alias or roomId

	return true, info
end

export type Member = {
	userId: string,
	displayName: string,
	avatarUrl: string?,
}

function Matrix.getMembers(session: Session?, roomId: string): (boolean, any)
	local result = authed(session, "GET", `/_matrix/client/v3/rooms/{enc(roomId)}/joined_members`)

	if not result.ok then
		return false, result.error
	end

	local members = {}
	local joined = type(result.data) == "table" and result.data.joined or {}

	for userId, info in pairs(joined) do
		table.insert(members, {
			userId = userId,
			displayName = (type(info) == "table" and info.display_name) or userId,
			avatarUrl = type(info) == "table" and info.avatar_url or nil,
		})
	end

	table.sort(members, function(a, b)
		return a.displayName:lower() < b.displayName:lower()
	end)

	return true, members
end

function Matrix.getMessages(session: Session?, roomId: string, options: any?): (boolean, any)
	options = options or {}

	local dir = options.dir or "b"

	local result = authed(session, "GET", `/_matrix/client/v3/rooms/{enc(roomId)}/messages` .. query({
		dir = dir,
		limit = options.limit or 50,
		from = options.from,
		filter = http:JSONEncode({ types = options.types or { "m.room.message" } }),
	}))

	if not result.ok then
		return false, result.error
	end

	local data = type(result.data) == "table" and result.data or {}
	local messages = {}

	for _, event in ipairs(data.chunk or {}) do
		table.insert(messages, Matrix.parseEvent(event))
	end

	if dir == "b" then
		local count = #messages

		for index = 1, math.floor(count / 2) do
			messages[index], messages[count - index + 1] = messages[count - index + 1], messages[index]
		end
	end

	return true, { messages = messages, nextToken = data["end"], startToken = data.start }
end

function Matrix.sendMessage(session: Session?, roomId: string, text: string, options: any?): (boolean, any)
	options = options or {}

	local content: any = {
		msgtype = options.msgtype or "m.text",
		body = tostring(text),
	}

	if options.replyTo then
		content["m.relates_to"] = { ["m.in_reply_to"] = { event_id = options.replyTo } }
	end

	local result = authed(
		session,
		"PUT",
		`/_matrix/client/v3/rooms/{enc(roomId)}/send/m.room.message/{enc(Matrix.newTxnId())}`,
		content
	)

	if not result.ok then
		return false, result.error
	end

	return true, type(result.data) == "table" and result.data.event_id or nil
end

function Matrix.markRead(session: Session?, roomId: string, eventId: string): (boolean, string?)
	local result = authed(session, "POST", `/_matrix/client/v3/rooms/{enc(roomId)}/receipt/m.read/{enc(eventId)}`, {})

	return result.ok, result.error
end

function Matrix.setTyping(session: Session?, roomId: string, typing: boolean, timeoutMs: number?): (boolean, string?)
	session = session or currentSession

	if not session then
		return false, "Not logged in."
	end

	local body: any = { typing = typing }

	if typing then
		body.timeout = timeoutMs or 30000
	end

	local result = authed(session, "PUT", `/_matrix/client/v3/rooms/{enc(roomId)}/typing/{enc(session.userId)}`, body)

	return result.ok, result.error
end

function Matrix.joinRoom(session: Session?, roomIdOrAlias: string): (boolean, any)
	local result = authed(session, "POST", `/_matrix/client/v3/join/{enc(roomIdOrAlias)}`, {})

	if not result.ok then
		return false, result.error
	end

	return true, type(result.data) == "table" and result.data.room_id or roomIdOrAlias
end

function Matrix.leaveRoom(session: Session?, roomId: string): (boolean, string?)
	local result = authed(session, "POST", `/_matrix/client/v3/rooms/{enc(roomId)}/leave`, {})

	return result.ok, result.error
end

function Matrix.forgetRoom(session: Session?, roomId: string): (boolean, string?)
	local result = authed(session, "POST", `/_matrix/client/v3/rooms/{enc(roomId)}/forget`, {})

	return result.ok, result.error
end

function Matrix.inviteUser(session: Session?, roomId: string, userId: string): (boolean, string?)
	local result = authed(session, "POST", `/_matrix/client/v3/rooms/{enc(roomId)}/invite`, { user_id = userId })

	return result.ok, result.error
end

function Matrix.createRoom(session: Session?, options: any?): (boolean, any)
	options = options or {}

	local body: any = {
		name = options.name,
		topic = options.topic,
		visibility = options.isPublic and "public" or "private",
		preset = options.preset or (options.isPublic and "public_chat" or "private_chat"),
		room_alias_name = options.alias,
		is_direct = options.isDirect,
	}

	if options.invite and #options.invite > 0 then
		body.invite = options.invite
	end

	local result = authed(session, "POST", "/_matrix/client/v3/createRoom", body)

	if not result.ok then
		return false, result.error
	end

	return true, type(result.data) == "table" and result.data.room_id or nil
end

function Matrix.createDirectRoom(session: Session?, userId: string): (boolean, any)
	session = session or currentSession

	if not session then
		return false, "Not logged in."
	end

	local ok, roomId = Matrix.createRoom(session, {
		invite = { userId },
		isDirect = true,
		preset = "trusted_private_chat",
	})

	if not ok then
		return false, roomId
	end

	local path = `/_matrix/client/v3/user/{enc(session.userId)}/account_data/m.direct`
	local existing = authed(session, "GET", path)
	local direct = (existing.ok and type(existing.data) == "table") and existing.data or {}

	local list = direct[userId]

	if type(list) ~= "table" then
		list = {}
	end

	table.insert(list, roomId)
	direct[userId] = list

	authed(session, "PUT", path, direct)

	return true, roomId
end

function Matrix.getProfile(session: Session?, userId: string?): (boolean, any)
	session = session or currentSession

	if not session then
		return false, "Not logged in."
	end

	local result = authed(session, "GET", `/_matrix/client/v3/profile/{enc(userId or session.userId)}`)

	if not result.ok then
		return false, result.error
	end

	local data = type(result.data) == "table" and result.data or {}

	return true, { displayName = data.displayname, avatarUrl = data.avatar_url }
end

function Matrix.setDisplayName(session: Session?, name: string): (boolean, string?)
	session = session or currentSession

	if not session then
		return false, "Not logged in."
	end

	local result =
		authed(session, "PUT", `/_matrix/client/v3/profile/{enc(session.userId)}/displayname`, { displayname = name })

	return result.ok, result.error
end

local function fire(handlers: any, name: string, ...)
	local handler = handlers[name]

	if not handler then
		return
	end

	local ok, err = pcall(handler, ...)

	if not ok and name ~= "onError" and handlers.onError then
		pcall(handlers.onError, `{name} handler failed: {tostring(err)}`)
	end
end

function Matrix.startSync(session: Session?, handlers: any?): () -> ()
	session = session or currentSession
	handlers = handlers or {}

	local running = true

	local function stop()
		running = false
	end

	if not session then
		fire(handlers, "onError", "Not logged in.")

		return stop
	end

	local activeSession: Session = session
	local since: string? = handlers.since

	task.spawn(function()
		local failures = 0

		while running do
			local isFirst = since == nil

			local ok, data, status = Matrix.sync(activeSession, {
				since = since,
				timeout = isFirst and 0 or (handlers.timeout or 10000),
				filter = handlers.filter or (isFirst and ROOM_LIST_FILTER or LIVE_FILTER),
			})

			if not running then
				break
			end

			if not ok then
				failures += 1

				fire(handlers, "onError", data)

				if status == 401 or status == 403 then
					running = false
					break
				end

				task.wait(math.min(2 ^ failures, 30))
			else
				failures = 0
				since = data.next_batch

				local roomsData = type(data.rooms) == "table" and data.rooms or {}
				local deliver = (not isFirst) or handlers.includeInitial == true

				for roomId, room in pairs(roomsData.join or {}) do
					if deliver then
						local timeline = type(room.timeline) == "table" and room.timeline.events or {}

						for _, event in ipairs(timeline) do
							local parsed = Matrix.parseEvent(event)

							fire(handlers, "onEvent", roomId, parsed)

							if event.type == "m.room.message" then
								fire(handlers, "onMessage", roomId, parsed)
							end
						end
					end

					local ephemeral = type(room.ephemeral) == "table" and room.ephemeral.events or {}

					for _, event in ipairs(ephemeral) do
						if event.type == "m.typing" and type(event.content) == "table" then
							fire(handlers, "onTyping", roomId, event.content.user_ids or {})
						end
					end
				end

				for roomId, room in pairs(roomsData.invite or {}) do
					local info = newRoomInfo(roomId, "invite")

					applyStateEvents(
						info,
						type(room.invite_state) == "table" and room.invite_state.events or {},
						activeSession.userId
					)
					finishRoomInfo(info, {})

					fire(handlers, "onInvite", roomId, info)
				end

				fire(handlers, "onSync", data)
			end
		end
	end)

	return stop
end

return Matrix

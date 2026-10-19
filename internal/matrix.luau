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

local cachedHttp: any = nil

local function getHttpService(): any
	if cachedHttp then
		return cachedHttp
	end

	for _, name in ipairs({ "HTTPService", "HttpService" }) do
		local ok, service = pcall(function()
			return game:GetService(name)
		end)

		if ok and service then
			cachedHttp = service
			return service
		end
	end

	return nil
end

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
	local http = getHttpService()

	if not http then
		return { ok = false, status = 0, error = "HttpService is not available." }
	end

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

return Matrix

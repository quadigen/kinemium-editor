local UI = require("@internal/editor_ui")
local MatrixService = game:GetService("MatrixService")
local SpaceService = game:GetService("SpaceService")
local http = game:GetService("HttpService")

local tokens = UI.tokens

local D = {
	rail = Color3.fromRGB(30, 31, 34),
	sidebar = Color3.fromRGB(43, 45, 49),
	userPanel = Color3.fromRGB(35, 36, 40),
	chat = Color3.fromRGB(49, 51, 56),
	input = Color3.fromRGB(56, 58, 64),
	hover = Color3.fromRGB(53, 55, 60),
	rowHover = Color3.fromRGB(46, 48, 54),
	selected = Color3.fromRGB(64, 66, 73),
	pressed = Color3.fromRGB(70, 72, 78),
	divider = Color3.fromRGB(63, 65, 71),
	text = Color3.fromRGB(219, 222, 225),
	bright = Color3.fromRGB(242, 243, 245),
	muted = Color3.fromRGB(148, 155, 164),
	blurple = Color3.fromRGB(88, 101, 242),
	red = Color3.fromRGB(242, 63, 66),
	green = Color3.fromRGB(35, 165, 89),
}

local AVATAR_COLORS = {
	D.blurple,
	D.green,
	Color3.fromRGB(240, 178, 50),
	Color3.fromRGB(235, 69, 158),
	Color3.fromRGB(237, 66, 69),
	Color3.fromRGB(26, 188, 156),
	Color3.fromRGB(155, 89, 182),
}

local RAIL = 64
local SIDEBAR = 232
local MEMBERS = 204
local HEADER = 48
local PANEL = 52
local COMPOSER = 44
local INFO = 20
local AVATAR = 36
local BODY_X = 64
local HISTORY_LIMIT = 50
local GROUP_SECONDS = 420

local function trim(text)
	return string.match(text or "", "^%s*(.-)%s*$")
end

local function localpart(userId)
	if not userId then
		return "unknown"
	end
	return string.match(userId, "^@([^:]+)") or userId
end

local function hash(text)
	local h = 0
	for i = 1, #text do
		h = (h * 31 + string.byte(text, i)) % 2147483647
	end
	return h
end

local function colorFor(seed)
	return AVATAR_COLORS[(hash(tostring(seed)) % #AVATAR_COLORS) + 1]
end

local function firstChar(text)
	local stripped = string.gsub(tostring(text or "?"), "^[#@!]+", "")
	local ch = string.match(stripped, "^[%z\1-\127\194-\244][\128-\191]*")
	return string.upper(ch or "?")
end

local function urlEncode(text)
	return (string.gsub(text, "[^%w%-_%.~]", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end

local function messageText(ev)
	local body = ev.body or ""
	local kind = ev.msgtype

	if kind and kind ~= "m.text" and kind ~= "m.notice" and kind ~= "m.emote" then
		return "[" .. string.gsub(kind, "^m%.", "") .. "] " .. body
	end

	return body
end

local function estimateHeight(text, width)
	local charsPerLine = math.max(8, math.floor(width / 7.2))
	local lines = 0

	for line in string.gmatch(text .. "\n", "(.-)\n") do
		lines += math.max(1, math.ceil(#line / charsPerLine))
	end

	return lines * 18
end

local function dayKey(ts)
	local d = os.date("*t", ts)
	return d.year * 1000 + d.yday
end

local function stamp(ts)
	local now = os.time()
	local clock = os.date("%H:%M", ts)

	if dayKey(ts) == dayKey(now) then
		return "Today at " .. clock
	elseif dayKey(ts) == dayKey(now - 86400) then
		return "Yesterday at " .. clock
	end

	return os.date("%m/%d/%Y", ts)
end

local function newScroller(parent, name, position, size, thickness)
	return UI.create("ScrollingFrame", {
		Name = name,
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ScrollBarThickness = thickness or 5,
		ScrollBarImageColor3 = D.muted,
		ScrollBarImageTransparency = 0.5,
		ScrollBarAutoHide = true,
		ClipsDescendants = true,
	}, parent)
end

local Messaging = {}

function Messaging.new(session, options)
	assert(session, "Messaging.new requires a Matrix session")
	options = options or {}

	local self = {}

	local rooms = {}
	local messages = {}
	local historyToken = {}
	local roomMembers = {}
	local profiles = {}
	local typing = {}
	local spaceChildren = {}
	local emojiCache = {}
	local imageCache = {}
	local imageWaiting = {}

	local current = nil
	local activeSpace = nil
	local started, destroyed = false, false
	local membersOpen = false
	local emojiOpen = false
	local loadingOlder = false
	local lastTypingSent = 0
	local statusText, statusIsError = nil, false
	local renderQueued = false
	local stopSync = nil

	local renderRail, renderSidebar, renderSidebarHeader, renderMessages, renderMembers, renderUserPanel
	local selectRoom, acceptInvite, refreshRooms, updateInfo

	local screen = workspace:GetWindowDimensions()
	local screenWidth = screen and screen.X or 1100
	local screenHeight = screen and screen.Y or 760
	local width = math.clamp(screenWidth - 80, 820, 1100)
	local height = math.clamp(screenHeight - 80, 520, 700)

	membersOpen = width >= 960

	local panel, page = UI.window(
		"MatrixMessaging",
		UDim2.fromOffset(
			math.max(0, math.floor((screenWidth - width) / 2)),
			math.max(0, math.floor((screenHeight - height) / 2))
		),
		UDim2.fromOffset(width, height),
		"Messages",
		{
			closable = true,
			headerColor = D.rail,
			contentColor = D.chat,
			titleColor = D.muted,
			borderColor = D.rail,
			onClose = function(window)
				window.Visible = false
			end,
		}
	)

	panel.Parent = UI.widgetOverlay()
	panel.Visible = false

	local rail = UI.frame(page, UDim2.fromOffset(0, 0), UDim2.new(0, RAIL, 1, 0), D.rail)
	local sidebar = UI.frame(page, UDim2.fromOffset(RAIL, 0), UDim2.new(0, SIDEBAR, 1, 0), D.sidebar)
	local chat = UI.frame(page, UDim2.fromOffset(RAIL + SIDEBAR, 0), UDim2.new(1, -(RAIL + SIDEBAR), 1, 0), D.chat)
	local membersPanel = UI.frame(page, UDim2.new(1, -MEMBERS, 0, 0), UDim2.new(0, MEMBERS, 1, 0), D.sidebar)
	chat.ClipsDescendants = true

	local railList = newScroller(rail, "Rail", UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), 0)

	local sidebarHeader = UI.frame(sidebar, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, HEADER), D.sidebar)
	UI.separator(sidebarHeader, UDim2.new(0, 0, 1, -1), UDim2.new(1, 0, 0, 1), D.rail)

	local searchInput = UI.input(
		sidebarHeader,
		"Find or start a conversation",
		UDim2.fromOffset(8, 10),
		UDim2.new(1, -16, 0, 28),
		{ color = D.rail, borderColor = D.rail, textSize = tokens.type.small, textColor = D.text }
	)

	local spaceTitle = UI.label(sidebarHeader, "", UDim2.fromOffset(14, 0), UDim2.new(1, -28, 1, 0), 15, D.bright)
	spaceTitle.Visible = false

	local roomList =
		newScroller(sidebar, "RoomList", UDim2.fromOffset(0, HEADER), UDim2.new(1, 0, 1, -(HEADER + PANEL)), 5)

	local userPanel = UI.frame(sidebar, UDim2.new(0, 0, 1, -PANEL), UDim2.new(1, 0, 0, PANEL), D.userPanel)

	local chatHeader = UI.frame(chat, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, HEADER), D.chat)
	UI.separator(chatHeader, UDim2.new(0, 0, 1, -1), UDim2.new(1, 0, 0, 1), D.rail)

	local prefixLabel = UI.label(chatHeader, "#", UDim2.fromOffset(16, 0), UDim2.fromOffset(16, HEADER), 22, D.muted)
	local titleLabel = UI.label(
		chatHeader,
		"Pick a conversation",
		UDim2.fromOffset(34, 0),
		UDim2.fromOffset(240, HEADER),
		15,
		D.bright
	)
	local dividerLine = UI.frame(chatHeader, UDim2.fromOffset(0, 12), UDim2.fromOffset(1, 24), D.divider)
	local topicLabel =
		UI.label(chatHeader, "", UDim2.fromOffset(0, 0), UDim2.fromOffset(300, HEADER), tokens.type.small, D.muted)
	dividerLine.Visible = false

	local membersButton = UI.button(
		chatHeader,
		"Members",
		UDim2.new(1, -(12 + 76), 0.5, -12),
		UDim2.fromOffset(76, 24),
		function() end,
		{
			color = D.chat,
			hoverColor = D.hover,
			pressedColor = D.pressed,
			textColor = D.muted,
			textSize = tokens.type.small,
			radius = 4,
			border = false,
			paddingX = 8,
			textY = 0,
		}
	)

	local scroller = newScroller(
		chat,
		"Messages",
		UDim2.fromOffset(0, HEADER),
		UDim2.new(1, 0, 1, -(HEADER + COMPOSER + INFO + 12)),
		8
	)

	local composer =
		UI.frame(chat, UDim2.new(0, 16, 1, -(INFO + COMPOSER + 2)), UDim2.new(1, -32, 0, COMPOSER), D.input, 8)

	local input = UI.input(
		composer,
		"Message",
		UDim2.fromOffset(14, 8),
		UDim2.new(1, -(14 + 46), 0, 28),
		{ color = D.input, borderColor = D.input, textSize = 14, textColor = D.text }
	)

	local emojiButton = UI.iconButton(
		composer,
		"builtin://icons/Sparkles.svg",
		UDim2.new(1, -40, 0.5, -16),
		UDim2.fromOffset(32, 32),
		function() end,
		{ color = D.input, hoverColor = D.hover, pressedColor = D.pressed, border = false, iconSize = 20, radius = 6 }
	)

	local infoLabel =
		UI.label(chat, "", UDim2.new(0, 18, 1, -INFO), UDim2.new(1, -36, 0, INFO - 2), tokens.type.caption, D.muted)

	local emojiPanel = UI.frame(
		chat,
		UDim2.new(1, -(16 + 320), 1, -(INFO + COMPOSER + 2 + 8 + 180)),
		UDim2.fromOffset(320, 180),
		D.sidebar,
		8
	)
	UI.stroke(emojiPanel, D.rail, 1, 0)
	emojiPanel.Visible = false
	emojiPanel.ZIndex = 5

	local emojiTitle = UI.label(
		emojiPanel,
		"Custom emoji",
		UDim2.fromOffset(12, 6),
		UDim2.new(1, -24, 0, 18),
		tokens.type.caption,
		D.muted
	)
	local emojiList = newScroller(emojiPanel, "Emoji", UDim2.fromOffset(8, 28), UDim2.new(1, -16, 1, -36), 5)

	local membersHeader =
		UI.label(membersPanel, "", UDim2.fromOffset(16, 0), UDim2.new(1, -32, 0, HEADER), tokens.type.caption, D.muted)
	local memberList = newScroller(membersPanel, "Members", UDim2.fromOffset(0, HEADER), UDim2.new(1, 0, 1, -HEADER), 5)

	local function loadImage(mxc, callback)
		if type(mxc) ~= "string" or mxc == "" then
			return
		end

		local cached = imageCache[mxc]

		if cached then
			callback(cached)
			return
		elseif cached == false then
			return
		end

		if imageWaiting[mxc] then
			table.insert(imageWaiting[mxc], callback)
			return
		end

		imageWaiting[mxc] = { callback }

		task.spawn(function()
			local bytes
			pcall(function()
				local url = MatrixService:MxcToHttp(session.homeserver, mxc, {
					authenticated = true,
					width = 64,
					height = 64,
					method = "crop",
				})

				if url then
					bytes = http:GetImageBytes(url, { Authorization = "Bearer " .. session.accessToken })
				end
			end)

			imageCache[mxc] = bytes or false

			local waiting = imageWaiting[mxc]
			imageWaiting[mxc] = nil

			if bytes and not destroyed then
				for _, cb in ipairs(waiting) do
					cb(bytes)
				end
			end
		end)
	end

	local function makeAvatar(parent, seed, label, mxc, position, size)
		local circle = UI.frame(parent, position, UDim2.fromOffset(size, size), colorFor(seed), math.floor(size / 2))

		local initial = UI.label(
			circle,
			firstChar(label),
			UDim2.fromScale(0, 0),
			UDim2.fromScale(1, 1),
			math.max(10, math.floor(size * 0.45)),
			Color3.new(1, 1, 1)
		)
		initial.TextXAlignment = Enum.TextXAlignment.Center

		if mxc and mxc ~= "" then
			loadImage(mxc, function(bytes)
				if UI.isAlive(circle) then
					local image = UI.image(circle, bytes, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1))
					UI.corner(image, math.floor(size / 2))
					initial.Visible = false
				end
			end)
		end

		return circle
	end

	local function scheduleRender()
		if renderQueued then
			return
		end

		renderQueued = true

		task.defer(function()
			renderQueued = false

			if destroyed then
				return
			end

			renderRail()
			renderSidebar()
			renderMessages(false)
			renderMembers()
			renderUserPanel()
		end)
	end

	local function ensureProfile(userId)
		if not userId or profiles[userId] ~= nil then
			return
		end

		profiles[userId] = false

		task.spawn(function()
			local ok, result = MatrixService:GetProfile(session, userId)

			if destroyed then
				return
			end

			profiles[userId] = (ok and type(result) == "table") and result or {}
			scheduleRender()
		end)
	end

	local function profileOf(userId)
		if profiles[userId] == nil then
			ensureProfile(userId)
		end

		return profiles[userId] or nil
	end

	local function displayName(userId)
		local profile = profileOf(userId)

		if profile and profile.displayName and profile.displayName ~= "" then
			return profile.displayName
		end

		return localpart(userId)
	end

	local function roomTitle(room)
		if room.isDirect and room.directUserId then
			return displayName(room.directUserId)
		end

		return room.displayName or room.roomId
	end

	local function roomAvatar(room)
		if room.isDirect and room.directUserId then
			local profile = profileOf(room.directUserId)
			return (profile and profile.avatarUrl) or room.avatarUrl
		end

		return room.avatarUrl
	end

	local function setStatus(text, isError)
		statusText, statusIsError = text, isError == true
		updateInfo()

		task.delay(4, function()
			if statusText == text then
				statusText = nil

				if not destroyed then
					updateInfo()
				end
			end
		end)
	end

	updateInfo = function()
		if statusText then
			infoLabel.Text = statusText
			infoLabel.TextColor3 = statusIsError and D.red or D.muted
			return
		end

		infoLabel.TextColor3 = D.muted

		local who = {}
		for _, userId in ipairs(current and typing[current.roomId] or {}) do
			table.insert(who, displayName(userId))
		end

		if #who == 0 then
			infoLabel.Text = ""
		else
			infoLabel.Text = table.concat(who, ", ") .. (#who == 1 and " is typing..." or " are typing...")
		end
	end

	local function findEvent(list, eventId)
		if not list or not eventId then
			return nil
		end

		for index, ev in ipairs(list) do
			if ev.eventId == eventId then
				return ev, index
			end
		end

		return nil
	end

	local function visible()
		return panel.Visible and not destroyed
	end

	local function inSpace(space, room)
		local set = spaceChildren[space.roomId]
		return set ~= nil and set[room.roomId] == true
	end

	local function inAnySpace(room)
		for _, space in ipairs(rooms) do
			if space.roomType == "m.space" and inSpace(space, room) then
				return true
			end
		end

		return false
	end

	local function unreadFor(filter)
		local total, highlights = 0, 0

		for _, room in ipairs(rooms) do
			if room.roomType ~= "m.space" and room.membership == "join" and filter(room) then
				total += room.unread or 0
				highlights += room.highlights or 0
			end
		end

		return total, highlights
	end

	renderRail = function()
		UI.clear(railList)

		local y = 12

		local function pill(selected, unread, itemY)
			if not selected and unread <= 0 then
				return
			end

			local h = selected and 32 or 8
			UI.frame(railList, UDim2.fromOffset(0, itemY + 24 - h / 2), UDim2.fromOffset(4, h), D.bright, 2)
		end

		local function badge(button, count, highlight)
			if count <= 0 then
				return
			end

			UI.badge(button, count > 99 and "99+" or tostring(count), UDim2.new(1, -20, 1, -16), {
				width = math.max(18, #tostring(count) * 7 + 10),
				height = 16,
				color = highlight and D.red or D.red,
				textColor = Color3.new(1, 1, 1),
			})
		end

		local homeUnread, homeHighlights = unreadFor(function(room)
			return not inAnySpace(room)
		end)

		local home = UI.button(railList, "", UDim2.fromOffset(8, y), UDim2.fromOffset(48, 48), function()
			activeSpace = nil
			renderRail()
			renderSidebarHeader()
			renderSidebar()
		end, {
			color = activeSpace == nil and D.blurple or D.chat,
			hoverColor = D.blurple,
			pressedColor = D.blurple,
			radius = activeSpace == nil and 14 or 24,
			border = false,
		})

		local homeIcon =
			UI.image(home, "builtin://icons/Player.svg", UDim2.fromOffset(12, 12), UDim2.fromOffset(24, 24))
		homeIcon.ImageColor3 = Color3.new(1, 1, 1)

		pill(activeSpace == nil, homeUnread, y)
		badge(home, homeUnread, homeHighlights > 0)
		y += 56

		UI.frame(railList, UDim2.fromOffset(16, y), UDim2.fromOffset(32, 2), D.divider, 1)
		y += 10

		for _, space in ipairs(rooms) do
			if space.roomType == "m.space" and space.membership == "join" then
				local selected = activeSpace ~= nil and activeSpace.roomId == space.roomId
				local unread, highlights = unreadFor(function(room)
					return inSpace(space, room)
				end)

				local button, label = UI.button(
					railList,
					"",
					UDim2.fromOffset(8, y),
					UDim2.fromOffset(48, 48),
					function()
						activeSpace = space
						renderRail()
						renderSidebarHeader()
						renderSidebar()
					end,
					{
						color = colorFor(space.roomId),
						hoverColor = D.blurple,
						pressedColor = D.blurple,
						radius = selected and 14 or 24,
						border = false,
					}
				)

				label.Text = firstChar(roomTitle(space))
				label.Position = UDim2.fromOffset(0, 0)
				label.Size = UDim2.fromScale(1, 1)
				label.TextSize = 20
				label.TextColor3 = Color3.new(1, 1, 1)
				label.TextXAlignment = Enum.TextXAlignment.Center
				label.TextYAlignment = Enum.TextYAlignment.Center

				loadImage(space.avatarUrl, function(bytes)
					if UI.isAlive(button) then
						local image = UI.image(button, bytes, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1))
						UI.corner(image, selected and 14 or 24)
						label.Visible = false
					end
				end)

				pill(selected, unread, y)
				badge(button, unread, highlights > 0)
				y += 56
			end
		end

		railList.CanvasSize = UDim2.new(0, 0, 0, y + 8)
	end

	renderSidebarHeader = function()
		if activeSpace then
			searchInput.Visible = false
			spaceTitle.Visible = true
			spaceTitle.Text = roomTitle(activeSpace)
		else
			searchInput.Visible = true
			spaceTitle.Visible = false
		end
	end

	renderSidebar = function()
		UI.clear(roomList)

		local query = string.lower(trim(searchInput.Text))
		local y = 8

		local function addHeader(text)
			local label = UI.label(roomList, text, UDim2.fromOffset(16, y + 6), UDim2.new(1, -32, 0, 14), 11, D.muted)
			label.TextXAlignment = Enum.TextXAlignment.Left
			y += 26
		end

		local function addRow(room, channelStyle)
			local selected = current ~= nil and current.roomId == room.roomId
			local isInvite = room.membership == "invite"
			local unread = room.unread or 0
			local rowHeight = channelStyle and 32 or 42
			local title = roomTitle(room)

			local text = channelStyle and ("#  " .. title) or title
			if isInvite then
				text ..= "  (invite)"
			end

			local button, label = UI.button(
				roomList,
				text,
				UDim2.fromOffset(8, y),
				UDim2.new(1, -16, 0, rowHeight - 2),
				function()
					if isInvite then
						acceptInvite(room)
					else
						selectRoom(room)
					end
				end,
				{
					color = selected and D.selected or D.sidebar,
					hoverColor = selected and D.selected or D.hover,
					pressedColor = D.pressed,
					textColor = (selected or unread > 0) and D.bright or D.muted,
					textSize = 14,
					radius = 4,
					border = false,
					paddingX = 8,
					textY = 0,
				}
			)

			local labelX = channelStyle and 10 or 48
			label.Position = UDim2.fromOffset(labelX, 0)
			label.Size = UDim2.new(1, -(labelX + (unread > 0 and 38 or 10)), 1, 0)
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextYAlignment = Enum.TextYAlignment.Center

			if not channelStyle then
				makeAvatar(
					button,
					room.directUserId or room.roomId,
					title,
					roomAvatar(room),
					UDim2.fromOffset(8, 3),
					34
				)
			end

			if unread > 0 then
				UI.badge(button, unread > 99 and "99+" or tostring(unread), UDim2.new(1, -34, 0.5, -8), {
					width = 26,
					height = 16,
					color = D.red,
					textColor = Color3.new(1, 1, 1),
				})
			end

			y += rowHeight
		end

		local function matches(room)
			return query == "" or string.find(string.lower(roomTitle(room)), query, 1, true) ~= nil
		end

		if activeSpace then
			local set = spaceChildren[activeSpace.roomId]

			if not set then
				local label = UI.label(
					roomList,
					"Loading channels...",
					UDim2.fromOffset(16, 16),
					UDim2.new(1, -32, 0, 18),
					tokens.type.small,
					D.muted
				)
				label.TextXAlignment = Enum.TextXAlignment.Left
			else
				local channels = {}

				for _, room in ipairs(rooms) do
					if room.roomType ~= "m.space" and set[room.roomId] and room.membership == "join" then
						table.insert(channels, room)
					end
				end

				table.sort(channels, function(a, b)
					return string.lower(roomTitle(a)) < string.lower(roomTitle(b))
				end)

				addHeader("CHANNELS")

				for _, room in ipairs(channels) do
					addRow(room, true)
				end

				if #channels == 0 then
					local label = UI.label(
						roomList,
						"No joined channels in this space.",
						UDim2.fromOffset(16, y),
						UDim2.new(1, -32, 0, 18),
						tokens.type.small,
						D.muted
					)
					label.TextXAlignment = Enum.TextXAlignment.Left
				end
			end
		else
			local invites, directs, others = {}, {}, {}

			for _, room in ipairs(rooms) do
				if room.roomType ~= "m.space" and matches(room) then
					if room.membership == "invite" then
						table.insert(invites, room)
					elseif room.isDirect then
						table.insert(directs, room)
					elseif not inAnySpace(room) then
						table.insert(others, room)
					end
				end
			end

			if #invites > 0 then
				addHeader("INVITES")
				for _, room in ipairs(invites) do
					addRow(room, false)
				end
			end

			addHeader("DIRECT MESSAGES")
			for _, room in ipairs(directs) do
				addRow(room, false)
			end

			if #others > 0 then
				addHeader("ROOMS")
				for _, room in ipairs(others) do
					addRow(room, false)
				end
			end
		end

		roomList.CanvasSize = UDim2.new(0, 0, 0, y + 8)
	end

	renderUserPanel = function()
		UI.clear(userPanel)

		local profile = profileOf(session.userId)
		local name = (profile and profile.displayName and profile.displayName ~= "") and profile.displayName
			or localpart(session.userId)

		makeAvatar(userPanel, session.userId, name, profile and profile.avatarUrl, UDim2.fromOffset(10, 10), 32)

		local nameLabel =
			UI.label(userPanel, name, UDim2.fromOffset(50, 9), UDim2.new(1, -96, 0, 18), tokens.type.small, D.bright)
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left

		local idLabel = UI.label(
			userPanel,
			session.userId or "",
			UDim2.fromOffset(50, 26),
			UDim2.new(1, -96, 0, 16),
			tokens.type.caption,
			D.muted
		)
		idLabel.TextXAlignment = Enum.TextXAlignment.Left

		if options.onSettings then
			UI.iconButton(
				userPanel,
				"builtin://icons/Settings.svg",
				UDim2.new(1, -38, 0.5, -15),
				UDim2.fromOffset(30, 30),
				options.onSettings,
				{
					color = D.userPanel,
					hoverColor = D.hover,
					pressedColor = D.pressed,
					border = false,
					iconSize = 18,
					radius = 4,
				}
			)
		end
	end

	renderMembers = function()
		UI.clear(memberList)

		local list = current and roomMembers[current.roomId]

		if not list then
			membersHeader.Text = ""
			return
		end

		membersHeader.Text = string.format("MEMBERS - %d", #list)

		local sorted = table.clone(list)
		table.sort(sorted, function(a, b)
			return string.lower(a.displayName or a.userId) < string.lower(b.displayName or b.userId)
		end)

		local y = 0

		for _, member in ipairs(sorted) do
			local name = member.displayName or localpart(member.userId)

			local button, label = UI.button(
				memberList,
				name,
				UDim2.fromOffset(8, y),
				UDim2.new(1, -16, 0, 40),
				function() end,
				{
					color = D.sidebar,
					hoverColor = D.hover,
					pressedColor = D.pressed,
					textColor = D.muted,
					textSize = 14,
					radius = 4,
					border = false,
					paddingX = 8,
					textY = 0,
				}
			)

			label.Position = UDim2.fromOffset(46, 0)
			label.Size = UDim2.new(1, -54, 1, 0)
			label.TextYAlignment = Enum.TextYAlignment.Center

			makeAvatar(button, member.userId, name, member.avatarUrl, UDim2.fromOffset(6, 4), 32)

			y += 42
		end

		memberList.CanvasSize = UDim2.new(0, 0, 0, y + 8)
	end

	local function applyLayout()
		membersPanel.Visible = membersOpen
		chat.Size = UDim2.new(1, -(RAIL + SIDEBAR + (membersOpen and MEMBERS or 0)), 1, 0)
		membersButton.BackgroundColor3 = membersOpen and D.selected or D.chat

		task.defer(function()
			task.wait()

			if not destroyed then
				renderMessages(false)
			end
		end)
	end

	local function updateHeader()
		if not current then
			prefixLabel.Text = ""
			titleLabel.Text = "Pick a conversation"
			titleLabel.Position = UDim2.fromOffset(16, 0)
			topicLabel.Text = ""
			dividerLine.Visible = false
			return
		end

		local title = roomTitle(current)
		prefixLabel.Text = current.isDirect and "@" or "#"
		titleLabel.Position = UDim2.fromOffset(34, 0)
		titleLabel.Text = title

		local topic = current.topic or ""
		local topicX = 34 + #title * 8.6 + 22

		dividerLine.Visible = topic ~= ""
		dividerLine.Position = UDim2.fromOffset(topicX - 11, 12)
		topicLabel.Position = UDim2.fromOffset(topicX, 0)
		topicLabel.Size = UDim2.new(1, -(topicX + 110), 0, HEADER)
		topicLabel.Text = topic
		topicLabel.TextXAlignment = Enum.TextXAlignment.Left

		input.PlaceholderText = "Message " .. (current.isDirect and "@" or "#") .. title
	end

	renderMessages = function(mode)
		local oldCanvas = scroller.CanvasSize.Y.Offset
		local oldPosition = scroller.CanvasPosition.Y
		local atBottom = oldPosition + scroller.AbsoluteSize.Y >= oldCanvas - 40

		UI.clear(scroller)

		local roomId = current and current.roomId
		local list = roomId and messages[roomId] or nil
		local textWidth = math.max(scroller.AbsoluteSize.X - (BODY_X + 28), 160)
		local y = 8

		local function bigText(text, size, color, h)
			local label = UI.label(scroller, text, UDim2.fromOffset(16, y), UDim2.new(1, -32, 0, h), size, color)
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextYAlignment = Enum.TextYAlignment.Center
			y += h
			return label
		end

		if not current then
			y = 40
			bigText("Pick a conversation from the sidebar.", 16, D.muted, 28)
		elseif not list then
			y = 40
			bigText("Loading messages...", 14, D.muted, 24)
		else
			if historyToken[roomId] then
				UI.button(
					scroller,
					"Load earlier messages",
					UDim2.fromOffset(16, y),
					UDim2.fromOffset(180, 28),
					function()
						if current and not loadingOlder then
							local room = current
							loadingOlder = true

							task.spawn(function()
								local ok, result = MatrixService:GetMessages(session, room.roomId, {
									dir = "b",
									limit = HISTORY_LIMIT,
									from = historyToken[room.roomId],
								})

								loadingOlder = false

								if destroyed then
									return
								end

								if not ok then
									setStatus("Could not load older messages: " .. tostring(result), true)
									return
								end

								local existing = messages[room.roomId] or {}
								local older = {}

								for _, ev in ipairs(result.messages or {}) do
									if ev.body and not findEvent(existing, ev.eventId) then
										table.insert(older, ev)
									end
								end

								for _, ev in ipairs(existing) do
									table.insert(older, ev)
								end

								messages[room.roomId] = older

								local token = result.nextToken
								historyToken[room.roomId] = (token and token ~= "" and #(result.messages or {}) > 0)
										and token
									or nil

								if current == room then
									renderMessages("prepend")
								end
							end)
						end
					end,
					{
						color = D.input,
						hoverColor = D.hover,
						pressedColor = D.pressed,
						textColor = D.text,
						textSize = tokens.type.small,
						radius = 4,
						border = false,
						textY = 0,
					}
				)

				y += 44
			else
				local title = roomTitle(current)
				y += 12
				bigText("Welcome to " .. (current.isDirect and "@" or "#") .. title .. "!", 26, D.bright, 36)
				bigText("This is the start of your conversation in " .. title .. ".", 14, D.muted, 22)
				y += 18
			end

			local previous
			local lastDay

			for _, ev in ipairs(list) do
				local ts = math.floor(ev.timestamp or os.time())
				local text = messageText(ev)
				if ev.failed then
					text ..= "\n(Message failed to send)"
				end

				local dayStarted = false
				if lastDay ~= dayKey(ts) then
					lastDay = dayKey(ts)
					dayStarted = true

					UI.frame(scroller, UDim2.new(0, 16, 0, y + 12), UDim2.new(1, -32, 0, 1), D.divider)

					local dayLabel = UI.label(
						scroller,
						os.date("%B %d, %Y", ts),
						UDim2.new(0.5, -60, 0, y + 3),
						UDim2.fromOffset(120, 18),
						11,
						D.muted
					)
					dayLabel.BackgroundTransparency = 0
					dayLabel.BackgroundColor3 = D.chat
					dayLabel.TextXAlignment = Enum.TextXAlignment.Center

					y += 28
				end

				local grouped = previous ~= nil
					and not dayStarted
					and previous.sender == ev.sender
					and ts - math.floor(previous.timestamp or ts) < GROUP_SECONDS

				local bodyHeight = estimateHeight(text, textWidth)
				local rowHeight = grouped and (bodyHeight + 2) or (22 + bodyHeight + 6)

				if not grouped then
					y += 10
				end

				local row = UI.create("TextButton", {
					Text = "",
					Position = UDim2.fromOffset(0, y),
					Size = UDim2.new(1, 0, 0, rowHeight),
					BackgroundColor3 = D.rowHover,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					AutoButtonColor = false,
					Active = true,
					InputSink = false,
				}, scroller)

				row.MouseEnter:Connect(function()
					row.BackgroundTransparency = 0
				end)

				row.MouseLeave:Connect(function()
					row.BackgroundTransparency = 1
				end)

				local bodyY = 1

				if not grouped then
					local name = displayName(ev.sender)
					local profile = profileOf(ev.sender)

					makeAvatar(
						row,
						ev.sender or "?",
						name,
						profile and profile.avatarUrl,
						UDim2.fromOffset(14, 5),
						AVATAR
					)

					local nameLabel = UI.label(
						row,
						name,
						UDim2.fromOffset(BODY_X, 4),
						UDim2.fromOffset(#name * 8 + 4, 18),
						14,
						D.bright
					)
					nameLabel.TextXAlignment = Enum.TextXAlignment.Left

					local timeText = stamp(ts) .. (ev.pending and "  (sending...)" or "")
					local timeLabel = UI.label(
						row,
						timeText,
						UDim2.fromOffset(BODY_X + #name * 8 + 10, 6),
						UDim2.fromOffset(200, 16),
						11,
						D.muted
					)
					timeLabel.TextXAlignment = Enum.TextXAlignment.Left

					bodyY = 22
				end

				local body = UI.label(
					row,
					text,
					UDim2.fromOffset(BODY_X, bodyY),
					UDim2.new(1, -(BODY_X + 20), 0, bodyHeight),
					14,
					ev.failed and D.red or D.text
				)
				body.TextWrapped = true
				body.TextXAlignment = Enum.TextXAlignment.Left
				body.TextYAlignment = Enum.TextYAlignment.Top
				body.TextTransparency = ev.pending and 0.5 or 0

				y += rowHeight
				previous = ev
			end

			y += 12
		end

		scroller.CanvasSize = UDim2.new(0, 0, 0, y)

		if mode == true or (mode == false and atBottom) then
			scroller.CanvasPosition = Vector2.new(0, math.max(0, y - scroller.AbsoluteSize.Y))
		elseif mode == "prepend" then
			scroller.CanvasPosition = Vector2.new(0, math.max(0, oldPosition + (y - oldCanvas)))
		else
			scroller.CanvasPosition = Vector2.new(0, oldPosition)
		end
	end

	local function sortRooms()
		table.sort(rooms, function(a, b)
			local ta = a.lastMessage and a.lastMessage.timestampMs or 0
			local tb = b.lastMessage and b.lastMessage.timestampMs or 0
			return ta > tb
		end)
	end

	local function loadSpaceChildren(space)
		spaceChildren[space.roomId] = nil

		task.spawn(function()
			local path = "/_matrix/client/v3/rooms/" .. urlEncode(space.roomId) .. "/state"
			local ok, data = MatrixService:AuthedRequest(session, "GET", path)

			if destroyed then
				return
			end

			local set = {}

			if ok and type(data) == "table" then
				for _, ev in ipairs(data) do
					if
						ev.type == "m.space.child"
						and ev.state_key
						and type(ev.content) == "table"
						and ev.content.via ~= nil
					then
						set[ev.state_key] = true
					end
				end
			end

			spaceChildren[space.roomId] = set
			scheduleRender()
		end)
	end

	refreshRooms = function()
		local ok, list = MatrixService:GetRooms(session)

		if destroyed then
			return false
		end

		if not ok then
			setStatus(tostring(list), true)
			return false
		end

		rooms = list or {}

		for _, room in ipairs(rooms) do
			if room.roomType == "m.space" and room.membership == "join" and spaceChildren[room.roomId] == nil then
				loadSpaceChildren(room)
			end

			if room.isDirect and room.directUserId then
				ensureProfile(room.directUserId)
			end
		end

		if current then
			for _, room in ipairs(rooms) do
				if room.roomId == current.roomId then
					room.unread = 0
					current = room
					break
				end
			end
		end

		if activeSpace then
			for _, room in ipairs(rooms) do
				if room.roomId == activeSpace.roomId then
					activeSpace = room
					break
				end
			end
		end

		sortRooms()
		renderRail()
		renderSidebarHeader()
		renderSidebar()
		renderUserPanel()

		return true
	end

	local function markRead(room)
		local list = messages[room.roomId]
		local last = list and list[#list]

		if last and last.eventId then
			task.spawn(function()
				MatrixService:MarkRead(session, room.roomId, last.eventId)
			end)
		end
	end

	local function loadMembers(room)
		task.spawn(function()
			local ok, list = MatrixService:GetMembers(session, room.roomId)

			if destroyed or not ok or type(list) ~= "table" then
				return
			end

			roomMembers[room.roomId] = list

			for _, member in ipairs(list) do
				profiles[member.userId] = {
					displayName = member.displayName,
					avatarUrl = member.avatarUrl,
				}
			end

			if current == room then
				renderMembers()
				renderMessages(false)
			end

			renderSidebar()
		end)
	end

	local function loadHistory(room)
		task.spawn(function()
			local ok, result = MatrixService:GetMessages(session, room.roomId, { dir = "b", limit = HISTORY_LIMIT })

			if destroyed then
				return
			end

			if not ok then
				setStatus("Could not load messages: " .. tostring(result), true)
				messages[room.roomId] = messages[room.roomId] or {}
			else
				local list = {}

				for _, ev in ipairs(result.messages or {}) do
					if ev.body then
						table.insert(list, ev)
					end
				end

				for _, ev in ipairs(messages[room.roomId] or {}) do
					if (ev.pending or ev.failed) and not findEvent(list, ev.eventId) then
						table.insert(list, ev)
					end
				end

				messages[room.roomId] = list

				local token = result.nextToken
				historyToken[room.roomId] = (token and token ~= "" and #(result.messages or {}) > 0) and token or nil
			end

			if current == room then
				renderMessages(true)
				markRead(room)
			end
		end)
	end

	local function buildEmojiPicker(list)
		UI.clear(emojiList)

		if #list == 0 then
			local label = UI.label(
				emojiList,
				"No custom emoji in this room.",
				UDim2.fromOffset(4, 8),
				UDim2.new(1, -8, 0, 18),
				tokens.type.small,
				D.muted
			)
			label.TextXAlignment = Enum.TextXAlignment.Left
			return
		end

		local x, y, rowHeight = 4, 4, 36
		local maxX = 288

		for _, entry in ipairs(list) do
			local hasImage = entry.mxc ~= nil
			local cellWidth = hasImage and 36 or (#entry.code * 7 + 18)

			if x + cellWidth > maxX then
				x = 4
				y += rowHeight + 4
			end

			local button, label = UI.button(
				emojiList,
				hasImage and "" or (":" .. entry.code .. ":"),
				UDim2.fromOffset(x, y),
				UDim2.fromOffset(cellWidth, rowHeight),
				function()
					input.Text ..= ":" .. entry.code .. ":"
					emojiOpen = false
					emojiPanel.Visible = false
					input:CaptureFocus()
				end,
				{
					color = D.input,
					hoverColor = D.hover,
					pressedColor = D.pressed,
					textColor = D.text,
					textSize = tokens.type.caption,
					radius = 4,
					border = false,
					paddingX = 4,
					textY = 0,
				}
			)

			label.TextXAlignment = Enum.TextXAlignment.Center
			label.TextYAlignment = Enum.TextYAlignment.Center

			if hasImage then
				loadImage(entry.mxc, function(bytes)
					if UI.isAlive(button) then
						UI.image(button, bytes, UDim2.fromOffset(4, 4), UDim2.fromOffset(28, 28))
					end
				end)
			end

			x += cellWidth + 4
		end

		emojiList.CanvasSize = UDim2.new(0, 0, 0, y + rowHeight + 8)
	end

	local function loadEmojis(room)
		if emojiCache[room.roomId] then
			buildEmojiPicker(emojiCache[room.roomId])
			return
		end

		task.spawn(function()
			local called, ok, data = pcall(function()
				return SpaceService:ListSpaceEmojis(session, room.roomId)
			end)

			local list = {}

			if called and ok and type(data) == "table" then
				for key, entry in pairs(data.emojis or data) do
					local code, mxc

					if type(entry) == "table" then
						code = entry.shortcode or entry.name
						mxc = entry.url or entry.mxc or entry.mxcUrl or entry.imageUrl
					elseif type(entry) == "string" and type(key) == "string" then
						code, mxc = key, entry
					end

					if type(code) == "string" then
						if type(mxc) ~= "string" or string.sub(mxc, 1, 6) ~= "mxc://" then
							mxc = nil
						end

						table.insert(list, { code = code, mxc = mxc })
					end
				end

				table.sort(list, function(a, b)
					return a.code < b.code
				end)
			end

			emojiCache[room.roomId] = list

			if not destroyed and current == room then
				buildEmojiPicker(list)
			end
		end)
	end

	selectRoom = function(room)
		current = room
		room.unread = 0
		room.highlights = 0

		emojiOpen = false
		emojiPanel.Visible = false

		updateHeader()
		updateInfo()
		renderRail()
		renderSidebar()
		renderMembers()
		renderMessages(true)
		loadEmojis(room)
		loadMembers(room)

		if messages[room.roomId] then
			markRead(room)
		else
			loadHistory(room)
		end
	end

	local function selectRoomById(roomId)
		for _, room in ipairs(rooms) do
			if room.roomId == roomId then
				selectRoom(room)
				return
			end
		end
	end

	acceptInvite = function(room)
		task.spawn(function()
			local ok, result = MatrixService:JoinRoom(session, room.roomId)

			if not ok then
				setStatus("Could not join: " .. tostring(result), true)
				return
			end

			if refreshRooms() then
				selectRoomById(type(result) == "string" and result or room.roomId)
			end
		end)
	end

	local function sendMessage()
		local text = trim(input.Text)

		if text == "" or not current then
			return
		end

		local room = current
		local roomId = room.roomId

		input.Text = ""
		lastTypingSent = 0

		local pending = {
			sender = session.userId,
			body = text,
			msgtype = "m.text",
			timestamp = os.time(),
			pending = true,
		}

		messages[roomId] = messages[roomId] or {}
		table.insert(messages[roomId], pending)
		renderMessages(true)

		task.spawn(function()
			MatrixService:SetTyping(session, roomId, false)

			local ok, eventId = MatrixService:SendMessage(session, roomId, text)

			if destroyed then
				return
			end

			pending.pending = false

			if not ok then
				pending.failed = true
				setStatus("Failed to send: " .. tostring(eventId), true)
			else
				local list = messages[roomId]
				local duplicate = findEvent(list, eventId)

				if duplicate and duplicate ~= pending then
					for i, ev in ipairs(list) do
						if ev == pending then
							table.remove(list, i)
							break
						end
					end
				else
					pending.eventId = eventId
				end

				room.lastMessage = {
					eventId = eventId,
					sender = session.userId,
					body = text,
					timestampMs = os.time() * 1000,
				}
				sortRooms()
				renderSidebar()
			end

			if current == room then
				renderMessages(true)
			end
		end)
	end

	local function onIncoming(roomId, ev)
		if not ev or not ev.body then
			return
		end

		local list = messages[roomId]

		if list then
			if findEvent(list, ev.eventId) then
				return
			end

			if ev.sender == session.userId then
				for _, existing in ipairs(list) do
					if existing.pending and existing.body == ev.body then
						existing.pending = false
						existing.eventId = ev.eventId
						existing.timestamp = ev.timestamp or existing.timestamp

						if current and current.roomId == roomId then
							renderMessages(false)
						end

						return
					end
				end
			end

			table.insert(list, ev)
		end

		local room
		for _, candidate in ipairs(rooms) do
			if candidate.roomId == roomId then
				room = candidate
				break
			end
		end

		if not room then
			task.spawn(refreshRooms)
			return
		end

		room.lastMessage = ev

		if current == room and visible() then
			renderMessages(false)
			markRead(room)
		elseif ev.sender ~= session.userId then
			room.unread = (room.unread or 0) + 1
		end

		sortRooms()
		renderRail()
		renderSidebar()
	end

	local function startSync()
		stopSync = MatrixService:StartSync(session, {
			onMessage = function(roomId, ev)
				if not destroyed then
					onIncoming(roomId, ev)
				end
			end,
			onInvite = function()
				if not destroyed then
					task.spawn(refreshRooms)
				end
			end,
			onTyping = function(roomId, userIds)
				if destroyed then
					return
				end

				local others = {}

				for _, userId in ipairs(userIds or {}) do
					if userId ~= session.userId then
						table.insert(others, userId)
					end
				end

				typing[roomId] = others

				if current and current.roomId == roomId then
					updateInfo()
				end
			end,
			onError = function(err)
				if not destroyed then
					setStatus("Sync error: " .. tostring(err), true)
				end
			end,
		})
	end

	input.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			sendMessage()

			task.defer(function()
				if not destroyed then
					input:CaptureFocus()
				end
			end)
		end
	end)

	input.TextChanged:Connect(function()
		if not current or input.Text == "" then
			return
		end

		local now = os.clock()

		if now - lastTypingSent > 3 then
			lastTypingSent = now
			local roomId = current.roomId

			task.spawn(function()
				MatrixService:SetTyping(session, roomId, true, 5000)
			end)
		end
	end)

	emojiButton.MouseButton1Click:Connect(function()
		if not current then
			return
		end

		emojiOpen = not emojiOpen
		emojiPanel.Visible = emojiOpen

		if emojiOpen then
			loadEmojis(current)
		end
	end)

	membersButton.MouseButton1Click:Connect(function()
		membersOpen = not membersOpen
		applyLayout()
	end)

	searchInput.TextChanged:Connect(renderSidebar)

	searchInput.FocusLost:Connect(function(enterPressed)
		if not enterPressed then
			return
		end

		local target = trim(searchInput.Text)
		local first = string.sub(target, 1, 1)

		if first ~= "@" and first ~= "#" and first ~= "!" then
			return
		end

		searchInput.Text = ""

		task.spawn(function()
			local ok, result

			if first == "@" then
				ok, result = MatrixService:CreateDirectRoom(session, target)
			else
				ok, result = MatrixService:JoinRoom(session, target)
			end

			if not ok then
				setStatus(tostring(result), true)
				return
			end

			if refreshRooms() then
				selectRoomById(result)
			end
		end)
	end)

	function self:Open()
		panel.Visible = true

		if not started then
			started = true
			ensureProfile(session.userId)
			applyLayout()
			renderRail()
			renderSidebarHeader()
			renderSidebar()
			renderUserPanel()
			renderMessages(true)
			task.spawn(refreshRooms)
			startSync()
		elseif current then
			current.unread = 0
			renderRail()
			renderSidebar()
			markRead(current)
		end
	end

	function self:Close()
		panel.Visible = false
	end

	function self:Toggle()
		if panel.Visible then
			self:Close()
		else
			self:Open()
		end
	end

	function self:Destroy()
		if destroyed then
			return
		end

		destroyed = true

		if stopSync then
			stopSync()
			stopSync = nil
		end

		panel:Destroy()
	end

	self.Window = panel

	return self
end

return Messaging

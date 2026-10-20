if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local UI = require("@internal/editor_ui")
local Auth = require("@internal/auth")

local MatrixService = game:GetService("MatrixService")
local SpaceService = game:GetService("SpaceService")
local StudioThemeService = game:GetService("StudioThemeService")
local RunService = game:GetService("RunService")
local http = game:GetService("HttpService")

local theme = StudioThemeService.SelectedTheme
local tokens = UI.tokens
local colors = tokens.color

local RAIL = 64
local SIDEBAR = 232
local MEMBERS = 204
local HEADER = 40
local PANEL = 52
local COMPOSER = 44
local INFO = 20
local HISTORY_LIMIT = 50
local GROUP_SECONDS = 420

local AVATAR_COLORS = {
	colors.accent,
	colors.success,
	colors.warning,
	colors.error,
	Color3.fromRGB(235, 69, 158),
	Color3.fromRGB(26, 188, 156),
	Color3.fromRGB(155, 89, 182),
}

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
	local charsPerLine = math.max(6, math.floor(width / 7.2))
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
		ScrollBarImageColor3 = colors.subtext,
		ScrollBarImageTransparency = 0.4,
		ScrollBarAutoHide = true,
		ClipsDescendants = true,
	}, parent)
end

local function onFrame(callback)
	if renderer and renderer.Pool and renderer.Pool.new then
		renderer.Pool.new("2d", callback)
	else
		RunService.Heartbeat:Connect(callback)
	end
end

local Messaging = {}

function Messaging.mount(content, session, options)
	options = options or {}

	local self = {}
	local windowControls = options.windowControls
	local tabName = options.tabName or "Messages"

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
	local destroyed = false
	local wide = false
	local membersOpen = true
	local emojiOpen = false
	local loadingOlder = false
	local lastTypingSent = 0
	local statusText, statusIsError = nil, false
	local renderQueued = false
	local navDirty = false
	local wasActive = true
	local stopSync = nil

	local renderRail, renderSidebar, renderSidebarHeader, renderMessages, renderMembers, renderUserPanel
	local renderNav, selectRoom, selectRoomById, acceptInvite, refreshRooms, updateInfo, updateHeader

	local function tabActive()
		if windowControls == nil or windowControls.getSelectedTab == nil then
			return true
		end

		return windowControls.getSelectedTab() == tabName
	end

	local function computeWide()
		local width = content.AbsoluteSize.X
		local outputWidth = 0

		if theme.OutputCoordinates and theme.OutputCoordinates.Size then
			outputWidth = theme.OutputCoordinates.Size.X.Offset
		end

		if outputWidth <= 0 then
			return width >= 700
		end

		return width >= outputWidth
	end

	wide = computeWide()

	local root = UI.create("Frame", {
		Name = "MessagesRoot",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = colors.panel,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, content)

	local rail = UI.frame(root, UDim2.fromOffset(0, 0), UDim2.new(0, RAIL, 1, 0), colors.canvas)
	local sidebar = UI.frame(root, UDim2.fromOffset(RAIL, 0), UDim2.new(0, SIDEBAR, 1, 0), colors.panelRaised)
	local chat = UI.frame(root, UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), colors.panel)
	local membersPanel = UI.frame(root, UDim2.new(1, -MEMBERS, 0, 0), UDim2.new(0, MEMBERS, 1, 0), colors.panelRaised)
	chat.ClipsDescendants = true

	local railList = newScroller(rail, "Rail", UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), 0)

	local sidebarHeader = UI.frame(sidebar, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, HEADER), colors.panelRaised)
	UI.separator(sidebarHeader, UDim2.new(0, 0, 1, -1), UDim2.new(1, 0, 0, 1), colors.canvas)

	local searchInput = UI.input(
		sidebarHeader,
		"Find or start a conversation",
		UDim2.fromOffset(8, 6),
		UDim2.new(1, -16, 0, 28),
		{ textSize = tokens.type.small }
	)

	local spaceTitle =
		UI.label(sidebarHeader, "", UDim2.fromOffset(14, 0), UDim2.new(1, -28, 1, 0), tokens.type.title, colors.text)
	spaceTitle.Visible = false

	local roomList =
		newScroller(sidebar, "RoomList", UDim2.fromOffset(0, HEADER), UDim2.new(1, 0, 1, -(HEADER + PANEL)), 5)
	local userPanel = UI.frame(sidebar, UDim2.new(0, 0, 1, -PANEL), UDim2.new(1, 0, 0, PANEL), colors.surface)

	local chatHeader = UI.frame(chat, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, HEADER), colors.panel)
	UI.separator(chatHeader, UDim2.new(0, 0, 1, -1), UDim2.new(1, 0, 0, 1), colors.border)

	local prefixLabel =
		UI.label(chatHeader, "#", UDim2.fromOffset(14, 0), UDim2.fromOffset(16, HEADER), 20, colors.muted)
	local titleLabel = UI.label(
		chatHeader,
		"Pick a conversation",
		UDim2.fromOffset(32, 0),
		UDim2.fromOffset(240, HEADER),
		tokens.type.title,
		colors.text
	)
	local dividerLine = UI.frame(chatHeader, UDim2.fromOffset(0, 9), UDim2.fromOffset(1, 22), colors.border)
	local topicLabel =
		UI.label(chatHeader, "", UDim2.fromOffset(0, 0), UDim2.fromOffset(300, HEADER), tokens.type.small, colors.muted)
	dividerLine.Visible = false

	local membersButton = UI.button(
		chatHeader,
		"Members",
		UDim2.new(1, -(10 + 76), 0.5, -12),
		UDim2.fromOffset(76, 24),
		function() end,
		{
			color = colors.panel,
			hoverColor = colors.hover,
			pressedColor = colors.pressed,
			textColor = colors.subtext,
			textSize = tokens.type.small,
			radius = tokens.radius.sm,
			border = false,
			paddingX = 8,
			textY = 0,
		}
	)

	local channelButton, channelController

	local function navTitle(roomId)
		for _, room in ipairs(rooms) do
			if room.roomId == roomId then
				local title = room.isDirect
						and room.directUserId
						and (profiles[room.directUserId] and profiles[room.directUserId].displayName)
					or room.displayName
					or room.roomId
				return (room.isDirect and "@" or "#") .. tostring(title)
			end
		end

		return "Select a channel"
	end

	channelButton, _, channelController = UI.dropdown(
		chatHeader,
		"",
		UDim2.fromOffset(8, 7),
		UDim2.new(1, -16, 0, 26),
		"builtin://global-icons/chevron-down.svg",
		{
			items = {},
			showSearch = true,
			searchPlaceholder = "Search channels...",
			menuWidth = 240,
			maxVisibleItems = 8,
			color = colors.input,
			hoverColor = colors.hover,
			pressedColor = colors.pressed,
			textColor = colors.text,
			menuColor = colors.panelRaised,
			borderColor = colors.border,
			radius = tokens.radius.sm,
			textSize = tokens.type.small,
			format = navTitle,
			menuPosition = function()
				local position = channelButton.AbsolutePosition
				local size = channelButton.AbsoluteSize

				return UDim2.fromOffset(math.floor(position.X), math.floor(position.Y + size.Y + 2))
			end,
			onChanged = function(value)
				selectRoomById(value)
			end,
		}
	)

	local scroller = newScroller(
		chat,
		"Messages",
		UDim2.fromOffset(0, HEADER),
		UDim2.new(1, 0, 1, -(HEADER + COMPOSER + INFO + 12)),
		6
	)

	local composer = UI.frame(
		chat,
		UDim2.new(0, 10, 1, -(INFO + COMPOSER + 2)),
		UDim2.new(1, -20, 0, COMPOSER),
		colors.input,
		tokens.radius.md
	)

	local input = UI.input(
		composer,
		"Message",
		UDim2.fromOffset(10, 8),
		UDim2.new(1, -(10 + 42), 0, 28),
		{ color = colors.input, borderColor = colors.input, textSize = tokens.type.body }
	)

	local emojiButton = UI.iconButton(
		composer,
		"builtin://icons/Sparkles.svg",
		UDim2.new(1, -38, 0.5, -15),
		UDim2.fromOffset(30, 30),
		function() end,
		{
			color = colors.input,
			hoverColor = colors.hover,
			pressedColor = colors.pressed,
			border = false,
			iconSize = 18,
			radius = tokens.radius.sm,
		}
	)

	local infoLabel = UI.label(
		chat,
		"",
		UDim2.new(0, 12, 1, -INFO),
		UDim2.new(1, -24, 0, INFO - 2),
		tokens.type.caption,
		colors.muted
	)

	local emojiWidth = 320
	local emojiPanel = UI.frame(
		chat,
		UDim2.new(1, -(10 + emojiWidth), 1, -(INFO + COMPOSER + 10 + 180)),
		UDim2.fromOffset(emojiWidth, 180),
		colors.panelRaised,
		tokens.radius.md
	)
	UI.stroke(emojiPanel, colors.border, 1, 0)
	emojiPanel.Visible = false
	emojiPanel.ZIndex = 5

	UI.label(
		emojiPanel,
		"Custom emoji",
		UDim2.fromOffset(12, 6),
		UDim2.new(1, -24, 0, 18),
		tokens.type.caption,
		colors.muted
	)
	local emojiList = newScroller(emojiPanel, "Emoji", UDim2.fromOffset(8, 28), UDim2.new(1, -16, 1, -36), 5)

	local membersHeader = UI.label(
		membersPanel,
		"",
		UDim2.fromOffset(16, 0),
		UDim2.new(1, -32, 0, HEADER),
		tokens.type.caption,
		colors.muted
	)
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

			renderNav()
			updateHeader()
			renderMessages(false)

			if wide then
				renderMembers()
				renderUserPanel()
			end
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
			infoLabel.TextColor3 = statusIsError and colors.error or colors.muted
			return
		end

		infoLabel.TextColor3 = colors.muted

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
		if not wide then
			return
		end

		UI.clear(railList)

		local y = 10

		local function pill(selected, unread, itemY)
			if not selected and unread <= 0 then
				return
			end

			local h = selected and 28 or 8
			UI.frame(railList, UDim2.fromOffset(0, itemY + 20 - h / 2), UDim2.fromOffset(4, h), colors.text, 2)
		end

		local function badge(button, count)
			if count <= 0 then
				return
			end

			UI.badge(button, count > 99 and "99+" or tostring(count), UDim2.new(1, -18, 1, -14), {
				width = math.max(18, #tostring(count) * 7 + 10),
				height = 16,
				color = colors.error,
				textColor = Color3.new(1, 1, 1),
			})
		end

		local homeUnread = unreadFor(function(room)
			return not inAnySpace(room)
		end)

		local home = UI.button(railList, "", UDim2.fromOffset(12, y), UDim2.fromOffset(40, 40), function()
			activeSpace = nil
			renderNav()
			renderSidebarHeader()
		end, {
			color = activeSpace == nil and colors.accent or colors.panel,
			hoverColor = colors.accent,
			pressedColor = colors.accent,
			radius = activeSpace == nil and 12 or 20,
			border = false,
		})

		local homeIcon =
			UI.image(home, "builtin://icons/Player.svg", UDim2.fromOffset(10, 10), UDim2.fromOffset(20, 20))
		homeIcon.ImageColor3 = Color3.new(1, 1, 1)

		pill(activeSpace == nil, homeUnread, y)
		badge(home, homeUnread)
		y += 48

		UI.frame(railList, UDim2.fromOffset(18, y), UDim2.fromOffset(28, 2), colors.border, 1)
		y += 10

		for _, space in ipairs(rooms) do
			if space.roomType == "m.space" and space.membership == "join" then
				local selected = activeSpace ~= nil and activeSpace.roomId == space.roomId
				local unread = unreadFor(function(room)
					return inSpace(space, room)
				end)

				local button, label = UI.button(
					railList,
					"",
					UDim2.fromOffset(12, y),
					UDim2.fromOffset(40, 40),
					function()
						activeSpace = space
						renderNav()
						renderSidebarHeader()
					end,
					{
						color = colorFor(space.roomId),
						hoverColor = colors.accent,
						pressedColor = colors.accent,
						radius = selected and 12 or 20,
						border = false,
					}
				)

				label.Text = firstChar(roomTitle(space))
				label.Position = UDim2.fromOffset(0, 0)
				label.Size = UDim2.fromScale(1, 1)
				label.TextSize = 18
				label.TextColor3 = Color3.new(1, 1, 1)
				label.TextXAlignment = Enum.TextXAlignment.Center
				label.TextYAlignment = Enum.TextYAlignment.Center

				loadImage(space.avatarUrl, function(bytes)
					if UI.isAlive(button) then
						local image = UI.image(button, bytes, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1))
						UI.corner(image, selected and 12 or 20)
						label.Visible = false
					end
				end)

				pill(selected, unread, y)
				badge(button, unread)
				y += 48
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
		if not wide then
			return
		end

		UI.clear(roomList)

		local query = string.lower(trim(searchInput.Text))
		local y = 8

		local function addHeader(text)
			local label = UI.label(
				roomList,
				text,
				UDim2.fromOffset(16, y + 6),
				UDim2.new(1, -32, 0, 14),
				tokens.type.caption,
				colors.muted
			)
			label.TextXAlignment = Enum.TextXAlignment.Left
			y += 26
		end

		local function addRow(room, channelStyle)
			local selected = current ~= nil and current.roomId == room.roomId
			local isInvite = room.membership == "invite"
			local unread = room.unread or 0
			local rowHeight = channelStyle and 30 or 40
			local title = roomTitle(room)

			local text = channelStyle and ("#  " .. title) or title
			if isInvite then
				text ..= "  (invite)"
			end

			local button, label = UI.button(
				roomList,
				text,
				UDim2.fromOffset(6, y),
				UDim2.new(1, -12, 0, rowHeight - 2),
				function()
					if isInvite then
						acceptInvite(room)
					else
						selectRoom(room)
					end
				end,
				{
					color = selected and colors.selection or colors.panelRaised,
					hoverColor = selected and colors.selectionHover or colors.hover,
					pressedColor = colors.pressed,
					textColor = (selected or unread > 0) and colors.text or colors.subtext,
					textSize = tokens.type.body,
					radius = tokens.radius.sm,
					border = false,
					paddingX = 8,
					textY = 0,
				}
			)

			local labelX = channelStyle and 10 or 46
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
					UDim2.fromOffset(7, 3),
					32
				)
			end

			if unread > 0 then
				UI.badge(button, unread > 99 and "99+" or tostring(unread), UDim2.new(1, -34, 0.5, -8), {
					width = 26,
					height = 16,
					color = colors.error,
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
					colors.muted
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
						colors.muted
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
		if not wide then
			return
		end

		UI.clear(userPanel)

		local profile = profileOf(session.userId)
		local name = (profile and profile.displayName and profile.displayName ~= "") and profile.displayName
			or localpart(session.userId)

		makeAvatar(userPanel, session.userId, name, profile and profile.avatarUrl, UDim2.fromOffset(10, 10), 32)

		local nameLabel =
			UI.label(userPanel, name, UDim2.fromOffset(50, 9), UDim2.new(1, -96, 0, 18), tokens.type.small, colors.text)
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left

		local idLabel = UI.label(
			userPanel,
			session.userId or "",
			UDim2.fromOffset(50, 26),
			UDim2.new(1, -96, 0, 16),
			tokens.type.caption,
			colors.muted
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
					color = colors.surface,
					hoverColor = colors.hover,
					pressedColor = colors.pressed,
					border = false,
					iconSize = 18,
					radius = tokens.radius.sm,
				}
			)
		end
	end

	local function dropdownOpen()
		local active = UI.shared().activeDropdown
		return active ~= nil and active.controller == channelController
	end

	local function refreshChannelDropdown()
		if wide then
			return
		end

		if dropdownOpen() then
			navDirty = true
			return
		end

		navDirty = false

		local items = {}

		for _, room in ipairs(rooms) do
			if room.roomType ~= "m.space" and room.membership == "join" then
				local unread = room.unread or 0
				table.insert(items, {
					value = room.roomId,
					label = navTitle(room.roomId) .. (unread > 0 and ("  (" .. unread .. ")") or ""),
				})
			end
		end

		channelController:SetItems(items)
		channelController:SetValue(current and current.roomId or "", true)
	end

	renderNav = function()
		if wide then
			renderRail()
			renderSidebar()
		else
			refreshChannelDropdown()
		end
	end

	renderMembers = function()
		if not wide then
			return
		end

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
				UDim2.fromOffset(6, y),
				UDim2.new(1, -12, 0, 38),
				function() end,
				{
					color = colors.panelRaised,
					hoverColor = colors.hover,
					pressedColor = colors.pressed,
					textColor = colors.subtext,
					textSize = tokens.type.body,
					radius = tokens.radius.sm,
					border = false,
					paddingX = 8,
					textY = 0,
				}
			)

			label.Position = UDim2.fromOffset(44, 0)
			label.Size = UDim2.new(1, -52, 1, 0)
			label.TextYAlignment = Enum.TextYAlignment.Center

			makeAvatar(button, member.userId, name, member.avatarUrl, UDim2.fromOffset(6, 3), 32)

			y += 40
		end

		memberList.CanvasSize = UDim2.new(0, 0, 0, y + 8)
	end

	updateHeader = function()
		titleLabel.Visible = wide
		prefixLabel.Visible = wide
		topicLabel.Visible = wide
		channelButton.Visible = not wide

		if not wide then
			dividerLine.Visible = false
			channelController:SetValue(current and current.roomId or "", true)
		elseif not current then
			prefixLabel.Text = ""
			titleLabel.Text = "Pick a conversation"
			titleLabel.Position = UDim2.fromOffset(14, 0)
			topicLabel.Text = ""
			dividerLine.Visible = false
		else
			local title = roomTitle(current)
			prefixLabel.Text = current.isDirect and "@" or "#"
			titleLabel.Position = UDim2.fromOffset(32, 0)
			titleLabel.Text = title

			local topic = current.topic or ""
			local topicX = 32 + #title * 8.6 + 22

			dividerLine.Visible = topic ~= ""
			dividerLine.Position = UDim2.fromOffset(topicX - 11, 9)
			topicLabel.Position = UDim2.fromOffset(topicX, 0)
			topicLabel.Size = UDim2.new(1, -(topicX + 110), 0, HEADER)
			topicLabel.Text = topic
			topicLabel.TextXAlignment = Enum.TextXAlignment.Left
		end

		input.PlaceholderText = current and ("Message " .. (current.isDirect and "@" or "#") .. roomTitle(current))
			or "Message"
	end

	local function applyLayout()
		rail.Visible = wide
		sidebar.Visible = wide

		local left = wide and (RAIL + SIDEBAR) or 0
		local right = (wide and membersOpen) and MEMBERS or 0

		membersPanel.Visible = wide and membersOpen
		membersButton.Visible = wide
		membersButton.BackgroundColor3 = membersOpen and colors.surface or colors.panel

		chat.Position = UDim2.fromOffset(left, 0)
		chat.Size = UDim2.new(1, -(left + right), 1, 0)

		emojiOpen = false
		emojiPanel.Visible = false

		renderSidebarHeader()
		renderNav()
		updateHeader()
		renderMembers()
		renderUserPanel()

		task.defer(function()
			task.wait()

			if not destroyed then
				renderMessages(true)
			end
		end)
	end

	renderMessages = function(mode)
		local oldCanvas = scroller.CanvasSize.Y.Offset
		local oldPosition = scroller.CanvasPosition.Y
		local atBottom = oldPosition + scroller.AbsoluteSize.Y >= oldCanvas - 40

		UI.clear(scroller)

		local avatarSize = wide and 36 or 28
		local bodyX = wide and 64 or 46
		local avatarX = wide and 14 or 10

		local roomId = current and current.roomId
		local list = roomId and messages[roomId] or nil
		local textWidth = math.max(scroller.AbsoluteSize.X - (bodyX + 24), 120)
		local y = 8

		local function bigText(text, size, color, h)
			local label = UI.label(scroller, text, UDim2.fromOffset(12, y), UDim2.new(1, -24, 0, h), size, color)
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextYAlignment = Enum.TextYAlignment.Center
			label.TextWrapped = true
			y += h
			return label
		end

		if not current then
			y = 30
			bigText(
				wide and "Pick a conversation from the sidebar." or "Pick a channel from the dropdown above.",
				tokens.type.title,
				colors.muted,
				40
			)
		elseif not list then
			y = 30
			bigText("Loading messages...", tokens.type.body, colors.muted, 24)
		else
			if historyToken[roomId] then
				UI.button(
					scroller,
					"Load earlier messages",
					UDim2.fromOffset(12, y),
					UDim2.fromOffset(170, 26),
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
						color = colors.input,
						hoverColor = colors.hover,
						pressedColor = colors.pressed,
						textColor = colors.text,
						textSize = tokens.type.small,
						radius = tokens.radius.sm,
						border = false,
						textY = 0,
					}
				)

				y += 40
			else
				local title = roomTitle(current)
				y += 8
				bigText(
					"Welcome to " .. (current.isDirect and "@" or "#") .. title .. "!",
					wide and 24 or 16,
					colors.text,
					wide and 36 or 44
				)
				bigText("This is the start of your conversation.", tokens.type.small, colors.muted, 20)
				y += 12
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

					UI.frame(scroller, UDim2.new(0, 12, 0, y + 11), UDim2.new(1, -24, 0, 1), colors.border)

					local dayLabel = UI.label(
						scroller,
						os.date("%B %d, %Y", ts),
						UDim2.new(0.5, -60, 0, y + 3),
						UDim2.fromOffset(120, 16),
						tokens.type.caption,
						colors.muted
					)
					dayLabel.BackgroundTransparency = 0
					dayLabel.BackgroundColor3 = colors.panel
					dayLabel.TextXAlignment = Enum.TextXAlignment.Center

					y += 26
				end

				local grouped = previous ~= nil
					and not dayStarted
					and previous.sender == ev.sender
					and ts - math.floor(previous.timestamp or ts) < GROUP_SECONDS

				local bodyHeight = estimateHeight(text, textWidth)
				local rowHeight = grouped and (bodyHeight + 2) or (22 + bodyHeight + 6)

				if not grouped then
					y += 8
				end

				local row = UI.create("TextButton", {
					Text = "",
					Position = UDim2.fromOffset(0, y),
					Size = UDim2.new(1, 0, 0, rowHeight),
					BackgroundColor3 = colors.hover,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					AutoButtonColor = false,
					Active = true,
					InputSink = false,
				}, scroller)

				row.MouseEnter:Connect(function()
					row.BackgroundTransparency = 0.5
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
						UDim2.fromOffset(avatarX, 4),
						avatarSize
					)

					local nameLabel = UI.label(
						row,
						name,
						UDim2.fromOffset(bodyX, 3),
						UDim2.fromOffset(#name * 8 + 4, 18),
						tokens.type.body,
						colors.text
					)
					nameLabel.TextXAlignment = Enum.TextXAlignment.Left

					local timeText = stamp(ts) .. (ev.pending and "  (sending...)" or "")
					local timeLabel = UI.label(
						row,
						timeText,
						UDim2.fromOffset(bodyX + #name * 8 + 10, 5),
						UDim2.fromOffset(200, 16),
						tokens.type.caption,
						colors.muted
					)
					timeLabel.TextXAlignment = Enum.TextXAlignment.Left

					bodyY = 22
				end

				local body = UI.label(
					row,
					text,
					UDim2.fromOffset(bodyX, bodyY),
					UDim2.new(1, -(bodyX + 12), 0, bodyHeight),
					tokens.type.body,
					ev.failed and colors.error or colors.subtext
				)
				body.TextWrapped = true
				body.TextXAlignment = Enum.TextXAlignment.Left
				body.TextYAlignment = Enum.TextYAlignment.Top
				body.TextTransparency = ev.pending and 0.5 or 0

				y += rowHeight
				previous = ev
			end

			y += 10
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

		if not current and not wide then
			for _, room in ipairs(rooms) do
				if room.roomType ~= "m.space" and room.membership == "join" then
					selectRoom(room)
					break
				end
			end
		end

		renderNav()
		renderSidebarHeader()
		updateHeader()
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

			renderNav()
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
				colors.muted
			)
			label.TextXAlignment = Enum.TextXAlignment.Left
			return
		end

		local x, y, rowHeight = 4, 4, 36
		local maxX = emojiWidth - 32

		for _, entry in ipairs(list) do
			local hasImage = entry.mxc ~= nil
			local cellWidth = hasImage and 36 or (#entry.code * 7 + 18)

			if x + cellWidth > maxX and x > 4 then
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
					color = colors.input,
					hoverColor = colors.hover,
					pressedColor = colors.pressed,
					textColor = colors.text,
					textSize = tokens.type.caption,
					radius = tokens.radius.sm,
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
		renderNav()
		renderMembers()
		renderMessages(true)
		loadEmojis(room)

		if wide then
			loadMembers(room)
		end

		if messages[room.roomId] then
			markRead(room)
		else
			loadHistory(room)
		end
	end

	selectRoomById = function(roomId)
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
				renderNav()
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

		if current == room and tabActive() then
			renderMessages(false)
			markRead(room)
		elseif ev.sender ~= session.userId then
			room.unread = (room.unread or 0) + 1
		end

		sortRooms()
		renderNav()
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

		if emojiOpen then
			emojiWidth = math.clamp(chat.AbsoluteSize.X - 20, 160, 320)
			emojiPanel.Size = UDim2.fromOffset(emojiWidth, 180)
			emojiPanel.Position = UDim2.new(1, -(10 + emojiWidth), 1, -(INFO + COMPOSER + 10 + 180))
			loadEmojis(current)
		end

		emojiPanel.Visible = emojiOpen
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

	function self:Step()
		if destroyed then
			return
		end

		local active = tabActive()

		if active and not wasActive and current then
			current.unread = 0
			renderNav()
			markRead(current)
		end

		wasActive = active

		if not active then
			return
		end

		local newWide = computeWide()

		if newWide ~= wide then
			wide = newWide
			applyLayout()

			if not wide and not current then
				for _, room in ipairs(rooms) do
					if room.roomType ~= "m.space" and room.membership == "join" then
						selectRoom(room)
						break
					end
				end
			end
		end

		if navDirty and not dropdownOpen() then
			refreshChannelDropdown()
		end
	end

	function self:SelectRoom(roomId)
		selectRoomById(roomId)
	end

	function self:Destroy()
		if destroyed then
			return
		end

		destroyed = true

		if stopSync then
			pcall(stopSync)
			stopSync = nil
		end

		if channelController then
			pcall(function()
				channelController:Close()
			end)
		end

		UI.forgetButtons(root)
		root:Destroy()
	end

	applyLayout()
	ensureProfile(session.userId)
	task.spawn(refreshRooms)
	startSync()

	return self
end

return function(content, windowControls)
	local view = nil
	local viewSession = nil
	local gate = nil
	local frame = 0

	local function clearGate()
		if gate and UI.isAlive(gate) then
			UI.forgetButtons(gate)
			gate:Destroy()
		end

		gate = nil
	end

	local function showGate()
		if gate then
			return
		end

		gate = UI.create("Frame", {
			Name = "MessagesGate",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = colors.panel,
			BorderSizePixel = 0,
		}, content)

		local label = UI.label(
			gate,
			"Log in to Matrix to use messages",
			UDim2.new(0.5, 0, 0.5, -24),
			UDim2.fromOffset(260, 20),
			tokens.type.small,
			colors.muted
		)
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.TextXAlignment = Enum.TextXAlignment.Center

		local button = UI.button(
			gate,
			"Log in",
			UDim2.new(0.5, -45, 0.5, 0),
			UDim2.fromOffset(90, UI.metrics.buttonHeight + 4),
			function()
				Auth.Login({
					onSuccess = function(session)
						shared.CurrentSession = session
					end,
				})
			end,
			{
				color = colors.accent,
				hoverColor = colors.selectionHover,
				pressedColor = colors.pressed,
				textColor = colors.text,
				textSize = tokens.type.small,
				radius = tokens.radius.sm,
				border = false,
			}
		)
	end

	local function unmount()
		if view then
			view:Destroy()
			view = nil
			viewSession = nil
		end
	end

	local function mountFor(session)
		clearGate()
		unmount()

		viewSession = session
		view = Messaging.mount(content, session, { windowControls = windowControls })
	end

	if shared.CurrentSession then
		mountFor(shared.CurrentSession)
	else
		showGate()
	end

	onFrame(function()
		frame += 1

		if view then
			view:Step()
		end

		if frame % 15 == 0 then
			local session = shared.CurrentSession

			if session ~= viewSession then
				unmount()

				if session then
					mountFor(session)
				else
					showGate()
				end
			end
		end
	end)

	return {
		GetView = function()
			return view
		end,
	}
end

local UI = require("@internal/editor_ui")
local MatrixService = game:GetService("MatrixService")
local SpaceService = game:GetService("SpaceService")

local tokens = UI.tokens
local colors = tokens.color

local INSET = tokens.space.md
local SIDEBAR_WIDTH = 220
local HISTORY_LIMIT = 50
local COMPOSER_HEIGHT = 28
local INFO_HEIGHT = 22

local function trim(text)
	return string.match(text or "", "^%s*(.-)%s*$")
end

local function localpart(userId)
	if not userId then
		return "unknown"
	end
	return string.match(userId, "^@([^:]+)") or userId
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
	local charsPerLine = math.max(8, math.floor(width / 6.6))
	local lines = 0

	for line in string.gmatch(text .. "\n", "(.-)\n") do
		lines += math.max(1, math.ceil(#line / charsPerLine))
	end

	return lines * 15
end

local Messaging = {}

function Messaging.new(session)
	assert(session, "Messaging.new requires a Matrix session")

	local self = {}

	local rooms = {}
	local messages = {}
	local names = {}
	local memberCounts = {}
	local typing = {}
	local current = nil
	local started = false
	local destroyed = false
	local emojiOpen = false
	local lastTypingSent = 0
	local statusText, statusIsError = nil, false
	local stopSync = nil

	local renderSidebar, renderMessages, selectRoom, acceptInvite, refreshRooms

	local screen = workspace:GetWindowDimensions()
	local screenWidth = screen and screen.X or 960
	local screenHeight = screen and screen.Y or 720
	local width = math.clamp(screenWidth - 120, 700, 860)
	local height = math.clamp(screenHeight - 120, 480, 600)

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
			onClose = function(window)
				window.Visible = false
			end,
		}
	)

	panel.Parent = UI.widgetOverlay()
	panel.Visible = false

	local cardStyle = {
		color = colors.panel,
		radius = tokens.radius.md,
		border = true,
		borderColor = colors.border,
		borderTransparency = 0.35,
	}

	local sidebar = UI.card(page, UDim2.fromOffset(INSET, INSET), UDim2.new(0, SIDEBAR_WIDTH, 1, -INSET * 2), cardStyle)

	local chat = UI.card(
		page,
		UDim2.fromOffset(SIDEBAR_WIDTH + INSET * 2, INSET),
		UDim2.new(1, -(SIDEBAR_WIDTH + INSET * 3), 1, -INSET * 2),
		{
			color = colors.panelRaised,
			radius = tokens.radius.md,
			border = true,
			borderColor = colors.border,
			borderTransparency = 0.35,
		}
	)
	chat.ClipsDescendants = true

	local search = UI.input(
		sidebar,
		"Search rooms...",
		UDim2.fromOffset(INSET, INSET),
		UDim2.new(1, -INSET * 2, 0, UI.metrics.inputHeight),
		{ textSize = tokens.type.small }
	)

	local roomList = UI.create("ScrollingFrame", {
		Name = "RoomList",
		Position = UDim2.fromOffset(INSET, 40),
		Size = UDim2.new(1, -INSET * 2, 1, -(40 + INSET * 2 + UI.metrics.inputHeight)),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = colors.subtext,
		ScrollBarImageTransparency = 0.4,
		ScrollBarAutoHide = true,
		ClipsDescendants = true,
	}, sidebar)

	local joinInput = UI.input(
		sidebar,
		"Join #room:server or DM @user...",
		UDim2.new(0, INSET, 1, -(INSET + UI.metrics.inputHeight)),
		UDim2.new(1, -INSET * 2, 0, UI.metrics.inputHeight),
		{ textSize = tokens.type.small }
	)

	local header = UI.group(chat, UDim2.fromOffset(INSET, INSET), UDim2.new(1, -INSET * 2, 0, 48), {
		color = colors.surface,
		radius = tokens.radius.sm,
	})
	UI.stroke(header, colors.border, 1, 0.45)
	UI.frame(header, UDim2.fromOffset(0, 8), UDim2.fromOffset(3, 32), colors.accent, 2)

	local titleLabel = UI.label(
		header,
		"Select a room",
		UDim2.fromOffset(16, 6),
		UDim2.new(1, -32, 0, 20),
		tokens.type.title,
		colors.text
	)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left

	local subtitleLabel =
		UI.label(header, "", UDim2.fromOffset(16, 27), UDim2.new(1, -32, 0, 16), tokens.type.caption, colors.subtext)
	subtitleLabel.TextXAlignment = Enum.TextXAlignment.Left

	local scroller = UI.create("ScrollingFrame", {
		Name = "Messages",
		Position = UDim2.fromOffset(INSET, INSET + 48 + INSET),
		Size = UDim2.new(1, -INSET * 2, 1, -(INSET + 48 + INSET + INSET + COMPOSER_HEIGHT + 4 + INFO_HEIGHT + 4)),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = colors.subtext,
		ScrollBarImageTransparency = 0.4,
		ScrollBarAutoHide = true,
		ClipsDescendants = true,
	}, chat)

	local infoY = -(INSET + COMPOSER_HEIGHT + 4 + INFO_HEIGHT)

	local infoLabel = UI.label(
		chat,
		"",
		UDim2.new(0, INSET + 2, 1, infoY),
		UDim2.new(1, -INSET * 2, 0, INFO_HEIGHT),
		tokens.type.caption,
		colors.muted
	)
	infoLabel.TextXAlignment = Enum.TextXAlignment.Left

	local emojiBar = UI.frame(
		chat,
		UDim2.new(0, INSET, 1, infoY),
		UDim2.new(1, -INSET * 2, 0, INFO_HEIGHT),
		colors.input,
		tokens.radius.sm
	)
	emojiBar.ClipsDescendants = true
	emojiBar.Visible = false

	local BUTTON_SEND, BUTTON_EMOJI = 60, 60
	local composerY = -(INSET + COMPOSER_HEIGHT)

	local input = UI.input(
		chat,
		"Message...",
		UDim2.new(0, INSET, 1, composerY),
		UDim2.new(1, -(INSET * 2 + BUTTON_SEND + BUTTON_EMOJI + 8), 0, COMPOSER_HEIGHT),
		{ textSize = tokens.type.body }
	)

	local function buttonStyle(textColor)
		return {
			color = colors.panel,
			hoverColor = colors.hover,
			pressedColor = colors.pressed,
			textColor = textColor,
			textSize = tokens.type.small,
			radius = tokens.radius.sm,
			border = true,
			borderColor = colors.border,
			paddingX = tokens.space.md,
			textY = 0,
		}
	end

	local emojiButton = UI.button(
		chat,
		"Emoji",
		UDim2.new(1, -(INSET + BUTTON_SEND + 4 + BUTTON_EMOJI), 1, composerY),
		UDim2.fromOffset(BUTTON_EMOJI, COMPOSER_HEIGHT),
		function() end,
		buttonStyle(colors.subtext)
	)

	local sendButton = UI.button(
		chat,
		"Send",
		UDim2.new(1, -(INSET + BUTTON_SEND), 1, composerY),
		UDim2.fromOffset(BUTTON_SEND, COMPOSER_HEIGHT),
		function() end,
		buttonStyle(colors.text)
	)

	local function displayName(userId)
		return names[userId] or localpart(userId)
	end

	local function updateInfo()
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

	renderMessages = function(stickToBottom)
		local atBottom = scroller.CanvasPosition.Y + scroller.AbsoluteSize.Y >= scroller.CanvasSize.Y.Offset - 40

		UI.clear(scroller)

		local list = current and messages[current.roomId] or nil
		local contentWidth = math.max(scroller.AbsoluteSize.X - 10, 300)
		local y = 4

		if not current or not list or #list == 0 then
			local text = not current and "Select a room to start chatting."
				or (not list and "Loading messages..." or "No messages yet. Say hello!")

			local empty = UI.label(
				scroller,
				text,
				UDim2.fromOffset(0, 20),
				UDim2.new(1, 0, 0, 20),
				tokens.type.small,
				colors.muted
			)
			empty.TextXAlignment = Enum.TextXAlignment.Center
		end

		for _, ev in ipairs(list or {}) do
			local own = ev.sender == session.userId
			local text = messageText(ev)
			local bodyHeight = estimateHeight(text, contentWidth - 20)
			local cardHeight = bodyHeight + 30

			local bubble = UI.card(scroller, UDim2.fromOffset(0, y), UDim2.new(1, -10, 0, cardHeight), {
				color = own and colors.surface or colors.panel,
				radius = tokens.radius.md,
				border = true,
				borderColor = own and colors.accent or colors.border,
				borderTransparency = own and 0.5 or 0.35,
			})

			local meta = displayName(ev.sender)
			if ev.timestamp then
				meta ..= "  |  " .. os.date("%H:%M", math.floor(ev.timestamp))
			end
			if ev.pending then
				meta ..= "  (sending...)"
			elseif ev.failed then
				meta ..= "  (failed to send)"
			end

			local sender = UI.label(
				bubble,
				meta,
				UDim2.fromOffset(10, 5),
				UDim2.new(1, -20, 0, 14),
				tokens.type.caption,
				ev.failed and colors.error or (own and colors.accent or colors.subtext)
			)
			sender.TextXAlignment = Enum.TextXAlignment.Left

			local body = UI.label(
				bubble,
				text,
				UDim2.fromOffset(10, 22),
				UDim2.new(1, -20, 0, bodyHeight),
				tokens.type.body,
				colors.text
			)
			body.TextWrapped = true
			body.TextXAlignment = Enum.TextXAlignment.Left
			body.TextYAlignment = Enum.TextYAlignment.Top
			body.TextTransparency = ev.pending and 0.4 or 0

			y += cardHeight + 6
		end

		scroller.CanvasSize = UDim2.new(0, 0, 0, y)

		if stickToBottom or atBottom then
			scroller.CanvasPosition = Vector2.new(0, math.max(0, y - scroller.AbsoluteSize.Y))
		end
	end

	local function sortRooms()
		table.sort(rooms, function(a, b)
			local ta = a.lastMessage and a.lastMessage.timestampMs or 0
			local tb = b.lastMessage and b.lastMessage.timestampMs or 0
			return ta > tb
		end)
	end

	renderSidebar = function()
		UI.clear(roomList)

		local query = string.lower(trim(search.Text))
		local groups = { invites = {}, direct = {}, rooms = {} }

		for _, room in ipairs(rooms) do
			local name = room.displayName or room.roomId
			local matches = query == "" or string.find(string.lower(name), query, 1, true) ~= nil

			if matches and room.roomType ~= "m.space" then
				if room.membership == "invite" then
					table.insert(groups.invites, room)
				elseif room.isDirect then
					table.insert(groups.direct, room)
				else
					table.insert(groups.rooms, room)
				end
			end
		end

		local y = 0

		local function addHeader(text)
			local label = UI.label(
				roomList,
				text,
				UDim2.fromOffset(4, y + 4),
				UDim2.new(1, -8, 0, 16),
				tokens.type.caption,
				colors.muted
			)
			label.TextXAlignment = Enum.TextXAlignment.Left
			y += 24
		end

		local function addRow(room)
			local selected = current ~= nil and current.roomId == room.roomId
			local isInvite = room.membership == "invite"
			local count = room.unread or 0

			local text = room.displayName or room.roomId
			if isInvite then
				text ..= " (invite)"
			end

			local button, label = UI.button(roomList, text, UDim2.fromOffset(0, y), UDim2.new(1, -8, 0, 28), function()
				if isInvite then
					acceptInvite(room)
				else
					selectRoom(room)
				end
			end, {
				color = selected and colors.surface or colors.panel,
				hoverColor = colors.hover,
				pressedColor = colors.pressed,
				textColor = selected and colors.text or colors.subtext,
				textSize = tokens.type.small,
				radius = tokens.radius.sm,
				border = false,
				paddingX = 8,
				textY = 0,
			})

			label.Size = UDim2.new(1, -(8 + (count > 0 and 34 or 8)), 1, 0)
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextYAlignment = Enum.TextYAlignment.Center

			if count > 0 then
				UI.badge(button, count > 99 and "99+" or tostring(count), UDim2.new(1, -32, 0.5, -8), {
					width = 26,
					height = 16,
					color = (room.highlights or 0) > 0 and colors.error or colors.accent,
				})
			end

			y += 30
		end

		for _, group in ipairs({
			{ "Invites", groups.invites },
			{ "Direct messages", groups.direct },
			{ "Rooms", groups.rooms },
		}) do
			if #group[2] > 0 then
				addHeader(group[1])
				for _, room in ipairs(group[2]) do
					addRow(room)
				end
				y += 6
			end
		end

		if y == 0 then
			local empty = UI.label(
				roomList,
				"No rooms",
				UDim2.fromOffset(0, 12),
				UDim2.new(1, -8, 0, 20),
				tokens.type.small,
				colors.muted
			)
			empty.TextXAlignment = Enum.TextXAlignment.Center
		end

		roomList.CanvasSize = UDim2.new(0, 0, 0, y)
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

		if current then
			for _, room in ipairs(rooms) do
				if room.roomId == current.roomId then
					room.unread = 0
					current = room
					break
				end
			end
		end

		sortRooms()
		renderSidebar()

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

			for _, member in ipairs(list) do
				names[member.userId] = member.displayName
			end

			memberCounts[room.roomId] = #list

			if current == room then
				local topic = room.topic and room.topic ~= "" and ("  |  " .. room.topic) or ""
				subtitleLabel.Text = string.format("%d member%s%s", #list, #list == 1 and "" or "s", topic)
				renderMessages(false)
			end
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
			end

			if current == room then
				renderMessages(true)
				markRead(room)
			end
		end)
	end

	local function loadEmojis(room)
		UI.clear(emojiBar)

		task.spawn(function()
			local called, ok, data = pcall(function()
				return SpaceService:ListSpaceEmojis(session, room.roomId)
			end)

			if destroyed or not called or not ok or current ~= room or type(data) ~= "table" then
				return
			end

			local list = data.emojis or data
			local x = 6

			for key, entry in pairs(list) do
				local code = type(entry) == "table" and (entry.shortcode or entry.name)
					or (type(key) == "string" and key or (type(entry) == "string" and entry or nil))

				if code then
					local buttonWidth = #code * 7 + 22

					UI.button(
						emojiBar,
						":" .. code .. ":",
						UDim2.fromOffset(x, 1),
						UDim2.fromOffset(buttonWidth, INFO_HEIGHT - 2),
						function()
							input.Text ..= ":" .. code .. ":"
							input:CaptureFocus()
						end,
						{
							color = colors.input,
							hoverColor = colors.hover,
							pressedColor = colors.pressed,
							textSize = tokens.type.caption,
							radius = tokens.radius.sm,
							border = false,
							paddingX = 4,
							textY = 0,
						}
					)

					x += buttonWidth + 4
				end
			end
		end)
	end

	local function setEmojiOpen(open)
		emojiOpen = open
		emojiBar.Visible = open
		infoLabel.Visible = not open
	end

	selectRoom = function(room)
		current = room
		room.unread = 0
		room.highlights = 0

		titleLabel.Text = room.displayName or room.roomId
		subtitleLabel.Text = room.topic or ""
		setEmojiOpen(false)

		renderSidebar()
		renderMessages(true)
		updateInfo()
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

			if not ok then
				pending.pending = false
				pending.failed = true
				setStatus("Failed to send: " .. tostring(eventId), true)
			else
				pending.pending = false

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

		local viewing = current == room and visible()

		if viewing then
			renderMessages(false)
			markRead(room)
		elseif ev.sender ~= session.userId then
			room.unread = (room.unread or 0) + 1
		end

		sortRooms()
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

	sendButton.MouseButton1Click:Connect(sendMessage)

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
		setEmojiOpen(not emojiOpen)
	end)

	search.TextChanged:Connect(renderSidebar)

	joinInput.FocusLost:Connect(function(enterPressed)
		if not enterPressed then
			return
		end

		local target = trim(joinInput.Text)

		if target == "" then
			return
		end

		joinInput.Text = ""

		task.spawn(function()
			local ok, result
			if string.sub(target, 1, 1) == "@" then
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
			renderMessages(true)
			task.spawn(refreshRooms)
			startSync()
		elseif current then
			current.unread = 0
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

local Preferences = require("@internal/preferences")
local UI = require("@internal/editor_ui")

local ScriptContext = game:GetService("ScriptContext")
local LogService = game:GetService("LogService")
local RunService = game:GetService("RunService")

local colors = UI.tokens.color
local tokens = UI.tokens

local function createConsole()
	local WINDOW_NAME = "Console"
	local MAX_ENTRIES = 1600
	local MAX_COMMAND_HISTORY = 50
	local MAX_MESSAGES_PER_POLL = 320
	local MAX_LOG_CHARS = 131072
	local MAX_PREVIEW_CHARS = 260
	local MAX_SEARCH_CHARS = 8192
	local MAX_TABLE_DEPTH = 12
	local TABLE_PAGE_SIZE = 64
	local TEXT_PAGE_SIZE = 48
	local TEXT_CHUNK_SIZE = 160
	local MAX_VISIBLE_ROWS = 16000
	local ROW_HEIGHT = math.max(UI.metrics.treeRow, 20)
	local TEXT_ROW_HEIGHT = 76
	local TIMESTAMP_X = 41
	local TIMESTAMP_WIDTH = 164
	local MESSAGE_X = TIMESTAMP_X + TIMESTAMP_WIDTH + 4
	local TOOLBAR_HEIGHT = 30
	local COMMANDBAR_HEIGHT = 30
	local POLL_INTERVAL = 0.15
	local SEARCH_DELAY = 0.14
	local OVERSCAN = 6

	local KIND_COLORS = {
		Log = colors.text,
		Info = Color3.fromRGB(110, 170, 255),
		Warn = colors.warning,
		Error = colors.error,
	}
	local KIND_ICONS = {
		Log = "builtin://global-icons/Output.svg",
		Info = "builtin://global-icons/Info.svg",
		Warn = "builtin://global-icons/Warning.svg",
		Error = "builtin://global-icons/Error.svg",
	}
	local filterItems = {
		{ value = "All", text = "All" },
		{ value = "Log", text = "Log" },
		{ value = "Log", text = "Kinemium" },
		{ value = "Info", text = "Info" },
		{ value = "Warn", text = "Warn" },
		{ value = "Error", text = "Error" },
	}

	local activeFilter = "All"
	local searchQuery = ""
	local entries = {}
	local visibleRows = {}
	local rowPool = {}
	local lastSeenCount = 0
	local historyGeneration = LogService.HistoryGeneration
	local commandHistory = {}
	local historyIndex = 0
	local rebuild
	local renderViewport

	local gui = Instance.new("ScreenGui")
	gui.Name = "Console"
	gui.Parent = game.StarterGui
	UI.trackRoot(gui)

	local panel, content =
		UI.window(WINDOW_NAME, UDim2.fromOffset(0, 0), UDim2.fromOffset(0, 0), "Console", { closable = true })
	panel.Size = UDim2.new(0.4, 0, 0.7, 0)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Parent = gui

	local BUTTON_WIDTH, PAD = 52, 6
	local FILTER_SIZE = UI.metrics.buttonHeight
	local search = UI.input(
		content,
		"Search...",
		UDim2.fromOffset(PAD, 4),
		UDim2.new(1, -(BUTTON_WIDTH + FILTER_SIZE + PAD * 4), 0, UI.metrics.inputHeight),
		{ textSize = tokens.type.small }
	)

	local filterButton, filterRecord
	local filterMenu = nil

	local function closeFilterMenu()
		if not filterMenu then
			return
		end
		UI.forgetButtons(filterMenu.popup)
		filterMenu.backdrop:Destroy()
		filterMenu.popup:Destroy()
		filterMenu = nil
	end

	local function updateFilterButton()
		UI.setButtonState(filterRecord, activeFilter ~= "All" and "selected" or nil)
	end

	local function openFilterMenu()
		if filterMenu then
			closeFilterMenu()
			return
		end
		local overlay = UI.RootOverlay()
		local width, menuPad, rowGap = 110, 8, 4
		local rowHeight = UI.metrics.propertyRow
		local height = menuPad * 2 + #filterItems * rowHeight + (#filterItems - 1) * rowGap
		local backdrop = UI.create("TextButton", {
			Name = "FilterBackdrop",
			Text = "",
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Active = true,
			InputSink = true,
			ZIndex = 99999,
		}, overlay)
		backdrop.MouseButton1Click:Connect(closeFilterMenu)

		local buttonPosition = filterButton.AbsolutePosition
		local buttonSize = filterButton.AbsoluteSize
		local screen = overlay.AbsoluteSize
		local x = math.clamp(buttonPosition.X + buttonSize.X - width, 4, math.max(4, screen.X - width - 4))
		local y = math.clamp(buttonPosition.Y + buttonSize.Y + 2, 4, math.max(4, screen.Y - height - 4))
		local popup = UI.frame(
			overlay,
			UDim2.fromOffset(x, y),
			UDim2.fromOffset(width, height),
			colors.panelRaised,
			tokens.radius.sm
		)
		popup.Name = "FilterMenu"
		popup.ZIndex = 100000
		UI.stroke(popup, colors.borderStrong, 1, 0)
		UI.radioGroup(
			popup,
			UDim2.fromOffset(menuPad, menuPad),
			UDim2.fromOffset(width - menuPad * 2, height - menuPad * 2),
			filterItems,
			activeFilter,
			function(selected)
				activeFilter = selected
				updateFilterButton()
				rebuild(false)
				closeFilterMenu()
			end,
			{ gap = rowGap }
		)
		for _, descendant in ipairs(popup:GetDescendants()) do
			if descendant:IsA("GuiObject") then
				descendant.ZIndex = 100001
			end
		end
		filterMenu = { backdrop = backdrop, popup = popup }
	end

	filterButton, filterRecord = UI.iconButton(
		content,
		"builtin://global-icons/filter.svg",
		UDim2.new(1, -(PAD * 2 + BUTTON_WIDTH + FILTER_SIZE), 0, 4),
		UDim2.fromOffset(FILTER_SIZE, UI.metrics.buttonHeight),
		openFilterMenu,
		{ iconSize = 14 }
	)
	UI.tooltip(filterButton, "Filter logs", { placement = "below" })

	UI.button(
		content,
		"Clear",
		UDim2.new(1, -(PAD + BUTTON_WIDTH), 0, 4),
		UDim2.fromOffset(BUTTON_WIDTH, UI.metrics.buttonHeight),
		function()
			table.clear(entries)
			lastSeenCount = LogService.MessageCount
			rebuild(false, true)
		end,
		{ paddingX = 4 }
	)

	local inset = UI.metrics.panelInset
	local scroll = UI.create("ScrollingFrame", {
		Name = "Log",
		Position = UDim2.fromOffset(inset, TOOLBAR_HEIGHT),
		Size = UDim2.new(1, -inset * 2, 1, -(TOOLBAR_HEIGHT + COMMANDBAR_HEIGHT + 6)),
		BackgroundColor3 = tokens.color.surface,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = tokens.color.subtext,
		ScrollBarImageTransparency = 0.4,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ClipsDescendants = true,
	}, content)
	UI.corner(scroll, tokens.radius.md)

	local command = UI.input(
		content,
		"Run a command...",
		UDim2.new(0, PAD, 1, -(COMMANDBAR_HEIGHT - 3)),
		UDim2.new(1, -PAD * 2, 0, UI.metrics.inputHeight),
		{ textSize = tokens.type.small, maxLength = 1000, focusColor = colors.accent }
	)

	local months = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

	local function formatTime(timestamp)
		local seconds = math.floor(tonumber(timestamp) or 0)
		local iso = DateTime.fromUnixTimestamp(seconds).fromIsoDate
		local year, month, day = string.match(iso, "^(%d+)-(%d%d)-(%d%d)$")
		local date = iso
		if year then
			local format = Preferences.get("dateFormat")
			if format == "Oct 19, 2026" then
				date = string.format("%s %s, %s", months[tonumber(month)], day, year)
			elseif format == "19/10/2026" then
				date = string.format("%s/%s/%s", day, month, year)
			elseif format ~= "2026-10-19" then
				date = string.format("%s %s %s", day, months[tonumber(month)], year)
			end
		end
		local hour = seconds // 3600 % 24
		local minute = seconds // 60 % 60
		local second = seconds % 60
		if Preferences.get("hour24") then
			return string.format("%s %02d:%02d:%02d", date, hour, minute, second)
		end
		return string.format("%s %02d:%02d:%02d %s", date, (hour + 11) % 12 + 1, minute, second, hour < 12 and "AM" or "PM")
	end

	local function preview(value, quoteStrings)
		local valueType = typeof(value)
		if valueType == "table" then
			return "{...}"
		end
		if valueType == "nil" then
			return "nil"
		end
		local text
		if valueType == "string" then
			text = string.sub(value, 1, MAX_PREVIEW_CHARS)
			text = string.gsub(text, "\r", "\\r")
			text = string.gsub(text, "\n", " ↵ ")
			text = string.gsub(text, "\t", "    ")
			if #value > MAX_PREVIEW_CHARS then
				text ..= "…"
			end
			if quoteStrings then
				return '"' .. text .. '"'
			end
			return text
		end
		local ok, converted = pcall(tostring, value)
		text = ok and converted or "<unprintable>"
		if #text > MAX_PREVIEW_CHARS then
			return string.sub(text, 1, MAX_PREVIEW_CHARS) .. "…"
		end
		return text
	end

	local function keyPreview(key)
		if type(key) == "string" then
			local short = string.sub(key, 1, 80)
			if string.match(short, "^[%a_][%w_]*$") and #key <= 80 then
				return short
			end
			return "[" .. preview(key, true) .. "]"
		end
		return "[" .. preview(key, true) .. "]"
	end

	local function circularReference(parent, value)
		local current = parent
		while current do
			if current.value == value then
				return true
			end
			current = current.parent
		end
		return false
	end

	local function newValueNode(value, label, parent, depth)
		local valueType = typeof(value)
		local circular = valueType == "table" and circularReference(parent, value)
		local canExpand = false
		if valueType == "table" then
			canExpand = not circular and depth < MAX_TABLE_DEPTH
		elseif valueType == "string" then
			canExpand = #value > MAX_PREVIEW_CHARS
				or string.find(string.sub(value, 1, MAX_PREVIEW_CHARS), "\n", 1, true) ~= nil
		end
		local suffix = circular and " <circular>" or ""
		return {
			type = "value",
			value = value,
			text = (label and label .. " = " or "") .. preview(value, label ~= nil) .. suffix,
			parent = parent,
			depth = depth,
			canExpand = canExpand,
			expanded = false,
			children = nil,
			hasMore = canExpand,
			cursor = nil,
			textPos = 1,
			chunkIndex = 0,
		}
	end

	local function loadPage(node)
		if not node.hasMore then
			return
		end
		if not node.children then
			node.children = {}
		end

		if typeof(node.value) == "table" then
			for _ = 1, TABLE_PAGE_SIZE do
				local ok, key, value = pcall(next, node.value, node.cursor)
				if not ok or key == nil then
					node.hasMore = false
					break
				end
				node.cursor = key
				node.children[#node.children + 1] = newValueNode(value, keyPreview(key), node, node.depth + 1)
			end
			if node.hasMore then
				local ok, nextKey = pcall(next, node.value, node.cursor)
				node.hasMore = ok and nextKey ~= nil
			end
		elseif typeof(node.value) == "string" then
			local message = node.value
			local length = #message
			for _ = 1, TEXT_PAGE_SIZE do
				if node.textPos > length then
					node.hasMore = false
					break
				end
				local last = math.min(length, node.textPos + TEXT_CHUNK_SIZE - 1)
				local part = string.sub(message, node.textPos, last)
				node.textPos = last + 1
				node.chunkIndex += 1
				node.children[#node.children + 1] = {
					type = "chunk",
					text = part,
					parent = node,
					depth = node.depth + 1,
					canExpand = false,
				}
			end
			node.hasMore = node.textPos <= length
		else
			node.hasMore = false
		end
	end

	local function makeEntry(item)
		local kind = KIND_COLORS[item.type] and item.type or "Log"
		local raw = item.message
		local truncated = typeof(raw) == "string" and #raw > MAX_LOG_CHARS
		if truncated then
			raw = string.sub(raw, 1, MAX_LOG_CHARS) .. "\n[Output truncated to protect editor performance]"
		end
		local node = newValueNode(raw, nil, nil, 0)
		node.type = "entry"
		node.kind = kind
		node.color = KIND_COLORS[kind]
		node.timestamp = item.timestamp
		node.time = formatTime(item.timestamp)
		node.playtest = type(raw) == "string" and string.sub(raw, 1, 10) == "[Playtest "
		node.repeats = 1
		node.truncated = truncated
		local matchText = preview(raw, false)
		if typeof(raw) == "string" then
			matchText = string.sub(raw, 1, MAX_SEARCH_CHARS)
		end
		node.searchText = string.lower(matchText)
		return node
	end

	local function passes(node)
		if node.playtest and not Preferences.get("playtestOutput") then return false end
		if not node.playtest and node.kind == "Info" and not Preferences.get("verboseLogging") and activeFilter == "All" then
			return false
		end
		if activeFilter ~= "All" and node.kind ~= activeFilter then
			return false
		end
		return searchQuery == "" or string.find(node.searchText, searchQuery, 1, true) ~= nil
	end

	local function isNearBottom()
		return scroll.CanvasPosition.Y + scroll.AbsoluteSize.Y >= scroll.CanvasSize.Y.Offset - ROW_HEIGHT * 3
	end

	local function scrollToBottom()
		scroll.CanvasPosition = Vector2.new(0, math.max(0, scroll.CanvasSize.Y.Offset - scroll.AbsoluteSize.Y))
	end

	local function appendNode(model, node, depth, y)
		if #model >= MAX_VISIBLE_ROWS then
			return y
		end
		local height = node.type == "chunk" and TEXT_ROW_HEIGHT or ROW_HEIGHT
		model[#model + 1] = { node = node, depth = depth, y = y, height = height }
		return y + height
	end

	local function rebuildModel()
		local model = {}
		local y = 0
		local remainingRoots = 0
		for _, entry in ipairs(entries) do
			if passes(entry) then
				remainingRoots += 1
			end
		end
		for _, entry in ipairs(entries) do
			if passes(entry) then
				remainingRoots -= 1
				y = appendNode(model, entry, 0, y)
				if entry.expanded then
					local stack = { { node = entry, depth = 0, index = 1 } }
					while #stack > 0 and #model < MAX_VISIBLE_ROWS - remainingRoots do
						local top = stack[#stack]
						local parent = top.node
						local children = parent.children or {}
						if top.index <= #children then
							local child = children[top.index]
							top.index += 1
							y = appendNode(model, child, top.depth + 1, y)
							if child.expanded and child.canExpand then
								stack[#stack + 1] = { node = child, depth = top.depth + 1, index = 1 }
							end
						elseif parent.hasMore and not top.moreShown then
							top.moreShown = true
							y = appendNode(model, {
								type = "more",
								text = "Show next "
									.. (typeof(parent.value) == "table" and TABLE_PAGE_SIZE or TEXT_PAGE_SIZE)
									.. " items…",
								parent = parent,
							}, top.depth + 1, y)
						else
							stack[#stack] = nil
						end
					end
				end
			end
		end
		visibleRows = model
		return y
	end

	local function toggleNode(node)
		if node.type == "more" then
			loadPage(node.parent)
			rebuild(false)
			return
		end
		if not node.canExpand then
			return
		end
		node.expanded = not node.expanded
		if node.expanded and node.children == nil then
			loadPage(node)
		end
		rebuild(false)
	end

	local function createRowSlot()
		local row = UI.create("TextButton", {
			Name = "Row",
			Text = "",
			Size = UDim2.new(1, -2, 0, ROW_HEIGHT),
			Position = UDim2.fromOffset(1, 0),
			BackgroundColor3 = tokens.color.rowEven,
			BackgroundTransparency = 0.12,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Active = true,
			Visible = false,
			ClipsDescendants = true,
		}, scroll)
		local arrow = UI.label(
			row,
			"",
			UDim2.fromOffset(5, 1),
			UDim2.fromOffset(14, ROW_HEIGHT - 2),
			tokens.type.small,
			colors.subtext
		)
		local icon = UI.image(row, KIND_ICONS.Log, UDim2.fromOffset(22, 3), UDim2.fromOffset(14, 14))
		local timestamp = UI.label(
			row,
			"",
			UDim2.fromOffset(TIMESTAMP_X, 1),
			UDim2.fromOffset(TIMESTAMP_WIDTH, ROW_HEIGHT - 2),
			tokens.type.small,
			colors.subtext
		)
		local message = UI.label(
			row,
			"",
			UDim2.fromOffset(MESSAGE_X, 1),
			UDim2.new(1, -MESSAGE_X - 8, 0, ROW_HEIGHT - 2),
			tokens.type.small,
			colors.text
		)
		local slot = {
			row = row,
			arrow = arrow,
			icon = icon,
			timestamp = timestamp,
			message = message,
			node = nil,
			hovering = false,
		}
		row.MouseButton1Click:Connect(function()
			local current = slot.node
			if current then
				toggleNode(current)
			end
		end)
		row.MouseEnter:Connect(function()
			slot.hovering = true
			row.BackgroundColor3 = colors.hover
		end)
		row.MouseLeave:Connect(function()
			slot.hovering = false
			local binding = slot.binding
			if binding then
				row.BackgroundColor3 = binding.index % 2 == 0 and tokens.color.rowEven or tokens.color.rowOdd
			end
		end)
		return slot
	end

	local function bindRow(slot, record, index)
		local node = record.node
		local depth = record.depth
		local row = slot.row
		if slot.node ~= node then
			slot.hovering = false
		end
		slot.node = node
		slot.binding = { index = index }
		row.Visible = true
		row.Position = UDim2.fromOffset(1, record.y)
		row.Size = UDim2.new(1, -2, 0, record.height)
		row.BackgroundColor3 = slot.hovering and colors.hover
			or (index % 2 == 0 and tokens.color.rowEven or tokens.color.rowOdd)

		local indent = math.min(depth * 16, 240)
		local isEntry = node.type == "entry"
		local expandText = node.type == "more" and "+" or (node.canExpand and (node.expanded and "▾" or "▸") or "")
		slot.arrow.Text = expandText
		slot.arrow.Position = UDim2.fromOffset(6 + indent, 1)
		slot.arrow.Visible = expandText ~= ""
		slot.icon.Visible = isEntry
		slot.timestamp.Visible = isEntry
		if isEntry then
			slot.icon.Image = KIND_ICONS[node.kind]
			slot.timestamp.Text = node.time
		end

		local x = isEntry and MESSAGE_X or 26 + indent
		slot.message.Position = UDim2.fromOffset(x, 2)
		slot.message.Size = UDim2.new(1, -x - 8, 0, record.height - 4)
		slot.message.TextColor3 = isEntry and node.color or (node.type == "more" and colors.accent or colors.text)
		slot.message.Text = node.text .. (isEntry and node.repeats > 1 and ("  (×" .. node.repeats .. ")") or "")
		slot.message.TextWrapped = node.type == "chunk"
		if node.type == "chunk" then
			slot.message.TextYAlignment = Enum.TextYAlignment.Top
		else
			slot.message.TextYAlignment = Enum.TextYAlignment.Center
		end
	end

	local renderedFirst = -1
	local renderedLast = -1
	local renderVersion = 0
	local boundVersion = -1
	local rendering = false

	renderViewport = function(force)
		if rendering then
			return
		end
		local size = scroll.AbsoluteSize
		if size.Y <= 0 then
			for _, slot in ipairs(rowPool) do
				slot.node = nil
				slot.row.Visible = false
			end
			return
		end
		rendering = true
		local fromY = math.max(0, scroll.CanvasPosition.Y - ROW_HEIGHT * OVERSCAN)
		local toY = scroll.CanvasPosition.Y + size.Y + ROW_HEIGHT * OVERSCAN
		local lo, hi = 1, #visibleRows
		while lo <= hi do
			local mid = (lo + hi) // 2
			local item = visibleRows[mid]
			if item.y + item.height < fromY then
				lo = mid + 1
			else
				hi = mid - 1
			end
		end
		local first = lo
		local last = first - 1
		for i = first, #visibleRows do
			if visibleRows[i].y > toY then
				break
			end
			last = i
		end
		if not force and first == renderedFirst and last == renderedLast and boundVersion == renderVersion then
			rendering = false
			return
		end
		renderedFirst, renderedLast = first, last
		boundVersion = renderVersion
		local needed = math.max(0, last - first + 1)
		while #rowPool < needed do
			rowPool[#rowPool + 1] = createRowSlot()
		end
		for index, slot in ipairs(rowPool) do
			if index <= needed then
				bindRow(slot, visibleRows[first + index - 1], first + index - 1)
			else
				slot.node = nil
				slot.binding = nil
				slot.row.Visible = false
			end
		end
		rendering = false
	end

	rebuild = function(stickToBottom, resetPosition)
		local oldY = resetPosition and 0 or scroll.CanvasPosition.Y
		local height = rebuildModel()
		renderVersion += 1
		scroll.CanvasSize = UDim2.fromOffset(0, height)
		if stickToBottom then
			scrollToBottom()
		else
			local maximum = math.max(0, height - scroll.AbsoluteSize.Y)
			scroll.CanvasPosition = Vector2.new(0, math.clamp(oldY, 0, maximum))
		end
		renderViewport(true)
	end

	scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		renderViewport(false)
	end)
	scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		renderViewport(true)
	end)

	local function appendBatch(batch)
		for _, node in ipairs(batch) do
			local previous = entries[#entries]
			if
				previous
				and not previous.truncated
				and not node.truncated
				and previous.kind == node.kind
				and previous.value == node.value
			then
				previous.repeats += 1
				previous.timestamp = node.timestamp
				previous.time = node.time
			else
				entries[#entries + 1] = node
			end
		end
		local excess = #entries - MAX_ENTRIES
		if excess > 0 then
			local kept = {}
			for index = excess + 1, #entries do
				kept[#kept + 1] = entries[index]
			end
			entries = kept
		end
	end

	local function poll()
		local count = LogService.MessageCount
		local generation = LogService.HistoryGeneration
		local reset = generation ~= historyGeneration or count < lastSeenCount
		if not reset and count == lastSeenCount then
			return
		end
		local previous = reset and 0 or lastSeenCount
		local ok, history = pcall(function()
			return LogService:GetLogHistory()
		end)
		if not ok or not history then
			return
		end
		if reset then
			table.clear(entries)
		end
		local delta = count - previous
		historyGeneration = generation
		lastSeenCount = count
		local n = math.min(delta, #history, MAX_MESSAGES_PER_POLL)
		if n <= 0 then
			if reset then
				rebuild(false, true)
			end
			return
		end
		local stick = isNearBottom()
		local batch = {}
		if delta > n then
			batch[#batch + 1] = makeEntry({
				type = "Warn",
				message = "[Output] Skipped " .. (delta - n) .. " older messages during a log burst.",
				timestamp = history[#history - n + 1].timestamp,
			})
		end
		for index = #history - n + 1, #history do
			batch[#batch + 1] = makeEntry(history[index])
		end
		appendBatch(batch)
		rebuild(stick and not reset, reset)
	end

	local function executeCommand(source)
		LogService:Log("> " .. source)
		ScriptContext:Run(source, "Console")
	end

	local function submitCommand()
		local source = command.Text
		source = string.match(source, "^%s*(.-)%s*$") or ""
		command.Text = ""
		if source == "" then
			return
		end
		if commandHistory[#commandHistory] ~= source then
			commandHistory[#commandHistory + 1] = source
			if #commandHistory > MAX_COMMAND_HISTORY then
				table.remove(commandHistory, 1)
			end
		end
		historyIndex = #commandHistory + 1
		executeCommand(source)
		pcall(function()
			command:CaptureFocus()
		end)
	end

	command.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			submitCommand()
		end
	end)

	local elapsed = 0
	local searchCountdown = -1
	local searchText = ""
	search:GetPropertyChangedSignal("Text"):Connect(function()
		searchText = string.lower(string.sub(search.Text or "", 1, 256))
		searchCountdown = SEARCH_DELAY
	end)

	RunService.Heartbeat:Connect(function(dt)
		if not panel.Visible then
			return
		end
		if searchCountdown >= 0 then
			searchCountdown -= dt
			if searchCountdown < 0 then
				searchQuery = searchText
				rebuild(false)
			end
		end
		elapsed += dt
		if elapsed >= POLL_INTERVAL then
			elapsed = 0
			poll()
		end
	end)

	local connection = Preferences.Changed:Connect(function(key)
		if key == "hour24" or key == "dateFormat" then
			for _, node in ipairs(entries) do node.time = formatTime(node.timestamp) end
		elseif key ~= "playtestOutput" and key ~= "verboseLogging" then
			return
		end
		rebuild(false)
	end)
	panel.Destroying:Connect(function() connection:Disconnect() end)
	poll()
	return {
		window = panel,
		gui = gui,
		toggle = function()
			UI.toggleWindow(WINDOW_NAME)
		end,
	}
end

if IsPlaytest then
	return
end

return {
	createConsole = createConsole,
	Refresh = function()
		UI.refreshWindow("Console")
	end,
	Show = function()
		local panel = UI.getWindow("Console")
		if panel then
			panel.Visible = true
		end
	end,
	Hide = function()
		local panel = UI.getWindow("Console")
		if panel then
			panel.Visible = false
		end
	end,
	IsVisible = function()
		local panel = UI.getWindow("Console")
		return panel ~= nil and panel.Visible
	end,
}

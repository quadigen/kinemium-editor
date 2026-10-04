local UI = require("@internal/editor_ui")
local CodeEditor = require("@internal/code_editor")

local ScriptContext = game:GetService("ScriptContext")
local LogService = game:GetService("LogService")
local RunService = game:GetService("RunService")

local colors = UI.tokens.color
local tokens = UI.tokens

local function createConsole()
	local WINDOW_NAME = "Console"
	local MAX_ENTRIES = 1000
	local MAX_COMMAND_HISTORY = 50
	local ROW_HEIGHT = UI.metrics.treeRow
	local TOOLBAR_HEIGHT = 30
	local POLL_INTERVAL = 0.1

	local KIND_COLORS = {
		Log = colors.text,
		Info = Color3.fromRGB(110, 170, 255),
		Warn = colors.warning,
		Error = colors.error,
	}

	local filterItems = {
		{ value = "All", text = "All" },
		{ value = "Log", text = "Log" },
		{ value = "Info", text = "Info" },
		{ value = "Warn", text = "Warn" },
		{ value = "Error", text = "Error" },
	}

	local activeFilter = "All"

	local searchQuery = ""
	local entries = {} -- { message, kind, color, time }
	local lastSeenCount = 0

	local commandHistory = {}
	local historyIndex = 0

	local gui = Instance.new("ScreenGui")
	gui.Name = "Console"
	gui.Parent = game.StarterGui

	local panel, content = UI.window(WINDOW_NAME, UDim2.fromOffset(0, 0), UDim2.fromOffset(0, 0), "Console", {
		closable = true,
	})
	panel.Size = UDim2.new(0.4, 0, 0.7, 0)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Parent = gui

	local BUTTON_WIDTH, PAD = 52, 6
	local FILTER_SIZE = UI.metrics.buttonHeight
	local FILTER_ICON = "builtin://global-icons/filter.svg"

	local search = UI.input(
		content,
		"Search...",
		UDim2.fromOffset(PAD, 4),
		UDim2.new(1, -(BUTTON_WIDTH + FILTER_SIZE + PAD * 4), 0, UI.metrics.inputHeight),
		{ textSize = UI.tokens.type.small }
	)

	local rebuild -- forward declaration

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

		local width = 110
		local menuPad = 8
		local rowGap = 4
		local rowHeight = UI.metrics.propertyRow
		local height = menuPad * 2 + #filterItems * rowHeight + (#filterItems - 1) * rowGap

		-- Invisible full-screen catcher: any click outside the popup closes it
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

		if not buttonPosition or not buttonSize then
			return
		end

		local screen = overlay.AbsoluteSize or Vector2.new(1920, 1080)

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
				rebuild()
				closeFilterMenu()
			end,
			{ gap = rowGap }
		)

		-- Keep everything inside the popup above the backdrop
		for _, descendant in ipairs(popup:GetDescendants()) do
			if descendant:IsA("GuiObject") then
				descendant.ZIndex = 100001
			end
		end

		filterMenu = { backdrop = backdrop, popup = popup }
	end

	filterButton, filterRecord = UI.iconButton(
		content,
		FILTER_ICON,
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
			rebuild()
		end,
		{ paddingX = 4 }
	)

	local inset = UI.metrics.panelInset

	local COMMAND_PAD = 5
	local EDITOR_PAD = 3
	local COMMAND_BUTTON = UI.metrics.buttonHeight
	local RUN_WIDTH = 44
	local COMMAND_GAP = 4
	local COMMAND_BUTTONS_WIDTH = RUN_WIDTH + COMMAND_BUTTON + COMMAND_GAP * 2

	local COMMAND_LINE_HEIGHT = 18
	local COMMANDBAR_EXPANDED_LINES = 10
	local COMMANDBAR_MAX_RATIO = 0.4

	local COMMANDBAR_COLLAPSED = 10

	local EXPAND_ICON = "builtin://global-icons/chevron-down.svg"
	local COLLAPSE_ICON = "builtin://global-icons/chevron-up.svg"

	local commandExpanded = false
	local commandHeight = COMMANDBAR_COLLAPSED

	local scroll = UI.create("ScrollingFrame", {
		Name = "Log",

		Position = UDim2.fromOffset(inset, TOOLBAR_HEIGHT),
		Size = UDim2.new(1, -inset * 2, 1, -(TOOLBAR_HEIGHT + commandHeight + 6)),

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

	local commandBar = UI.create("Frame", {
		Name = "CommandBar",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, content)

	local submitCommand -- forward declaration

	local commandEditor = CodeEditor.new(commandBar, {
		embedded = true,
		placeholder = "Run a command...  (Ctrl+Enter to run)",
		backgroundTransparency = 0,
		showMinimap = false,
		onSubmit = function()
			submitCommand()
		end,
	})

	local command = commandEditor.TextBox

	UI.corner(command, tokens.radius.sm)
	UI.stroke(command, tokens.color.border, 1, 0)

	local function commandBarHeight()
		if not commandExpanded then
			return COMMANDBAR_COLLAPSED
		end

		local available = content.AbsoluteSize.Y or 0

		local byLines = UI.metrics.inputHeight + COMMAND_LINE_HEIGHT * COMMANDBAR_EXPANDED_LINES
		local byPanel = math.floor(available * COMMANDBAR_MAX_RATIO)

		return math.max(COMMANDBAR_COLLAPSED, math.min(byLines, byPanel))
	end

	local function applyCommandLayout()
		commandHeight = commandBarHeight()

		commandBar.Position = UDim2.new(0, COMMAND_PAD, 1, -commandHeight)
		commandBar.Size = UDim2.new(1, -COMMAND_PAD * 2, 0, commandHeight)

		command.Position = UDim2.fromOffset(EDITOR_PAD, EDITOR_PAD)
		command.Size = UDim2.new(1, -(EDITOR_PAD * 2 + COMMAND_BUTTONS_WIDTH), 1, -EDITOR_PAD * 2)

		pcall(function()
			command.ShowMinimap = commandExpanded
		end)

		scroll.Size = UDim2.new(1, -inset * 2, 1, -(TOOLBAR_HEIGHT + commandHeight + 6))
	end

	local expandIcon = nil

	local function toggleCommandBar()
		commandExpanded = not commandExpanded

		if UI.isAlive(expandIcon) then
			expandIcon.Image = commandExpanded and COLLAPSE_ICON or EXPAND_ICON
		end

		applyCommandLayout()
	end

	local runButton = UI.button(
		commandBar,
		"Run",
		UDim2.new(1, -(COMMAND_PAD + COMMAND_BUTTON + COMMAND_GAP * 2), 1, -(COMMAND_PAD + COMMAND_BUTTON)),
		UDim2.fromOffset(RUN_WIDTH, COMMAND_BUTTON),
		function()
			submitCommand()
		end,
		{
			paddingX = 4,
			color = tokens.color.panelRaised,
			textColor = tokens.color.accent,
		}
	)

	UI.tooltip(runButton, "Run the command buffer (Ctrl+Enter)", { placement = "left" })

	local expandButton

	expandButton, _, expandIcon = UI.iconButton(
		commandBar,
		EXPAND_ICON,
		UDim2.new(1, -(COMMAND_PAD + COMMAND_BUTTON), 1, -(COMMAND_PAD + COMMAND_BUTTON)),
		UDim2.fromOffset(COMMAND_BUTTON, COMMAND_BUTTON),
		toggleCommandBar,
		{ iconSize = 12 }
	)

	UI.tooltip(expandButton, "Expand the command input", { placement = "left" })

	applyCommandLayout()

	local rowCount = 0

	local function passes(entry)
		if activeFilter ~= "All" and entry.kind ~= activeFilter then
			return false
		end

		if searchQuery ~= "" and not string.find(string.lower(entry.message), searchQuery, 1, true) then
			return false
		end

		return true
	end

	local function isNearBottom()
		return scroll.CanvasPosition.Y + scroll.AbsoluteSize.Y >= scroll.CanvasSize.Y.Offset - ROW_HEIGHT * 2
	end

	local function scrollToBottom()
		scroll.CanvasPosition = Vector2.new(0, math.max(0, scroll.CanvasSize.Y.Offset - scroll.AbsoluteSize.Y))
	end

	local function addRow(entry)
		local lines = 1

		for _ in string.gmatch(entry.message, "\n") do
			lines += 1
		end

		local height = math.max(ROW_HEIGHT, lines * 17 + 4)
		local y = 0

		if rowCount > 0 then
			local previousRows = scroll:GetChildren()

			for i = #previousRows, 1, -1 do
				local previous = previousRows[i]

				if previous.Name == "Row" then
					y = previous.Position.Y.Offset + previous.Size.Y.Offset
					break
				end
			end
		end

		local row = UI.button(scroll, "", UDim2.fromOffset(1, y), UDim2.new(1, 0, 0, height), function() end, {
			color = rowCount % 2 == 0 and tokens.color.rowEven or tokens.color.rowOdd,
			hoverColor = colors.hover,
			radius = 0,
			border = false,
		})

		row.Name = "Row"

		UI.image(row, "builtin://global-icons/" .. ({
			Log = "Output.svg",
			Info = "Info.svg",
			Warn = "Warning.svg",
			Error = "Error.svg",
		})[entry.kind], UDim2.fromOffset(6, 3), UDim2.fromOffset(14, 14))

		UI.label(row, entry.time, UDim2.fromOffset(25, 2), UDim2.fromOffset(58, 17), tokens.type.small, colors.subtext)

		UI.label(
			row,
			entry.message,
			UDim2.fromOffset(88, 2),
			UDim2.new(1, -96, 0, height - 4),
			tokens.type.small,
			entry.color
		)

		rowCount += 1

		local canvasHeight = 0
		for _, child in ipairs(scroll:GetChildren()) do
			if child.Name == "Row" then
				canvasHeight = math.max(canvasHeight, child.Position.Y.Offset + child.Size.Y.Offset)
			end
		end

		scroll.CanvasSize = UDim2.fromOffset(0, canvasHeight)
	end

	rebuild = function()
		UI.clear(scroll)
		rowCount = 0

		for _, entry in ipairs(entries) do
			if passes(entry) then
				addRow(entry)
			end
		end

		scrollToBottom()
	end

	local function formatTime(timestamp)
		local ok, text = pcall(function()
			return DateTime.fromUnixTimestamp(timestamp):FormatLocalTime("HH:mm:ss", "en-us")
		end)

		if ok and type(text) == "string" then
			return text
		end

		local seconds = math.floor(tonumber(timestamp) or 0) % 86400

		return string.format("%02d:%02d:%02d", seconds // 3600, (seconds % 3600) // 60, seconds % 60)
	end

	local function formatValue(value, depth, seen)
		depth = depth or 0
		seen = seen or {}

		if depth > 6 then
			return "{ ... }"
		end

		local valueType = typeof(value)

		if valueType == "string" then
			return value
		elseif valueType == "nil" then
			return "nil"
		elseif valueType == "boolean" or valueType == "number" then
			return tostring(value)
		elseif valueType ~= "table" then
			return tostring(value)
		end

		if seen[value] then
			return "<circular>"
		end

		seen[value] = true

		local parts = {}
		local isArray = true
		local length = #value

		for key in pairs(value) do
			if type(key) ~= "number" or key < 1 or key > length or key % 1 ~= 0 then
				isArray = false
				break
			end
		end

		if isArray then
			for i = 1, length do
				parts[#parts + 1] = formatValue(value[i], depth + 1, seen)
			end
		else
			for key, child in pairs(value) do
				local formattedKey

				if type(key) == "string" and string.match(key, "^[%a_][%w_]*$") then
					formattedKey = key
				else
					formattedKey = "[" .. formatValue(key, depth + 1, seen) .. "]"
				end

				parts[#parts + 1] = formattedKey .. " = " .. formatValue(child, depth + 1, seen)
			end

			table.sort(parts)
		end

		seen[value] = nil

		if #parts == 0 then
			return "{}"
		end

		local indent = string.rep("    ", depth)
		local childIndent = string.rep("    ", depth + 1)

		return "{\n" .. childIndent .. table.concat(parts, ",\n" .. childIndent) .. "\n" .. indent .. "}"
	end

	local function makeEntry(item)
		local kind = KIND_COLORS[item.type] and item.type or "Log"

		return {
			message = formatValue(item.message),
			kind = kind,
			color = KIND_COLORS[kind],
			time = formatTime(item.timestamp),
		}
	end

	local function poll()
		local count = LogService.MessageCount

		if count == lastSeenCount then
			return
		end

		if count < lastSeenCount then
			table.clear(entries)
			lastSeenCount = 0
		end

		local history = LogService:GetLogHistory()
		local newCount = math.min(count - lastSeenCount, #history)

		lastSeenCount = count

		if newCount <= 0 then
			return
		end

		local stick = isNearBottom()
		local needsRebuild = false

		for index = #history - newCount + 1, #history do
			local entry = makeEntry(history[index])

			table.insert(entries, entry)

			if #entries > MAX_ENTRIES then
				table.remove(entries, 1)
				needsRebuild = true
			end

			if not needsRebuild and passes(entry) then
				addRow(entry)
			end
		end

		if needsRebuild then
			rebuild()
		elseif stick then
			scrollToBottom()
		end
	end

	local function executeCommand(source)
		-- Echo each line with its own prompt marker so multi-line buffers stay
		-- readable in the log.
		local echoed = string.gsub(source, "\n", "\n> ")

		LogService:Log("> " .. echoed)

		ScriptContext:Run(source, "Console")
	end

	submitCommand = function()
		local source = commandEditor:GetSource()

		source = string.match(source, "^%s*(.-)%s*$") or ""

		commandEditor:setSource("")

		if source == "" then
			return
		end

		if commandHistory[#commandHistory] ~= source then
			table.insert(commandHistory, source)

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

	do
		local ok, UserInputService = pcall(function()
			return game:GetService("UserInputService")
		end)

		if ok and UserInputService then
			UserInputService.InputBegan:Connect(function(input)
				if not command:IsFocused() or #commandHistory == 0 then
					return
				end

				-- The editor owns plain Up/Down for caret movement and
				-- suggestion navigation, so history rides the modifier.
				local control = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
					or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)

				if not control then
					return
				end

				if input.KeyCode == Enum.KeyCode.Up then
					historyIndex = math.max(1, historyIndex - 1)
					commandEditor:setSource(commandHistory[historyIndex] or "")
				elseif input.KeyCode == Enum.KeyCode.Down then
					historyIndex = math.min(#commandHistory + 1, historyIndex + 1)
					commandEditor:setSource(commandHistory[historyIndex] or "")
				end
			end)
		end
	end

	local elapsed = 0
	local lastContentHeight = content.AbsoluteSize.Y

	RunService.Heartbeat:Connect(function(dt)
		if panel == nil then
			return
		end
		if not panel.Visible then
			return
		end

		-- The expanded command bar is sized against the panel, so it has to
		-- follow the console being resized (dimension switches, docking).
		local contentHeight = content.AbsoluteSize.Y

		if contentHeight ~= lastContentHeight then
			lastContentHeight = contentHeight

			if commandExpanded then
				applyCommandLayout()
			end
		end

		elapsed += dt

		if elapsed < POLL_INTERVAL then
			return
		end

		elapsed = 0
		poll()
	end)

	search:GetPropertyChangedSignal("Text"):Connect(function()
		searchQuery = string.lower(search.Text)
		rebuild()
	end)

	do
		lastSeenCount = 0
		poll()
	end

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
}

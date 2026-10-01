local UI = require("@internal/editor_ui")

local ScriptContext = game:GetService("ScriptContext")
local LogService = game:GetService("LogService")
local RunService = game:GetService("RunService")

local colors = UI.tokens.color
local tokens = UI.tokens

local function createConsole()
	local WINDOW_NAME = "Console"
	local MAX_ENTRIES = 1000 -- matches LOG_HISTORY_LIMIT in LogService
	local MAX_COMMAND_HISTORY = 50
	local ROW_HEIGHT = UI.metrics.treeRow
	local TOOLBAR_HEIGHT = 30
	local COMMANDBAR_HEIGHT = 30
	local POLL_INTERVAL = 0.1

	local KIND_COLORS = {
		Log = colors.text,
		Info = Color3.fromRGB(110, 170, 255),
		Warn = colors.warning,
		Error = colors.error,
	}

	local filters = { Log = true, Info = true, Warn = true, Error = true }
	local filterOrder = { "Log", "Info", "Warn", "Error" }

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
	panel.Size = UDim2.new(0.5, 0, 0.4, 0)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Parent = gui

	local BUTTON_WIDTH, BUTTON_GAP, PAD = 52, 4, 6
	local buttonCount = #filterOrder + 1 -- filters + Clear
	local buttonsWidth = buttonCount * BUTTON_WIDTH + (buttonCount - 1) * BUTTON_GAP

	local search = UI.input(
		content,
		"Search...",
		UDim2.fromOffset(PAD, 4),
		UDim2.new(1, -(buttonsWidth + PAD * 3), 0, UI.metrics.inputHeight),
		{ textSize = UI.tokens.type.small }
	)

	local rebuild -- forward declaration

	local function buttonX(index) -- index 1 = leftmost of the right-aligned group
		local fromRight = buttonCount - index
		return UDim2.new(1, -(PAD + BUTTON_WIDTH + fromRight * (BUTTON_WIDTH + BUTTON_GAP)), 0, 4)
	end

	for index, kind in ipairs(filterOrder) do
		local record
		local _, _, created = UI.button(
			content,
			kind,
			buttonX(index),
			UDim2.fromOffset(BUTTON_WIDTH, UI.metrics.buttonHeight),
			function()
				filters[kind] = not filters[kind]
				UI.setButtonState(record, filters[kind] and "selected" or nil)
				rebuild()
			end,
			{ paddingX = 4 }
		)

		record = created
		UI.setButtonState(record, "selected")
	end

	UI.button(
		content,
		"Clear",
		buttonX(buttonCount),
		UDim2.fromOffset(BUTTON_WIDTH, UI.metrics.buttonHeight),
		function()
			table.clear(entries)
			lastSeenCount = LogService.MessageCount
			rebuild()
		end,
		{ paddingX = 4 }
	)

	local scroll = UI.create("ScrollingFrame", {
		Name = "Log",
		Position = UDim2.fromOffset(0, TOOLBAR_HEIGHT),
		Size = UDim2.new(1, 0, 1, -(TOOLBAR_HEIGHT + COMMANDBAR_HEIGHT)),
		BackgroundColor3 = tokens.color.rowOdd,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = colors.subtext,
		ScrollBarImageTransparency = 0.4,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ClipsDescendants = true,
	}, content)

	local command = UI.input(
		content,
		"Run a command...",
		UDim2.new(0, PAD, 1, -(COMMANDBAR_HEIGHT - 3)),
		UDim2.new(1, -PAD * 2, 0, UI.metrics.inputHeight),
		{
			textSize = UI.tokens.type.small,
			maxLength = 1000,
			focusColor = colors.accent,
		}
	)

	local rowCount = 0

	local function passes(entry)
		if not filters[entry.kind] then
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
		local row = UI.button(
			scroll,
			"",
			UDim2.fromOffset(1, rowCount * ROW_HEIGHT),
			UDim2.new(1, -2, 0, ROW_HEIGHT),
			function()
				-- Optional: select/copy the log entry later
			end,
			{
				color = rowCount % 2 == 0 and tokens.color.rowEven or tokens.color.rowOdd,
				hoverColor = colors.hover,
				radius = 0,
				border = false,
			}
		)

		row.Name = "Row"

		UI.image(row, "builtin://global-icons/" .. ({
			Log = "Output.svg",
			Info = "Info.svg",
			Warn = "Warning.svg",
			Error = "Error.svg",
		})[entry.kind], UDim2.fromOffset(6, 3), UDim2.fromOffset(14, 14))

		UI.label(row, entry.time, UDim2.fromOffset(25, 2), UDim2.fromOffset(58, 17), tokens.type.small, colors.subtext)

		UI.label(row, entry.message, UDim2.fromOffset(88, 2), UDim2.new(1, -96, 0, 17), tokens.type.small, entry.color)

		rowCount += 1
		scroll.CanvasSize = UDim2.new(0, 0, 0, rowCount * ROW_HEIGHT)
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
		-- Prefer DateTime (local time) when the environment provides it.
		local ok, text = pcall(function()
			return DateTime.fromUnixTimestamp(timestamp):FormatLocalTime("HH:mm:ss", "en-us")
		end)

		if ok and type(text) == "string" then
			return text
		end

		local seconds = math.floor(tonumber(timestamp) or 0) % 86400

		return string.format("%02d:%02d:%02d", seconds // 3600, (seconds % 3600) // 60, seconds % 60)
	end

	local function makeEntry(item)
		local kind = KIND_COLORS[item.type] and item.type or "Log"

		return {
			message = tostring(item.message),
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

		-- Counter went backwards: someone called LogService:Clear()
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

		-- Don't stack identical consecutive entries in the command history
		if commandHistory[#commandHistory] ~= source then
			table.insert(commandHistory, source)

			if #commandHistory > MAX_COMMAND_HISTORY then
				table.remove(commandHistory, 1)
			end
		end

		historyIndex = #commandHistory + 1

		executeCommand(source)

		-- Keep typing without clicking again
		pcall(function()
			command:CaptureFocus()
		end)
	end

	command.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			submitCommand()
		end
	end)

	-- Up/Down arrows cycle through previous commands (skipped if UserInputService
	-- isn't available in this environment).
	do
		local ok, UserInputService = pcall(function()
			return game:GetService("UserInputService")
		end)

		if ok and UserInputService then
			UserInputService.InputBegan:Connect(function(input)
				if not command:IsFocused() or #commandHistory == 0 then
					return
				end

				if input.KeyCode == Enum.KeyCode.Up then
					historyIndex = math.max(1, historyIndex - 1)
					command.Text = commandHistory[historyIndex] or ""
				elseif input.KeyCode == Enum.KeyCode.Down then
					historyIndex = math.min(#commandHistory + 1, historyIndex + 1)
					command.Text = commandHistory[historyIndex] or ""
				end
			end)
		end
	end

	----------------------------------------------------------------
	-- Wiring
	----------------------------------------------------------------

	local elapsed = 0

	RunService.Heartbeat:Connect(function(dt)
		if not panel.Visible then
			return
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
	createConsole()
end

return {
	createConsole = createConsole,
}

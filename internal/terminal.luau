if IsServer or IsClient or IsPlaytest then
	return nil
end

local UI = require("@internal/editor_ui")
local History = require("@internal/terminal_history")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local ThemeService = game:GetService("StudioThemeService")
local UserInputService = game:GetService("UserInputService")
local available, service = pcall(function()
	return game:GetService("TerminalService")
end)

local Terminal = {}
local tokens = UI.tokens
local colors = tokens.color
local metrics = UI.metrics
local FONT = "builtin://fonts/RobotoMono-Regular.ttf"
local mono = Font.new(FONT, Enum.FontWeight.Regular, Enum.FontStyle.Normal)
local INSET = metrics.panelInset
local TAB_HEIGHT = metrics.tabHeight
local BUTTON_HEIGHT = metrics.buttonHeight
local STATUS_HEIGHT = metrics.propertyRow
local measuredSize, measuredHeight
local function rowHeight()
	if measuredSize ~= tokens.type.body then
		measuredSize = tokens.type.body
		measuredHeight = math.ceil(TextService:GetLineHeight(measuredSize, FONT))
	end
	return math.max(measuredSize + tokens.space.sm, measuredHeight)
end
local MAX_OUTPUT = 48000
local sessions = {}
local active = 0
local opened = false
local progress = 0
local elapsed = 0
local panel, body, input, prompt, scroll, status, tabStrip, tabContainer, tabController
local historyView, copyMenu
local fitting = false
local promptStrip, pathBadge, pathLabel, pathIcon, timeBadge, timeLabel, timeIcon, promptArrow
local windowOptions
local floatingPosition
local wasDocked = false
local function docked()
	local slots = ThemeService.SelectedTheme.DockedWindows
	return slots and slots.Terminal ~= nil
end

local function terminalColor()
	local canvas = colors.canvas
	if canvas.R + canvas.G + canvas.B < 1.5 then
		return canvas:Lerp(Color3.new(0, 0, 0), 0.28)
	end
	return canvas
end

local function badgeInk(fill)
	if fill.R * 0.2126 + fill.G * 0.7152 + fill.B * 0.0722 > 0.52 then
		return Color3.fromRGB(20, 20, 20)
	end
	return Color3.fromRGB(245, 245, 245)
end

local function shortPath(path, home)
	if home and home ~= "" and (path == home or path:sub(1, #home + 1) == home .. "/") then
		return "~" .. path:sub(#home + 1)
	end
	return path
end

local PROMPT_PATTERN = "__KINE_PROMPT__(%d+):([^\n]-)__KINE_HOME__([^\n]-)__KINE_END__ %$ "
local function plainHistory(text)
	return (text:gsub(PROMPT_PATTERN, function(_, path, home)
		return shortPath(path, home) .. " $ "
	end))
end

local function refreshPromptStyle()
	local success, warning = colors.success, colors.warning
	pathBadge.BackgroundColor3 = success
	pathLabel.TextColor3 = badgeInk(success)
	pathIcon.ImageColor3 = badgeInk(success)
	timeBadge.BackgroundColor3 = warning
	timeLabel.TextColor3 = badgeInk(warning)
	timeIcon.ImageColor3 = badgeInk(warning)
end
local measuredPrompt, measuredPromptSize, measuredPromptWidth
local lastPromptBounds
local tabsDirty = true
local tabWidth = 0
local setOpen, selectSession, newSession, closeSession
local connections = {}

local function connect(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(connections, connection)
	return connection
end

local function appendOutput(session, chunk)
	local parts = {}
	local state = session.escape or "text"
	for i = 1, #chunk do
		local b = chunk:byte(i)
		if state == "text" then
			if b == 27 then
				state = "escape"
			elseif b == 13 then
				table.insert(parts, "\r")
			elseif b == 10 or b == 9 or (b >= 32 and b ~= 127) then
				table.insert(parts, chunk:sub(i, i))
			end
		elseif state == "escape" then
			if b == 91 then
				state = "csi"
			elseif b == 93 or b == 80 or b == 95 or b == 94 then
				state = "string"
			else
				state = "text"
			end
		elseif state == "csi" then
			if b >= 64 and b <= 126 then
				state = "text"
			end
		elseif state == "string" then
			if b == 7 then
				state = "text"
			elseif b == 27 then
				state = "stringEscape"
			end
		elseif state == "stringEscape" then
			state = b == 92 and "text" or "string"
		end
	end
	session.escape = state
	local raw = (session.text .. table.concat(parts)):gsub("\r\n", "\n")
	raw = raw:gsub("\r([^\n])", "\n%1")
	if #raw > MAX_OUTPUT then
		local start = #raw - MAX_OUTPUT + 1
		while start <= #raw and raw:byte(start) >= 128 and raw:byte(start) < 192 do
			start += 1
		end
		session.offset = (session.offset or 0) + start - 1
		for key in session.promptTimes do
			if key <= session.offset then session.promptTimes[key] = nil end
		end
		raw = raw:sub(start)
	end
	session.text = raw
end

local function setStatus(message, failed)
	status.Text = message
	status.TextColor3 = failed and colors.error or colors.muted
end

local function repaint()
	local session = sessions[active]
	local text = session and session.text or "No terminal session. Use New Terminal to start a shell."
	local lastLine = text:match("([^\n]*)$") or ""
	local code, path, home = lastLine:match("^" .. PROMPT_PATTERN .. "$")
	if not path and session and session.shell == "cmd" then
		path = lastLine:match("^([%a]:[^\n]*)>%s*$")
	end
	local styled = session ~= nil and session.running and path ~= nil
	promptStrip.Visible = styled
	promptArrow.Visible = styled
	if styled then
		pathLabel.Text = shortPath(path, home)
		timeLabel.Text = string.format("%.1fs", session.duration or 0)
		promptArrow.ImageColor3 = code and tonumber(code) ~= 0 and colors.error or colors.accent
	end
	if session and session.running then
		local history = text:sub(1, #text - #lastLine)
		historyView:setText(history:sub(1, -2), session.promptTimes, session.offset, session.shell)
		prompt.Text = styled and "" or plainHistory(lastLine)
	else
		historyView:setText(text, session and session.promptTimes, session and session.offset, session and session.shell)
		prompt.Text = ""
	end
	input.Visible = session ~= nil and session.running
	input.TextEditable = input.Visible
	prompt.Visible = input.Visible and not styled
	if session then
		setStatus(session.running and "Local " .. session.shell .. " running" or "Local " .. session.shell .. " exited")
	else
		setStatus("Terminal")
	end
end

local function fitOutput(follow)
	if fitting or not scroll then
		return
	end
	fitting = true
	local previousEnd = math.max(0, scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteWindowSize.Y)
	local atBottom = scroll.CanvasPosition.Y >= previousEnd - rowHeight() * 3
	local width = math.max(1, scroll.AbsoluteSize.X - INSET * 2 - scroll.ScrollBarThickness)
	local lineHeight = rowHeight()
	local historyHeight = historyView:layout(width, lineHeight)
	local y = INSET + historyHeight
	if measuredPrompt ~= prompt.Text or measuredPromptSize ~= tokens.type.body then
		measuredPrompt = prompt.Text
		measuredPromptSize = tokens.type.body
		measuredPromptWidth = TextService:GetTextWidth(measuredPrompt, measuredPromptSize, FONT)
	end
	local promptWidth = measuredPromptWidth
	local available = width - promptWidth
	if promptStrip.Visible then
		local badgeHeight = lineHeight
		local iconSize = tokens.type.caption
		local padding = tokens.space.sm
		local timeWidth = math.ceil(TextService:GetTextWidth(timeLabel.Text, tokens.type.caption, FONT))
			+ iconSize
			+ padding * 3
		local pathWidth = math.min(
			math.max(1, width - timeWidth - padding),
			math.ceil(TextService:GetTextWidth(pathLabel.Text, tokens.type.caption, FONT)) + iconSize + padding * 3
		)
		promptStrip.Position = UDim2.fromOffset(INSET, y)
		promptStrip.Size = UDim2.fromOffset(width, badgeHeight)
		timeBadge.Size = UDim2.fromOffset(timeWidth, badgeHeight)
		pathBadge.Position = UDim2.fromOffset(timeWidth + padding, 0)
		pathBadge.Size = UDim2.fromOffset(pathWidth, badgeHeight)
		y += badgeHeight + tokens.space.xs
		promptArrow.Position = UDim2.fromOffset(INSET, y + math.floor((lineHeight - iconSize) / 2))
		promptWidth = iconSize + padding
	elseif input.Visible and available < lineHeight * 3 then
		prompt.TextWrapped = true
		if prompt.Size.X.Offset ~= width then
			prompt.Size = UDim2.fromOffset(width, lineHeight)
		end
		local height = math.max(lineHeight, math.ceil(prompt.TextBounds.Y))
		prompt.Size = UDim2.fromOffset(width, height)
		prompt.Position = UDim2.fromOffset(INSET, y)
		y += height
		promptWidth = 0
	else
		prompt.TextWrapped = false
		prompt.Position = UDim2.fromOffset(INSET, y)
		prompt.Size = UDim2.fromOffset(math.max(1, promptWidth), lineHeight)
	end
	input.Position = UDim2.fromOffset(INSET + promptWidth, y)
	input.Size = UDim2.fromOffset(math.max(1, width - promptWidth), lineHeight)
	local height = math.max(scroll.AbsoluteSize.Y, y + (input.Visible and lineHeight or 0) + INSET)
	scroll.CanvasSize = UDim2.new(1, 0, 0, height)
	if follow or (atBottom and not historyView.dragging and not historyView:hasSelection()) then
		scroll.CanvasPosition = Vector2.new(0, math.max(0, scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteWindowSize.Y))
	end
	historyView:render()
	lastPromptBounds = prompt.TextBounds
	fitting = false
end

local function tabs()
	if not tabStrip then
		return
	end
	local width = math.clamp(
		math.floor((tabStrip.AbsoluteSize.X - tokens.space.sm) / math.max(1, #sessions)) - tokens.space.xs,
		48,
		116
	)
	if not tabsDirty and width == tabWidth then
		return
	end
	tabWidth = width
	tabsDirty = false
	if tabContainer then
		UI.forgetButtons(tabContainer)
		tabContainer:Destroy()
		tabContainer = nil
		tabController = nil
	end
	if #sessions == 0 then
		return
	end
	local definitions = {}
	for _, session in sessions do
		table.insert(
			definitions,
			{ name = tostring(session.id), text = session.shell .. " " .. tostring(session.id), width = width }
		)
	end
	local selected = sessions[active]
	local rebuilding = true
	tabContainer, tabController = UI.tabs(tabStrip, UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), {
		tabs = definitions,
		selectedTab = selected and tostring(selected.id) or nil,
		startX = tokens.space.xs,
		barHeight = TAB_HEIGHT,
		tabTop = tokens.space.xs,
		tabGap = tokens.space.xs,
		barColor = body.BackgroundColor3,
		contentColor = body.BackgroundColor3,
		activeTabColor = body.BackgroundColor3,
		inactiveTabColor = body.BackgroundColor3,
		tabAccentColor = colors.accent,
		tabPaddingX = tokens.space.xs,
		onTabChanged = function(name)
			if rebuilding then
				return
			end
			for index, session in sessions do
				if tostring(session.id) == name then
					selectSession(index, true)
					break
				end
			end
		end,
	})
	tabContainer.BackgroundTransparency = 1
	tabController.bar.BackgroundTransparency = 1
	tabController.content.Visible = false
	rebuilding = false
end

local function focusTerminal()
	if not panel or not opened or not input.TextEditable then
		return
	end
	if not input:IsFocused() then
		input:CaptureFocus()
	end
end

selectSession = function(index, fromTabs)
	historyView:clearSelection()
	local previous = sessions[active]
	if previous then
		previous.draft = input.Text
	end
	active = index
	local session = sessions[active]
	input.Text = session and session.draft or ""
	tabs()
	if not fromTabs and tabController and session then
		tabController.selectTab(tostring(session.id))
	end
	repaint()
	fitOutput(true)
	focusTerminal()
end

newSession = function()
	if not available or not service then
		setStatus("TerminalService is unavailable in this engine build", true)
		return
	end
	local directory
	pcall(function()
		local project = game:GetService("Project"):GetActiveProject()
		if project then
			directory = project.Path
		end
	end)
	local ok, id = pcall(function()
		return service:CreateTerminal(directory, true)
	end)
	if not ok then
		setStatus(tostring(id), true)
		return
	end
	local shell = service:GetShellName(id)
	table.insert(
		sessions,
		{ id = id, shell = shell, text = "", running = true, historyIndex = nil, draft = "", duration = 0, promptTimes = {}, offset = 0 }
	)
	tabsDirty = true
	selectSession(#sessions)
end

closeSession = function()
	local session = sessions[active]
	if not session then
		return
	end
	local ok, err = pcall(function()
		service:CloseTerminal(session.id)
	end)
	if not ok then
		setStatus(tostring(err), true)
		return
	end
	table.remove(sessions, active)
	tabsDirty = true
	local nextIndex = math.min(active, #sessions)
	active = 0
	selectSession(nextIndex)
end

local function submit()
	local session = sessions[active]
	local command = input.Text
	if not session or not session.running then
		return
	end
	local ok, accepted = pcall(function()
		if command == "" then
			return service:WriteInput(session.id, string.char(13))
		end
		return service:Execute(session.id, command)
	end)
	if not ok or not accepted then
		setStatus(ok and "Input queue is busy; retry" or tostring(accepted), true)
		return
	end
	session.commandStarted = os.clock()
	fitOutput(true)
	input.Text = ""
	session.historyIndex = nil
	session.draft = ""
end

local function historyMove(session, delta)
	local ok, history = pcall(function()
		return service:GetHistory(session.id)
	end)
	if not ok or #history == 0 then
		return
	end
	if not session.historyIndex then
		session.historyIndex = #history + 1
		session.draft = input.Text
	end
	session.historyIndex = math.clamp(session.historyIndex + delta, 1, #history + 1)
	input.Text = history[session.historyIndex] or session.draft
	input.CursorPosition = (utf8.len(input.Text) or #input.Text) + 1
end

local function build()
	floatingPosition = UDim2.new(0.09, 0, 0.50, -20)
	windowOptions = {
		closable = true,
		closeIcon = "builtin://global-icons/x.svg",
		draggable = true,
		dockable = true,
		resizable = true,
		minSize = Vector2.new(280, 160),
		contentColor = terminalColor(),
		activeTabColor = terminalColor(),
		backgroundImage = "",
		onClose = function()
			setOpen(false)
		end,
	}
	local header, controls
	panel, body, header, controls =
		UI.window("Terminal", floatingPosition, UDim2.new(0.82, 0, 0.49, 0), "Terminal", windowOptions)
	panel.AnchorPoint = Vector2.new(0, 0)
	panel.Parent = UI.widgetOverlay()
	UI.tooltip(controls.closeButton, "Hide Terminal")
	panel.Visible = false
	tabStrip = UI.frame(
		body,
		UDim2.fromOffset(INSET, tokens.space.xs),
		UDim2.new(1, -(INSET * 3 + BUTTON_HEIGHT * 2 + tokens.space.sm), 0, TAB_HEIGHT),
		colors.panel
	)
	tabStrip.BackgroundTransparency = 1
	tabStrip.ClipsDescendants = true
	local options = { iconSize = 14, color = colors.panel, border = false }
	local add = UI.iconButton(
		body,
		"builtin://global-icons/plus.svg",
		UDim2.new(1, -(INSET + BUTTON_HEIGHT * 2 + tokens.space.xs), 0, tokens.space.xs),
		UDim2.fromOffset(BUTTON_HEIGHT, BUTTON_HEIGHT),
		newSession,
		options
	)
	UI.tooltip(add, "New Terminal", { placement = "below" })
	local close = UI.iconButton(
		body,
		"builtin://global-icons/x.svg",
		UDim2.new(1, -(INSET + BUTTON_HEIGHT), 0, tokens.space.xs),
		UDim2.fromOffset(BUTTON_HEIGHT, BUTTON_HEIGHT),
		closeSession,
		options
	)
	UI.tooltip(close, "Close current terminal", { placement = "below" })
	local top = TAB_HEIGHT + tokens.space.sm
	UI.separator(body, UDim2.fromOffset(INSET, top), UDim2.new(1, -INSET * 2, 0, 1), colors.border)
	scroll = UI.create("ScrollingFrame", {
		Name = "TerminalViewport",
		Position = UDim2.fromOffset(INSET, top + tokens.space.xs),
		Size = UDim2.new(1, -INSET * 2, 1, -(top + tokens.space.xs + STATUS_HEIGHT + INSET)),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasPosition = Vector2.new(0, 0),
		CanvasSize = UDim2.new(1, 0, 0, 0),
		ScrollingEnabled = true,
		ScrollSpeed = 38,
		SmoothScrollingEnabled = not UI.shared().reduceMotion,
		ScrollSmoothness = 18,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = colors.subtext,
		ScrollBarImageTransparency = 0.4,
		ScrollBarAutoHide = true,
		ScrollBarFadeDelay = 0.45,
		ScrollBarFadeSpeed = 12,
		ScrollBarMinimumHandleSize = 24,
		ClipsDescendants = true,
		Active = true,
		InputSink = true,
	}, body)
	historyView = History.new(scroll, INSET)
	copyMenu = UI.contextMenu(UI.contextMenuOverlay(), "", UDim2.fromOffset(-400, -400), UDim2.fromOffset(1, 1), nil, {
		items = {
			{label = "Copy", value = "copy", shortcut = "Ctrl+C", icon = "builtin://global-icons/copy.svg"},
		},
		menuWidth = 160,
		onChanged = function(action)
			if action == "copy" then historyView:copy() end
		end,
	})
	prompt = UI.label(
		scroll,
		"",
		UDim2.fromOffset(INSET, INSET),
		UDim2.fromOffset(1, rowHeight()),
		tokens.type.body,
		colors.text
	)
	prompt.Name = "TerminalPrompt"
	prompt.FontFace = mono
	prompt.RichText = false
	prompt.TextYAlignment = Enum.TextYAlignment.Center
	promptStrip =
		UI.frame(scroll, UDim2.fromOffset(INSET, INSET), UDim2.new(1, -INSET * 2, 0, rowHeight()), colors.panel)
	promptStrip.Name = "TerminalPromptStrip"
	promptStrip.BackgroundTransparency = 1
	promptStrip.Visible = false
	local iconSize = tokens.type.caption
	local pad = tokens.space.sm
	local function segment(name, icon, fill)
		local badge, label = UI.badge(promptStrip, "", UDim2.fromOffset(0, 0), {
			height = rowHeight(),
			color = fill,
			textColor = badgeInk(fill),
			textSize = tokens.type.caption,
		})
		badge.Name = name
		label.FontFace = mono
		label.Position = UDim2.fromOffset(iconSize + pad * 2, 0)
		label.Size = UDim2.new(1, -(iconSize + pad * 3), 1, 0)
		label.TextTruncate = Enum.TextTruncate.AtEnd
		local image = UI.image(
			badge,
			icon,
			UDim2.fromOffset(pad, math.floor((rowHeight() - iconSize) / 2)),
			UDim2.fromOffset(iconSize, iconSize)
		)
		image.ImageColor3 = badgeInk(fill)
		return badge, label, image
	end
	timeBadge, timeLabel, timeIcon = segment("CommandDuration", "builtin://global-icons/clock.svg", colors.warning)
	pathBadge, pathLabel, pathIcon = segment("WorkingDirectory", "builtin://icons/Folder.svg", colors.success)
	promptArrow = UI.image(
		scroll,
		"builtin://icons/ArrowRight.svg",
		UDim2.fromOffset(INSET, INSET),
		UDim2.fromOffset(iconSize, iconSize)
	)
	promptArrow.Name = "TerminalPromptArrow"
	promptArrow.ImageColor3 = colors.accent
	promptArrow.Visible = false
	input = UI.input(scroll, "", UDim2.fromOffset(INSET, INSET), UDim2.new(1, -INSET * 2, 0, rowHeight()), {
		textSize = tokens.type.body,
		textColor = colors.text,
		caretColor = colors.text,
		selectionColor = colors.selection,
		strokeTransparency = 1,
		focusTransparency = 1,
		animate = false,
		maxLength = 8190,
	})
	input.Name = "TerminalInput"
	input.FontFace = mono
	input.BackgroundTransparency = 1
	input.TextXAlignment = Enum.TextXAlignment.Left
	input.TextYAlignment = Enum.TextYAlignment.Center
	input.MultiLine = false
	input.TextPadding = 0
	input.BlockCaret = false
	input.SmoothCaret = not UI.shared().reduceMotion
	input.FocusIndicatorVisible = false
	status = UI.label(
		body,
		"Terminal",
		UDim2.new(0, INSET, 1, -STATUS_HEIGHT),
		UDim2.new(1, -INSET * 2, 0, STATUS_HEIGHT),
		tokens.type.caption,
		colors.muted
	)
	status.Name = "TerminalStatus"
	UI.separator(body, UDim2.new(0, INSET, 1, -STATUS_HEIGHT), UDim2.new(1, -INSET * 2, 0, 1), colors.border)

	connect(input.TextChanged, function()
		if opened and input:IsFocused() then
			historyView:clearSelection()
			fitOutput(true)
		end
	end)
	connect(input.FocusLost, function(enterPressed)
		if not enterPressed then
			return
		end
		submit()
		task.defer(function()
			if panel and opened and input.TextEditable then
				input:CaptureFocus()
			end
		end)
	end)
	connect(prompt:GetPropertyChangedSignal("TextBounds"), function()
		fitOutput(false)
	end)
	connect(scroll:GetPropertyChangedSignal("AbsoluteSize"), function()
		fitOutput(false)
	end)
	connect(tabStrip:GetPropertyChangedSignal("AbsoluteSize"), tabs)
	local themeConnection = UI.onThemeChanged(function()
		if not panel then
			return
		end
		historyView:themeChanged()
		prompt.FontFace = mono
		input.FontFace = mono
		prompt.TextSize = tokens.type.body
		input.TextSize = tokens.type.body
		windowOptions.contentColor = terminalColor()
		windowOptions.activeTabColor = windowOptions.contentColor
		UI.refreshWindow("Terminal")
		refreshPromptStyle()
		if tabController then
			local fill = body.BackgroundColor3
			tabController.setColors({
				bar = fill,
				content = fill,
				activeTab = fill,
				inactiveTab = fill,
				hover = colors.hover,
				pressed = colors.pressed,
				activeText = colors.text,
				inactiveText = colors.muted,
				accent = colors.accent,
			})
		end
		fitOutput(false)
	end)
	table.insert(connections, themeConnection)
	connect(UserInputService.InputBegan, function(event)
		if not opened or not panel.Visible then return end
		local kind = event.UserInputType
		local point = UserInputService:GetMouseLocation()
		if kind == Enum.UserInputType.MouseButton1 then
			if copyMenu:IsOpen() then return end
			if UI.pointInside(scroll, point) and point.X < scroll.AbsolutePosition.X + scroll.AbsoluteSize.X - scroll.ScrollBarThickness then
				if historyView:contains(point) then
					input:ReleaseFocus()
					historyView:begin(point)
					historyView:render()
				else
					historyView:clearSelection()
					if not UI.pointInside(input, point) then task.defer(focusTerminal) end
				end
			else
				historyView:clearSelection()
			end
		elseif kind == Enum.UserInputType.MouseButton2 and historyView:contains(point) and historyView:hasSelection() then
			copyMenu:Open(UDim2.fromOffset(point.X, point.Y))
		elseif kind == Enum.UserInputType.Keyboard and historyView:hasSelection() then
			local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
			if ctrl and event.KeyCode == Enum.KeyCode.C then
				local focused = UserInputService:GetFocusedTextBox()
				if not focused then historyView:copy() end
			end
		end
	end)
	connect(UserInputService.InputChanged, function(event)
		if opened and event.UserInputType == Enum.UserInputType.MouseMovement and historyView.dragging then
			historyView:move(UserInputService:GetMouseLocation())
			historyView:render()
		end
	end)
	connect(UserInputService.InputEnded, function(event)
		if event.UserInputType == Enum.UserInputType.MouseButton1 and historyView.dragging then
			historyView:move(UserInputService:GetMouseLocation())
			historyView.dragging = false
			if not historyView:hasSelection() then task.defer(focusTerminal) end
			historyView:render()
		end
	end)
	connect(input.KeyDown, function(event)
		if not opened or not input:IsFocused() then
			return
		end
		local session = sessions[active]
		if not session or not session.running then
			return
		end
		local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
		if ctrl and event.KeyCode == Enum.KeyCode.C and input.SelectionStart == input.SelectionEnd then
			input.KeyHandled = true
			local ok, accepted = pcall(function()
				return service:WriteInput(session.id, string.char(3))
			end)
			if ok and accepted then
				input.Text = ""
				session.historyIndex = nil
				session.draft = ""
			end
		elseif ctrl and event.KeyCode == Enum.KeyCode.D and input.Text == "" then
			input.KeyHandled = true
			pcall(function()
				service:WriteInput(session.id, string.char(4))
			end)
		elseif event.KeyCode == Enum.KeyCode.Up then
			input.KeyHandled = true
			historyMove(session, -1)
		elseif event.KeyCode == Enum.KeyCode.Down then
			input.KeyHandled = true
			historyMove(session, 1)
		end
	end)
	connect(RunService.Heartbeat, function(dt)
		if panel.Visible then
			if prompt.TextBounds ~= lastPromptBounds then
				fitOutput(false)
			end
			if historyView.dragging then
				local point = UserInputService:GetMouseLocation()
				local top = scroll.AbsolutePosition.Y
				local bottom = top + scroll.AbsoluteWindowSize.Y
				local delta = point.Y < top and point.Y - top or (point.Y > bottom and point.Y - bottom or 0)
				if delta ~= 0 then
					scroll.CanvasPosition = Vector2.new(0, scroll.CanvasPosition.Y + math.clamp(delta * 9, -900, 900) * dt)
					historyView:move(point)
				end
			end
			historyView:render()
			local smooth = not UI.shared().reduceMotion
			if input.SmoothCaret ~= smooth then
				input.SmoothCaret = smooth
			end
			if scroll.SmoothScrollingEnabled ~= smooth then
				scroll.SmoothScrollingEnabled = smooth
			end
		end
		local target = opened and 1 or 0
		local inLayout = docked()
		if inLayout then
			wasDocked = true
		end
		if panel:GetAttribute("Dragging") == true or inLayout then
			progress = target
			if not opened then
				panel.Visible = false
			end
		elseif progress ~= target then
			if UI.shared().reduceMotion then
				progress = target
			else
				progress = math.clamp(progress + (opened and 1 or -1) * dt * 7, 0, 1)
			end
			local eased = 1 - (1 - progress) ^ 3
			local position = floatingPosition
			panel.Position =
				UDim2.new(position.X.Scale, position.X.Offset, position.Y.Scale, position.Y.Offset + (1 - eased) * 30)
			if progress == 0 and not opened then
				panel.Visible = false
				panel.Position = position
			end
		elseif opened and not inLayout then
			floatingPosition = panel.Position
			wasDocked = false
		end
		elapsed += dt
		if elapsed < 0.05 then
			return
		end
		elapsed = 0
		for index, session in sessions do
			if not session.drained then
				local ok, chunk, running = pcall(function()
					return service:ReadOutput(session.id), service:IsRunning(session.id)
				end)
				if ok then
					if chunk ~= "" then
						appendOutput(session, chunk)
						if
							session.commandStarted
							and (
								session.text:match(PROMPT_PATTERN .. "$")
								or (session.shell == "cmd" and session.text:match("[%a]:[^\n]*>%s*$"))
							)
						then
							session.duration = math.max(0, os.clock() - session.commandStarted)
							session.commandStarted = nil
						end
						local lastLine = session.text:match("([^\n]*)$") or ""
						if lastLine:match("^" .. PROMPT_PATTERN .. "$") then
							local key = session.offset + #session.text - #lastLine + 1
							session.promptTimes[key] = session.duration
						end
					end
					local changed = session.running ~= running
					session.running = running
					if not running and chunk == "" then
						session.drained = true
						local codeOK, code = pcall(function()
							return service:GetExitCode(session.id)
						end)
						appendOutput(session, "\n[Shell exited: " .. (codeOK and tostring(code) or "?") .. "]\n")
					end
					if opened and index == active and (chunk ~= "" or changed or session.drained) then
						repaint()
						fitOutput(false)
					end
				else
					session.running = false
					session.drained = true
					appendOutput(session, "\n" .. tostring(chunk))
					if opened and index == active then
						repaint()
						fitOutput(false)
					end
				end
			end
		end
	end)
	panel.Destroying:Connect(function()
		for _, session in sessions do
			pcall(function()
				service:CloseTerminal(session.id)
			end)
		end
		table.clear(sessions)
		UI.forgetButtons(body)
		tabContainer = nil
		tabController = nil
		tabsDirty = true
		lastPromptBounds = nil
		copyMenu:Destroy()
		historyView, copyMenu = nil, nil
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		panel = nil
		opened = false
		progress = 0
		wasDocked = false
		active = 0
	end)
	repaint()
end

setOpen = function(value)
	if not panel then
		build()
	end
	local inLayout = docked() or wasDocked
	opened = value
	if value then
		if inLayout then
			progress = 1
		elseif progress == 0 then
			panel.Position = floatingPosition
		end
		panel.Visible = true
		repaint()
		fitOutput(true)
		focusTerminal()
		newSession()
	else
		input:ReleaseFocus()
		historyView:clearSelection()
		copyMenu:Close()
		if inLayout or panel:GetAttribute("Dragging") == true or UI.shared().reduceMotion then
			progress = 0
			panel.Visible = false
		elseif progress == 1 then
			floatingPosition = panel.Position
		end
	end
end

function Terminal.Toggle()
	setOpen(not opened)
end

return Terminal

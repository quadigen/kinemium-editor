if IsServer or IsClient or IsPlaytest then
	return nil
end

local UI = require("@internal/editor_ui")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local available, service = pcall(function()
	return game:GetService("TerminalService")
end)

local Terminal = {}
local C = {
	bg = Color3.fromRGB(17, 19, 25),
	bar = Color3.fromRGB(30, 33, 42),
	text = Color3.fromRGB(220, 225, 237),
	dim = Color3.fromRGB(143, 153, 174),
	accent = Color3.fromRGB(148, 226, 190),
	error = Color3.fromRGB(243, 139, 168),
}
local mono = Font.new("builtin://fonts/RobotoMono-Regular.ttf", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
local MAX_OUTPUT = 48000
local sessions = {}
local active = 0
local opened = false
local progress = 0
local elapsed = 0
local panel, body, input, output, scroll, status, tabStrip
local setOpen, selectSession, newSession, closeSession
local connections = {}

local function connect(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(connections, connection)
	return connection
end

local function textProps(text, position, size)
	return {
		Text = text,
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		TextSize = 13,
		TextColor3 = C.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		RichText = false,
		BorderSizePixel = 0,
		FontFace = mono,
	}
end

local function button(parent, text, position, size, callback)
	local props = textProps(text, position, size)
	props.BackgroundTransparency = 0
	props.BackgroundColor3 = C.bar
	props.TextXAlignment = Enum.TextXAlignment.Center
	local item = UI.create("TextButton", props, parent)
	item.MouseButton1Click:Connect(callback)
	return item
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
		raw = raw:sub(start)
	end
	session.text = raw
end

local function setStatus(message, failed)
	status.Text = "  " .. message
	status.TextColor3 = failed and C.error or C.dim
end

local function repaint()
	local session = sessions[active]
	output.Text = session and session.text or "No terminal session. Select + to create one."
	input.TextEditable = session ~= nil and session.running
	if session then
		setStatus(session.running and "LOCAL SHELL  ·  RUNNING" or "LOCAL SHELL  ·  EXITED")
	else
		setStatus("TERMINAL")
	end
end

local function fitOutput(follow)
	local previousEnd = math.max(0, scroll.CanvasSize.Y.Offset - scroll.AbsoluteSize.Y)
	local atBottom = scroll.CanvasPosition.Y >= previousEnd - 24
	local height = math.max(scroll.AbsoluteSize.Y, output.TextBounds.Y + 16)
	local size = UDim2.new(1, -18, 0, height)
	if output.Size ~= size then
		output.Size = size
	end
	scroll.CanvasSize = UDim2.new(1, 0, 0, height)
	if follow or atBottom then
		scroll.CanvasPosition = Vector2.new(0, math.max(0, height - scroll.AbsoluteSize.Y))
	end
end

local function tabs()
	for _, child in tabStrip:GetChildren() do
		child:Destroy()
	end
	local width = math.clamp(math.floor((tabStrip.AbsoluteSize.X - 4) / math.max(1, #sessions)), 44, 100)
	for index, session in sessions do
		local i = index
		local tab = button(
			tabStrip,
			"shell " .. tostring(session.id),
			UDim2.fromOffset((index - 1) * width, 0),
			UDim2.fromOffset(width - 2, 26),
			function()
				selectSession(i)
			end
		)
		tab.TextColor3 = index == active and C.accent or C.dim
	end
end

selectSession = function(index)
	local previous = sessions[active]
	if previous then
		previous.draft = input.Text
	end
	active = index
	local session = sessions[active]
	input.Text = session and session.draft or ""
	tabs()
	repaint()
	fitOutput(true)
end

newSession = function()
	if not available or not service then
		setStatus("TerminalService is unavailable in this engine build", true)
		return
	end
	local ok, id = pcall(function()
		return service:CreateTerminal()
	end)
	if not ok then
		setStatus(tostring(id), true)
		return
	end
	table.insert(sessions, { id = id, text = "", running = true, historyIndex = nil, draft = "" })
	selectSession(#sessions)
	input:CaptureFocus()
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
	local nextIndex = math.min(active, #sessions)
	active = 0
	selectSession(nextIndex)
end

local function submit()
	local session = sessions[active]
	local command = input.Text
	if not session or not session.running or command == "" then
		return
	end
	local ok, accepted = pcall(function()
		return service:Execute(session.id, command)
	end)
	if not ok or not accepted then
		setStatus(ok and "Input queue is busy; retry" or tostring(accepted), true)
		return
	end
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
	input.CursorPosition = #input.Text + 1
end

local function build()
	panel, body = UI.window("Terminal", UDim2.new(0.5, 0, 1, 32), UDim2.new(0.82, 0, 0.49, 0), "Terminal", {
		closable = true,
		draggable = false,
		dockable = false,
		resizable = false,
		headerColor = C.bar,
		contentColor = C.bg,
		activeTabColor = C.bg,
		titleColor = C.accent,
		backgroundImage = "",
		onClose = function()
			setOpen(false)
		end,
	})
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Visible = false
	panel.ZIndex = 50
	body.BackgroundColor3 = C.bg
	tabStrip = UI.create("Frame", {
		Position = UDim2.fromOffset(8, 3),
		Size = UDim2.new(1, -100, 0, 26),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
	}, body)
	button(body, "+", UDim2.new(1, -82, 0, 3), UDim2.fromOffset(34, 26), newSession)
	button(body, "×", UDim2.new(1, -44, 0, 3), UDim2.fromOffset(34, 26), closeSession)
	scroll = UI.create("ScrollingFrame", {
		Position = UDim2.fromOffset(8, 34),
		Size = UDim2.new(1, -16, 1, -92),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, 0),
		ScrollBarThickness = 4,
		ScrollingEnabled = true,
	}, body)
	local props = textProps("", UDim2.fromOffset(6, 4), UDim2.new(1, -18, 0, 32))
	props.TextWrapped = true
	props.TextYAlignment = Enum.TextYAlignment.Top
	output = UI.create("TextLabel", props, scroll)
	output.Name = "TerminalOutput"
	local prompt = textProps("❯", UDim2.new(0, 12, 1, -54), UDim2.fromOffset(20, 32))
	prompt.TextColor3 = C.accent
	UI.create("TextLabel", prompt, body)
	props = textProps("", UDim2.new(0, 34, 1, -54), UDim2.new(1, -46, 0, 32))
	props.PlaceholderText = "Enter a command"
	props.PlaceholderColor3 = C.dim
	props.ClearTextOnFocus = false
	props.MultiLine = false
	input = UI.create("TextBox", props, body)
	input.Name = "TerminalInput"
	local footer = textProps("  TERMINAL", UDim2.new(0, 0, 1, -22), UDim2.new(1, 0, 0, 22))
	footer.BackgroundTransparency = 0
	footer.BackgroundColor3 = C.bar
	footer.TextColor3 = C.dim
	footer.TextSize = 11
	status = UI.create("TextLabel", footer, body)
	status.Name = "TerminalStatus"

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
	connect(output:GetPropertyChangedSignal("TextBounds"), function()
		fitOutput(false)
	end)
	connect(scroll:GetPropertyChangedSignal("AbsoluteSize"), function()
		fitOutput(false)
	end)
	connect(tabStrip:GetPropertyChangedSignal("AbsoluteSize"), tabs)
	connect(UserInputService.InputBegan, function(event)
		if not opened or not input:IsFocused() then
			return
		end
		local session = sessions[active]
		if not session or not session.running then
			return
		end
		if event.KeyCode == Enum.KeyCode.Up then
			historyMove(session, -1)
		elseif event.KeyCode == Enum.KeyCode.Down then
			historyMove(session, 1)
		end
	end)
	connect(RunService.Heartbeat, function(dt)
		local target = opened and 1 or 0
		if progress ~= target then
			local speed = UI.shared().reduceMotion and 1000 or 7
			progress = math.clamp(progress + (opened and 1 or -1) * dt * speed, 0, 1)
			local eased = 1 - (1 - progress) ^ 3
			panel.Position = UDim2.new(0.5, 0, 1, -20 + (1 - eased) * (panel.AbsoluteSize.Y + 32))
			if progress == 0 and not opened then
				panel.Visible = false
			end
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
					if index == active and (chunk ~= "" or changed or session.drained) then
						repaint()
						fitOutput(false)
					end
				else
					session.running = false
					session.drained = true
					appendOutput(session, "\n" .. tostring(chunk))
					if index == active then
						repaint()
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
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		panel = nil
		opened = false
		progress = 0
		active = 0
	end)
	repaint()
end

setOpen = function(value)
	if not panel then
		build()
	end
	opened = value
	if value then
		panel.Position = UDim2.new(0.5, 0, 1, -20 + (1 - progress) * (panel.AbsoluteSize.Y + 32))
		panel.Visible = true
		if #sessions == 0 then
			newSession()
		else
			input:CaptureFocus()
		end
	else
		input:ReleaseFocus()
	end
end

function Terminal.Toggle()
	setOpen(not opened)
end

return Terminal

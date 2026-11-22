if IsServer or IsClient or IsPlaytest then
	return nil
end

local UI = require("@internal/editor_ui")
local RunService = game:GetService("RunService")
local tokens = UI.tokens
local colors = tokens.color
local PAD = tokens.space.lg
local ROW = UI.metrics.treeRow or 24
local TOOLBAR = 52
local FOOTER = 31
local SIDEBAR = 224
local FRAME_WIDTH = 210
local BREAKPOINTS_HEIGHT = 142
local UPDATE_INTERVAL = 0.25
local MAX_VISIBLE_ROWS = 144

local panel, content = UI.window(
	"LuauDebugger",
	UDim2.fromScale(0.5, 0.5),
	UDim2.fromOffset(970, 635),
	"Luau Debugger",
	{ closable = true, closeIcon = "builtin://global-icons/x.svg" }
)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Parent = UI.widgetOverlay()
panel.Visible = false
content.ClipsDescendants = true

local function text(parent, label, x, y, width, height, color, size)
	local object = UI.label(
		parent,
		label,
		UDim2.new(0, x, 0, y),
		width or UDim2.new(1, -(x + PAD), 0, height or ROW),
		size or tokens.type.small,
		color or colors.text
	)
	object.TextXAlignment = Enum.TextXAlignment.Left
	object.TextYAlignment = Enum.TextYAlignment.Center
	object.TextTruncate = Enum.TextTruncate.AtEnd
	return object
end

local function line(parent, y)
	UI.frame(parent, UDim2.new(0, PAD, 0, y), UDim2.new(1, -PAD * 2, 0, 1), colors.border, 0)
end

local function surface(parent, name, position, size)
	local widget = UI.frame(parent, position, size, colors.panel)
	widget.Name = name
	widget.BorderSizePixel = 0
	return widget
end

local function scroll(parent, name, position, size)
	return UI.create("ScrollingFrame", {
		Name = name,
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, 0),
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = colors.subtext,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollingEnabled = true,
		ClipsDescendants = true,
	}, parent)
end

local status = text(
	content,
	"Debugger idle · This panel controls only the local Luau VM.",
	PAD,
	0,
	UDim2.new(1, -(PAD * 2), 0, 20),
	20,
	colors.subtext,
	tokens.type.caption
)
local toolbar = surface(content, "DebugToolbar", UDim2.fromOffset(PAD, 24), UDim2.new(1, -(PAD * 2), 0, TOOLBAR))
toolbar.BackgroundTransparency = 1

local threadsPane = surface(
	content,
	"Threads",
	UDim2.fromOffset(PAD, 24 + TOOLBAR + PAD),
	UDim2.new(0, SIDEBAR, 1, -(24 + TOOLBAR + PAD * 3 + BREAKPOINTS_HEIGHT + FOOTER))
)
local framesPane = surface(
	content,
	"CallStack",
	UDim2.fromOffset(PAD + SIDEBAR + 2, 24 + TOOLBAR + PAD),
	UDim2.new(0, FRAME_WIDTH, 1, -(24 + TOOLBAR + PAD * 3 + BREAKPOINTS_HEIGHT + FOOTER))
)
local variablesPane = surface(
	content,
	"Locals",
	UDim2.fromOffset(PAD + SIDEBAR + FRAME_WIDTH + 4, 24 + TOOLBAR + PAD),
	UDim2.new(1, -(PAD * 2 + SIDEBAR + FRAME_WIDTH + 4), 1, -(24 + TOOLBAR + PAD * 3 + BREAKPOINTS_HEIGHT + FOOTER))
)

local threadsHeader =
	text(threadsPane, "PAUSED THREADS", 10, 5, UDim2.new(1, -20, 0, 22), 22, colors.subtext, tokens.type.caption)
local framesHeader =
	text(framesPane, "CALL STACK", 10, 5, UDim2.new(1, -20, 0, 22), 22, colors.subtext, tokens.type.caption)
local variablesHeader =
	text(variablesPane, "LOCALS", 10, 5, UDim2.new(1, -20, 0, 22), 22, colors.subtext, tokens.type.caption)
line(threadsPane, 29)
line(framesPane, 29)
line(variablesPane, 29)

local threadList = scroll(threadsPane, "ThreadItems", UDim2.fromOffset(0, 34), UDim2.new(1, 0, 1, -34))
local frameList = scroll(framesPane, "FrameItems", UDim2.fromOffset(0, 34), UDim2.new(1, 0, 1, -34))
local variableList = scroll(variablesPane, "LocalItems", UDim2.fromOffset(0, 34), UDim2.new(1, 0, 1, -34))

local breakpointsPane = surface(
	content,
	"Breakpoints",
	UDim2.new(0, PAD, 1, -(BREAKPOINTS_HEIGHT + FOOTER + PAD)),
	UDim2.new(1, -(PAD * 2), 0, BREAKPOINTS_HEIGHT)
)
text(breakpointsPane, "BREAKPOINTS", 10, 5, UDim2.new(1, -20, 0, 22), 22, colors.subtext, tokens.type.caption)
line(breakpointsPane, 29)
local breakpointList = scroll(breakpointsPane, "BreakpointItems", UDim2.fromOffset(0, 34), UDim2.new(1, 0, 1, -34))
local footer = text(
	content,
	"F9 · Toggle breakpoint at cursor    |    Select a paused thread to inspect frames and locals",
	PAD,
	0,
	UDim2.new(1, -(PAD * 2), 0, 20),
	20,
	colors.muted,
	tokens.type.caption
)
footer.Position = UDim2.new(0, PAD, 1, -(FOOTER - 3))

local state = {
	enabled = false,
	selectedThread = nil,
	selectedFrame = 0,
	selectedSource = nil,
	pausedThreads = {},
	breakpoints = {},
	frames = {},
	locals = {},
	lastError = nil,
}

local context
local function resolveContext()
	if context then
		return context
	end
	local ok, service = pcall(function()
		return game:GetService("ScriptContext")
	end)
	if ok then
		context = service
	end
	return context
end

local function request(method, ...)
	local service = resolveContext()
	if not service then
		state.lastError = "ScriptContext is unavailable in this editor session"
		return nil
	end
	local args = table.pack(...)
	local ok, result = pcall(function()
		return service[method](service, table.unpack(args, 1, args.n))
	end)
	if not ok then
		state.lastError = tostring(result)
		return nil
	end
	state.lastError = nil
	return result
end

local function action(textValue, x, width, handler)
	return UI.button(toolbar, textValue, UDim2.fromOffset(x, 10), UDim2.fromOffset(width, 30), handler, {
		color = colors.panelRaised,
		hoverColor = colors.hover,
		pressedColor = colors.pressed,
		textColor = colors.text,
		textSize = tokens.type.small,
		radius = tokens.radius.sm,
		border = false,
	})
end

local refreshing = false
local lastSnapshotKey
local refresh
local function goToSource(source, line)
	if type(source) ~= "string" or source == "" then
		return false
	end
	local ok, viewport = pcall(require, "@internal/viewport")
	if not ok or not viewport or not viewport.OpenScript then
		return false
	end
	local target = source:gsub("^=", "")
	for _, object in ipairs(game:GetDescendants()) do
		if object:IsA("Script") or object:IsA("LocalScript") or object:IsA("ModuleScript") then
			if object:GetFullName() == target then
				viewport.OpenScript(object, line)
				return true
			end
		end
	end
	return false
end

local function rowButton(parent, labelValue, index, handler, selected, secondary)
	local button = UI.button(
		parent,
		labelValue,
		UDim2.fromOffset(3, (index - 1) * ROW + 2),
		UDim2.new(1, -8, 0, ROW - 2),
		handler,
		{
			color = selected and colors.accentSoft or (index % 2 == 0 and colors.rowEven or colors.rowOdd),
			hoverColor = colors.hover,
			textColor = secondary and colors.subtext or colors.text,
			textSize = tokens.type.small,
			radius = 0,
			border = false,
			paddingX = 8,
		}
	)
	button.Name = "DebuggerRow" .. tostring(index)
	return button
end

local function populate(container, count)
	container.CanvasSize = UDim2.fromOffset(0, math.max(0, count * ROW + 5))
end

local function refreshLists()
	UI.clear(threadList)
	UI.clear(frameList)
	UI.clear(variableList)
	UI.clear(breakpointList)

	local threads = state.pausedThreads
	for i, item in ipairs(threads) do
		if i > MAX_VISIBLE_ROWS then
			break
		end
		local labelValue = ("%s · %s:%s"):format(
			item.script ~= "" and item.script or ("Thread " .. tostring(item.id)),
			tostring(item.source or "?"),
			tostring(item.line or 0)
		)
		rowButton(threadList, labelValue, i, function()
			state.selectedThread = item.id
			state.selectedFrame = 0
			refresh(true)
		end, state.selectedThread == item.id)
	end
	populate(threadList, math.max(math.min(#threads, MAX_VISIBLE_ROWS), 1))
	if #threads == 0 then
		text(threadList, "No paused threads", 12, 5, UDim2.new(1, -20, 0, ROW), ROW, colors.muted)
	end

	for i, item in ipairs(state.frames) do
		if i > MAX_VISIBLE_ROWS then
			break
		end
		local name = item.name or ""
		local title = ("%s  :%s"):format(name ~= "" and name or "(anonymous)", tostring(item.line or 0))
		rowButton(frameList, title, i, function()
			state.selectedFrame = item.depth or (i - 1)
			if not goToSource(item.source, item.line) then
				state.lastError = "The selected frame's script is not in this editor's DataModel"
			end
			refresh(true)
		end, state.selectedFrame == (item.depth or i - 1))
	end
	populate(frameList, math.max(math.min(#state.frames, MAX_VISIBLE_ROWS), 1))

	for i, variable in ipairs(state.locals) do
		if i > MAX_VISIBLE_ROWS then
			break
		end
		rowButton(
			variableList,
			("%s  =  %s"):format(variable.name or "?", variable.value or "nil"),
			i,
			nil,
			false,
			false
		)
	end
	if #state.locals == 0 then
		text(variableList, "No locals in this frame", 10, 4, UDim2.new(1, -20, 0, ROW), ROW, colors.muted)
	end
	populate(variableList, math.max(math.min(#state.locals, MAX_VISIBLE_ROWS), 1))

	for i, point in ipairs(state.breakpoints) do
		if i > MAX_VISIBLE_ROWS then
			break
		end
		local source = point.source or "?"
		local displayLine = point.resolvedLine and point.resolvedLine > 0 and tostring(point.resolvedLine)
			or tostring(point.line)
		local labelValue = ("●  %s  :%s    (click to remove)"):format(source, displayLine)
		rowButton(breakpointList, labelValue, i, function()
			request("DebugSetBreakpoint", source, point.line, false)
			refresh(true)
		end, false)
	end
	if #state.breakpoints == 0 then
		text(
			breakpointList,
			"No breakpoints. Open a script and press F9.",
			12,
			4,
			UDim2.new(1, -24, 0, ROW),
			ROW,
			colors.muted
		)
	end
	populate(breakpointList, math.max(math.min(#state.breakpoints, MAX_VISIBLE_ROWS), 1))
end

refresh = function(force)
	if refreshing then
		return
	end
	refreshing = true
	local service = resolveContext()
	local resultEnabled = false
	if service then
		local ok, value = pcall(function()
			return service.DebuggerEnabled
		end)
		resultEnabled = ok and value == true
	end
	state.enabled = resultEnabled
	state.pausedThreads = request("DebugGetPausedThreads") or {}
	state.breakpoints = request("DebugGetBreakpoints") or {}
	local current = state.selectedThread
	local found = false
	for _, thread in ipairs(state.pausedThreads) do
		if thread.id == current then
			found = true
			break
		end
	end
	if not found then
		current = state.pausedThreads[1] and state.pausedThreads[1].id or nil
		state.selectedThread = current
		state.selectedFrame = 0
	end
	state.frames = current and (request("DebugGetFrames", current) or {}) or {}
	if state.selectedFrame >= #state.frames then
		state.selectedFrame = 0
	end
	state.locals = current and (request("DebugGetLocals", current, state.selectedFrame) or {}) or {}
	if state.lastError then
		status.Text = state.lastError
		status.TextColor3 = colors.error
	elseif not state.enabled then
		status.Text = "Debugger disabled · Local VM only; external playtest requires a debugger transport"
		status.TextColor3 = colors.subtext
	elseif #state.pausedThreads > 0 then
		status.Text = ("%d paused thread(s) · Select a frame to inspect execution"):format(#state.pausedThreads)
		status.TextColor3 = colors.warning
	else
		status.Text = "Debugger attached · Waiting for local Luau breakpoint"
		status.TextColor3 = colors.success
	end
	local bits = { tostring(state.enabled), tostring(state.selectedThread), tostring(state.selectedFrame) }
	for _, thread in ipairs(state.pausedThreads) do
		table.insert(bits, tostring(thread.id) .. ":" .. tostring(thread.line))
	end
	for _, point in ipairs(state.breakpoints) do
		table.insert(bits, tostring(point.source) .. ":" .. tostring(point.line) .. ":" .. tostring(point.resolvedLine))
	end
	for _, frame in ipairs(state.frames) do
		table.insert(bits, tostring(frame.source) .. ":" .. tostring(frame.line))
	end
	for _, variable in ipairs(state.locals) do
		table.insert(bits, tostring(variable.name) .. "=" .. tostring(variable.value))
	end
	local snapshotKey = table.concat(bits, "|")
	if force or snapshotKey ~= lastSnapshotKey then
		lastSnapshotKey = snapshotKey
		refreshLists()
	end
	refreshing = false
end

local function selectedAction(mode)
	if not state.selectedThread then
		state.lastError = "Select a paused thread first"
		refresh(true)
		return
	end
	request("DebugResume", state.selectedThread, mode)
	refresh(true)
end

action("Attach", 0, 96, function()
	request("DebugEnable", true)
	refresh(true)
end)
action("Detach", 102, 94, function()
	request("DebugEnable", false)
	refresh(true)
end)
action("Pause", 202, 78, function()
	request("DebugPause")
	refresh(true)
end)
action("Continue", 286, 104, function()
	selectedAction("continue")
end)
action("Step Into", 396, 104, function()
	selectedAction("into")
end)
action("Step Over", 506, 110, function()
	selectedAction("over")
end)
action("Step Out", 622, 108, function()
	selectedAction("out")
end)
action("Refresh", 736, 105, function()
	refresh(true)
end)

local function toggleBreakpoint(scriptInstance, line)
	if
		not scriptInstance
		or (
			not scriptInstance:IsA("Script")
			and not scriptInstance:IsA("LocalScript")
			and not scriptInstance:IsA("ModuleScript")
		)
	then
		return false
	end
	local n = tonumber(line)
	if not n or n < 1 then
		return false
	end
	n = math.floor(n)
	if not state.enabled then
		request("DebugEnable", true)
	end
	local source = scriptInstance:GetFullName()
	local points = request("DebugGetBreakpoints") or {}
	local enabled = true
	for _, point in ipairs(points) do
		if point.source == source and point.line == n then
			enabled = false
			break
		end
	end
	local result = request("DebugSetBreakpoint", scriptInstance, n, enabled)
	refresh(true)
	return result == true
end

UI.shared().toggleDebugBreakpoint = toggleBreakpoint

local updateElapsed = 0
local heartbeat = RunService.Heartbeat:Connect(function(dt)
	if not panel.Visible then
		return
	end
	updateElapsed += dt
	if updateElapsed < UPDATE_INTERVAL then
		return
	end
	updateElapsed = 0
	refresh()
end)

panel.Destroying:Connect(function()
	heartbeat:Disconnect()
	if UI.shared().toggleDebugBreakpoint == toggleBreakpoint then
		UI.shared().toggleDebugBreakpoint = nil
	end
	UI.forgetButtons(content)
end)

return {
	Enable = function()
		panel.Visible = true
		refresh(true)
	end,
	Disable = function()
		panel.Visible = false
	end,
	Toggle = function()
		panel.Visible = not panel.Visible
		if panel.Visible then
			refresh(true)
		end
	end,
	ToggleBreakpoint = toggleBreakpoint,
	Refresh = function()
		refresh(true)
	end,
}

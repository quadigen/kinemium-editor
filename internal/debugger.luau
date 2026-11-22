if IsServer or IsClient or IsPlaytest then
	return nil
end

local UI = require("@internal/editor_ui")
local RunService = game:GetService("RunService")
local tokens = UI.tokens
local colors = tokens.color
local PAD = tokens.space.lg
local ROW = UI.metrics.treeRow
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
	UI.separator(parent, UDim2.new(0, PAD, 0, y), UDim2.new(1, -PAD * 2, 0, 1), colors.border)
end

local function surface(parent, name, position, size)
	local widget = UI.frame(parent, position, size, colors.panel)
	widget.Name = name
	widget.BorderSizePixel = 0
	widget.BackgroundTransparency = 1
	return widget
end

local function scroll(parent, name, position, size)
	return UI.create("ScrollingFrame", {
		Name = name,
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(1, 0, 0, 0),
		CanvasPosition = Vector2.new(0, 0),
		ScrollSpeed = 38,
		SmoothScrollingEnabled = true,
		ScrollSmoothness = 18,
		ScrollBarAutoHide = true,
		ScrollBarFadeDelay = 0.45,
		ScrollBarFadeSpeed = 12,
		ScrollBarImageTransparency = 0.4,
		ScrollBarMinimumHandleSize = 24,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = colors.subtext,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollingEnabled = true,
		Active = true,
		InputSink = true,
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

local request
local playtest = game:GetService("PlaytestService")
local remote = {
	role = "Server",
	activeRole = nil,
	pending = false,
	connected = false,
	snapshot = nil,
	pendingAction = nil,
	queued = {},
	synced = nil,
	lastError = nil,
}
local function runningRole()
	local ok, running = pcall(function() return playtest.IsRunning end)
	if not ok or not running then return nil end
	local server, client = 0, 0
	pcall(function()
		server = playtest.ServerProcessId or 0
		client = playtest.ClientProcessId or 0
	end)
	if remote.role == "Server" and server > 0 then return "Server" end
	if remote.role == "Client" and client > 0 then return "Client" end
	if server > 0 then return "Server" end
	if client > 0 then return "Client" end
	return nil
end

local function breakpointSignature(points)
	local keys = {}
	for _, item in ipairs(points or {}) do
		table.insert(keys, tostring(item.source) .. ":" .. tostring(item.line))
	end
	table.sort(keys)
	return table.concat(keys, "|")
end

local function enqueueRemote(actionName, mode, id, frame)
	if not runningRole() then return false end
	if actionName ~= "detach" and not state.enabled then
		request("DebugEnable", true)
	end
	table.insert(remote.queued, {
		action = actionName,
		mode = mode or "continue",
		id = id or 0,
		frame = frame or 0,
	})
	return true
end

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

request = function(method, ...)
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

-- Each list owns a small reusable button pool. Scroll changes reposition its
-- existing rows; even a project with hundreds of breakpoints only creates
-- enough controls for the visible viewport and a few overscan rows.
local OVERSCAN = 6
local rowPools = {}
local emptyLabels = {
	[threadList] = text(threadList, "No paused threads", 12, 5, UDim2.new(1, -20, 0, ROW), ROW, colors.muted),
	[frameList] = text(frameList, "Select a thread to inspect its call stack", 10, 4,
		UDim2.new(1, -20, 0, ROW), ROW, colors.muted),
	[variableList] = text(variableList, "No locals in this frame", 10, 4,
		UDim2.new(1, -20, 0, ROW), ROW, colors.muted),
	[breakpointList] = text(breakpointList, "Press F9 in a script to set a breakpoint", 12, 4,
		UDim2.new(1, -24, 0, ROW), ROW, colors.muted),
}

local function visibleRange(list, count)
	list.CanvasSize = UDim2.new(1, 0, 0, count * ROW + 5)
	local start = math.max(1, math.floor(list.CanvasPosition.Y / ROW) - OVERSCAN + 1)
	local viewRows = math.ceil(math.max(list.AbsoluteSize.Y, ROW * 10) / ROW) + OVERSCAN * 2
	return start, math.min(count, start + math.min(viewRows, MAX_VISIBLE_ROWS) - 1)
end

local function rowButton(parent, labelValue, index, slot, handler, selected, secondary, iconPath)
	local pool = rowPools[parent]
	if not pool then
		pool = {}
		rowPools[parent] = pool
	end
	local record = pool[slot]
	if not record then
		local button, caption, buttonRecord = UI.button(
			parent, "", UDim2.fromOffset(3, 0),
			UDim2.new(1, -8, 0, ROW - 2),
			nil, {
				color = colors.rowOdd,
				hoverColor = colors.hover,
				textColor = colors.text,
				textSize = tokens.type.small,
				radius = 0,
				border = false,
				paddingX = 8,
				icon = iconPath,
				iconSize = 14,
			}
		)
		record = { button = button, label = caption, action = buttonRecord }
		pool[slot] = record
	end
	local base = index % 2 == 0 and colors.rowEven or colors.rowOdd
	record.button.Name = "DebuggerRow" .. tostring(index)
	record.button.Position = UDim2.fromOffset(3, (index - 1) * ROW + 2)
	record.button.Visible = true
	record.label.Text = labelValue
	record.label.TextColor3 = secondary and colors.subtext or colors.text
	record.action.callback = handler
	record.action.defaultColor = base
	record.action.defaultHoverColor = colors.hover
	UI.setButtonState(record.action, selected and "selected" or nil)
	return record.button
end

local function hideUnused(parent, used)
	for i = used + 1, #(rowPools[parent] or {}) do
		local item = rowPools[parent][i]
		item.button.Visible = false
		item.action.callback = nil
	end
end

local function refreshLists()
	local threads = state.pausedThreads
	local first, last = visibleRange(threadList, #threads)
	local used = 0
	for i = first, last do
		local item = threads[i]
		local labelValue = ("%s · %s:%s"):format(
			item.script ~= "" and item.script or ("Thread " .. tostring(item.id)),
			tostring(item.source or "?"), tostring(item.line or 0)
		)
		used += 1
		rowButton(threadList, labelValue, i, used, function()
			state.selectedThread = item.id
			state.selectedFrame = 0
			refresh(true)
		end, state.selectedThread == item.id)
	end
	hideUnused(threadList, used)
	emptyLabels[threadList].Visible = #threads == 0

	local frames = state.frames
	first, last = visibleRange(frameList, #frames)
	used = 0
	for i = first, last do
		local item = frames[i]
		local name = item.name or ""
		local title = ("%s  :%s"):format(name ~= "" and name or "(anonymous)", tostring(item.line or 0))
		used += 1
		rowButton(frameList, title, i, used, function()
			state.selectedFrame = item.depth or (i - 1)
			if not goToSource(item.source, item.line) then
				state.lastError = "The selected frame's script is not in this editor's DataModel"
			end
			refresh(true)
		end, state.selectedFrame == (item.depth or i - 1))
	end
	hideUnused(frameList, used)
	emptyLabels[frameList].Visible = #frames == 0

	local vars = state.locals
	first, last = visibleRange(variableList, #vars)
	used = 0
	for i = first, last do
		local variable = vars[i]
		used += 1
		rowButton(variableList,
			("%s = %s"):format(variable.name or "?", variable.value or "nil"),
			i, used, nil, false, false)
	end
	hideUnused(variableList, used)
	emptyLabels[variableList].Visible = #vars == 0

	local points = state.breakpoints
	first, last = visibleRange(breakpointList, #points)
	used = 0
	for i = first, last do
		local point = points[i]
		local source = point.source or "?"
		local line = point.resolvedLine and point.resolvedLine > 0 and point.resolvedLine or point.line
		used += 1
		rowButton(breakpointList, ("%s :%s  (click to remove)"):format(source, tostring(line)),
			i, used, function()
				request("DebugSetBreakpoint", source, point.line, false)
				remote.synced = nil
				refresh(true)
			end, false, false, "builtin://icons/Script.svg")
	end
	hideUnused(breakpointList, used)
	emptyLabels[breakpointList].Visible = #points == 0
end

local scrollConnections = {}
for _, list in ipairs({ threadList, frameList, variableList, breakpointList }) do
	table.insert(scrollConnections, list:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		if panel.Visible then refreshLists() end
	end))
end

local function updateRemote()
	local role = runningRole()
	if role ~= remote.activeRole then
		remote.activeRole = role
		remote.pending = false
		remote.connected = false
		remote.snapshot = nil
		remote.synced = nil
		remote.lastError = nil
		state.selectedThread = nil
		state.selectedFrame = 0
	end
	if not role then return end
	if remote.pending then
		local result = request("DebugRemotePoll", role)
		if type(result) == "table" then
			remote.pending = false
			remote.connected = true
			remote.lastError = nil
			remote.snapshot = result
		elseif state.lastError then
			remote.pending = false
			remote.lastError = state.lastError
		end
		return
	end
	local localPoints = request("DebugGetBreakpoints") or {}
	local signature = state.enabled and breakpointSignature(localPoints) or ""
	local nextCommand = nil
	-- User actions take precedence; otherwise synchronize pending breakpoint edits.
	if #remote.queued > 0 then
		nextCommand = remote.queued[1]
	elseif state.enabled and remote.synced ~= signature then
		nextCommand = { action = "sync", id = state.selectedThread or 0, frame = state.selectedFrame }
	else
		nextCommand = { action = "snapshot", id = state.selectedThread or 0, frame = state.selectedFrame }
	end
	if request("DebugRemoteSend", role, nextCommand.action,
		nextCommand.id or 0, nextCommand.frame or 0, nextCommand.mode or "continue") then
		if #remote.queued > 0 then table.remove(remote.queued, 1) end
		if nextCommand.action == "sync" then remote.synced = signature end
		remote.pending = true
	elseif state.lastError then
		remote.lastError = state.lastError
	end
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
	local localBreakpoints = request("DebugGetBreakpoints") or {}
	local role = runningRole()
	local snapshot = role and remote.snapshot or nil
	if snapshot then
		state.pausedThreads = snapshot.pausedThreads or {}
		state.breakpoints = snapshot.breakpoints or localBreakpoints
	else
		state.pausedThreads = role and {} or (request("DebugGetPausedThreads") or {})
		state.breakpoints = localBreakpoints
	end
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
	if snapshot then
		state.frames = snapshot.frames or {}
		state.locals = snapshot.locals or {}
	else
		state.frames = current and (request("DebugGetFrames", current) or {}) or {}
		if state.selectedFrame >= #state.frames then state.selectedFrame = 0 end
		state.locals = current and (request("DebugGetLocals", current, state.selectedFrame) or {}) or {}
	end
	if remote.lastError and role then
		status.Text = remote.lastError
		status.TextColor3 = colors.error
	elseif state.lastError then
		status.Text = state.lastError
		status.TextColor3 = colors.error
	elseif role and not state.enabled then
		status.Text = ("Playtest %s is running. Attach to start debugging."):format(role)
		status.TextColor3 = colors.subtext
	elseif role and not remote.connected then
		status.Text = ("Connecting to %s playtest debugger..."):format(role)
		status.TextColor3 = colors.warning
	elseif role and snapshot then
		local count = #state.pausedThreads
		status.Text = count > 0
			and ("%s playtest paused · %d thread(s)"):format(role, count)
			or ("%s playtest connected · waiting for breakpoint"):format(role)
		status.TextColor3 = count > 0 and colors.warning or colors.success
	elseif not state.enabled then
		status.Text = "Debugger disabled · Set F9 breakpoints and attach before starting a playtest"
		status.TextColor3 = colors.subtext
	elseif #state.pausedThreads > 0 then
		status.Text = ("%d paused local thread(s)"):format(#state.pausedThreads)
		status.TextColor3 = colors.warning
	else
		status.Text = "No playtest running · Debugger armed for the next playtest"
		status.TextColor3 = colors.subtext
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
	if runningRole() then
		enqueueRemote("resume", mode, state.selectedThread, state.selectedFrame)
	else
		request("DebugResume", state.selectedThread, mode)
	end
	refresh(true)
end

action("Attach", 0, 79, function()
	request("DebugEnable", true)
	remote.synced = nil
	refresh(true)
end)
action("Detach", 83, 79, function()
	enqueueRemote("detach")
	request("DebugEnable", false)
	remote.synced = ""
	refresh(true)
end)
action("Pause", 166, 79, function()
	if not enqueueRemote("pause") then request("DebugPause") end
	refresh(true)
end)
action("Continue", 249, 86, function() selectedAction("continue") end)
action("Step Into", 339, 83, function() selectedAction("into") end)
action("Step Over", 426, 84, function() selectedAction("over") end)
action("Step Out", 514, 80, function() selectedAction("out") end)
action("Refresh", 598, 79, function()
	remote.synced = nil
	refresh(true)
end)
local serverButton, _, serverRecord = action("Server", 682, 80, function()
	remote.role = "Server"
	refresh(true)
end)
local clientButton, _, clientRecord = action("Client", 766, 80, function()
	remote.role = "Client"
	refresh(true)
end)
local function markRoleButtons()
	if UI.setButtonState then
		UI.setButtonState(serverRecord, remote.role == "Server" and "selected" or nil)
		UI.setButtonState(clientRecord, remote.role == "Client" and "selected" or nil)
	end
end
markRoleButtons()

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
	if result then remote.synced = nil end
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
	updateRemote()
	markRoleButtons()
	refresh()
end)

panel.Destroying:Connect(function()
	heartbeat:Disconnect()
	for _, connection in ipairs(scrollConnections) do connection:Disconnect() end
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

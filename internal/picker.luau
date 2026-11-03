local UI = require("@internal/editor_ui")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")

local tokens = UI.tokens
local picker = {}

local session = nil

local function getMouse()
	local player = Players.LocalPlayer
	return player and player:GetMouse() or nil
end

local function setHighlight(highlight, target)
	if not highlight then
		return
	end
	highlight.Adornee = target
	highlight.Parent = target and workspace or nil
end

local function stop()
	if session == nil then
		return
	end
	local s = session
	session = nil

	for _, c in ipairs(s.connections) do
		c:Disconnect()
	end
	if s.highlight then
		s.highlight:Destroy()
	end
	if s.tooltip and UI.isAlive(s.tooltip) then
		s.tooltip:Destroy()
	end
	if s.mouse then
		pcall(function()
			s.mouse.Icon = s.previousIcon or ""
		end)
	end
end

function picker.isActive(owner)
	return session ~= nil and (owner == nil or session.owner == owner)
end

function picker.cancel()
	if session == nil then
		return
	end
	local onCancel = session.onCancel
	stop()
	if onCancel then
		onCancel()
	end
end

function picker.submit(instance)
	local s = session
	if s == nil or s.cancelRequested or instance == nil or (s.filter and not s.filter(instance)) then
		return false
	end
	if s.owner and not UI.isAlive(s.owner) then
		picker.cancel()
		return false
	end
	if s.onPicked(instance) == false then
		return false
	end
	if session == s then
		stop()
	end
	return true
end

function picker.queueViewportPick(instance)
	if session then
		-- Let other listeners see the active session for the rest of this input.
		session.pendingTarget = instance
	end
end

function picker.setViewportTarget(target)
	if session then
		session.viewportTarget = target
	end
end

function picker.pick(options)
	picker.cancel()

	local mouse = getMouse()
	local ok, highlight = pcall(Instance.new, "BoxHandleAdornment")

	local s = {
		owner = options.owner,
		filter = options.filter,
		onPicked = options.onPicked,
		onCancel = options.onCancel,
		connections = {},
		highlight = ok and highlight or nil,
		mouse = mouse,
		hovered = nil,
	}
	session = s

	if mouse then
		s.previousIcon = mouse.Icon
		pcall(function()
			mouse.Icon = "builtin://icons/Crosshair.svg"
		end)
	end

	s.tooltip = UI.create("Frame", {
		Size = UDim2.fromOffset(190, 20),
		BackgroundColor3 = tokens.color.surface,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Active = false,
		ZIndex = 6000,
	}, UI.widgetOverlay())
	UI.corner(s.tooltip, tokens.radius.sm)
	s.tooltipLabel = UI.label(
		s.tooltip,
		options.hint or "Click an object to select it",
		UDim2.fromOffset(6, 2),
		UDim2.new(1, -12, 0, 16),
		tokens.type.small,
		tokens.color.text
	)

	local function valid(target)
		return target ~= nil and (s.filter == nil or s.filter(target))
	end

	local function updateHover()
		if session ~= s then
			return
		end
		if s.cancelRequested or (s.owner and not UI.isAlive(s.owner)) then
			picker.cancel()
			return
		end
		local pendingTarget = s.pendingTarget
		s.pendingTarget = nil
		if pendingTarget and picker.submit(pendingTarget) then
			return
		end
		local pos = UserInputService:GetMouseLocation()
		s.tooltip.Position = UDim2.fromOffset(pos.X + 14, pos.Y + 14)

		local target = s.viewportTarget
		if not valid(target) then
			target = nil
		end

		if target ~= s.hovered then
			s.hovered = target
			setHighlight(s.highlight, target)
			s.tooltipLabel.Text = target and target.Name or (options.hint or "Click an object to select it")
		end
	end

	table.insert(s.connections, RunService.RenderStepped:Connect(updateHover))

	local previousSelection = {}
	for _, instance in ipairs(Selection:Get()) do
		previousSelection[instance] = true
	end
	table.insert(s.connections, Selection.SelectionChanged:Connect(function()
		if session ~= s then
			return
		end
		local selection = Selection:Get()
		local oldSelection = previousSelection
		previousSelection = {}
		for _, instance in ipairs(selection) do
			previousSelection[instance] = true
		end
		for _, instance in ipairs(selection) do
			if not oldSelection[instance] and picker.submit(instance) then
				return
			end
		end
	end))

	table.insert(
		s.connections,
		UserInputService.InputBegan:Connect(function(input)
			if session ~= s then
				return
			end

			if input.KeyCode == Enum.KeyCode.Escape or input.UserInputType == Enum.UserInputType.MouseButton2 then
				s.cancelRequested = true
			end
		end)
	)

	return s
end

function picker.row(parent, position, width, options)
	local frame = UI.create("Frame", {
		Position = position,
		Size = UDim2.new(0, width, 0, UI.metrics.inputHeight),
		BackgroundColor3 = tokens.color.input,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
	}, parent)
	UI.corner(frame, tokens.radius.sm)

	local valueLabel
	local pickButton

	local function display(value)
		valueLabel.Text = value and value.Name or "nil"
	end

	valueLabel =
		UI.label(frame, "nil", UDim2.fromOffset(6, 3), UDim2.new(1, -62, 0, 16), tokens.type.small, tokens.color.text)

	local current = options.value
	display(current)

	local function setValue(value)
		current = value
		display(value)
		if options.onChanged then
			options.onChanged(value)
		end
	end

	pickButton = UI.button(
		frame,
		"Pick",
		UDim2.new(1, -56, 0, 1),
		UDim2.fromOffset(32, UI.metrics.inputHeight - 2),
		function()
			if picker.isActive(frame) then
				picker.cancel()
				return
			end
			valueLabel.Text = "Picking..."
			picker.pick({
				owner = frame,
				filter = options.filter,
				onPicked = setValue,
				onCancel = function()
					display(current)
				end,
			})
		end,
		{ color = tokens.color.input, border = false }
	)

	UI.button(frame, "X", UDim2.new(1, -22, 0, 1), UDim2.fromOffset(20, UI.metrics.inputHeight - 2), function()
		picker.cancel()
		setValue(nil)
	end, { color = tokens.color.input, border = false })

	return frame, function(value)
		current = value
		display(value)
	end
end

function picker.Refresh()
	return UI.refreshAllWindows()
end

return picker

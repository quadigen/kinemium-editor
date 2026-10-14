local UI = require("@internal/editor_ui")

local Selection = game:GetService("Selection")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local colors = UI.colors
local tokens = UI.tokens

local HANDLE_SIZE = 7
local MIN_SIZE = 4
local Z = 10
local MENU_Z = 50000
local ROW_H, SEP_H, PAD, MENU_W = 24, 9, 4, 214
local GUIDE_THRESHOLD = 6
local WHITE = Color3.new(1, 1, 1)
local GUIDE_COLOR = Color3.fromRGB(255, 82, 170)
local NONE = {}
local LOCK_ATTR = "GuiEditorLocked"
local SNAP_PROPS = { "Name", "Position", "Size", "AnchorPoint", "Rotation", "ZIndex", "Visible", "Parent" }
local INSERTABLE = { "Frame", "TextLabel", "TextButton", "TextBox", "ImageLabel", "ImageButton", "ScrollingFrame" }
local CHEVRON = "builtin://global-icons/chevron-down.svg"

local RESIZE_HANDLES = {
	{ name = "NW", x = 0, y = 0, l = true, t = true, corner = true },
	{ name = "N", x = 0.5, y = 0, t = true },
	{ name = "NE", x = 1, y = 0, r = true, t = true, corner = true },
	{ name = "E", x = 1, y = 0.5, r = true },
	{ name = "SE", x = 1, y = 1, r = true, b = true, corner = true },
	{ name = "S", x = 0.5, y = 1, b = true },
	{ name = "SW", x = 0, y = 1, l = true, b = true, corner = true },
	{ name = "W", x = 0, y = 0.5, l = true },
}

local ARROWS = {
	[Enum.KeyCode.Left] = Vector2.new(-1, 0),
	[Enum.KeyCode.Right] = Vector2.new(1, 0),
	[Enum.KeyCode.Up] = Vector2.new(0, -1),
	[Enum.KeyCode.Down] = Vector2.new(0, 1),
}

local ANCHORS = {
	{ "Top Left", Vector2.new(0, 0) },
	{ "Top", Vector2.new(0.5, 0) },
	{ "Top Right", Vector2.new(1, 0) },
	{ "Left", Vector2.new(0, 0.5) },
	{ "Center", Vector2.new(0.5, 0.5) },
	{ "Right", Vector2.new(1, 0.5) },
	{ "Bottom Left", Vector2.new(0, 1) },
	{ "Bottom", Vector2.new(0.5, 1) },
	{ "Bottom Right", Vector2.new(1, 1) },
}

local Editor = {}
Editor.__index = Editor

local function damp(current, target, speed, dt)
	return current + (target - current) * (1 - math.exp(-speed * dt))
end

local function dampAngle(current, target, speed, dt)
	local delta = ((target - current + 180) % 360) - 180
	return current + delta * (1 - math.exp(-speed * dt))
end

local function round(n)
	return math.floor(n + 0.5)
end

local function shiftUDim(u, deltaPx, span)
	if u.Scale ~= 0 and u.Offset == 0 and span > 0 then
		return UDim.new(u.Scale + deltaPx / span, 0)
	end

	return UDim.new(u.Scale, round(u.Offset + deltaPx))
end

local function udim2(x, y)
	return UDim2.new(x.Scale, x.Offset, y.Scale, y.Offset)
end

local function snapValue(value, origin, step)
	return math.floor((value - origin) / step + 0.5) * step + origin
end

local function stepUDim2(current, goal, k)
	local function s(a, b)
		return a + (b - a) * k
	end

	return UDim2.new(
		s(current.X.Scale, goal.X.Scale),
		s(current.X.Offset, goal.X.Offset),
		s(current.Y.Scale, goal.Y.Scale),
		s(current.Y.Offset, goal.Y.Offset)
	)
end

local function closeUDim2(a, b)
	return math.abs(a.X.Scale - b.X.Scale) < 0.0005
		and math.abs(a.Y.Scale - b.Y.Scale) < 0.0005
		and math.abs(a.X.Offset - b.X.Offset) < 0.2
		and math.abs(a.Y.Offset - b.Y.Offset) < 0.2
end

local function isShift()
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

local function isCtrl()
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
end

local function isAlt()
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt)
end

local function newRect()
	return { x = 0, y = 0, w = 0, h = 0, rot = 0, alpha = 0, ready = false }
end

local function stepRect(r, x, y, w, h, rot, speed, dt, instant)
	if instant or not r.ready then
		r.x, r.y, r.w, r.h, r.rot = x, y, w, h, rot
		r.ready = true
		return
	end

	r.x = damp(r.x, x, speed, dt)
	r.y = damp(r.y, y, speed, dt)
	r.w = damp(r.w, w, speed, dt)
	r.h = damp(r.h, h, speed, dt)
	r.rot = dampAngle(r.rot, rot, speed, dt)

	if math.abs(r.x - x) < 0.05 then
		r.x = x
	end
	if math.abs(r.y - y) < 0.05 then
		r.y = y
	end
	if math.abs(r.w - w) < 0.05 then
		r.w = w
	end
	if math.abs(r.h - h) < 0.05 then
		r.h = h
	end
	if math.abs(((rot - r.rot + 180) % 360) - 180) < 0.05 then
		r.rot = rot
	end
end

local function snapshot(obj)
	local props = {}

	for _, key in ipairs(SNAP_PROPS) do
		local ok, value = pcall(function()
			return obj[key]
		end)

		if ok then
			if key == "Parent" and value == nil then
				value = NONE
			end

			props[key] = value
		end
	end

	return props
end

local function snapAxis(values, cands)
	local bestDelta = nil

	for _, v in ipairs(values) do
		for _, c in ipairs(cands) do
			local d = c.v - v

			if math.abs(d) <= GUIDE_THRESHOLD and (bestDelta == nil or math.abs(d) < math.abs(bestDelta)) then
				bestDelta = d
			end
		end
	end

	return bestDelta
end

function Editor.new(options)
	options = options or {}

	local self = setmetatable({}, Editor)

	self.overlay = options.overlay
	self.getTool = options.getTool or function()
		return "Select"
	end
	self.getSnap = options.getSnap or function()
		return true
	end
	self.snapStep = options.snapStep or 4
	self.rotateSnap = options.rotateSnap or 15
	self.canPick = options.canPick ~= false
	self.clearOnEmpty = options.clearOnEmpty == true
	self.contextMenu = options.contextMenu ~= false
	self.contextOnEmpty = options.contextOnEmpty == true
	self.shortcuts = options.shortcuts ~= false
	self.guides = options.guides ~= false
	self.smoothDrag = options.smoothDrag ~= false
	self.smoothSpeed = options.smoothSpeed or 38
	self.followSpeed = options.followSpeed or 30

	self.enabled = true
	self.target = nil
	self.selection = {}
	self.hoverObj = nil
	self.drag = nil
	self.goals = {}
	self.guideList = {}
	self.guideFrames = {}
	self.extraFrames = {}
	self.undoStack = {}
	self.redoStack = {}
	self.clipboard = {}
	self.pasteCount = 0
	self.menus = {}
	self.menuContext = { point = Vector2.zero, over = false }
	self.connections = {}

	self.view = newRect()
	self.hv = newRect()
	self.dragAlpha = 0
	self.readoutAlpha = 0
	self.statusAlpha = 0
	self.statusTimer = 0

	local overlay = self.overlay

	self.hit = UI.create("TextButton", {
		Name = "GuiEditorHit",
		Text = "",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Active = true,
		InputSink = false,
		ZIndex = 0,
		Visible = self.canPick,
	}, overlay)

	self.hover = UI.create("Frame", {
		Name = "GuiEditorHover",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
		InputSink = false,
		Visible = false,
		ZIndex = Z - 1,
	}, overlay)

	self.hoverStroke = UI.stroke(self.hover, colors.accent, 1, 1)

	self.box = UI.create("TextButton", {
		Name = "GuiEditorBox",
		Text = "",
		BackgroundColor3 = colors.accent,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Active = true,
		InputSink = true,
		Visible = false,
		ZIndex = Z,
	}, overlay)

	self.boxStroke = UI.stroke(self.box, colors.accent, 1, 1)

	self.handles = {}
	self.handleDefs = {}
	self.handleStrokes = {}
	self.handleState = {}

	for _, definition in ipairs(RESIZE_HANDLES) do
		local handle = UI.create("TextButton", {
			Name = "Handle" .. definition.name,
			Text = "",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(definition.x, definition.y),
			Size = UDim2.fromOffset(HANDLE_SIZE, HANDLE_SIZE),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Active = true,
			InputSink = true,
			Visible = false,
			ZIndex = Z + 1,
		}, self.box)

		UI.corner(handle, 2)

		local state = { show = 0, hover = 0, hovered = false }

		handle.MouseButton1Down:Connect(function()
			self:beginDrag("resize", definition)
		end)

		handle.MouseEnter:Connect(function()
			state.hovered = true
		end)

		handle.MouseLeave:Connect(function()
			state.hovered = false
		end)

		self.handles[definition.name] = handle
		self.handleDefs[definition.name] = definition
		self.handleStrokes[definition.name] = UI.stroke(handle, colors.accent, 1, 0)
		self.handleState[definition.name] = state
	end

	self.rotateStem = UI.create("Frame", {
		Name = "RotateStem",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(1, 16),
		BackgroundColor3 = colors.accent,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = Z + 1,
	}, self.box)

	self.rotateHandle = UI.create("TextButton", {
		Name = "RotateHandle",
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, -22),
		Size = UDim2.fromOffset(11, 11),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Active = true,
		InputSink = true,
		Visible = false,
		ZIndex = Z + 2,
	}, self.box)

	UI.corner(self.rotateHandle, 6)
	self.rotateStroke = UI.stroke(self.rotateHandle, colors.accent, 1, 0)
	self.rotateState = { show = 0, hover = 0, hovered = false }

	self.rotateHandle.MouseButton1Down:Connect(function()
		self:beginDrag("rotate")
	end)

	self.rotateHandle.MouseEnter:Connect(function()
		self.rotateState.hovered = true
	end)

	self.rotateHandle.MouseLeave:Connect(function()
		self.rotateState.hovered = false
	end)

	self.readout = UI.label(overlay, "", UDim2.fromOffset(0, 0), UDim2.fromOffset(80, 18), tokens.type.caption, WHITE)
	self.readout.BackgroundColor3 = colors.accent
	self.readout.BackgroundTransparency = 1
	self.readout.TextTransparency = 1
	self.readout.TextXAlignment = Enum.TextXAlignment.Center
	self.readout.TextYAlignment = Enum.TextYAlignment.Center
	self.readout.ZIndex = Z + 3
	self.readout.Visible = false
	UI.corner(self.readout, 4)

	self.status =
		UI.label(overlay, "", UDim2.new(0.5, 0, 0, 10), UDim2.fromOffset(160, 24), tokens.type.small, colors.text)
	self.status.AnchorPoint = Vector2.new(0.5, 0)
	self.status.BackgroundColor3 = colors.secondary
	self.status.BackgroundTransparency = 1
	self.status.TextTransparency = 1
	self.status.TextXAlignment = Enum.TextXAlignment.Center
	self.status.TextYAlignment = Enum.TextYAlignment.Center
	self.status.ZIndex = Z + 3
	self.status.Visible = false
	UI.corner(self.status, 5)
	self.statusStroke = UI.stroke(self.status, colors.line, 1, 1)

	self.catcher = UI.create("TextButton", {
		Name = "GuiEditorMenuCatcher",
		Text = "",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Active = true,
		InputSink = true,
		Visible = false,
		ZIndex = MENU_Z - 1,
	}, overlay)

	self.catcher.MouseButton1Down:Connect(function()
		self:closeMenus()
	end)

	self.catcher.MouseButton2Down:Connect(function(x, y)
		self:closeMenus()
		self:onRightClick(Vector2.new(x, y))
	end)

	local function startMove()
		self:beginDrag("move")
	end

	self.box.MouseButton1Down:Connect(startMove)

	self.box.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			startMove()
		end
	end)

	self.box.MouseButton2Down:Connect(function(x, y)
		self:onRightClick(Vector2.new(x, y))
	end)

	self.box.MouseEnter:Connect(function()
		self.hoverObj = nil
	end)

	self.hit.MouseButton1Down:Connect(function(x, y)
		self:pickAt(Vector2.new(x, y))
	end)

	self.hit.MouseButton2Down:Connect(function(x, y)
		self:onRightClick(Vector2.new(x, y))
	end)

	self.hit.MouseMoved:Connect(function(x, y)
		if not self.drag then
			self.hoverObj = self:findAt(Vector2.new(x, y))
		end
	end)

	self.hit.MouseLeave:Connect(function()
		self.hoverObj = nil
	end)

	table.insert(
		self.connections,
		UserInputService.InputChanged:Connect(function(input)
			if self.drag and input.UserInputType == Enum.UserInputType.MouseMovement then
				self:applyDrag(UserInputService:GetMouseLocation())
			end
		end)
	)

	table.insert(
		self.connections,
		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				self:endDrag()
			end
		end)
	)

	table.insert(
		self.connections,
		UserInputService.InputBegan:Connect(function(input)
			self:onKey(input)
		end)
	)

	table.insert(
		self.connections,
		Selection.SelectionChanged:Connect(function()
			self:refresh()
		end)
	)

	table.insert(
		self.connections,
		RunService.Heartbeat:Connect(function(dt)
			self:tick(dt)
		end)
	)

	self:refresh()

	return self
end

function Editor:screenGuiOf(obj)
	local screenGui = obj:FindFirstAncestorWhichIsA("ScreenGui")

	if screenGui and screenGui.Parent == StarterGui then
		return screenGui
	end

	return nil
end

function Editor:parentInfo(obj)
	local parent = obj.Parent

	if parent and parent:IsA("GuiBase2d") then
		local size = parent.AbsoluteSize

		if parent:IsA("ScreenGui") and (size.X <= 0 or size.Y <= 0) then
			size = parent.Size
		end

		return Vector2.new(math.max(size.X, 1), math.max(size.Y, 1)), parent.AbsolutePosition
	end

	return Vector2.new(1, 1), Vector2.zero
end

function Editor:isLocked(obj)
	local ok, value = pcall(function()
		return obj:GetAttribute(LOCK_ATTR)
	end)

	return ok and value == true
end

function Editor:snapping()
	if isAlt() then
		return false
	end

	return self.getSnap() == true
end

function Editor:targets()
	local out = {}

	for _, obj in ipairs(self.selection) do
		if not self:isLocked(obj) then
			table.insert(out, obj)
		end
	end

	return out
end

function Editor:setSelection(list)
	pcall(function()
		Selection:Set(list)
	end)

	self:refresh()
end

function Editor:refresh()
	local list = {}
	local selected = Selection:Get()

	for _, obj in ipairs(selected or {}) do
		if obj:IsA("GuiObject") and self:screenGuiOf(obj) then
			table.insert(list, obj)
		end
	end

	self.selection = list

	local newTarget = list[1]

	if newTarget ~= self.target then
		self.drag = nil
	end

	self.target = newTarget
end

function Editor:SetEnabled(value)
	value = value == true

	if self.enabled and not value then
		self:closeMenus()
		self:cancelDrag()
	end

	self.enabled = value
end

function Editor:IsDragging()
	return self.drag ~= nil
end

function Editor:Update() end

function Editor:Notify(text)
	self.status.Text = tostring(text)
	self.status.Size = UDim2.fromOffset(#self.status.Text * 6.6 + 28, 24)
	self.statusTimer = 1.8
end

Editor.notify = Editor.Notify

function Editor:SetSnapStep(step)
	self.snapStep = math.max(1, step or 1)
end

function Editor:SetGuides(value)
	self.guides = value == true
end

function Editor:SetSmoothDrag(value)
	self.smoothDrag = value == true
end

local function isVisibleChain(obj)
	local current = obj

	while current and current:IsA("GuiObject") do
		if not current.Visible then
			return false
		end

		current = current.Parent
	end

	return true
end

local function depthOf(obj)
	local depth = 0
	local current = obj.Parent

	while current do
		depth += 1
		current = current.Parent
	end

	return depth
end

function Editor:findAt(point, includeLocked)
	local best, bestZ, bestDepth, bestOrder = nil, -math.huge, -1, -1
	local order = 0

	for _, screenGui in ipairs(StarterGui:GetChildren()) do
		if screenGui:IsA("ScreenGui") and screenGui.Enabled ~= false then
			for _, obj in ipairs(screenGui:GetDescendants()) do
				if obj:IsA("GuiObject") then
					order += 1

					if isVisibleChain(obj) and (includeLocked or not self:isLocked(obj)) then
						local size = obj.AbsoluteSize
						local center = obj.AbsolutePosition + size / 2
						local v = point - center
						local r = math.rad(-obj.Rotation)
						local lx = v.X * math.cos(r) - v.Y * math.sin(r)
						local ly = v.X * math.sin(r) + v.Y * math.cos(r)

						if math.abs(lx) <= size.X / 2 and math.abs(ly) <= size.Y / 2 then
							local z = obj.ZIndex
							local depth = depthOf(obj)

							if
								z > bestZ
								or (z == bestZ and depth > bestDepth)
								or (z == bestZ and depth == bestDepth and order > bestOrder)
							then
								best, bestZ, bestDepth, bestOrder = obj, z, depth, order
							end
						end
					end
				end
			end
		end
	end

	return best
end

function Editor:inSelection(obj)
	for _, o in ipairs(self.selection) do
		if o == obj then
			return true
		end
	end

	return false
end

function Editor:pickAt(point)
	local best = self:findAt(point)

	if best and isShift() then
		local list = {}
		local removed = false

		for _, o in ipairs(self.selection) do
			if o == best then
				removed = true
			else
				table.insert(list, o)
			end
		end

		if not removed then
			table.insert(list, best)
		end

		self:setSelection(list)
		return
	end

	if best then
		if not self:inSelection(best) then
			self:setSelection({ best })
		end
	elseif self.clearOnEmpty then
		self:setSelection({})
	end

	if best and self.target then
		local tool = self.getTool()

		if tool == "Select" or tool == "Move" then
			self:beginDrag("move")
		end
	end
end

function Editor:restore(map)
	for obj, props in pairs(map) do
		self.goals[obj] = nil

		for _, key in ipairs(SNAP_PROPS) do
			local value = props[key]

			if value ~= nil and key ~= "Parent" then
				pcall(function()
					obj[key] = value
				end)
			end
		end

		if props.Parent ~= nil then
			pcall(function()
				obj.Parent = props.Parent ~= NONE and props.Parent or nil
			end)
		end
	end
end

function Editor:commit(label, before, mergeKey)
	local after = {}
	local changed = false

	for obj, props in pairs(before) do
		local current = snapshot(obj)

		after[obj] = current

		for key, value in pairs(props) do
			if current[key] ~= value then
				changed = true
			end
		end
	end

	if not changed then
		return false
	end

	local command = {
		label = label,
		merge = mergeKey,
		time = os.clock(),
		undo = function()
			self:restore(before)
		end,
		redo = function()
			self:restore(after)
		end,
	}

	local top = self.undoStack[#self.undoStack]

	if mergeKey and top and top.merge == mergeKey and os.clock() - top.time < 0.8 then
		top.redo = command.redo
		top.time = command.time
	else
		table.insert(self.undoStack, command)

		if #self.undoStack > 100 then
			table.remove(self.undoStack, 1)
		end
	end

	self.redoStack = {}

	return true
end

function Editor:transact(label, fn, mergeKey)
	local before = {}
	local ctx = {}

	function ctx.touch(obj)
		if before[obj] == nil then
			before[obj] = snapshot(obj)
		end
	end

	function ctx.created(obj)
		before[obj] = { Parent = NONE }
	end

	fn(ctx)

	return self:commit(label, before, mergeKey)
end

function Editor:syncSelection()
	local alive = {}

	for _, obj in ipairs(self.selection) do
		if self:screenGuiOf(obj) then
			table.insert(alive, obj)
		end
	end

	self:setSelection(alive)
end

function Editor:Undo()
	local command = table.remove(self.undoStack)

	if not command then
		self:notify("Nothing to undo")
		return false
	end

	self.drag = nil
	self:flushGoals()

	command.undo()

	table.insert(self.redoStack, command)

	self:syncSelection()
	self:notify("Undo " .. command.label)

	return true
end

function Editor:Redo()
	local command = table.remove(self.redoStack)

	if not command then
		self:notify("Nothing to redo")
		return false
	end

	self.drag = nil
	self:flushGoals()

	command.redo()

	table.insert(self.undoStack, command)

	self:syncSelection()
	self:notify("Redo " .. command.label)

	return true
end

function Editor:collectCandidates(obj)
	local xs, ys = {}, {}
	local parentSize, parentAbs = self:parentInfo(obj)

	local function add(ax, ay, aw, ah)
		table.insert(xs, { v = ax, lo = ay, hi = ay + ah })
		table.insert(xs, { v = ax + aw / 2, lo = ay, hi = ay + ah })
		table.insert(xs, { v = ax + aw, lo = ay, hi = ay + ah })

		table.insert(ys, { v = ay, lo = ax, hi = ax + aw })
		table.insert(ys, { v = ay + ah / 2, lo = ax, hi = ax + aw })
		table.insert(ys, { v = ay + ah, lo = ax, hi = ax + aw })
	end

	add(parentAbs.X, parentAbs.Y, parentSize.X, parentSize.Y)

	local parent = obj.Parent
	local count = 0

	if parent then
		for _, sibling in ipairs(parent:GetChildren()) do
			if sibling:IsA("GuiObject") and sibling.Visible and not self:inSelection(sibling) then
				local p, s = sibling.AbsolutePosition, sibling.AbsoluteSize

				add(p.X, p.Y, s.X, s.Y)

				count += 1

				if count >= 200 then
					break
				end
			end
		end
	end

	return xs, ys
end

function Editor:beginDrag(mode, handle)
	local obj = self.target

	if not obj or not self.enabled or self.drag then
		return
	end

	if self:isLocked(obj) then
		self:notify("Object is locked")
		return
	end

	local parentSize, parentAbs = self:parentInfo(obj)
	local pos, size = obj.AbsolutePosition, obj.AbsoluteSize

	local before = {}
	local others = {}

	before[obj] = snapshot(obj)

	if mode == "move" then
		for _, other in ipairs(self.selection) do
			if other ~= obj and not self:isLocked(other) then
				local otherParentSize = self:parentInfo(other)

				before[other] = snapshot(other)

				table.insert(others, { obj = other, position = other.Position, parentSize = otherParentSize })
			end
		end
	end

	local xc, yc = {}, {}

	if mode ~= "rotate" then
		xc, yc = self:collectCandidates(obj)
	end

	self.drag = {
		mode = mode,
		handle = handle,
		mouse = UserInputService:GetMouseLocation(),
		pos = pos,
		size = size,
		position = obj.Position,
		sizeValue = obj.Size,
		rotation = obj.Rotation,
		anchor = obj.AnchorPoint,
		parentSize = parentSize,
		parentAbs = parentAbs,
		center = pos + size / 2,
		before = before,
		others = others,
		xc = xc,
		yc = yc,
		active = false,
	}
end

function Editor:applyProps(obj, props)
	if self.smoothDrag and self.drag then
		local goal = self.goals[obj]

		if not goal then
			goal = {}
			self.goals[obj] = goal
		end

		for key, value in pairs(props) do
			goal[key] = value
		end
	else
		for key, value in pairs(props) do
			obj[key] = value
		end
	end
end

function Editor:flushGoals()
	for obj, goal in pairs(self.goals) do
		if UI.isAlive(obj) then
			for key, value in pairs(goal) do
				obj[key] = value
			end
		end
	end

	self.goals = {}
end

function Editor:collectGuides(d, left, top, right, bottom)
	local out, seen = {}, {}

	local function scan(values, cands, axis)
		for _, v in ipairs(values) do
			for _, c in ipairs(cands) do
				if math.abs(c.v - v) < 0.5 then
					local lo, hi

					if axis == "x" then
						lo, hi = math.min(c.lo, top), math.max(c.hi, bottom)
					else
						lo, hi = math.min(c.lo, left), math.max(c.hi, right)
					end

					local key = axis .. tostring(math.floor(c.v * 2))
					local guide = seen[key]

					if guide then
						guide.lo = math.min(guide.lo, lo)
						guide.hi = math.max(guide.hi, hi)
					else
						guide = { axis = axis, pos = c.v, lo = lo, hi = hi }
						seen[key] = guide
						table.insert(out, guide)
					end
				end
			end
		end
	end

	local xv, yv

	if d.mode == "move" then
		xv = { left, (left + right) / 2, right }
		yv = { top, (top + bottom) / 2, bottom }
	else
		local h = d.handle

		xv, yv = {}, {}

		if h.l then
			table.insert(xv, left)
		end
		if h.r then
			table.insert(xv, right)
		end
		if h.t then
			table.insert(yv, top)
		end
		if h.b then
			table.insert(yv, bottom)
		end
	end

	scan(xv, d.xc, "x")
	scan(yv, d.yc, "y")

	return out
end

function Editor:applyDrag(mouse)
	local d = self.drag
	local obj = self.target

	if not d or not obj or not UI.isAlive(obj) then
		self.drag = nil
		return
	end

	local dx, dy = mouse.X - d.mouse.X, mouse.Y - d.mouse.Y

	if not d.active then
		if math.abs(dx) + math.abs(dy) < 3 then
			return
		end

		d.active = true
	end

	local snap = self:snapping()
	local guidesOn = self.guides and not isAlt()
	local step = self.snapStep
	local pa = d.parentAbs

	if d.mode == "rotate" then
		local v0 = d.mouse - d.center
		local v1 = mouse - d.center
		local delta = math.deg(math.atan2(v1.Y, v1.X) - math.atan2(v0.Y, v0.X))
		local rotation = d.rotation + delta

		if snap then
			rotation = math.floor(rotation / self.rotateSnap + 0.5) * self.rotateSnap
		end

		self:applyProps(obj, { Rotation = rotation % 360 })
		return
	end

	local left, top = d.pos.X, d.pos.Y
	local right, bottom = left + d.size.X, top + d.size.Y

	local function moveEdge(value, delta, cands, origin)
		value += delta

		if guidesOn then
			local snapped = snapAxis({ value }, cands)

			if snapped then
				return value + snapped
			end
		end

		if snap then
			return snapValue(value, origin, step)
		end

		return value
	end

	if d.mode == "move" then
		local w, h = d.size.X, d.size.Y

		left += dx
		top += dy

		local snappedX, snappedY = false, false

		if guidesOn then
			local ddx = snapAxis({ left, left + w / 2, left + w }, d.xc)
			local ddy = snapAxis({ top, top + h / 2, top + h }, d.yc)

			if ddx then
				left += ddx
				snappedX = true
			end

			if ddy then
				top += ddy
				snappedY = true
			end
		end

		if snap then
			if not snappedX then
				left = snapValue(left, pa.X, step)
			end

			if not snappedY then
				top = snapValue(top, pa.Y, step)
			end
		end

		right = left + w
		bottom = top + h
	else
		local h = d.handle

		if h.l then
			left = moveEdge(left, dx, d.xc, pa.X)
		end
		if h.r then
			right = moveEdge(right, dx, d.xc, pa.X)
		end
		if h.t then
			top = moveEdge(top, dy, d.yc, pa.Y)
		end
		if h.b then
			bottom = moveEdge(bottom, dy, d.yc, pa.Y)
		end

		if right - left < MIN_SIZE then
			if h.l then
				left = right - MIN_SIZE
			else
				right = left + MIN_SIZE
			end
		end

		if bottom - top < MIN_SIZE then
			if h.t then
				top = bottom - MIN_SIZE
			else
				bottom = top + MIN_SIZE
			end
		end
	end

	self.guideList = guidesOn and self:collectGuides(d, left, top, right, bottom) or {}

	local newW, newH = right - left, bottom - top
	local a = d.anchor

	local dPosX = (left + a.X * newW) - (d.pos.X + a.X * d.size.X)
	local dPosY = (top + a.Y * newH) - (d.pos.Y + a.Y * d.size.Y)

	local props = {
		Position = udim2(
			shiftUDim(d.position.X, dPosX, d.parentSize.X),
			shiftUDim(d.position.Y, dPosY, d.parentSize.Y)
		),
	}

	if d.mode == "resize" then
		props.Size = udim2(
			shiftUDim(d.sizeValue.X, newW - d.size.X, d.parentSize.X),
			shiftUDim(d.sizeValue.Y, newH - d.size.Y, d.parentSize.Y)
		)
	end

	self:applyProps(obj, props)

	if d.mode == "move" then
		local appliedX, appliedY = left - d.pos.X, top - d.pos.Y

		for _, entry in ipairs(d.others) do
			self:applyProps(entry.obj, {
				Position = udim2(
					shiftUDim(entry.position.X, appliedX, entry.parentSize.X),
					shiftUDim(entry.position.Y, appliedY, entry.parentSize.Y)
				),
			})
		end
	end
end

function Editor:endDrag()
	local d = self.drag

	if not d then
		return
	end

	self.drag = nil
	self.guideList = {}

	self:flushGoals()

	if d.active then
		local label = d.mode == "move" and "Move" or d.mode == "resize" and "Resize" or "Rotate"

		self:commit(label, d.before)
	end
end

function Editor:cancelDrag()
	local d = self.drag

	if not d then
		return
	end

	self.drag = nil
	self.guideList = {}
	self.goals = {}

	self:restore(d.before)
	self:notify("Cancelled")
end

function Editor:nudge(direction)
	local list = self:targets()

	if #list == 0 then
		return
	end

	self:transact("Nudge", function(ctx)
		for _, obj in ipairs(list) do
			ctx.touch(obj)

			local parentSize = self:parentInfo(obj)
			local p = obj.Position

			obj.Position = udim2(shiftUDim(p.X, direction.X, parentSize.X), shiftUDim(p.Y, direction.Y, parentSize.Y))
		end
	end, "nudge")
end

function Editor:ensureScreenGui(ctx)
	for _, child in ipairs(StarterGui:GetChildren()) do
		if child:IsA("ScreenGui") then
			return child
		end
	end

	local screenGui = Instance.new("ScreenGui")

	ctx.created(screenGui)

	screenGui.Name = "ScreenGui"
	screenGui.Parent = StarterGui

	return screenGui
end

function Editor:Delete()
	local list = self:targets()

	if #list == 0 then
		return
	end

	self:transact("Delete", function(ctx)
		for _, obj in ipairs(list) do
			ctx.touch(obj)

			obj.Parent = nil
		end
	end)

	self:setSelection({})
	self:notify(#list == 1 and "Deleted" or ("Deleted " .. #list .. " objects"))
end

function Editor:Copy()
	local clones = {}

	for _, obj in ipairs(self.selection) do
		local ok, clone = pcall(function()
			return obj:Clone()
		end)

		if ok and clone then
			table.insert(clones, clone)
		end
	end

	if #clones == 0 then
		return
	end

	self.clipboard = clones
	self.pasteCount = 0

	self:notify(#clones == 1 and "Copied" or ("Copied " .. #clones .. " objects"))
end

function Editor:Paste()
	if #self.clipboard == 0 then
		self:notify("Clipboard is empty")
		return
	end

	self.pasteCount += 1

	local created = {}
	local offset = 10 * self.pasteCount

	self:transact("Paste", function(ctx)
		local parent = self.target and self.target.Parent or self:ensureScreenGui(ctx)

		for _, source in ipairs(self.clipboard) do
			local ok, clone = pcall(function()
				return source:Clone()
			end)

			if ok and clone then
				ctx.created(clone)

				local parentSize = select(1, self:parentInfo(clone))

				clone.Parent = parent

				parentSize = select(1, self:parentInfo(clone))

				local p = clone.Position

				clone.Position = udim2(shiftUDim(p.X, offset, parentSize.X), shiftUDim(p.Y, offset, parentSize.Y))

				table.insert(created, clone)
			end
		end
	end)

	self:setSelection(created)
	self:notify(#created == 1 and "Pasted" or ("Pasted " .. #created .. " objects"))
end

function Editor:Duplicate()
	local list = self:targets()

	if #list == 0 then
		return
	end

	local created = {}

	self:transact("Duplicate", function(ctx)
		for _, obj in ipairs(list) do
			local ok, clone = pcall(function()
				return obj:Clone()
			end)

			if ok and clone then
				ctx.created(clone)

				clone.Parent = obj.Parent

				local parentSize = self:parentInfo(clone)
				local p = clone.Position

				clone.Position = udim2(shiftUDim(p.X, 10, parentSize.X), shiftUDim(p.Y, 10, parentSize.Y))

				table.insert(created, clone)
			end
		end
	end)

	self:setSelection(created)
	self:notify("Duplicated")
end

function Editor:SelectAll()
	local all = {}

	for _, screenGui in ipairs(StarterGui:GetChildren()) do
		if screenGui:IsA("ScreenGui") then
			for _, child in ipairs(screenGui:GetChildren()) do
				if child:IsA("GuiObject") then
					table.insert(all, child)
				end
			end
		end
	end

	self:setSelection(all)
	self:notify("Selected " .. #all .. " objects")
end

function Editor:Group()
	local list = self:targets()

	if #list == 0 then
		return
	end

	local parent = list[1].Parent
	local members = {}

	for _, obj in ipairs(list) do
		if obj.Parent == parent then
			table.insert(members, obj)
		end
	end

	local minX, minY, maxX, maxY, maxZ = math.huge, math.huge, -math.huge, -math.huge, -math.huge

	for _, obj in ipairs(members) do
		local p, s = obj.AbsolutePosition, obj.AbsoluteSize

		minX = math.min(minX, p.X)
		minY = math.min(minY, p.Y)
		maxX = math.max(maxX, p.X + s.X)
		maxY = math.max(maxY, p.Y + s.Y)
		maxZ = math.max(maxZ, obj.ZIndex)
	end

	local _, parentAbs = self:parentInfo(members[1])
	local frame = Instance.new("Frame")

	self:transact("Group", function(ctx)
		ctx.created(frame)

		frame.Name = "Group"
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.Position = UDim2.fromOffset(round(minX - parentAbs.X), round(minY - parentAbs.Y))
		frame.Size = UDim2.fromOffset(round(maxX - minX), round(maxY - minY))
		frame.ZIndex = maxZ
		frame.Parent = parent

		for _, obj in ipairs(members) do
			ctx.touch(obj)

			local p, s, a = obj.AbsolutePosition, obj.AbsoluteSize, obj.AnchorPoint
			local anchorAbs = p + Vector2.new(a.X * s.X, a.Y * s.Y)

			obj.Parent = frame
			obj.Position = UDim2.fromOffset(round(anchorAbs.X - minX), round(anchorAbs.Y - minY))
			obj.Size = UDim2.fromOffset(round(s.X), round(s.Y))
		end
	end)

	self:setSelection({ frame })
	self:notify("Grouped " .. #members .. " objects")
end

function Editor:Ungroup()
	local frame = self.target

	if not frame or self:isLocked(frame) then
		return
	end

	local kids = {}

	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("GuiObject") then
			table.insert(kids, child)
		end
	end

	if #kids == 0 then
		self:notify("Nothing to ungroup")
		return
	end

	local _, parentAbs = self:parentInfo(frame)
	local newParent = frame.Parent

	self:transact("Ungroup", function(ctx)
		ctx.touch(frame)

		for _, kid in ipairs(kids) do
			ctx.touch(kid)

			local p, s, a = kid.AbsolutePosition, kid.AbsoluteSize, kid.AnchorPoint
			local anchorAbs = p + Vector2.new(a.X * s.X, a.Y * s.Y)

			kid.Parent = newParent
			kid.Position = UDim2.fromOffset(round(anchorAbs.X - parentAbs.X), round(anchorAbs.Y - parentAbs.Y))
			kid.Size = UDim2.fromOffset(round(s.X), round(s.Y))
		end

		frame.Parent = nil
	end)

	self:setSelection(kids)
	self:notify("Ungrouped")
end

function Editor:align(mode)
	local list = self:targets()

	if #list == 0 then
		return
	end

	self:transact("Align", function(ctx)
		for _, obj in ipairs(list) do
			ctx.touch(obj)

			if mode == "fill" then
				obj.AnchorPoint = Vector2.new(0, 0)
				obj.Position = UDim2.new(0, 0, 0, 0)
				obj.Size = UDim2.new(1, 0, 1, 0)
			else
				local ps, pa = self:parentInfo(obj)
				local pos, size = obj.AbsolutePosition, obj.AbsoluteSize
				local dx, dy = 0, 0

				if mode == "left" then
					dx = pa.X - pos.X
				elseif mode == "hcenter" or mode == "center" then
					dx = pa.X + (ps.X - size.X) / 2 - pos.X
				elseif mode == "right" then
					dx = pa.X + ps.X - size.X - pos.X
				end

				if mode == "top" then
					dy = pa.Y - pos.Y
				elseif mode == "vcenter" or mode == "center" then
					dy = pa.Y + (ps.Y - size.Y) / 2 - pos.Y
				elseif mode == "bottom" then
					dy = pa.Y + ps.Y - size.Y - pos.Y
				end

				local p = obj.Position

				obj.Position = udim2(shiftUDim(p.X, dx, ps.X), shiftUDim(p.Y, dy, ps.Y))
			end
		end
	end)
end

function Editor:setAnchor(anchor)
	local list = self:targets()

	if #list == 0 then
		return
	end

	self:transact("Anchor", function(ctx)
		for _, obj in ipairs(list) do
			ctx.touch(obj)

			local ps = self:parentInfo(obj)
			local a1, size, p = obj.AnchorPoint, obj.AbsoluteSize, obj.Position
			local dx, dy = (anchor.X - a1.X) * size.X, (anchor.Y - a1.Y) * size.Y

			obj.AnchorPoint = anchor
			obj.Position = udim2(shiftUDim(p.X, dx, ps.X), shiftUDim(p.Y, dy, ps.Y))
		end
	end)
end

function Editor:convertUnits(toScale)
	local list = self:targets()

	if #list == 0 then
		return
	end

	local function convert(u, span)
		local px = u.Scale * span + u.Offset

		if toScale then
			return UDim.new(px / span, 0)
		end

		return UDim.new(0, round(px))
	end

	self:transact("Convert units", function(ctx)
		for _, obj in ipairs(list) do
			ctx.touch(obj)

			local ps = self:parentInfo(obj)
			local p, s = obj.Position, obj.Size

			obj.Position = udim2(convert(p.X, ps.X), convert(p.Y, ps.Y))
			obj.Size = udim2(convert(s.X, ps.X), convert(s.Y, ps.Y))
		end
	end)

	self:notify(toScale and "Converted to Scale" or "Converted to Offset")
end

function Editor:reorder(mode)
	local list = self:targets()

	if #list == 0 then
		return
	end

	self:transact("Reorder", function(ctx)
		for _, obj in ipairs(list) do
			ctx.touch(obj)

			local maxZ, minZ = obj.ZIndex, obj.ZIndex

			if obj.Parent then
				for _, sibling in ipairs(obj.Parent:GetChildren()) do
					if sibling:IsA("GuiObject") then
						maxZ = math.max(maxZ, sibling.ZIndex)
						minZ = math.min(minZ, sibling.ZIndex)
					end
				end
			end

			if mode == "front" then
				obj.ZIndex = maxZ + 1
			elseif mode == "back" then
				obj.ZIndex = minZ - 1
			elseif mode == "forward" then
				obj.ZIndex = obj.ZIndex + 1
			elseif mode == "backward" then
				obj.ZIndex = obj.ZIndex - 1
			end
		end
	end)
end

function Editor:resetRotation()
	local list = self:targets()

	self:transact("Reset rotation", function(ctx)
		for _, obj in ipairs(list) do
			ctx.touch(obj)

			obj.Rotation = 0
		end
	end)
end

function Editor:toggleVisible()
	local list = self.selection
	local hide = self.target and self.target.Visible

	self:transact(hide and "Hide" or "Show", function(ctx)
		for _, obj in ipairs(list) do
			ctx.touch(obj)

			obj.Visible = not hide
		end
	end)
end

function Editor:toggleLock()
	local lock = self.target and not self:isLocked(self.target)

	for _, obj in ipairs(self.selection) do
		pcall(function()
			obj:SetAttribute(LOCK_ATTR, lock and true or nil)
		end)
	end

	self:notify(lock and "Locked" or "Unlocked")
end

function Editor:insertObject(class)
	local ok, obj = pcall(Instance.new, class)

	if not ok or not obj then
		self:notify("Cannot create " .. class)
		return
	end

	local point = self.menuContext.point
	local over = self.menuContext.over and self.target ~= nil

	self:transact("Insert " .. class, function(ctx)
		ctx.created(obj)

		local parent = over and self.target or self:ensureScreenGui(ctx)
		local parentAbs = Vector2.zero

		if parent:IsA("GuiBase2d") then
			parentAbs = parent.AbsolutePosition
		end

		obj.Name = class
		obj.Position = UDim2.fromOffset(round(point.X - parentAbs.X), round(point.Y - parentAbs.Y))
		obj.Size = UDim2.fromOffset(class:find("Label") and 120 or 100, class:find("Text") and 30 or 100)

		pcall(function()
			obj.BackgroundColor3 = WHITE
			obj.BorderSizePixel = 0
		end)

		if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
			obj.Text = class == "TextBox" and "" or class
			obj.TextColor3 = Color3.new(0, 0, 0)
		end

		obj.Parent = parent
	end)

	self:setSelection({ obj })
	self:notify("Inserted " .. class)
end

function Editor:onKey(input)
	if not self.enabled then
		return
	end

	local key = input.KeyCode

	if key == Enum.KeyCode.Unknown then
		return
	end

	local ok, focused = pcall(function()
		return UserInputService:GetFocusedTextBox()
	end)

	if ok and focused then
		return
	end

	if key == Enum.KeyCode.Escape then
		if #self.menus > 0 then
			self:closeMenus()
		elseif self.drag then
			self:cancelDrag()
		end

		return
	end

	local direction = ARROWS[key]

	if direction and self.target and #self.menus == 0 and not self.drag then
		self:nudge(direction * (isShift() and 10 or 1))
		return
	end

	if not self.shortcuts then
		return
	end

	if key == Enum.KeyCode.Delete and self.target then
		self:Delete()
		return
	end

	if not isCtrl() then
		return
	end

	if key == Enum.KeyCode.Z then
		if isShift() then
			if #self.redoStack > 0 then
				self:Redo()
			end
		elseif #self.undoStack > 0 then
			self:Undo()
		end
	elseif key == Enum.KeyCode.Y then
		if #self.redoStack > 0 then
			self:Redo()
		end
	elseif key == Enum.KeyCode.C and self.target then
		self:Copy()
	elseif key == Enum.KeyCode.V and #self.clipboard > 0 then
		self:Paste()
	elseif key == Enum.KeyCode.D and self.target then
		self:Duplicate()
	elseif key == Enum.KeyCode.G and self.target then
		if isShift() then
			self:Ungroup()
		else
			self:Group()
		end
	elseif key == Enum.KeyCode.A and self.target then
		self:SelectAll()
	elseif key == Enum.KeyCode.RightBracket and self.target then
		self:reorder(isShift() and "front" or "forward")
	elseif key == Enum.KeyCode.LeftBracket and self.target then
		self:reorder(isShift() and "back" or "backward")
	end
end

function Editor:onRightClick(point)
	if not self.contextMenu or not self.enabled or self.drag then
		return
	end

	local hit = self:findAt(point, true)
	local over = false

	if hit then
		over = true

		if not self:inSelection(hit) then
			self:setSelection({ hit })
		end
	elseif not self.contextOnEmpty then
		return
	end

	self.menuContext = { point = point, over = over }

	self:openMenu(self:contextItems(over), point, 1, nil)
end

function Editor:contextItems(over)
	local hasSel = #self.selection > 0 and over
	local primary = self.target
	local locked = primary ~= nil and self:isLocked(primary)

	local function item(text, callback, o)
		o = o or {}

		return {
			text = text,
			callback = callback,
			shortcut = o.shortcut,
			enabled = o.enabled ~= false,
			check = o.check,
			submenu = o.submenu,
		}
	end

	local sep = { separator = true }

	local insertItems = {}

	for _, class in ipairs(INSERTABLE) do
		table.insert(
			insertItems,
			item(class, function()
				self:insertObject(class)
			end)
		)
	end

	local settingsItems = {}

	for _, stepSize in ipairs({ 1, 2, 4, 8, 16 }) do
		table.insert(
			settingsItems,
			item(stepSize .. " px snap", function()
				self.snapStep = stepSize
				self:notify("Snap step " .. stepSize .. " px")
			end, { check = self.snapStep == stepSize })
		)
	end

	table.insert(settingsItems, sep)

	table.insert(
		settingsItems,
		item("Smart guides", function()
			self.guides = not self.guides
			self:notify(self.guides and "Smart guides on" or "Smart guides off")
		end, { check = self.guides })
	)

	table.insert(
		settingsItems,
		item("Smooth drag", function()
			self.smoothDrag = not self.smoothDrag
			self:notify(self.smoothDrag and "Smooth drag on" or "Smooth drag off")
		end, { check = self.smoothDrag })
	)

	local items = {}

	local function add(entry)
		table.insert(items, entry)
	end

	if hasSel then
		local canUngroup = false

		if primary and primary:IsA("Frame") then
			for _, child in ipairs(primary:GetChildren()) do
				if child:IsA("GuiObject") then
					canUngroup = true
					break
				end
			end
		end

		local orderItems = {
			item("Bring to front", function()
				self:reorder("front")
			end, { shortcut = "Ctrl+Shift+]" }),
			item("Move forward", function()
				self:reorder("forward")
			end, { shortcut = "Ctrl+]" }),
			item("Move backward", function()
				self:reorder("backward")
			end, { shortcut = "Ctrl+[" }),
			item("Send to back", function()
				self:reorder("back")
			end, { shortcut = "Ctrl+Shift+[" }),
		}

		local alignItems = {
			item("Left", function()
				self:align("left")
			end),
			item("Centre horizontally", function()
				self:align("hcenter")
			end),
			item("Right", function()
				self:align("right")
			end),
			sep,
			item("Top", function()
				self:align("top")
			end),
			item("Centre vertically", function()
				self:align("vcenter")
			end),
			item("Bottom", function()
				self:align("bottom")
			end),
			sep,
			item("Centre in parent", function()
				self:align("center")
			end),
			item("Fill parent", function()
				self:align("fill")
			end),
		}

		local anchorItems = {}

		for _, entry in ipairs(ANCHORS) do
			local name, vector = entry[1], entry[2]

			table.insert(
				anchorItems,
				item(name, function()
					self:setAnchor(vector)
				end, { check = primary ~= nil and primary.AnchorPoint == vector })
			)
		end

		local unitItems = {
			item("Convert to Scale", function()
				self:convertUnits(true)
			end),
			item("Convert to Offset", function()
				self:convertUnits(false)
			end),
		}

		add(item("Copy", function()
			self:Copy()
		end, { shortcut = "Ctrl+C" }))
		add(item("Paste", function()
			self:Paste()
		end, { shortcut = "Ctrl+V", enabled = #self.clipboard > 0 }))
		add(item("Duplicate", function()
			self:Duplicate()
		end, { shortcut = "Ctrl+D", enabled = not locked }))
		add(item("Delete", function()
			self:Delete()
		end, { shortcut = "Del", enabled = not locked }))
		add(sep)
		add(item("Insert object", nil, { submenu = insertItems }))
		add(item("Group", function()
			self:Group()
		end, { shortcut = "Ctrl+G", enabled = not locked }))
		add(item("Ungroup", function()
			self:Ungroup()
		end, { shortcut = "Ctrl+Shift+G", enabled = canUngroup and not locked }))
		add(sep)
		add(item("Order", nil, { submenu = orderItems, enabled = not locked }))
		add(item("Align to parent", nil, { submenu = alignItems, enabled = not locked }))
		add(item("Anchor point", nil, { submenu = anchorItems, enabled = not locked }))
		add(item("Units", nil, { submenu = unitItems, enabled = not locked }))
		add(item("Reset rotation", function()
			self:resetRotation()
		end, { enabled = not locked }))
		add(sep)
		add(item(primary and primary.Visible and "Hide" or "Show", function()
			self:toggleVisible()
		end))
		add(item(locked and "Unlock" or "Lock", function()
			self:toggleLock()
		end))
		add(sep)
		add(item("Editor settings", nil, { submenu = settingsItems }))
		add(item("Deselect", function()
			self:setSelection({})
		end))
	else
		add(item("Paste", function()
			self:Paste()
		end, { shortcut = "Ctrl+V", enabled = #self.clipboard > 0 }))
		add(item("Insert object", nil, { submenu = insertItems }))
		add(item("Select all", function()
			self:SelectAll()
		end, { shortcut = "Ctrl+A" }))
		add(sep)
		add(item("Editor settings", nil, { submenu = settingsItems }))
	end

	return items
end

function Editor:closeMenus(fromLevel)
	fromLevel = fromLevel or 1

	for i = #self.menus, fromLevel, -1 do
		local menu = self.menus[i]

		menu.shell:Destroy()

		self.menus[i] = nil
	end

	if #self.menus == 0 then
		self.catcher.Visible = false
	end
end

function Editor:openMenu(items, point, level, rowRect)
	self:closeMenus(level)

	local overlay = self.overlay
	local origin = overlay.AbsolutePosition
	local bounds = overlay.AbsoluteSize

	local height = PAD * 2

	for _, entry in ipairs(items) do
		height += entry.separator and SEP_H or ROW_H
	end

	local x, y

	if rowRect then
		x = rowRect.right - 2

		if x + MENU_W > bounds.X - 4 then
			x = rowRect.left - MENU_W + 2
		end

		y = rowRect.top - PAD
	else
		x, y = point.X - origin.X, point.Y - origin.Y

		if x + MENU_W > bounds.X - 4 then
			x -= MENU_W
		end
	end

	x = math.clamp(x, 4, math.max(4, bounds.X - MENU_W - 4))
	y = math.clamp(y, 4, math.max(4, bounds.Y - height - 4))

	local z = MENU_Z + level * 10

	local shell = UI.create("Frame", {
		Name = "GuiEditorMenu" .. level,
		Position = UDim2.fromOffset(round(x), round(y)),
		Size = UDim2.fromOffset(MENU_W, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = z,
	}, overlay)

	local inner = UI.frame(shell, UDim2.fromOffset(0, 0), UDim2.fromOffset(MENU_W, height), colors.secondary, 6)

	inner.BackgroundTransparency = 0.08
	inner.ZIndex = z + 1

	UI.stroke(inner, colors.line, 1, 0)
	UI.backdrop(inner)

	local menu = { shell = shell, inner = inner, level = level, cur = 0, h = height, rows = {} }

	table.insert(self.menus, menu)
	self.catcher.Visible = true

	local cursorY = PAD

	for _, entry in ipairs(items) do
		if entry.separator then
			local line = UI.separator(
				inner,
				UDim2.fromOffset(PAD + 6, cursorY + math.floor(SEP_H / 2)),
				UDim2.fromOffset(MENU_W - (PAD + 6) * 2, 1),
				colors.line
			)

			line.ZIndex = z + 2

			cursorY += SEP_H
		else
			local enabled = entry.enabled ~= false

			local row = UI.create("TextButton", {
				Text = "",
				Position = UDim2.fromOffset(PAD, cursorY),
				Size = UDim2.fromOffset(MENU_W - PAD * 2, ROW_H),
				BackgroundColor3 = colors.accent,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Active = enabled,
				InputSink = true,
				ZIndex = z + 2,
			}, inner)

			UI.corner(row, 4)

			local label = UI.label(
				row,
				entry.text,
				UDim2.fromOffset(24, 0),
				UDim2.new(1, -24 - (entry.shortcut and 84 or 22), 1, 0),
				tokens.type.small,
				enabled and colors.text or colors.muted
			)

			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextYAlignment = Enum.TextYAlignment.Center
			label.ZIndex = z + 3

			if entry.check then
				local dot = UI.frame(
					row,
					UDim2.fromOffset(10, math.floor(ROW_H / 2) - 3),
					UDim2.fromOffset(6, 6),
					colors.accent,
					3
				)

				dot.ZIndex = z + 3
			end

			if entry.shortcut then
				local hint = UI.label(
					row,
					entry.shortcut,
					UDim2.new(1, -90, 0, 0),
					UDim2.fromOffset(82, ROW_H),
					tokens.type.caption,
					colors.muted
				)

				hint.TextXAlignment = Enum.TextXAlignment.Right
				hint.TextYAlignment = Enum.TextYAlignment.Center
				hint.ZIndex = z + 3
			end

			if entry.submenu then
				local arrow = UI.image(row, CHEVRON, UDim2.new(1, -18, 0.5, -5), UDim2.fromOffset(10, 10))

				arrow.Rotation = -90
				arrow.ZIndex = z + 3
			end

			local record = { button = row, hover = 0, hovered = false, enabled = enabled }

			table.insert(menu.rows, record)

			local function openSub()
				local position = row.AbsolutePosition - origin

				self:openMenu(entry.submenu, nil, level + 1, {
					left = position.X,
					right = position.X + row.AbsoluteSize.X + PAD,
					top = position.Y,
				})
			end

			row.MouseEnter:Connect(function()
				record.hovered = true

				if not enabled then
					return
				end

				if entry.submenu then
					openSub()
				else
					self:closeMenus(level + 1)
				end
			end)

			row.MouseLeave:Connect(function()
				record.hovered = false
			end)

			row.MouseButton1Click:Connect(function()
				if not enabled then
					return
				end

				if entry.submenu then
					openSub()
				elseif entry.callback then
					self:closeMenus()
					entry.callback()
				end
			end)

			cursorY += ROW_H
		end
	end
end

function Editor:tick(dt)
	dt = math.min(dt, 0.1)

	self:tickGoals(dt)
	self:tickBox(dt)
	self:tickExtras()
	self:tickHover(dt)
	self:tickGuides()
	self:tickChips(dt)
	self:tickMenus(dt)
end

function Editor:tickGoals(dt)
	local k = 1 - math.exp(-self.smoothSpeed * dt)

	for obj, goal in pairs(self.goals) do
		if not UI.isAlive(obj) then
			self.goals[obj] = nil
		else
			local done = true

			if goal.Position then
				local current = obj.Position

				if closeUDim2(current, goal.Position) then
					obj.Position = goal.Position
				else
					obj.Position = stepUDim2(current, goal.Position, k)
					done = false
				end
			end

			if goal.Size then
				local current = obj.Size

				if closeUDim2(current, goal.Size) then
					obj.Size = goal.Size
				else
					obj.Size = stepUDim2(current, goal.Size, k)
					done = false
				end
			end

			if goal.Rotation then
				local current = obj.Rotation
				local delta = ((goal.Rotation - current + 180) % 360) - 180

				if math.abs(delta) < 0.05 then
					obj.Rotation = goal.Rotation
				else
					obj.Rotation = current + delta * k
					done = false
				end
			end

			if done then
				self.goals[obj] = nil
			end
		end
	end
end

function Editor:tickBox(dt)
	local obj = self.target

	if obj and (not UI.isAlive(obj) or not self:screenGuiOf(obj)) then
		self.target = nil
		self.drag = nil
		obj = nil
	end

	local show = self.enabled and obj ~= nil
	local v = self.view

	local canMove, canSize, canRotate = false, false, false
	local locked = false

	if show then
		local size = obj.AbsoluteSize
		local pos = obj.AbsolutePosition - self.overlay.AbsolutePosition
		local rotation = obj.Rotation
		local tool = self.getTool()
		local r = rotation % 360
		local unrotated = r < 0.01 or r > 359.99

		locked = self:isLocked(obj)

		canMove = not locked and (tool == "Select" or tool == "Move")
		canSize = not locked and (tool == "Select" or tool == "Size") and unrotated
		canRotate = not locked and tool == "Rotate"

		stepRect(v, pos.X, pos.Y, size.X, size.Y, rotation, self.followSpeed, dt, self.drag ~= nil)
	end

	local alphaTarget = show and 1 or 0

	v.alpha = damp(v.alpha, alphaTarget, 16, dt)

	if math.abs(v.alpha - alphaTarget) < 0.01 then
		v.alpha = alphaTarget
	end

	if v.alpha <= 0.01 and not show then
		self.box.Visible = false
		v.ready = false
		return
	end

	local box = self.box
	local rotated = math.abs(((v.rot + 180) % 360) - 180) > 0.05

	if not rotated then
		box.AnchorPoint = Vector2.new(0, 0)
		box.Position = UDim2.fromOffset(round(v.x), round(v.y))
		box.Size = UDim2.fromOffset(math.max(round(v.w), 1), math.max(round(v.h), 1))
		box.Rotation = 0
	else
		box.AnchorPoint = Vector2.new(0.5, 0.5)
		box.Position = UDim2.fromOffset(v.x + v.w / 2, v.y + v.h / 2)
		box.Size = UDim2.fromOffset(math.max(v.w, 1), math.max(v.h, 1))
		box.Rotation = v.rot
	end

	box.Visible = true
	box.Active = canMove
	box.InputSink = canMove

	self.dragAlpha = damp(self.dragAlpha, (self.drag and self.drag.active) and 1 or 0, 18, dt)
	box.BackgroundTransparency = 1 - 0.1 * self.dragAlpha

	self.boxStroke.Color = locked and colors.warning or colors.accent
	self.boxStroke.Transparency = 1 - v.alpha

	local small = v.w < 30 or v.h < 30

	for name, handle in pairs(self.handles) do
		local state = self.handleState[name]
		local want = (canSize and (not small or self.handleDefs[name].corner)) and 1 or 0

		state.show = damp(state.show, want, 20, dt)
		state.hover = damp(state.hover, state.hovered and 1 or 0, 24, dt)

		local a = state.show * v.alpha
		local size = (HANDLE_SIZE + 3 * state.hover) * (0.5 + 0.5 * state.show)

		handle.Visible = a > 0.02
		handle.Size = UDim2.fromOffset(size, size)
		handle.BackgroundColor3 = WHITE:Lerp(colors.accent, state.hover)
		handle.BackgroundTransparency = 1 - a

		self.handleStrokes[name].Transparency = 1 - a
	end

	local rs = self.rotateState

	rs.show = damp(rs.show, canRotate and 1 or 0, 20, dt)
	rs.hover = damp(rs.hover, rs.hovered and 1 or 0, 24, dt)

	local ra = rs.show * v.alpha
	local rsize = (11 + 3 * rs.hover) * (0.5 + 0.5 * rs.show)

	self.rotateHandle.Visible = ra > 0.02
	self.rotateHandle.Size = UDim2.fromOffset(rsize, rsize)
	self.rotateHandle.BackgroundColor3 = WHITE:Lerp(colors.accent, rs.hover)
	self.rotateHandle.BackgroundTransparency = 1 - ra
	self.rotateStroke.Transparency = 1 - ra
	self.rotateStem.Visible = ra > 0.02
	self.rotateStem.BackgroundTransparency = 1 - ra

	local dragging = self.drag ~= nil and self.drag.active

	self.readoutAlpha = damp(self.readoutAlpha, dragging and show and 1 or 0, 20, dt)

	if dragging and show then
		local _, parentAbs = self:parentInfo(obj)
		local rel = obj.AbsolutePosition - parentAbs
		local size = obj.AbsoluteSize
		local mode = self.drag.mode
		local text

		if mode == "rotate" then
			text = string.format("%d°", round(obj.Rotation))
		elseif mode == "resize" then
			text = string.format("%d × %d", round(size.X), round(size.Y))
		else
			text = string.format("%d, %d", round(rel.X), round(rel.Y))
		end

		local width = #text * 6.5 + 18
		local bounds = self.overlay.AbsoluteSize

		self.readout.Text = text
		self.readout.Size = UDim2.fromOffset(width, 18)
		self.readout.Position = UDim2.fromOffset(
			math.clamp(v.x + v.w / 2 - width / 2, 0, math.max(bounds.X - width, 0)),
			math.clamp(v.y + v.h + 10, 0, math.max(bounds.Y - 18, 0))
		)
	end

	self.readout.Visible = self.readoutAlpha > 0.02
	self.readout.BackgroundTransparency = 1 - 0.9 * self.readoutAlpha
	self.readout.TextTransparency = 1 - self.readoutAlpha
end

function Editor:tickExtras()
	local used = 0

	if self.enabled then
		for _, obj in ipairs(self.selection) do
			if obj ~= self.target and UI.isAlive(obj) then
				used += 1

				local frame = self.extraFrames[used]

				if not frame then
					frame = UI.create("Frame", {
						Name = "GuiEditorExtra",
						AnchorPoint = Vector2.new(0.5, 0.5),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Active = false,
						InputSink = false,
						ZIndex = Z - 1,
					}, self.overlay)

					UI.stroke(frame, colors.accent, 1, 0.35)

					self.extraFrames[used] = frame
				end

				local size = obj.AbsoluteSize
				local center = obj.AbsolutePosition - self.overlay.AbsolutePosition + size / 2

				frame.Position = UDim2.fromOffset(center.X, center.Y)
				frame.Size = UDim2.fromOffset(math.max(size.X, 1), math.max(size.Y, 1))
				frame.Rotation = obj.Rotation
				frame.Visible = true
			end
		end
	end

	for i = used + 1, #self.extraFrames do
		self.extraFrames[i].Visible = false
	end
end

function Editor:tickHover(dt)
	local obj = self.hoverObj

	if obj and (not UI.isAlive(obj) or obj == self.target or self.drag or not self.enabled or #self.menus > 0) then
		obj = nil
	end

	local hv = self.hv

	if obj then
		local size = obj.AbsoluteSize
		local pos = obj.AbsolutePosition - self.overlay.AbsolutePosition

		stepRect(hv, pos.X, pos.Y, size.X, size.Y, obj.Rotation, 34, dt, false)
	end

	local target = obj and 1 or 0

	hv.alpha = damp(hv.alpha, target, 18, dt)

	if math.abs(hv.alpha - target) < 0.01 then
		hv.alpha = target
	end

	if not obj and hv.alpha <= 0.01 then
		self.hover.Visible = false
		hv.ready = false
		return
	end

	self.hover.Visible = true
	self.hover.Position = UDim2.fromOffset(hv.x + hv.w / 2, hv.y + hv.h / 2)
	self.hover.Size = UDim2.fromOffset(math.max(hv.w, 1), math.max(hv.h, 1))
	self.hover.Rotation = hv.rot
	self.hoverStroke.Transparency = 1 - 0.55 * hv.alpha
end

function Editor:tickGuides()
	local origin = self.overlay.AbsolutePosition
	local used = 0

	if self.drag and self.drag.active then
		for _, guide in ipairs(self.guideList) do
			used += 1

			local frame = self.guideFrames[used]

			if not frame then
				frame = UI.create("Frame", {
					Name = "GuiEditorGuide",
					BackgroundColor3 = GUIDE_COLOR,
					BorderSizePixel = 0,
					Active = false,
					InputSink = false,
					ZIndex = Z - 2,
				}, self.overlay)

				self.guideFrames[used] = frame
			end

			if guide.axis == "x" then
				frame.Position = UDim2.fromOffset(round(guide.pos - origin.X), round(guide.lo - origin.Y))
				frame.Size = UDim2.fromOffset(1, math.max(round(guide.hi - guide.lo), 1))
			else
				frame.Position = UDim2.fromOffset(round(guide.lo - origin.X), round(guide.pos - origin.Y))
				frame.Size = UDim2.fromOffset(math.max(round(guide.hi - guide.lo), 1), 1)
			end

			frame.Visible = true
		end
	end

	for i = used + 1, #self.guideFrames do
		self.guideFrames[i].Visible = false
	end
end

function Editor:tickChips(dt)
	self.statusTimer = math.max(self.statusTimer - dt, 0)

	local target = self.statusTimer > 0 and 1 or 0

	self.statusAlpha = damp(self.statusAlpha, target, 16, dt)

	if math.abs(self.statusAlpha - target) < 0.01 then
		self.statusAlpha = target
	end

	local a = self.statusAlpha

	self.status.Visible = a > 0.02
	self.status.BackgroundTransparency = 1 - 0.92 * a
	self.status.TextTransparency = 1 - a
	self.statusStroke.Transparency = 1 - a
	self.status.Position = UDim2.new(0.5, 0, 0, 6 + 6 * a)
end

function Editor:tickMenus(dt)
	for _, menu in ipairs(self.menus) do
		menu.cur = damp(menu.cur, menu.h, 24, dt)

		if math.abs(menu.cur - menu.h) < 0.5 then
			menu.cur = menu.h
		end

		menu.shell.Size = UDim2.fromOffset(MENU_W, round(menu.cur))

		for _, row in ipairs(menu.rows) do
			row.hover = damp(row.hover, (row.hovered and row.enabled) and 1 or 0, 26, dt)
			row.button.BackgroundTransparency = 1 - 0.9 * row.hover
		end
	end
end

function Editor:Destroy()
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end

	self.connections = {}

	self:closeMenus()

	UI.forgetButtons(self.hit)
	UI.forgetButtons(self.box)

	self.hit:Destroy()
	self.hover:Destroy()
	self.box:Destroy()
	self.readout:Destroy()
	self.status:Destroy()
	self.catcher:Destroy()

	for _, frame in ipairs(self.guideFrames) do
		frame:Destroy()
	end

	for _, frame in ipairs(self.extraFrames) do
		frame:Destroy()
	end
end

return Editor

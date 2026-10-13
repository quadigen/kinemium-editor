local UI = require("@internal/editor_ui")

local Selection = game:GetService("Selection")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local colors = UI.colors
local tokens = UI.tokens

local HANDLE_SIZE = 7
local MIN_SIZE = 4
local Z = 10
local WHITE = Color3.new(1, 1, 1)

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

local Editor = {}
Editor.__index = Editor

local function shiftUDim(u, deltaPx, span)
	if u.Scale ~= 0 and u.Offset == 0 and span > 0 then
		return UDim.new(u.Scale + deltaPx / span, 0)
	end

	return UDim.new(u.Scale, math.floor(u.Offset + deltaPx + 0.5))
end

local function udim2(x, y)
	return UDim2.new(x.Scale, x.Offset, y.Scale, y.Offset)
end

local function snapValue(value, origin, step)
	return math.floor((value - origin) / step + 0.5) * step + origin
end

local function round(n)
	return math.floor(n + 0.5)
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
	self.enabled = true
	self.target = nil
	self.hoverObj = nil
	self.drag = nil
	self.connections = {}

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
	}, self.overlay)

	self.hover = UI.create("Frame", {
		Name = "GuiEditorHover",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
		InputSink = false,
		Visible = false,
		ZIndex = Z - 1,
	}, self.overlay)

	self.hoverStroke = UI.stroke(self.hover, colors.accent, 1, 0.45)

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
	}, self.overlay)

	UI.stroke(self.box, colors.accent, 1, 0)

	self.handles = {}
	self.handleDefs = {}

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
			ZIndex = Z + 1,
		}, self.box)

		UI.corner(handle, 2)
		UI.stroke(handle, colors.accent, 1, 0)

		handle.MouseButton1Down:Connect(function()
			self:beginDrag("resize", definition)
		end)

		handle.MouseEnter:Connect(function()
			handle.BackgroundColor3 = colors.accent
		end)

		handle.MouseLeave:Connect(function()
			handle.BackgroundColor3 = WHITE
		end)

		self.handles[definition.name] = handle
		self.handleDefs[definition.name] = definition
	end

	self.rotateStem = UI.create("Frame", {
		Name = "RotateStem",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(1, 16),
		BackgroundColor3 = colors.accent,
		BorderSizePixel = 0,
		ZIndex = Z + 1,
		Visible = false,
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
		ZIndex = Z + 2,
		Visible = false,
	}, self.box)

	UI.corner(self.rotateHandle, 6)
	UI.stroke(self.rotateHandle, colors.accent, 1, 0)

	self.rotateHandle.MouseEnter:Connect(function()
		self.rotateHandle.BackgroundColor3 = colors.accent
	end)

	self.rotateHandle.MouseLeave:Connect(function()
		self.rotateHandle.BackgroundColor3 = WHITE
	end)

	self.readout =
		UI.label(self.overlay, "", UDim2.fromOffset(0, 0), UDim2.fromOffset(120, 18), tokens.type.caption, WHITE)
	self.readout.BackgroundColor3 = colors.accent
	self.readout.BackgroundTransparency = 0.1
	self.readout.TextXAlignment = Enum.TextXAlignment.Center
	self.readout.TextYAlignment = Enum.TextYAlignment.Center
	self.readout.ZIndex = Z + 3
	self.readout.Visible = false
	UI.corner(self.readout, 4)

	local function startMove()
		self:beginDrag("move")
	end

	self.box.MouseButton1Down:Connect(startMove)

	self.box.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and not self.drag then
			startMove()
		end
	end)

	self.box.MouseEnter:Connect(function()
		self.hoverObj = nil
	end)

	self.rotateHandle.MouseButton1Down:Connect(function()
		self:beginDrag("rotate")
	end)

	self.hit.MouseButton1Down:Connect(function(x, y)
		self:pickAt(Vector2.new(x, y))
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
				self.drag = nil
			end
		end)
	)

	table.insert(
		self.connections,
		UserInputService.InputBegan:Connect(function(input)
			local direction = ARROWS[input.KeyCode]

			if not direction or not self.enabled or not self.target then
				return
			end

			local ok, focused = pcall(function()
				return UserInputService:GetFocusedTextBox()
			end)

			if ok and focused then
				return
			end

			local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)

			self:nudge(direction * (shift and 10 or 1))
		end)
	)

	table.insert(
		self.connections,
		Selection.SelectionChanged:Connect(function()
			self:refresh()
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

function Editor:snapping()
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) then
		return false
	end

	return self.getSnap() == true
end

function Editor:refresh()
	local selected = Selection:Get()
	local obj = selected and selected[1]

	local newTarget = nil

	if obj and obj:IsA("GuiObject") and self:screenGuiOf(obj) then
		newTarget = obj
	end

	if newTarget ~= self.target then
		self.drag = nil
	end

	self.target = newTarget
end

function Editor:SetEnabled(value)
	self.enabled = value == true
end

function Editor:IsDragging()
	return self.drag ~= nil
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

function Editor:findAt(point)
	local best, bestZ, bestDepth, bestOrder = nil, -math.huge, -1, -1
	local order = 0

	for _, screenGui in ipairs(StarterGui:GetChildren()) do
		if screenGui:IsA("ScreenGui") and screenGui.Enabled ~= false then
			for _, obj in ipairs(screenGui:GetDescendants()) do
				if obj:IsA("GuiObject") then
					order += 1

					if isVisibleChain(obj) then
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

function Editor:pickAt(point)
	local best = self:findAt(point)

	if best then
		pcall(function()
			Selection:Set({ best })
		end)
	elseif self.clearOnEmpty then
		pcall(function()
			Selection:Set({})
		end)
	end

	self:refresh()

	if best and self.target == best then
		local tool = self.getTool()

		if tool == "Select" or tool == "Move" then
			self:beginDrag("move")
		end
	end
end

function Editor:beginDrag(mode, handle)
	local obj = self.target

	if not obj or not self.enabled then
		return
	end

	local parentSize, parentAbs = self:parentInfo(obj)
	local pos, size = obj.AbsolutePosition, obj.AbsoluteSize

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
	}
end

function Editor:applyDrag(mouse)
	local d = self.drag
	local obj = self.target

	if not d or not obj or not UI.isAlive(obj) then
		self.drag = nil
		return
	end

	local snap = self:snapping()
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

		obj.Rotation = rotation % 360
		return
	end

	local dx, dy = mouse.X - d.mouse.X, mouse.Y - d.mouse.Y

	local left, top = d.pos.X, d.pos.Y
	local right, bottom = left + d.size.X, top + d.size.Y

	if d.mode == "move" then
		left += dx
		top += dy

		if snap then
			left = snapValue(left, pa.X, step)
			top = snapValue(top, pa.Y, step)
		end

		right = left + d.size.X
		bottom = top + d.size.Y
	else
		local h = d.handle

		if h.l then
			left += dx
		end
		if h.r then
			right += dx
		end
		if h.t then
			top += dy
		end
		if h.b then
			bottom += dy
		end

		if snap then
			if h.l then
				left = snapValue(left, pa.X, step)
			end
			if h.r then
				right = snapValue(right, pa.X, step)
			end
			if h.t then
				top = snapValue(top, pa.Y, step)
			end
			if h.b then
				bottom = snapValue(bottom, pa.Y, step)
			end
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

	local newW, newH = right - left, bottom - top
	local a = d.anchor

	local dPosX = (left + a.X * newW) - (d.pos.X + a.X * d.size.X)
	local dPosY = (top + a.Y * newH) - (d.pos.Y + a.Y * d.size.Y)

	obj.Position = udim2(shiftUDim(d.position.X, dPosX, d.parentSize.X), shiftUDim(d.position.Y, dPosY, d.parentSize.Y))

	if d.mode == "resize" then
		obj.Size = udim2(
			shiftUDim(d.sizeValue.X, newW - d.size.X, d.parentSize.X),
			shiftUDim(d.sizeValue.Y, newH - d.size.Y, d.parentSize.Y)
		)
	end
end

function Editor:nudge(direction)
	local obj = self.target

	if not obj or not UI.isAlive(obj) then
		return
	end

	local parentSize = self:parentInfo(obj)
	local p = obj.Position

	obj.Position = udim2(shiftUDim(p.X, direction.X, parentSize.X), shiftUDim(p.Y, direction.Y, parentSize.Y))
end

function Editor:Update()
	local obj = self.target

	if obj and (not UI.isAlive(obj) or not self:screenGuiOf(obj)) then
		self.target = nil
		self.drag = nil
		obj = nil
	end

	self.hit.Visible = self.enabled and self.canPick

	local hoverObj = self.hoverObj

	if hoverObj and (not UI.isAlive(hoverObj) or hoverObj == obj or self.drag or not self.enabled) then
		hoverObj = nil
	end

	if hoverObj then
		local hs = hoverObj.AbsoluteSize
		local hc = hoverObj.AbsolutePosition - self.overlay.AbsolutePosition + hs / 2

		self.hover.Position = UDim2.fromOffset(hc.X, hc.Y)
		self.hover.Size = UDim2.fromOffset(math.max(hs.X, 1), math.max(hs.Y, 1))
		self.hover.Rotation = hoverObj.Rotation
		self.hover.Visible = true
	else
		self.hover.Visible = false
	end

	local show = self.enabled and obj ~= nil
	self.box.Visible = show

	if not show then
		self.readout.Visible = false
		return
	end

	local size = obj.AbsoluteSize
	local pos = obj.AbsolutePosition - self.overlay.AbsolutePosition
	local rotation = obj.Rotation

	local tool = self.getTool()
	local r = rotation % 360
	local unrotated = r < 0.01 or r > 359.99

	local canMove = tool == "Select" or tool == "Move"
	local canSize = (tool == "Select" or tool == "Size") and unrotated
	local canRotate = tool == "Rotate"

	if unrotated then
		self.box.AnchorPoint = Vector2.new(0, 0)
		self.box.Position = UDim2.fromOffset(round(pos.X), round(pos.Y))
		self.box.Size = UDim2.fromOffset(math.max(round(size.X), 1), math.max(round(size.Y), 1))
		self.box.Rotation = 0
	else
		local center = pos + size / 2

		self.box.AnchorPoint = Vector2.new(0.5, 0.5)
		self.box.Position = UDim2.fromOffset(center.X, center.Y)
		self.box.Size = UDim2.fromOffset(math.max(size.X, 1), math.max(size.Y, 1))
		self.box.Rotation = rotation
	end

	self.box.Active = canMove
	self.box.InputSink = canMove
	self.box.BackgroundTransparency = self.drag and 0.92 or 1

	local small = size.X < 30 or size.Y < 30

	for name, handle in pairs(self.handles) do
		handle.Visible = canSize and (not small or self.handleDefs[name].corner == true)
	end

	self.rotateHandle.Visible = canRotate
	self.rotateStem.Visible = canRotate

	if self.drag then
		local _, parentAbs = self:parentInfo(obj)
		local rel = obj.AbsolutePosition - parentAbs

		local text
		if self.drag.mode == "rotate" then
			text = string.format("%d°", round(rotation))
		elseif self.drag.mode == "resize" then
			text = string.format("%d × %d", round(size.X), round(size.Y))
		else
			text = string.format("%d, %d", round(rel.X), round(rel.Y))
		end

		local width = #text * 6.5 + 16
		local center = pos + size / 2
		local bounds = self.overlay.AbsoluteSize

		self.readout.Text = text
		self.readout.Size = UDim2.fromOffset(width, 18)
		self.readout.Position = UDim2.fromOffset(
			math.clamp(center.X - width / 2, 0, math.max(bounds.X - width, 0)),
			math.clamp(pos.Y + size.Y + 10, 0, math.max(bounds.Y - 18, 0))
		)
		self.readout.Visible = true
	else
		self.readout.Visible = false
	end
end

function Editor:Destroy()
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end

	self.connections = {}

	UI.forgetButtons(self.hit)
	UI.forgetButtons(self.box)

	self.hit:Destroy()
	self.hover:Destroy()
	self.box:Destroy()
	self.readout:Destroy()
end

return Editor

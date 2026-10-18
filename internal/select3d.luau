if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")
local UserInputService = game:GetService("UserInputService")

local editor_ui = require("@internal/editor_ui")
local accent = editor_ui.tokens.color.accent

local MAX_PICK_SIZE = 100
local MAX_RAY_DISTANCE = 2000
local MAX_RAY_SKIPS = 8
local DRAG_THRESHOLD = 4
local DOUBLE_CLICK_TIME = 0.3
local GRID_SIZES = { 0.25, 0.5, 1, 2, 4, 8 }
local DRAG_COLOR = Color3.fromRGB(255, 180, 60)

local KEY_MOVE_MODE = Enum.KeyCode.M
local KEY_CYCLE_GRID = Enum.KeyCode.G
local KEY_TOGGLE_SNAP = Enum.KeyCode.N
local KEY_ROTATE = Enum.KeyCode.R
local KEY_CANCEL = Enum.KeyCode.Escape

local state = {
	moveMode = false,
	snapEnabled = true,
	gridIndex = 3,
	lastClickTime = 0,
	lastClickPart = nil :: BasePart?,
}

local drag = {
	pending = false,
	active = false,
	grabbed = nil :: BasePart?,
	startMouse = Vector2.zero,
	parts = {} :: { BasePart },
	startCFrames = {} :: { [BasePart]: CFrame },
	pivotStart = Vector3.zero,
	offset = Vector3.zero,
	rotY = 0,
	lastPoint = nil :: Vector3?,
	lastMode = nil :: string?,
}

local highlight = Instance.new("Highlight")
highlight.Name = "SelectionHighlight"
highlight.FillTransparency = 1
highlight.OutlineColor = accent
highlight.Enabled = false
highlight.Parent = workspace

local hud = nil

local HUD_HEIGHT = 22
local HUD_Z = 5900

local HUD_HINTS = {
	{ key = "vertical", text = "Shift: vertical" },
	{ key = "snapToggle", text = "Ctrl: toggle snap" },
	{ key = "rotate", text = "R: rotate 90" },
	{ key = "cancel", text = "Esc: cancel" },
}

local function createHud()
	local tokens = editor_ui.tokens
	local colors = tokens.color

	local bar = editor_ui.frame(
		editor_ui.widgetOverlay(),
		UDim2.new(0.5, 0, 1, -12),
		UDim2.fromOffset(0, HUD_HEIGHT + 8),
		colors.panelRaised,
		tokens.radius.md
	)
	bar.Name = "SelectionToolHud"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.BackgroundTransparency = 0.1
	bar.AutomaticSize = Enum.AutomaticSize.X
	bar.ZIndex = HUD_Z
	bar.Visible = false
	pcall(function()
		bar.InputSink = false
	end)
	editor_ui.stroke(bar, colors.borderStrong, 1, 0.25)

	editor_ui.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 14),
	}, bar)

	editor_ui.create("UIPadding", {
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
	}, bar)

	local parts = { bar = bar }
	local order = 0

	local function makeLabel(key, text, color)
		order += 1
		local label = editor_ui.label(
			bar,
			text,
			UDim2.fromOffset(0, 0),
			UDim2.fromOffset(0, HUD_HEIGHT),
			tokens.type.small,
			color
		)
		label.Name = key
		label.AutomaticSize = Enum.AutomaticSize.X
		label.LayoutOrder = order
		label.ZIndex = HUD_Z + 1
		parts[key] = label
		return label
	end

	makeLabel("mode", "MOVE MODE", colors.accent)
	makeLabel("snap", "", colors.text)

	for _, hint in ipairs(HUD_HINTS) do
		makeLabel(hint.key, hint.text, colors.muted)
	end

	return parts
end

local function updateHud()
	if not hud then
		local ok, result = pcall(createHud)
		if not ok then
			return
		end
		hud = result
	end

	if not state.moveMode then
		hud.bar.Visible = false
		return
	end

	local grid = GRID_SIZES[state.gridIndex]
	hud.snap.Text = state.snapEnabled and ("Snap: " .. grid .. " studs") or "Snap: off"
	hud.bar.Visible = true
end

local AXIS_COLORS = {
	x = Color3.fromRGB(231, 91, 91),
	y = Color3.fromRGB(81, 184, 122),
	z = Color3.fromRGB(82, 150, 235),
}

local READOUT_ROWS = {
	{ key = "x", prefix = "X", color = AXIS_COLORS.x },
	{ key = "y", prefix = "Y", color = AXIS_COLORS.y },
	{ key = "z", prefix = "Z", color = AXIS_COLORS.z },
	{ key = "dist", prefix = "Dist" },
	{ key = "rot", prefix = "Rot" },
	{ key = "size", prefix = "Size" },
}

local READOUT_WIDTH = 196
local READOUT_ROW_HEIGHT = 16
local READOUT_PAD = 8
local READOUT_Z = 6000

local readout = nil

local function createReadout()
	local tokens = editor_ui.tokens
	local colors = tokens.color

	local height = READOUT_PAD * 2 + 18 + #READOUT_ROWS * READOUT_ROW_HEIGHT + 18

	local frame = editor_ui.frame(
		editor_ui.widgetOverlay(),
		UDim2.fromOffset(0, 0),
		UDim2.fromOffset(READOUT_WIDTH, height),
		colors.panelRaised,
		tokens.radius.md
	)
	frame.Name = "MoveReadout"
	frame.BackgroundTransparency = 0.1
	frame.ZIndex = READOUT_Z
	frame.Visible = false
	pcall(function()
		frame.InputSink = false
	end)
	editor_ui.stroke(frame, colors.borderStrong, 1, 0.25)

	local innerWidth = READOUT_WIDTH - READOUT_PAD * 2

	local header = editor_ui.label(
		frame,
		"",
		UDim2.fromOffset(READOUT_PAD, READOUT_PAD),
		UDim2.fromOffset(innerWidth, 18),
		tokens.type.small,
		colors.text
	)
	header.ZIndex = READOUT_Z + 1

	local parts = { frame = frame, header = header }

	local y = READOUT_PAD + 18
	for _, row in ipairs(READOUT_ROWS) do
		local prefix = editor_ui.label(
			frame,
			row.prefix,
			UDim2.fromOffset(READOUT_PAD, y),
			UDim2.fromOffset(34, READOUT_ROW_HEIGHT),
			tokens.type.caption,
			row.color or colors.subtext
		)
		prefix.ZIndex = READOUT_Z + 1

		local value = editor_ui.label(
			frame,
			"",
			UDim2.fromOffset(READOUT_PAD + 34, y),
			UDim2.fromOffset(innerWidth - 34, READOUT_ROW_HEIGHT),
			tokens.type.small,
			colors.text
		)
		value.TextXAlignment = Enum.TextXAlignment.Right
		value.ZIndex = READOUT_Z + 1

		parts[row.key] = value
		y += READOUT_ROW_HEIGHT
	end

	local footer = editor_ui.label(
		frame,
		"",
		UDim2.fromOffset(READOUT_PAD, y + 2),
		UDim2.fromOffset(innerWidth, 14),
		tokens.type.caption,
		colors.muted
	)
	footer.ZIndex = READOUT_Z + 1
	parts.footer = footer

	return parts
end

local function positionReadout(worldPosition: Vector3, radius: number): boolean
	local camera = workspace.CurrentCamera
	if not readout or not camera then
		return false
	end

	local onScreen, centerX, centerY = camera:WorldToViewportPoint(worldPosition)
	if not onScreen or type(centerX) ~= "number" or type(centerY) ~= "number" then
		return false
	end

	local spread = 40
	local _, edgeX = camera:WorldToViewportPoint(worldPosition + camera.CFrame.RightVector * radius)
	if type(edgeX) == "number" then
		spread = math.clamp(math.abs(edgeX - centerX), 12, 400)
	end

	local screen = workspace:GetWindowDimensions()
	local width = readout.frame.Size.X.Offset
	local height = readout.frame.Size.Y.Offset
	local margin = 4
	local gap = 16

	local x = centerX + spread + gap
	if x + width > screen.X - margin then
		x = centerX - spread - gap - width
	end
	local y = centerY - height / 2

	x = math.clamp(x, margin, math.max(margin, screen.X - width - margin))
	y = math.clamp(y, margin, math.max(margin, screen.Y - height - margin))

	readout.frame.Position = UDim2.fromOffset(x, y)
	return true
end

local function hideReadout()
	if readout then
		readout.frame.Visible = false
	end
end

local function updateReadout(info)
	if not readout then
		readout = createReadout()
	end

	readout.header.Text = info.header
	readout.x.Text = string.format("%+.2f studs", info.delta.X)
	readout.y.Text = string.format("%+.2f studs", info.delta.Y)
	readout.z.Text = string.format("%+.2f studs", info.delta.Z)
	readout.dist.Text = string.format("%.2f studs", info.delta.Magnitude)
	readout.rot.Text = string.format("%d°", math.round(math.deg(info.rotation)))

	local sizeDelta = info.sizeDelta
	if sizeDelta.Magnitude < 1e-3 then
		readout.size.Text = "none"
	else
		readout.size.Text = string.format("%+.2f, %+.2f, %+.2f", sizeDelta.X, sizeDelta.Y, sizeDelta.Z)
	end

	readout.footer.Text = info.footer

	readout.frame.Visible = positionReadout(info.position, info.radius)
end

local function setHover(part: BasePart?)
	if part then
		highlight.Adornee = part
		highlight.Enabled = true
	else
		highlight.Adornee = nil
		highlight.Enabled = false
	end
end

local GIZMO_ADORNMENT_NAMES = { "ViewportHandles", "ViewportArcHandles" }

local function gizmoCapturesMouse()
	for _, name in ipairs(GIZMO_ADORNMENT_NAMES) do
		local adornment = workspace:FindFirstChild(name)
		if adornment and adornment.Visible and (adornment.Hovered or adornment.Dragging) then
			return true
		end
	end
	return false
end

-- The engine reports gameProcessedEvent (the second input callback argument) as
-- true whenever the pointer is over a GUI object, so a panel or toolbar owns the
-- cursor. Mouse movement carries that flag, so track it to keep the hover
-- highlight off a part that sits behind the interface; the click handler below
-- already ignores processed input.
local mouseOverGui = false
UserInputService.InputChanged:Connect(function(input, processed)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		mouseOverGui = processed == true
	end
end)

local function isOutOfBounds(num: number)
	return num >= MAX_PICK_SIZE
end

local function isOutOfBoundsTarget(target: BasePart)
	local size = target.Size
	return isOutOfBounds(size.X) or isOutOfBounds(size.Y) or isOutOfBounds(size.Z)
end

local function isPickable(inst: Instance): boolean
	if not inst:IsA("BasePart") then
		return false
	end
	if inst:IsA("Terrain") then
		return false
	end
	if inst.Locked then
		return false
	end
	if isOutOfBoundsTarget(inst) then
		return false
	end
	return true
end

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.RespectCanCollide = false

local function getMouseRay(): Ray?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local pos = UserInputService:GetMouseLocation()
	return camera:ViewportPointToRay(pos.X, pos.Y)
end

local function pickPart(): (BasePart?, RaycastResult?)
	local ray = getMouseRay()
	if not ray then
		return nil, nil
	end

	local excluded = { highlight }
	for _ = 1, MAX_RAY_SKIPS do
		raycastParams.FilterDescendantsInstances = excluded
		local result = workspace:Raycast(ray.Origin, ray.Direction * MAX_RAY_DISTANCE, raycastParams)
		if not result then
			return nil, nil
		end
		if isPickable(result.Instance) then
			return result.Instance :: BasePart, result
		end
		table.insert(excluded, result.Instance)
	end
	return nil, nil
end

local function isSelected(part: BasePart): boolean
	for _, inst in ipairs(Selection:Get()) do
		if inst == part or part:IsDescendantOf(inst) then
			return true
		end
	end
	return false
end

local function toggleInSelection(inst: Instance)
	local current = Selection:Get()
	for i, existing in ipairs(current) do
		if existing == inst then
			table.remove(current, i)
			Selection:Set(current)
			return
		end
	end
	table.insert(current, inst)
	Selection:Set(current)
end

local function getSelectableModel(part: BasePart): Instance?
	local model = part:FindFirstAncestorOfClass("Model")
	if model and model ~= workspace then
		return model
	end
	return nil
end

local function collectMovableParts(): { BasePart }
	local seen = {}
	local list = {}
	local function add(part: Instance)
		if part:IsA("BasePart") and not part:IsA("Terrain") and not part.Locked and not seen[part] then
			seen[part] = true
			table.insert(list, part)
		end
	end
	for _, inst in ipairs(Selection:Get()) do
		add(inst)
		for _, desc in ipairs(inst:GetDescendants()) do
			add(desc)
		end
	end
	return list
end

local gizmo = {
	active = false,
	parts = {} :: { BasePart },
	startCFrames = {} :: { [BasePart]: CFrame },
	startSizes = {} :: { [BasePart]: Vector3 },
	startCenter = Vector3.zero,
	first = nil :: BasePart?,
}

local function gizmoDragging(): boolean
	for _, name in ipairs(GIZMO_ADORNMENT_NAMES) do
		local adornment = workspace:FindFirstChild(name)
		if adornment and adornment.Visible and adornment.Dragging then
			return true
		end
	end
	return false
end

local function centroidOf(parts: { BasePart }): Vector3
	local sum = Vector3.zero
	local count = 0
	for _, part in ipairs(parts) do
		if part.Parent then
			sum += part.Position
			count += 1
		end
	end
	return count > 0 and sum / count or Vector3.zero
end

local function beginGizmoTracking()
	local parts = collectMovableParts()
	if #parts == 0 then
		return
	end

	gizmo.active = true
	gizmo.parts = parts
	gizmo.first = parts[1]
	gizmo.startCFrames = {}
	gizmo.startSizes = {}
	for _, part in ipairs(parts) do
		gizmo.startCFrames[part] = part.CFrame
		gizmo.startSizes[part] = part.Size
	end
	gizmo.startCenter = centroidOf(parts)
end

local function updateGizmoTracking()
	local first = gizmo.first
	if not first or not first.Parent then
		return
	end

	local center = centroidOf(gizmo.parts)
	local delta = center - gizmo.startCenter

	local startCFrame = gizmo.startCFrames[first]
	local startRotation = startCFrame - startCFrame.Position
	local currentRotation = first.CFrame - first.CFrame.Position
	local _, angle = (startRotation:Inverse() * currentRotation):ToAxisAngle()

	local sizeDelta = first.Size - gizmo.startSizes[first]

	local header = "Moving"
	if sizeDelta.Magnitude >= 1e-3 then
		header = "Resizing"
	elseif angle >= math.rad(0.05) then
		header = "Rotating"
	end
	local count = #gizmo.parts
	header = header .. (count == 1 and " 1 part" or (" " .. count .. " parts"))

	updateReadout({
		position = center,
		radius = first.Size.Magnitude / 2,
		delta = delta,
		rotation = angle,
		sizeDelta = sizeDelta,
		header = header,
		footer = "Gizmo",
	})
end

local function endGizmoTracking()
	gizmo.active = false
	gizmo.parts = {}
	gizmo.startCFrames = {}
	gizmo.startSizes = {}
	gizmo.first = nil
	hideReadout()
end

local function intersectPlane(ray: Ray, origin: Vector3, normal: Vector3): Vector3?
	local denom = ray.Direction:Dot(normal)
	if math.abs(denom) < 1e-3 then
		return nil
	end
	local t = (origin - ray.Origin):Dot(normal) / denom
	if t < 0 or t > MAX_RAY_DISTANCE then
		return nil
	end
	return ray.Origin + ray.Direction * t
end

local function snapValue(value: number, grid: number): number
	return math.round(value / grid) * grid
end

local function beginDrag()
	drag.pending = false

	local parts = collectMovableParts()
	if #parts == 0 or not drag.grabbed then
		return
	end

	drag.active = true
	drag.parts = parts
	drag.startCFrames = {}
	for _, part in ipairs(parts) do
		drag.startCFrames[part] = part.CFrame
	end
	drag.pivotStart = drag.grabbed.CFrame.Position
	drag.offset = Vector3.zero
	drag.rotY = 0
	drag.lastPoint = nil
	drag.lastMode = nil

	highlight.FillColor = DRAG_COLOR
	highlight.OutlineColor = DRAG_COLOR
	highlight.FillTransparency = 0.8
	setHover(drag.grabbed)
end

local function applyDrag()
	local camera = workspace.CurrentCamera
	local ray = getMouseRay()
	if not camera or not ray then
		return
	end

	local vertical = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
	local mode = vertical and "vertical" or "horizontal"

	local current = drag.pivotStart + drag.offset
	local normal
	if vertical then
		local look = camera.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		normal = flat.Magnitude > 1e-3 and -flat.Unit or Vector3.zAxis
	else
		normal = Vector3.yAxis
	end

	local point = intersectPlane(ray, current, normal)
	if point then
		if drag.lastPoint and drag.lastMode == mode then
			local delta = point - drag.lastPoint
			if vertical then
				delta = Vector3.new(0, delta.Y, 0)
			else
				delta = Vector3.new(delta.X, 0, delta.Z)
			end
			drag.offset += delta
		end
		drag.lastPoint = point
		drag.lastMode = mode
	end

	local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
	local snap = state.snapEnabled ~= ctrl
	local target = drag.pivotStart + drag.offset
	if snap then
		local grid = GRID_SIZES[state.gridIndex]
		if vertical then
			target = Vector3.new(target.X, snapValue(target.Y, grid), target.Z)
		else
			target = Vector3.new(snapValue(target.X, grid), target.Y, snapValue(target.Z, grid))
		end
	end

	local rotation = CFrame.Angles(0, drag.rotY, 0)
	local pivotInverse = CFrame.new(drag.pivotStart):Inverse()
	for _, part in ipairs(drag.parts) do
		if part.Parent then
			local relative = pivotInverse * drag.startCFrames[part]
			part.CFrame = CFrame.new(target) * rotation * relative
		end
	end

	local grabbed = drag.grabbed
	if grabbed then
		local count = #drag.parts
		updateReadout({
			position = grabbed.Position,
			radius = grabbed.Size.Magnitude / 2,
			delta = target - drag.pivotStart,
			rotation = drag.rotY % (math.pi * 2),
			sizeDelta = Vector3.zero,
			header = count == 1 and "Moving 1 part" or ("Moving " .. count .. " parts"),
			footer = (vertical and "Vertical" or "Horizontal")
				.. "  |  "
				.. (snap and ("Snap " .. GRID_SIZES[state.gridIndex]) or "Snap off"),
		})
	end
end

local function endDrag(commit: boolean)
	if not drag.active then
		drag.pending = false
		return
	end

	if not commit then
		for part, cf in pairs(drag.startCFrames) do
			if part.Parent then
				part.CFrame = cf
			end
		end
	end

	drag.active = false
	drag.pending = false
	drag.grabbed = nil
	drag.parts = {}
	drag.startCFrames = {}
	drag.lastPoint = nil
	drag.lastMode = nil

	highlight.FillTransparency = 1
	highlight.OutlineColor = accent
	setHover(nil)
	hideReadout()
end

local function setMoveMode(enabled: boolean)
	if state.moveMode == enabled then
		return
	end
	if drag.active then
		endDrag(true)
	end
	state.moveMode = enabled
	highlight.FillTransparency = enabled and 0.9 or 1
	updateHud()
end

RunService.RenderStepped:Connect(function()
	if drag.active then
		if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
			endDrag(true)
			return
		end
		applyDrag()
		return
	end

	if drag.pending then
		local moved = (UserInputService:GetMouseLocation() - drag.startMouse).Magnitude
		if moved >= DRAG_THRESHOLD then
			beginDrag()
		end
		return
	end

	if gizmoDragging() then
		if not gizmo.active then
			beginGizmoTracking()
		end
		if gizmo.active then
			updateGizmoTracking()
		end
		setHover(nil)
		return
	elseif gizmo.active then
		endGizmoTracking()
	end

	if
		mouseOverGui
		or gizmoCapturesMouse()
		or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
	then
		setHover(nil)
		return
	end

	local target = pickPart()
	setHover(target)
end)

local function handleClick(target: BasePart?)
	local additive = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)

	if state.moveMode then
		additive = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
	end

	if not target then
		if not additive then
			Selection:Set({})
		end
		return
	end

	local now = os.clock()
	local isDoubleClick = state.lastClickPart == target and (now - state.lastClickTime) <= DOUBLE_CLICK_TIME
	state.lastClickPart = target
	state.lastClickTime = now

	if isDoubleClick then
		local model = getSelectableModel(target)
		if model then
			Selection:Set({ model })
			return
		end
	end

	if additive then
		toggleInSelection(target)
	elseif state.moveMode and isSelected(target) then
		return
	else
		Selection:Set({ target })
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if gizmoCapturesMouse() then
			return
		end

		local target = pickPart()
		handleClick(target)

		if state.moveMode and target and isSelected(target) then
			drag.pending = true
			drag.grabbed = target
			drag.startMouse = UserInputService:GetMouseLocation()
		end
		return
	end

	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end

	local key = input.KeyCode
	if key == KEY_MOVE_MODE then
		setMoveMode(not state.moveMode)
	elseif key == KEY_CYCLE_GRID then
		state.gridIndex = state.gridIndex % #GRID_SIZES + 1
		updateHud()
	elseif key == KEY_TOGGLE_SNAP then
		state.snapEnabled = not state.snapEnabled
		updateHud()
	elseif key == KEY_ROTATE and drag.active then
		drag.rotY += math.pi / 2
	elseif key == KEY_CANCEL then
		if drag.active then
			endDrag(false)
		else
			drag.pending = false
		end
	end
end)

local function focusOn(target: Instance)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local center, radius
	if target:IsA("BasePart") then
		center = target.Position
		radius = target.Size.Magnitude / 2
	elseif target:IsA("Model") then
		local cf, size = target:GetBoundingBox()
		center = cf.Position
		radius = size.Magnitude / 2
	else
		return
	end

	local look = camera.CFrame.LookVector
	local distance = math.max(radius * 2.5, 4)
	local position = center - look * distance

	camera.CFrame = CFrame.lookAt(position, center)
end

UserInputService.InputEnded:Connect(function(input, processed)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if drag.active then
			endDrag(true)
		else
			drag.pending = false
		end
	elseif input.KeyCode == Enum.KeyCode.F and not processed then
		local selection = Selection:Get()[1]
		if selection then
			focusOn(selection)
		end
	end
end)

local terrain = game:GetService("Terrain")
local UserInputService = game:GetService("UserInputService")
local mouse: Mouse = UserInputService:GetMouse()
local RunService = game:GetService("RunService")

local CHEVRON = "builtin://global-icons/chevron-down.svg"

local UI = require("@internal/editor_ui")
local colors = UI.tokens.color

local VOXEL = 4
local MAX_SIZE = 512
local MAX_HISTORY = 60
local WEDGE_TALL_SIDE = 1

local MATERIAL_LIST = {
	{ "Grass", Enum.Material.Grass },
	{ "LeafyGrass", Enum.Material.LeafyGrass },
	{ "Sand", Enum.Material.Sand },
	{ "Sandstone", Enum.Material.Sandstone },
	{ "Rock", Enum.Material.Rock },
	{ "Basalt", Enum.Material.Basalt },
	{ "Slate", Enum.Material.Slate },
	{ "Limestone", Enum.Material.Limestone },
	{ "Mud", Enum.Material.Mud },
	{ "Ground", Enum.Material.Ground },
	{ "Snow", Enum.Material.Snow },
	{ "Ice", Enum.Material.Ice },
	{ "Glacier", Enum.Material.Glacier },
	{ "Salt", Enum.Material.Salt },
	{ "Concrete", Enum.Material.Concrete },
	{ "Pavement", Enum.Material.Pavement },
	{ "Asphalt", Enum.Material.Asphalt },
	{ "Cobblestone", Enum.Material.Cobblestone },
	{ "Brick", Enum.Material.Brick },
	{ "WoodPlanks", Enum.Material.WoodPlanks },
	{ "CrackedLava", Enum.Material.CrackedLava },
	{ "Water", Enum.Material.Water },
}

local materialByName = {}
local materialNames = {}
for _, entry in ipairs(MATERIAL_LIST) do
	materialByName[entry[1]] = entry[2]
	table.insert(materialNames, entry[1])
end

local sourceNames = { "Any" }
for _, name in ipairs(materialNames) do
	table.insert(sourceNames, name)
end

local cfg = {
	mode = "Add", -- Add | Subtract | Paint
	shape = "Ball", -- Ball | Block | Cylinder | Wedge
	material = Enum.Material.Grass,
	source = nil, -- Paint only: nil = any material
	radius = 4, -- Ball / Cylinder
	height = 8, -- Cylinder
	size = Vector3.new(4, 4, 4), -- Block / Wedge
	rotation = 0, -- degrees around Y
	snap = false,
	grid = 4,
	offset = 0, -- vertical offset from the hit position
	hold = true,
	spacing = 2,
	interval = 0.05,
	showPreview = true,
	previewColor = Color3.new(0, 0.701961, 1),
	previewTransparency = 0.6,
}

local history = {}
local strokeId = 0
local painting = false
local lastPos, lastTime = nil, 0

------------------------------------------------------------------ window

local gui = Instance.new("ScreenGui")
gui.Name = "TerrainEditor"
gui.RenderOnTop = true
gui.Parent = game.CoreGui

local panel, content = UI.window("Terrain", UDim2.fromOffset(40, 40), UDim2.fromOffset(320, 480), "Terrain", {
	closable = true,
})
panel.ClipsDescendants = true
panel.Parent = gui

local scroller = Instance.new("ScrollingFrame")
scroller.BackgroundTransparency = 1
scroller.BorderSizePixel = 0
scroller.Size = UDim2.fromScale(1, 1)
scroller.CanvasSize = UDim2.new(0, 0, 0, 0)
scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroller.ScrollBarThickness = 5
scroller.ClipsDescendants = true
scroller.Parent = content

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Vertical
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 2)
layout.Parent = scroller

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 8)
padding.PaddingBottom = UDim.new(0, 8)
padding.PaddingLeft = UDim.new(0, 6)
padding.PaddingRight = UDim.new(0, 10)
padding.Parent = scroller

local nextOrder = 0
local function place(object)
	nextOrder += 1
	object.LayoutOrder = nextOrder
	return object
end

local function section(text)
	local header = UI.sectionHeader(scroller, text)
	UI.corner(header, 5)
	return place(header)
end

local function numberRow(text, value, min, max, decimals, onChanged)
	local row, ctrl = UI.property(scroller, text, nil, nil, value, function(v)
		onChanged(v)
	end, { numeric = true, min = min, max = max, decimals = decimals })

	return place(row), ctrl
end

local function dropdownRow(text, list, initial, onChanged)
	local items = {}
	for _, name in ipairs(list) do
		table.insert(items, { value = name, label = name })
	end

	local row, ctrl = UI.property(scroller, text, nil, nil, initial, function(v)
		onChanged(v)
	end, {
		custom = function(holder, ctrl, c)
			local innerHeight = UI.metrics.propertyRow - 2

			local dropOptions = {
				items = items,
				menuWidth = 140,
				showSearch = #items > 8,
				menuPosition = function()
					local button = ctrl.custom.button
					local p, s = button.AbsolutePosition, button.AbsoluteSize
					return UDim2.fromOffset(p.X, p.Y + s.Y + 2)
				end,
				onChanged = function(v)
					ctrl:Fire(v)
				end,
			}

			local button, label, dropdown = UI.dropdown(
				holder,
				initial,
				UDim2.new(0, 0, 0.5, -math.floor(innerHeight / 2)),
				UDim2.new(1, 0, 0, innerHeight),
				CHEVRON,
				dropOptions
			)

			local function syncWidth()
				local width = button.AbsoluteSize.X
				if width > 0 then
					dropOptions.menuWidth = width
				end
			end

			syncWidth()
			button:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncWidth)

			return {
				button = button,
				GetValue = function()
					return dropdown:GetValue()
				end,
				SetValue = function(_, v, silent)
					dropdown:SetValue(v, true)
					if not silent then
						ctrl:Fire(v)
					end
				end,
				SetEnabled = function(_, enabled)
					dropdown.record.enabled = enabled
					button.Active = enabled
					label.TextColor3 = enabled and c.subtext or c.muted
				end,
				Destroy = function()
					dropdown:Close()
				end,
			}
		end,
	})

	return place(row), ctrl
end

local function hexToColor(text)
	local raw = string.gsub(text, "#", "")
	if #raw ~= 6 then
		return nil
	end

	local r, g, b =
		tonumber(string.sub(raw, 1, 2), 16), tonumber(string.sub(raw, 3, 4), 16), tonumber(string.sub(raw, 5, 6), 16)

	if r and g and b then
		return Color3.fromRGB(r, g, b)
	end

	return nil
end

------------------------------------------------------------------ brush math

local function brushDims()
	if cfg.shape == "Ball" then
		local d = cfg.radius * 2
		return Vector3.new(d, d, d)
	elseif cfg.shape == "Cylinder" then
		local d = cfg.radius * 2
		return Vector3.new(d, cfg.height, d)
	end

	return cfg.size
end

local function snapVec(v, g)
	return Vector3.new(math.floor(v.X / g + 0.5) * g, math.floor(v.Y / g + 0.5) * g, math.floor(v.Z / g + 0.5) * g)
end

local function brushCFrame()
	local hit = mouse.Hit

	if not hit then
		return nil
	end

	local pos = hit.Position + Vector3.new(0, cfg.offset, 0)

	if cfg.snap then
		pos = snapVec(pos, cfg.grid)
	end

	return CFrame.new(pos) * CFrame.Angles(0, math.rad(cfg.rotation), 0)
end

-- voxel-aligned world region that fully contains the (rotated) brush
local function brushRegion(cf, dims)
	local h = dims / 2
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector

	local ext = Vector3.new(
		math.abs(r.X) * h.X + math.abs(u.X) * h.Y + math.abs(l.X) * h.Z,
		math.abs(r.Y) * h.X + math.abs(u.Y) * h.Y + math.abs(l.Y) * h.Z,
		math.abs(r.Z) * h.X + math.abs(u.Z) * h.Y + math.abs(l.Z) * h.Z
	) + Vector3.new(VOXEL, VOXEL, VOXEL)

	local p = cf.Position

	return Region3.new(p - ext, p + ext):ExpandToGrid(VOXEL)
end

-- lp = point in brush-local space
local function insideBrush(lp, dims)
	local h = dims / 2
	local shape = cfg.shape

	if shape == "Ball" then
		return lp.Magnitude <= cfg.radius
	elseif shape == "Cylinder" then
		return math.sqrt(lp.X * lp.X + lp.Z * lp.Z) <= cfg.radius and math.abs(lp.Y) <= h.Y
	elseif shape == "Block" then
		return math.abs(lp.X) <= h.X and math.abs(lp.Y) <= h.Y and math.abs(lp.Z) <= h.Z
	end

	-- Wedge
	if math.abs(lp.X) > h.X or math.abs(lp.Z) > h.Z or math.abs(lp.Y) > h.Y then
		return false
	end

	local t = lp.Z / dims.Z + 0.5

	if WEDGE_TALL_SIDE < 0 then
		t = 1 - t
	end

	return (lp.Y + h.Y) <= dims.Y * t
end

------------------------------------------------------------------ history

local function pushHistory(cf, dims)
	local region = brushRegion(cf, dims)
	local mats, occs = terrain:ReadVoxels(region, VOXEL)

	table.insert(history, { id = strokeId, region = region, mats = mats, occs = occs })

	while #history > MAX_HISTORY do
		table.remove(history, 1)
	end
end

local function undo()
	local top = history[#history]

	if not top then
		return
	end

	-- one undo reverts a whole stroke
	while #history > 0 and history[#history].id == top.id do
		local entry = table.remove(history)
		terrain:WriteVoxels(entry.region, VOXEL, entry.mats, entry.occs)
	end
end

------------------------------------------------------------------ applying the brush

local function paintBrush(cf, dims)
	local region = brushRegion(cf, dims)
	local mats, occs = terrain:ReadVoxels(region, VOXEL)

	local sz = mats.Size
	local origin = region.CFrame.Position - region.Size / 2

	for x = 1, sz.X do
		for y = 1, sz.Y do
			for z = 1, sz.Z do
				if occs[x][y][z] > 0 then
					local current = mats[x][y][z]

					if not cfg.source or current == cfg.source then
						local p = origin + Vector3.new(x - 0.5, y - 0.5, z - 0.5) * VOXEL

						if insideBrush(cf:PointToObjectSpace(p), dims) then
							mats[x][y][z] = cfg.material
						end
					end
				end
			end
		end
	end

	terrain:WriteVoxels(region, VOXEL, mats, occs)
end

local function applyBrush(cf)
	local dims = brushDims()

	pushHistory(cf, dims)

	if cfg.mode == "Paint" then
		paintBrush(cf, dims)
		return
	end

	local material = cfg.mode == "Subtract" and Enum.Material.Air or cfg.material

	if cfg.shape == "Ball" then
		terrain:FillBall(cf.Position, cfg.radius, material)
	elseif cfg.shape == "Block" then
		terrain:FillBlock(cf, dims, material)
	elseif cfg.shape == "Cylinder" then
		terrain:FillCylinder(cf, cfg.height, cfg.radius, material)
	else
		terrain:FillWedge(cf, dims, material)
	end
end

------------------------------------------------------------------ UI rows

local rows = {}
local radiusCtrl, heightCtrl, sizeCtrl, rotationCtrl

local function refreshRows()
	rows.material.Visible = cfg.mode ~= "Subtract"
	rows.source.Visible = cfg.mode == "Paint"
	rows.radius.Visible = cfg.shape == "Ball" or cfg.shape == "Cylinder"
	rows.height.Visible = cfg.shape == "Cylinder"
	rows.size.Visible = cfg.shape == "Block" or cfg.shape == "Wedge"
end

section("Tool")

rows.mode = dropdownRow("Mode", { "Add", "Subtract", "Paint" }, cfg.mode, function(v)
	cfg.mode = v
	refreshRows()
end)

rows.shape = dropdownRow("Shape", { "Ball", "Block", "Cylinder", "Wedge" }, cfg.shape, function(v)
	cfg.shape = v
	refreshRows()
end)

section("Material")

rows.material = dropdownRow("Material", materialNames, "Grass", function(v)
	cfg.material = materialByName[v]
end)

rows.source = dropdownRow("Replace", sourceNames, "Any", function(v)
	cfg.source = v ~= "Any" and materialByName[v] or nil
end)

section("Brush")

rows.radius, radiusCtrl = numberRow("Radius", cfg.radius, 1, MAX_SIZE, 1, function(v)
	cfg.radius = v
end)

rows.height, heightCtrl = numberRow("Height", cfg.height, 1, MAX_SIZE, 1, function(v)
	cfg.height = v
end)

local sizeRow
sizeRow, sizeCtrl = UI.property(scroller, "Size", nil, nil, { 4, 4, 4 }, function(values)
	cfg.size = Vector3.new(values[1], values[2], values[3])
end, {
	fields = { { prefix = "X" }, { prefix = "Y" }, { prefix = "Z" } },
	numeric = true,
	min = 1,
	max = MAX_SIZE,
	decimals = 1,
	prefixColors = { colors.error, colors.success, colors.accent },
})
rows.size = place(sizeRow)

rows.rotation, rotationCtrl = numberRow("Rotation", cfg.rotation, nil, nil, 1, function(v)
	cfg.rotation = v % 360
end)

section("Placement")

do
	local box = UI.checkbox(scroller, "Snap to grid", nil, cfg.snap, function(v)
		cfg.snap = v
	end, { size = UDim2.new(1, 0, 0, UI.metrics.propertyRow) })
	place(box)

	numberRow("Grid size", cfg.grid, 1, 64, 1, function(v)
		cfg.grid = v
	end)

	numberRow("Y offset", cfg.offset, -256, 256, 1, function(v)
		cfg.offset = v
	end)
end

section("Stroke")

do
	local box = UI.checkbox(scroller, "Hold to paint", nil, cfg.hold, function(v)
		cfg.hold = v
	end, { size = UDim2.new(1, 0, 0, UI.metrics.propertyRow) })
	place(box)

	numberRow("Spacing", cfg.spacing, 0.5, 64, 1, function(v)
		cfg.spacing = v
	end)

	numberRow("Interval", cfg.interval, 0.01, 2, 2, function(v)
		cfg.interval = v
	end)
end

section("Preview")

local refreshPreviewStyle

do
	local box = UI.checkbox(scroller, "Show preview", nil, cfg.showPreview, function(v)
		cfg.showPreview = v
	end, { size = UDim2.new(1, 0, 0, UI.metrics.propertyRow) })
	place(box)

	local colorRow = UI.property(scroller, "Color", nil, nil, "#00B3FF", function(v)
		cfg.previewColor = hexToColor(v) or cfg.previewColor
		refreshPreviewStyle()
	end, {
		validate = function(text)
			local c = hexToColor(text)
			if not c then
				return false
			end
			return true, "#" .. string.upper((string.gsub(text, "#", "")))
		end,
	})
	place(colorRow)

	numberRow("Opacity", 1 - cfg.previewTransparency, 0, 1, 2, function(v)
		cfg.previewTransparency = 1 - v
		refreshPreviewStyle()
	end)
end

section("Actions")

local function confirmClear()
	UI.prompt({
		title = "Clear terrain",
		description = "Removes ALL terrain. This can't be undone.",
		size = UDim2.fromOffset(360, 150),
		destroyOnClose = true,
		buttons = {
			{ id = "cancel", text = "Cancel", role = "ghost" },
			{
				id = "clear",
				text = "Clear",
				role = "danger",
				callback = function()
					terrain:Clear()
					table.clear(history)
				end,
			},
		},
	})
end

place((UI.button(scroller, "Undo (Ctrl+Z)", nil, UDim2.new(1, 0, 0, UI.metrics.buttonHeight), undo)))
place((UI.button(scroller, "Clear terrain", nil, UDim2.new(1, 0, 0, UI.metrics.buttonHeight), confirmClear, {
	textColor = colors.error,
})))

do
	local hint = UI.label(
		scroller,
		"[ / ]  brush size     Q / E  rotate     Ctrl+Z  undo",
		nil,
		UDim2.new(1, 0, 0, 30),
		UI.tokens.type.caption,
		colors.muted
	)
	hint.TextWrapped = true
	place(hint)
end

refreshRows()

------------------------------------------------------------------ preview parts

local previewFolder = Instance.new("Folder")
previewFolder.Name = "TerrainBrushPreview"
previewFolder.Parent = workspace

mouse.TargetFilter = previewFolder

local previews = {}

local function makePreview(className, partShape)
	local part = Instance.new(className)
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false
	part.Transparency = 1

	if partShape then
		part.Shape = partShape
	end

	local highlight = Instance.new("Highlight")
	highlight.Parent = part

	return { part = part, highlight = highlight }
end

previews.Ball = makePreview("Part", Enum.PartType.Ball)
previews.Block = makePreview("Part", Enum.PartType.Block)
previews.Cylinder = makePreview("Part", Enum.PartType.Cylinder)
previews.Wedge = makePreview("Part", Enum.PartType.Wedge)

refreshPreviewStyle = function()
	for _, p in pairs(previews) do
		p.highlight.FillColor = cfg.previewColor
		p.highlight.FillTransparency = cfg.previewTransparency
		p.highlight.OutlineColor = cfg.previewColor
		p.highlight.OutlineTransparency = 0.3
	end
end

refreshPreviewStyle()

local function overUI()
	local point = Vector2.new(mouse.X, mouse.Y)

	if panel.Visible and UI.pointInside(panel, point) then
		return true
	end

	local active = UI.shared().activeDropdown

	if active and active.menu and UI.pointInside(active.menu, point) then
		return true
	end

	return false
end

local function tryApply(cf)
	local ok, err = pcall(applyBrush, cf)

	if not ok then
		warn("Terrain brush failed: " .. tostring(err))
	end
end

mouse.Button1Down:Connect(function()
	if not panel.Visible or overUI() then
		return
	end

	local cf = brushCFrame()

	if not cf then
		return
	end

	painting = true
	strokeId += 1
	lastPos = cf.Position
	lastTime = os.clock()

	tryApply(cf)
end)

mouse.Button1Up:Connect(function()
	painting = false
end)

local function scaleBrush(factor)
	cfg.radius = math.clamp(math.floor(cfg.radius * factor * 2 + 0.5) / 2, 1, MAX_SIZE)
	cfg.height = math.clamp(math.floor(cfg.height * factor * 2 + 0.5) / 2, 1, MAX_SIZE)
	cfg.size = Vector3.new(
		math.clamp(math.floor(cfg.size.X * factor * 2 + 0.5) / 2, 1, MAX_SIZE),
		math.clamp(math.floor(cfg.size.Y * factor * 2 + 0.5) / 2, 1, MAX_SIZE),
		math.clamp(math.floor(cfg.size.Z * factor * 2 + 0.5) / 2, 1, MAX_SIZE)
	)

	radiusCtrl:SetValue(cfg.radius, true)
	heightCtrl:SetValue(cfg.height, true)
	sizeCtrl:SetValue({ cfg.size.X, cfg.size.Y, cfg.size.Z }, true)
end

local function rotateBrush(degrees)
	cfg.rotation = (cfg.rotation + degrees) % 360
	rotationCtrl:SetValue(cfg.rotation, true)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not panel.Visible or UserInputService:GetFocusedTextBox() then
		return
	end

	local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)

	if input.KeyCode == Enum.KeyCode.Z and ctrl then
		undo()
	elseif input.KeyCode == Enum.KeyCode.RightBracket then
		scaleBrush(1.25)
	elseif input.KeyCode == Enum.KeyCode.LeftBracket then
		scaleBrush(0.8)
	elseif input.KeyCode == Enum.KeyCode.Q then
		rotateBrush(-15)
	elseif input.KeyCode == Enum.KeyCode.E then
		rotateBrush(15)
	end
end)

------------------------------------------------------------------ frame update

RunService.RenderStepped:Connect(function()
	local visible = panel.Visible

	if not visible then
		painting = false
	end

	local cf = visible and brushCFrame() or nil
	local show = cf ~= nil and cfg.showPreview and not overUI()

	for shape, p in pairs(previews) do
		local want = (show and shape == cfg.shape) and previewFolder or nil

		if p.part.Parent ~= want then
			p.part.Parent = want
		end
	end

	if not cf then
		return
	end

	local dims = brushDims()
	local p = previews[cfg.shape]

	if cfg.shape == "Cylinder" then
		-- Part cylinders run along X; terrain cylinders run along Y
		p.part.Size = Vector3.new(dims.Y, dims.X, dims.Z)
		p.part.CFrame = cf * CFrame.Angles(0, 0, math.pi / 2)
	else
		p.part.Size = dims
		p.part.CFrame = cf
	end

	if painting and cfg.hold then
		local now = os.clock()

		if now - lastTime >= cfg.interval and (cf.Position - lastPos).Magnitude >= cfg.spacing then
			lastPos = cf.Position
			lastTime = now

			tryApply(cf)
		end
	end
end)

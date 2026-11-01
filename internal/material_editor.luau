if IsPlaytest then
	return
end

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local MaterialService = game:GetService("Raytracer")

local CHEVRON = "builtin://global-icons/chevron-down.svg"

local UI = require("./editor_ui")
local colors = UI.tokens.color

local PREVIEW_VARIANT_NAME = "__MaterialMakerPreview"
local VIEWPORT_HEIGHT = 200

local MATERIAL_LIST = {
	{ "Plastic", Enum.Material.Plastic },
	{ "SmoothPlastic", Enum.Material.SmoothPlastic },
	{ "Wood", Enum.Material.Wood },
	{ "WoodPlanks", Enum.Material.WoodPlanks },
	{ "Marble", Enum.Material.Marble },
	{ "Granite", Enum.Material.Granite },
	{ "Brick", Enum.Material.Brick },
	{ "Pebble", Enum.Material.Pebble },
	{ "Cobblestone", Enum.Material.Cobblestone },
	{ "Concrete", Enum.Material.Concrete },
	{ "Slate", Enum.Material.Slate },
	{ "Metal", Enum.Material.Metal },
	{ "CorrodedMetal", Enum.Material.CorrodedMetal },
	{ "DiamondPlate", Enum.Material.DiamondPlate },
	{ "Foil", Enum.Material.Foil },
	{ "Fabric", Enum.Material.Fabric },
	{ "Ice", Enum.Material.Ice },
	{ "Sand", Enum.Material.Sand },
	{ "Grass", Enum.Material.Grass },
	{ "Neon", Enum.Material.Neon },
}

local materialByName = {}
local materialNames = {}
for _, entry in ipairs(MATERIAL_LIST) do
	materialByName[entry[1]] = entry[2]
	table.insert(materialNames, entry[1])
end

local cfg = {
	name = "MyMaterial",
	baseMaterial = Enum.Material.Plastic,
	color = Color3.new(1, 1, 1),
	reflectance = 0,
	transparency = 0,
	colorMap = "",
	normalMap = "",
	metalnessMap = "",
	roughnessMap = "",
	studsPerTile = 4,
	spin = true,
	spinSpeed = 30,
	lightAngle = 45,
}

local dirty = true
local previewVariant = nil
local spinAngle = 0

local panel, content =
	UI.window("MaterialMaker", UDim2.fromOffset(460, 120), UDim2.fromOffset(320, 560), "Material Maker", {
		closable = true,
	})
content.BackgroundTransparency = 1
panel.Visible = false
panel.BackgroundTransparency = 0.5
panel.ClipsDescendants = true
panel.Parent = UI.widgetOverlay()

UI.backdrop(panel, 15, Color3.new(0, 0, 0))

local scroller = Instance.new("ScrollingFrame")
scroller.BackgroundTransparency = 1
scroller.BorderSizePixel = 0
scroller.Size = UDim2.new(1, -10, 1, 0)
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
	end, { numeric = true, min = min, max = max, decimals = decimals, transparent = true })

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
		transparent = true,
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

-- accepts "", "123456", "rbxassetid://123456", or a url containing id=123456
local function normalizeAssetId(text)
	local trimmed = string.match(text, "^%s*(.-)%s*$")

	if trimmed == "" then
		return ""
	end

	if string.match(trimmed, "^%d+$") then
		return "rbxassetid://" .. trimmed
	end

	if string.match(trimmed, "^rbxassetid://%d+$") then
		return trimmed
	end

	local id = string.match(trimmed, "id=(%d+)")
	if id then
		return "rbxassetid://" .. id
	end

	return nil
end

local function assetRow(label, key)
	local row = UI.property(scroller, label, nil, nil, cfg[key], function(v)
		cfg[key] = normalizeAssetId(v) or cfg[key]
		dirty = true
	end, {
		transparent = true,
		validate = function(text)
			local id = normalizeAssetId(text)
			if not id then
				return false
			end
			return true, id
		end,
	})
	return place(row)
end

------------------------------------------------------------------ preview viewport

local viewport = Instance.new("ViewportFrame")
viewport.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
viewport.BackgroundTransparency = 0
viewport.BorderSizePixel = 0
viewport.Size = UDim2.new(1, 0, 0, VIEWPORT_HEIGHT)
viewport.Ambient = Color3.fromRGB(110, 110, 110)
viewport.LightColor = Color3.fromRGB(255, 255, 255)
viewport.LightDirection = Vector3.new(-1, -1, -0.6)
viewport.Parent = scroller
UI.corner(viewport, 6)
place(viewport)

local ball = Instance.new("Part")
ball.Shape = Enum.PartType.Ball
ball.Size = Vector3.new(2, 2, 2)
ball.Anchored = true
ball.CanCollide = false
ball.CFrame = CFrame.new(0, 0, 0)
ball.Parent = viewport

local camera = Instance.new("Camera")
camera.FieldOfView = 40
camera.CFrame = CFrame.lookAt(Vector3.new(0, 0.2, 3.4), Vector3.new(0, 0, 0))
camera.Parent = viewport
viewport.CurrentCamera = camera

------------------------------------------------------------------ preview variant lifecycle

local function destroyPreviewVariant()
	ball.MaterialVariant = ""

	if previewVariant then
		previewVariant:Destroy()
		previewVariant = nil
	end
end

local function fillVariant(variant)
	variant.BaseMaterial = cfg.baseMaterial
	variant.ColorMap = cfg.colorMap
	variant.NormalMap = cfg.normalMap
	variant.MetalnessMap = cfg.metalnessMap
	variant.RoughnessMap = cfg.roughnessMap
	variant.StudsPerTile = cfg.studsPerTile
end

local function applyPreview()
	dirty = false

	ball.Material = cfg.baseMaterial
	ball.Color = cfg.color
	ball.Reflectance = cfg.reflectance
	ball.Transparency = cfg.transparency

	if not previewVariant then
		previewVariant = Instance.new("MaterialVariant")
		previewVariant.Name = PREVIEW_VARIANT_NAME
		previewVariant.Parent = MaterialService
	end

	local ok, err = pcall(fillVariant, previewVariant)
	if not ok then
		warn("Material preview failed: " .. tostring(err))
	end

	-- re-assign so the viewport picks up the changed maps
	ball.MaterialVariant = ""
	ball.MaterialVariant = PREVIEW_VARIANT_NAME

	viewport.LightDirection = Vector3.new(-math.cos(math.rad(cfg.lightAngle)), -1, -math.sin(math.rad(cfg.lightAngle)))
end

------------------------------------------------------------------ controls

section("Main Maps")

dropdownRow("Base", materialNames, "Plastic", function(v)
	cfg.baseMaterial = materialByName[v]
	dirty = true
end)

do
	local colorRow = UI.property(scroller, "Albedo", nil, nil, "#FFFFFF", function(v)
		cfg.color = hexToColor(v) or cfg.color
		dirty = true
	end, {
		transparent = true,
		validate = function(text)
			local c = hexToColor(text)
			if not c then
				return false
			end
			return true, "#" .. string.upper((string.gsub(text, "#", "")))
		end,
	})
	place(colorRow)
end

assetRow("Color map", "colorMap")
assetRow("Normal map", "normalMap")
assetRow("Metalness map", "metalnessMap")
assetRow("Roughness map", "roughnessMap")

section("Surface")

numberRow("Reflectance", cfg.reflectance, 0, 1, 2, function(v)
	cfg.reflectance = v
	dirty = true
end)

numberRow("Transparency", cfg.transparency, 0, 1, 2, function(v)
	cfg.transparency = v
	dirty = true
end)

section("Tiling")

numberRow("Studs / tile", cfg.studsPerTile, 0.1, 100, 1, function(v)
	cfg.studsPerTile = v
	dirty = true
end)

section("Preview")

do
	local box = UI.checkbox(scroller, "Auto rotate", nil, cfg.spin, function(v)
		cfg.spin = v
	end, { size = UDim2.new(1, 0, 0, UI.metrics.propertyRow) })
	place(box)

	numberRow("Spin speed", cfg.spinSpeed, 0, 360, 0, function(v)
		cfg.spinSpeed = v
	end)

	numberRow("Light angle", cfg.lightAngle, 0, 360, 0, function(v)
		cfg.lightAngle = v
		dirty = true
	end)
end

section("Output")

do
	local nameRow = UI.property(scroller, "Name", nil, nil, cfg.name, function(v)
		local clean = string.gsub(v, "[^%w_%-]", "")
		if clean ~= "" then
			cfg.name = clean
		end
	end, {
		transparent = true,
		validate = function(text)
			local clean = string.gsub(text, "[^%w_%-]", "")
			if clean == "" then
				return false
			end
			return true, clean
		end,
	})
	place(nameRow)
end

local function createVariant()
	-- replace an existing variant with the same name + base material
	for _, child in ipairs(MaterialService:GetChildren()) do
		if child:IsA("MaterialVariant") and child.Name == cfg.name and child.BaseMaterial == cfg.baseMaterial then
			child:Destroy()
		end
	end

	local variant = Instance.new("MaterialVariant")
	variant.Name = cfg.name
	local ok, err = pcall(fillVariant, variant)

	if not ok then
		warn("Create material failed: " .. tostring(err))
		variant:Destroy()
		return
	end

	variant.Parent = MaterialService
end

local function applyToSelection()
	createVariant()

	local ok, err = pcall(function()
		local selection = game:GetService("Selection"):Get()

		for _, obj in ipairs(selection) do
			if obj:IsA("BasePart") then
				obj.Material = cfg.baseMaterial
				obj.MaterialVariant = cfg.name
				obj.Color = cfg.color
				obj.Reflectance = cfg.reflectance
				obj.Transparency = cfg.transparency
			end
		end
	end)

	if not ok then
		warn("Apply to selection failed: " .. tostring(err))
	end
end

local function resetAll()
	cfg.baseMaterial = Enum.Material.Plastic
	cfg.color = Color3.new(1, 1, 1)
	cfg.reflectance = 0
	cfg.transparency = 0
	cfg.colorMap = ""
	cfg.normalMap = ""
	cfg.metalnessMap = ""
	cfg.roughnessMap = ""
	cfg.studsPerTile = 4
	dirty = true
end

place((UI.button(scroller, "Create MaterialVariant", nil, UDim2.new(1, 0, 0, UI.metrics.buttonHeight), createVariant)))
place((UI.button(scroller, "Apply to selection", nil, UDim2.new(1, 0, 0, UI.metrics.buttonHeight), applyToSelection)))
place(
	(
		UI.button(
			scroller,
			"Reset (reopen to refresh fields)",
			nil,
			UDim2.new(1, 0, 0, UI.metrics.buttonHeight),
			resetAll,
			{
				textColor = colors.error,
			}
		)
	)
)

do
	local hint = UI.label(
		scroller,
		"Kinemium materials use Color / Normal / Metalness / Roughness maps. Paste a material path.",
		nil,
		UDim2.new(1, 0, 0, 42),
		UI.tokens.type.caption,
		colors.muted
	)
	hint.TextWrapped = true
	place(hint)
end

------------------------------------------------------------------ drag to rotate preview

local dragging = false
local dragYaw, dragPitch = 0, 0

viewport.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging = true
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging = false
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
		dragYaw += input.Delta.X * 0.5
		dragPitch = math.clamp(dragPitch + input.Delta.Y * 0.5, -80, 80)
	end
end)

RunService.RenderStepped:Connect(function(dt)
	if not panel.Visible then
		if previewVariant then
			destroyPreviewVariant()
		end
		dirty = true
		dragging = false
		return
	end

	if dirty then
		applyPreview()
	end

	if cfg.spin and not dragging then
		spinAngle = (spinAngle + cfg.spinSpeed * dt) % 360
	end

	ball.CFrame = CFrame.Angles(math.rad(dragPitch), math.rad(spinAngle + dragYaw), 0)
end)

return {
	Enable = function()
		panel.Visible = true
		dirty = true
	end,

	Disable = function()
		panel.Visible = false
		destroyPreviewVariant()
	end,

	Toggle = function()
		panel.Visible = not panel.Visible
		if not panel.Visible then
			destroyPreviewVariant()
		else
			dirty = true
		end
	end,

	Refresh = function()
		UI.refreshWindow("MaterialMaker")
		dirty = true
	end,

	IsVisible = function()
		return panel.Visible
	end,
}

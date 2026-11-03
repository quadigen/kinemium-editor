if IsServer or IsClient or IsPlaytest then
	return
end

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Selection = game:GetService("Selection")
local DialogService = game:GetService("DialogService")
local HttpService = game:GetService("HttpService")

local UI = require("@internal/editor_ui")
local colors = UI.tokens.color

local PREVIEW_VARIANT_NAME = "__MaterialMakerPreview_" .. HttpService:GenerateGUID(false)
local LIBRARY_NAME = "MaterialVariants"
local VIEWPORT_HEIGHT = 200

local maps = {
	{ "Color map", "ColorMap" }, { "Normal map", "NormalMap" },
	{ "Roughness map", "RoughnessMap" }, { "Metalness map", "MetalnessMap" },
	{ "Occlusion map", "AOMap" }, { "Emissive map", "EmissiveMap" }, { "Height map", "HeightMap" },
}
local surface = {
	{ "Roughness", "Roughness", 0, 1, 3 },
	{ "Metalness", "Metalness", 0, 1, 3 },
	{ "Normal strength", "NormalStrength", 0, nil, 3 },
	{ "Occlusion strength", "AOStrength", 0, 1, 3 },
	{ "Emissive strength", "EmissiveStrength", 0, nil, 3 },
	{ "Studs per tile", "StudsPerTile", 0.001, nil, 3 },
}
local geometry = {
	{ "Height scale", "HeightScale", nil, nil, 3 },
	{ "Height midlevel", "HeightMidlevel", 0, 1, 3 },
	{ "Parallax depth", "ParallaxDepth", 0, nil, 3 },
	{ "Parallax steps", "ParallaxSteps", 8, 64, 0 },
	{ "Subdivisions", "DisplacementSubdivisions", 0, 4, 0 },
	{ "Displacement bounds", "DisplacementBounds", 0, nil, 3 },
}
local shader = {
	{ "Full shader", "Source", "Edit the Filament material definition. Keep the hook markers if you use the vertex or fragment hook fields." },
	{ "Vertex hook", "VertexSource", "Code inserted inside materialVertex, at the vertex hook marker." },
	{ "Fragment hook", "FragmentSource", "Code inserted inside material, at the fragment hook marker." },
}

local propertyKeys = { "Enabled", "Color", "EmissiveColor" }
for _, group in ipairs({ maps, surface, geometry, shader }) do
	for _, spec in ipairs(group) do table.insert(propertyKeys, spec[2]) end
end

local function readVariant(variant)
	local values = {}
	for _, key in ipairs(propertyKeys) do values[key] = variant[key] end
	return values
end

local template = Instance.new("MaterialVariant")
local defaults = readVariant(template)
template:Destroy()

local cfg = table.clone(defaults)
local variantName = "MyMaterial"
local editing
local fields = {}

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

local function button(text, callback)
	return place((UI.button(scroller, text, nil, UDim2.new(1, 0, 0, UI.metrics.buttonHeight), callback)))
end

local function hint(text, height)
	local label = UI.label(scroller, text, nil, UDim2.new(1, 0, 0, height), UI.tokens.type.caption, colors.subtext)
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	return place(label)
end

local function notify(kind, title, message)
	UI.toast("material-maker", { type = kind, title = title, message = tostring(message), duration = 6 })
end

local function setValue(key, value)
	cfg[key] = value
	dirty = true
end

local function hexToColor(text)
	local digits = text:match("^%s*#?(%x%x%x%x%x%x)%s*$")
	if not digits then return nil end
	return Color3.fromRGB(tonumber(digits:sub(1, 2), 16), tonumber(digits:sub(3, 4), 16), tonumber(digits:sub(5, 6), 16))
end

local function colorToHex(color)
	return string.format("#%02X%02X%02X", math.round(color.R * 255), math.round(color.G * 255), math.round(color.B * 255))
end

local function colorRow(label, key)
	local row, ctrl = UI.property(scroller, label, nil, nil, colorToHex(cfg[key]), function(value)
		setValue(key, hexToColor(value))
	end, {
		transparent = true,
		validate = function(text)
			local color = hexToColor(text)
			if not color then return false end
			return true, colorToHex(color)
		end,
	})
	place(row)
	fields[key] = function(value) ctrl:SetValue(colorToHex(value), true) end
end

local function assetRow(label, key)
	local row, ctrl = UI.property(scroller, label, nil, nil, cfg[key], function(value)
		setValue(key, value)
	end, { transparent = true, validate = function(value) return true, value:match("^%s*(.-)%s*$") end })
	place(row)
	fields[key] = function(value) ctrl:SetValue(value, true) end
	button("Browse " .. label:lower(), function()
		local path = DialogService:PickFile()
		if path and path ~= "" then
			setValue(key, path)
			fields[key](path)
		end
	end)
end

local function numericRows(specs)
	for _, spec in ipairs(specs) do
		local label, key, min, max, decimals = spec[1], spec[2], spec[3], spec[4], spec[5]
		local _, ctrl = numberRow(label, cfg[key], min, max, decimals, function(value)
			setValue(key, value)
		end)
		fields[key] = function(value) ctrl:SetValue(value, true) end
	end
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
	for _, key in ipairs(propertyKeys) do
		if variant[key] ~= cfg[key] then variant[key] = cfg[key] end
	end
end

local spin = true
local spinSpeed = 30
local lightAngle = 45

local function applyPreview()
	dirty = false
	if not previewVariant then
		previewVariant = Instance.new("MaterialVariant")
		previewVariant.Name = PREVIEW_VARIANT_NAME
		previewVariant.Archivable = false
		previewVariant.Parent = viewport
	end
	fillVariant(previewVariant)
	ball.MaterialVariant = PREVIEW_VARIANT_NAME
	viewport.LightDirection = Vector3.new(-math.cos(math.rad(lightAngle)), -1, -math.sin(math.rad(lightAngle)))
end

section("Variant")
local nameRow, nameField = UI.property(scroller, "Name", nil, nil, variantName, function(value)
	variantName = value
end, {
	transparent = true,
	validate = function(value)
		local clean = value:match("^%s*(.-)%s*$")
		return clean ~= "" and #clean <= 128 and not clean:find("[%z\1-\31]"), clean
	end,
})
place(nameRow)

local function load(variant)
	editing = variant
	cfg = variant and readVariant(variant) or table.clone(defaults)
	variantName = variant and variant.Name or "MyMaterial"
	nameField:SetValue(variantName, true)
	nameField:SetEnabled(not variant)
	for key, update in pairs(fields) do update(cfg[key]) end
	dirty = true
end

local savedServices = {
	Workspace = true, ReplicatedFirst = true, ReplicatedStorage = true, Lighting = true,
	SoundService = true, StarterGui = true, StarterPack = true, StarterPlayer = true,
	ServerScriptService = true, ServerStorage = true,
}

local function variants()
	local list = {}
	local pending = {}
	for _, service in ipairs(game:GetChildren()) do
		if savedServices[service.Name] then table.insert(pending, service) end
	end
	while #pending > 0 do
		local instance = table.remove(pending)
		if instance.ClassName == "MaterialVariant" and instance ~= previewVariant then
			table.insert(list, instance)
		end
		for _, child in ipairs(instance:GetChildren()) do table.insert(pending, child) end
	end
	return list
end

button("New Variant", function() load(nil) end)
button("Load Existing Variant", function()
	local all = variants()
	if #all == 0 then
		notify("info", "Material Maker", "There are no saved variants to load.")
		return
	end
	table.sort(all, function(a, b) return a:GetFullName() < b:GetFullName() end)
	local selected
	UI.prompt({
		title = "Load Material Variant",
		size = UDim2.fromOffset(500, 365),
		destroyOnClose = true,
		buttons = {
			{ id = "cancel", text = "Cancel", role = "secondary" },
			{ id = "load", text = "Load", role = "primary", callback = function()
				if not selected or not selected:IsDescendantOf(game) then return false end
				load(selected)
			end },
		},
		build = function(parent, controller)
			local scroll = UI.create("ScrollingFrame", {
				BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
				CanvasSize = UDim2.fromOffset(0, #all * 32), ScrollBarThickness = 5,
			}, parent)
			local records = {}
			for index, variant in ipairs(all) do
				local _, _, record = UI.button(scroll, variant:GetFullName(), UDim2.fromOffset(0, (index - 1) * 32),
					UDim2.new(1, -10, 0, 29), function()
						selected = variant
						for item, state in pairs(records) do UI.setButtonState(state, item == selected and "selected" or nil) end
						controller:SetButtonEnabled("load", true)
					end)
				records[variant] = record
			end
			controller:SetButtonEnabled("load", false)
		end,
	})
end)

local function saveVariant()
	local ok, result = pcall(function()
		if editing then
			assert(editing:IsDescendantOf(game), "This variant was removed. Start a new variant or load one from the current project.")
		end
		local name = editing and editing.Name or variantName
		for _, variant in ipairs(variants()) do
			assert(variant == editing or variant.Name ~= name, "A variant named " .. name .. " already exists. Load it to edit it.")
		end

		local library
		if not editing then
			library = ReplicatedStorage:FindFirstChild(LIBRARY_NAME)
			assert(not library or library:IsA("Folder"), LIBRARY_NAME .. " in ReplicatedStorage must be a Folder.")
		end
		local variant = editing or Instance.new("MaterialVariant")
		local filled, message = pcall(fillVariant, variant)
		if not filled then
			if not editing then variant:Destroy() end
			error(message, 0)
		end
		if not editing then
			if not library then
				library = Instance.new("Folder")
				library.Name = LIBRARY_NAME
				library.Parent = ReplicatedStorage
			end
			variant.Name = name
			variant.Parent = library
		end
		editing = variant
		variantName = name
		nameField:SetValue(name, true)
		nameField:SetEnabled(false)
		return variant
	end)
	if not ok then
		notify("error", "Could not save material", result)
		return nil
	end
	return result
end

button("Save Variant", function()
	local variant = saveVariant()
	if variant then notify("success", "Material saved to scene", variant.Name .. " will be included in the next project save.") end
end)

button("Save and Apply to Selection", function()
	local parts = {}
	for _, object in ipairs(Selection:Get()) do
		if object:IsA("Part") then table.insert(parts, object) end
	end
	if #parts == 0 then
		notify("info", "Select a part", "Select a Part or MeshPart to apply the material.")
		return
	end
	local variant = saveVariant()
	if not variant then return end
	for _, part in ipairs(parts) do part.MaterialVariant = variant.Name end
	notify("success", "Material applied", variant.Name .. " applied to " .. #parts .. " parts.")
end)

section("Surface")
local enabledRow, enabledField = UI.checkbox(scroller, "Enabled", nil, cfg.Enabled, function(value)
	setValue("Enabled", value)
end, { size = UDim2.new(1, 0, 0, UI.metrics.propertyRow) })
place(enabledRow)
fields.Enabled = function(value) enabledField:SetValue(value, true, true) end
colorRow("Base color", "Color")
colorRow("Emissive color", "EmissiveColor")
numericRows(surface)

section("Texture Maps")
hint("Browse for an image or enter a local path or content URI. Leave a map empty to use the shader default.", 38)
for _, spec in ipairs(maps) do assetRow(spec[1], spec[2]) end

section("Height and Displacement")
numericRows(geometry)

section("Shader")
local shaderStatus = hint("Waiting for preview…", 34)
local lastStatus
local function updateShaderStatus()
	local message
	local isError = false
	if not cfg.Enabled then
		message = "Variant disabled"
	elseif previewVariant.LastError ~= "" then
		message = "Preview reported an error. Open the preview log for details."
		isError = true
	else
		message = previewVariant.Compiled and "Preview shader compiled" or "Waiting for preview compilation…"
	end
	if message == lastStatus then return end
	lastStatus = message
	shaderStatus.Text = message
	shaderStatus.TextColor3 = isError and colors.error or colors.subtext
end

button("Show Preview Log", function()
	local report = previewVariant and previewVariant.LastError or ""
	if report == "" then
		notify("info", "Preview Log", "There are no shader or texture errors to show.")
		return
	end
	UI.prompt({
		title = "Material Preview Log",
		size = UDim2.fromOffset(760, 440),
		destroyOnClose = true,
		build = function(content)
			UI.create("TextBox", {
				Size = UDim2.fromScale(1, 1), Text = report, CodeEditor = true, TextEditable = false,
				WordWrap = true, TextSize = 13, TextColor3 = colors.text, BackgroundColor3 = colors.input,
			}, content)
		end,
	})
end)

for _, spec in ipairs(shader) do
	local label, key, description = table.unpack(spec)
	button("Edit " .. label, function()
		local editor
		UI.prompt({
			title = label,
			description = description,
			size = UDim2.fromOffset(760, 510),
			destroyOnClose = true,
			buttons = {
				{ id = "cancel", text = "Cancel", role = "secondary" },
				{ id = "apply", text = "Apply to Preview", role = "primary", callback = function()
					if key == "Source" and not editor.Text:find("%S") then
						notify("error", "Shader source is empty", "Enter a Filament material definition or reset the shader.")
						return false
					end
					setValue(key, editor.Text)
				end },
			},
			build = function(content)
				editor = UI.create("TextBox", {
					Size = UDim2.fromScale(1, 1), Text = cfg[key], ClearTextOnFocus = false,
					TextSize = 14, CodeEditor = true, Active = true, AutoIndent = true, ShowLineNumbers = true, TextColor3 = colors.text, BackgroundColor3 = colors.input,
				}, content)
			end,
		})
	end)
end

button("Reset Shader to Default", function()
	for _, spec in ipairs(shader) do setValue(spec[2], defaults[spec[2]]) end
end)

section("Preview Controls")
place((UI.checkbox(scroller, "Auto rotate", nil, spin, function(value) spin = value end,
	{ size = UDim2.new(1, 0, 0, UI.metrics.propertyRow) })))
numberRow("Spin speed", spinSpeed, 0, 360, 0, function(value) spinSpeed = value end)
numberRow("Light angle", lightAngle, 0, 360, 0, function(value) lightAngle = value; dirty = true end)

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

	updateShaderStatus()

	if spin and not dragging then
		spinAngle = (spinAngle + spinSpeed * dt) % 360
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

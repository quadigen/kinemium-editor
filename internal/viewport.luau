if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local UI = require("./editor_ui")
local CodeEditor = require("@internal/code_editor")
local docker = require("@internal/docker")
local UIEditor = require("@internal/ui_editor")

local StudioThemeService = game:GetService("StudioThemeService")
local theme = StudioThemeService.SelectedTheme
local TextService = game:GetService("TextService")
local Selection = game:GetService("Selection")
local PlaytestService = game:GetService("PlaytestService")

local colors = UI.colors
local tokens = UI.tokens

local iconRoot = "builtin://icons/"

local panel, content, header =
	UI.window("Viewport", theme.ViewportCoordinates.Position, theme.ViewportCoordinates.Size, "Viewport")

panel.BackgroundTransparency = 1
content.BackgroundTransparency = 1

local chromeHeight = UI.metrics.windowHeader + 1

local root = UI.root()
local rootOverlay = UI.RootOverlay()

local scriptLayer = UI.create("ScreenGui", {
	Name = "ScriptEditorLayer",
	DisplayOrder = 1000,
	IgnoreGuiInset = true,
}, game.CoreGui)

shared.ScriptLayer = scriptLayer

scriptLayer.RenderOnTop = true

local scriptRoot = UI.frame(scriptLayer, UDim2.new(), UDim2.new(), tokens.color.canvas)

scriptRoot.Name = "ScriptEditorRoot"
scriptRoot.BackgroundTransparency = 1
scriptRoot.Visible = false

local function getViewportPosition()
	return UDim2.new(
		theme.ViewportCoordinates.Position.X.Scale,
		theme.ViewportCoordinates.Position.X.Offset,
		theme.ViewportCoordinates.Position.Y.Scale,
		theme.ViewportCoordinates.Position.Y.Offset + chromeHeight
	)
end

local function getViewportSize()
	return UDim2.new(
		theme.ViewportCoordinates.Size.X.Scale,
		theme.ViewportCoordinates.Size.X.Offset,
		theme.ViewportCoordinates.Size.Y.Scale,
		theme.ViewportCoordinates.Size.Y.Offset - chromeHeight
	)
end

local viewportRoot = UI.frame(root, getViewportPosition(), getViewportSize(), tokens.color.canvas)

viewportRoot.Name = "ViewportRoot"
viewportRoot.BackgroundTransparency = 1

local viewportOverlay = UI.frame(rootOverlay, getViewportPosition(), getViewportSize(), tokens.color.canvas)

viewportOverlay.Name = "ViewportOverlay"
viewportOverlay.BackgroundTransparency = 1
viewportOverlay.ClipsDescendants = true

local dropHighlight = UI.frame(viewportOverlay, UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), colors.accent)

dropHighlight.Name = "DropHighlight"
dropHighlight.BackgroundTransparency = 0.92
dropHighlight.Active = false
dropHighlight.Visible = false
dropHighlight.ZIndex = 50

UI.stroke(dropHighlight, colors.accent, 2, 0.2)

local activeTool = renderer.Dimension == "2D" and "Select" or "Move"
local snapEnabled = true

local handles = Instance.new("Handles")
handles.Name = "ViewportHandles"
handles.Snap = 1
handles.Parent = workspace

local arcHandles = Instance.new("ArcHandles")
arcHandles.Name = "ViewportArcHandles"
arcHandles.Snap = 30
arcHandles.Parent = workspace

local function selectedPart()
	local selected = Selection:Get()
	local object = selected and selected[1]
	if object and (object:IsA("Part") or object:IsA("MeshPart") or object:IsA("Model")) then
		return object
	end
	return nil
end

local function updateGizmos()
	local adornee = selectedPart()
	local is3D = renderer.Dimension == "3D"

	handles.Adornee = adornee
	arcHandles.Adornee = adornee
	handles.Visible = is3D and adornee ~= nil and (activeTool == "Move" or activeTool == "Size")
	arcHandles.Visible = is3D and adornee ~= nil and activeTool == "Rotate"

	if activeTool == "Move" then
		handles.Style = Enum.HandlesStyle.Movement
	elseif activeTool == "Size" then
		handles.Style = Enum.HandlesStyle.Resize
	elseif activeTool == "Select" then
		handles.Visible = false
		arcHandles.Visible = false
	else
		handles.Visible = false
		arcHandles.Visible = false
	end
end

local startSinglePlayer = false
local playGroup, playControls = UI.iconButtonGroup(header, UDim2.fromScale(0.5, 0.5), {
	{
		name = "Play",
		icon = iconRoot .. "Play.svg",
		tooltip = "Play",
		key = Enum.KeyCode.F5,
		onClick = function()
			if startSinglePlayer then
				PlaytestService:StartSinglePlayer()
			else
				PlaytestService:Start()
			end
		end,
	},
	{ separator = true },
	{
		name = "Stop",
		icon = iconRoot .. "Stop.svg",
		tooltip = "Stop",
		key = Enum.KeyCode.F8,
		onClick = function()
			PlaytestService:Stop()
		end,
	},
	{ separator = true },
	{
		name = "Settings",
		icon = iconRoot .. "Settings.svg",
		tooltip = "Playtest settings",
		toggle = true,
		onClick = function(open) end,
	},
}, { anchorPoint = Vector2.new(0.5, 0.5), color = tokens.color.surfaceAlt })

local settingsBtn = playControls:GetButton("Settings")

local frame = Instance.new("ScrollingFrame")
frame.Position =
	UDim2.fromOffset(settingsBtn.AbsolutePosition.X, settingsBtn.AbsolutePosition.Y + settingsBtn.AbsoluteSize.Y)
frame.AnchorPoint = Vector2.new(0.5, -0.02)
frame.BackgroundTransparency = 0.5
frame.Name = "PlaytestSettings"
frame.Size = UDim2.new(0, 140, 0, 200)
frame.BackgroundColor3 = colors.input
frame.Visible = false
frame.Parent = rootOverlay

settingsBtn.MouseButton1Click:Connect(function()
	frame.Visible = not frame.Visible
end)

UI.corner(frame, tokens.radius.sm)
UI.backdrop(frame)

local settings_layout = Instance.new("UIListLayout")
settings_layout.FillDirection = Enum.FillDirection.Vertical
settings_layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
settings_layout.VerticalAlignment = Enum.VerticalAlignment.Top
settings_layout.PaddingLeft = UDim.new(0, 10)
settings_layout.PaddingTop = UDim.new(0, 8)
settings_layout.Padding = UDim.new(0, 4)
settings_layout.Parent = frame

local _, headless_server_checkbox_playtest_settings = UI.checkbox(
	frame,
	"Headless Server",
	UDim2.fromOffset(8, 8),
	false,
	function(value)
		print(value)
	end
)

local _, headless_client = UI.checkbox(frame, "Headless Client", UDim2.fromOffset(8, 8), false, function(value)
	print(value)
end)

local uiEditor = UIEditor.new({
	overlay = viewportOverlay,
	canPick = true,
	clearOnEmpty = renderer.Dimension == "2D",
	contextOnEmpty = renderer.Dimension == "2D",
	getTool = function()
		return activeTool
	end,
	getSnap = function()
		return snapEnabled
	end,
	snapStep = 4,
	rotateSnap = 15,
	smoothDrag = true,
	guides = true,
	shortcuts = true,
})

local colorPicker
local colorPickerController

local function selectedColor()
	local object = selectedPart()
	if object and (object:IsA("Part") or object:IsA("MeshPart")) then
		return object.Color
	end
	return Color3.new(1, 1, 1)
end

local function applyColor(color)
	local object = selectedPart()
	if object and (object:IsA("Part") or object:IsA("MeshPart")) then
		object.Color = color
	end
end

colorPicker, colorPickerController =
	UI.colorPicker(viewportOverlay, UDim2.fromOffset(48, 99), UDim2.fromOffset(226, 286), selectedColor(), applyColor)

-- Transform toolbar (radio group; "Snap" is a toggle inside it in 2D)
local toolButtonSize = Vector2.new(30, UI.metrics.toolbarButton)

local toolItems = {
	{ name = "Select", icon = iconRoot .. "Cursor.svg", tooltip = "Select", key = Enum.KeyCode.One },
	{ name = "Move", icon = iconRoot .. "Move.svg", tooltip = "Move", key = Enum.KeyCode.Two },
	{ name = "Size", icon = iconRoot .. "Size.svg", tooltip = "Resize", key = Enum.KeyCode.Three },
	{ name = "Rotate", icon = iconRoot .. "Rotate.svg", tooltip = "Rotate", key = Enum.KeyCode.Four },
}

if renderer.Dimension == "2D" then
	table.insert(toolItems, { separator = true })
	table.insert(toolItems, {
		name = "Snap",
		icon = iconRoot .. "Snap.svg",
		tooltip = "Toggle Snap",
		toggle = true,
		active = snapEnabled,
	})
end

local toolbar, toolControls =
	UI.iconButtonGroup(viewportOverlay, UDim2.fromOffset(renderer.Dimension == "2D" and 22 or 8, 8), toolItems, {
		name = "TransformToolbar",
		orientation = "vertical",
		mode = "radio",
		selected = activeTool,
		buttonSize = toolButtonSize,
		iconSize = 18,
		padding = 2,
		gap = 2,
		color = tokens.color.surface,
		radius = tokens.radius.md,
	})

toolbar.BackgroundTransparency = 0.5

local toolbarBackdrop = Instance.new("UIBackdrop")
toolbarBackdrop.Parent = toolbar

local styleBar, styleControls
local materialMenu

local function closeMenus()
	colorPicker.Visible = false

	if materialMenu then
		materialMenu.Visible = false
	end

	if styleControls then
		styleControls:SetActive("Material", false, true)
		styleControls:SetActive("Color", false, true)
	end
end

toolControls.Changed:Connect(function(name, value)
	if name == "Snap" then
		snapEnabled = value
		return
	end

	activeTool = name
	closeMenus()
	updateGizmos()
end)

local STYLE_BAR_GAP = 10
local MENU_GAP = 8

if renderer.Dimension == "3D" then
	local function applyMaterial(material)
		local object = selectedPart()
		if object and (object:IsA("Part") or object:IsA("MeshPart")) then
			object.Material = material
		end
	end

	styleBar, styleControls = UI.iconButtonGroup(viewportOverlay, UDim2.fromOffset(8, 8), {
		{ name = "Material", icon = iconRoot .. "Material.svg", tooltip = "Material", toggle = true },
		{ name = "Color", icon = iconRoot .. "ColorEffect.svg", tooltip = "Color", toggle = true },
	}, {
		name = "StyleToolbar",
		orientation = "vertical",
		buttonSize = toolButtonSize,
		iconSize = 18,
		padding = 2,
		gap = 2,
		color = tokens.color.surface,
		radius = tokens.radius.md,
	})

	styleBar.BackgroundTransparency = 0.5

	local styleBackdrop = Instance.new("UIBackdrop")
	styleBackdrop.Parent = styleBar

	local materialNames = {
		Enum.Material.SmoothPlastic,
		Enum.Material.Wood,
		Enum.Material.Concrete,
		Enum.Material.Brick,
		Enum.Material.Sand,
		Enum.Material.Grass,
		Enum.Material.Ice,
		Enum.Material.Glass,
	}

	local rowHeight, rowGap = 24, 2

	materialMenu = UI.group(viewportOverlay, UDim2.fromOffset(0, 0), UDim2.fromOffset(180, 230), {
		color = tokens.color.surface,
		radius = tokens.radius.md,
	})
	materialMenu.Name = "MaterialMenu"
	materialMenu.BackgroundTransparency = 0.5
	materialMenu.Visible = false
	materialMenu.ZIndex = 20

	local materialBackdrop = Instance.new("UIBackdrop")
	materialBackdrop.Parent = materialMenu

	local list = Instance.new("ScrollingFrame")
	list.Name = "MaterialList"
	list.Position = UDim2.fromOffset(6, 6)
	list.Size = UDim2.new(1, -12, 1, -12)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 3
	list.ZIndex = materialMenu.ZIndex + 1
	list.Parent = materialMenu

	local listLayout = Instance.new("UIGridLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.CellSize = UDim2.new(0, 50, 0, 50)
	listLayout.Parent = list

	local shown = 0
	for _, materialName in ipairs(materialNames) do
		local button = UI.button(list, "", UDim2.fromOffset(0, 0), UDim2.fromOffset(50, 50), {
			color = tokens.color.surfaceAlt,
			radius = tokens.radius.sm,
		})
		button.BackgroundTransparency = 0.5

		local preview = Instance.new("ViewportFrame", button)
		preview.Size = UDim2.fromScale(1, 1)
		preview.BackgroundTransparency = 1

		local part = Instance.new("Part", preview)
		part.Size = Vector3.new(3, 3, 3)
		part.Position = Vector3.zero
		part.Anchored = true
		part.Shape = Enum.PartType.Ball
		part.Material = materialName

		local camera = Instance.new("Camera", preview)
		camera.FieldOfView = 30
		camera.CFrame = CFrame.lookAt(Vector3.new(0, 0, 7.5), part.Position)
		preview.CurrentCamera = camera
	end

	list.CanvasSize = UDim2.fromOffset(0, shown * (rowHeight + rowGap))

	styleControls.Changed:Connect(function(name, open)
		if name == "Material" then
			materialMenu.Visible = open
			if open then
				colorPicker.Visible = false
				styleControls:SetActive("Color", false, true)
			end
		elseif name == "Color" then
			colorPicker.Visible = open
			if open then
				colorPickerController:SetColor(selectedColor(), true)
				materialMenu.Visible = false
				styleControls:SetActive("Material", false, true)
			end
		end
	end)
end

local function placeMenu(menu, buttonName)
	if not menu or not styleControls or not menu.Visible then
		return
	end

	local button = styleControls:GetButton(buttonName)
	local origin = viewportOverlay.AbsolutePosition

	local x = styleBar.AbsolutePosition.X - origin.X + styleBar.AbsoluteSize.X + MENU_GAP
	local y = button.AbsolutePosition.Y - origin.Y
	local maxY = viewportOverlay.AbsoluteSize.Y - menu.AbsoluteSize.Y - 8

	menu.Position = UDim2.fromOffset(x, math.max(8, math.min(y, maxY)))
end

local breadcrumb = UI.group(viewportOverlay, UDim2.new(0, 8, 1, -30), UDim2.new(1, -16, 0, 26), {
	color = tokens.color.surface,
	radius = tokens.radius.sm,
})

breadcrumb.BackgroundTransparency = 1
breadcrumb.Name = "ViewportBreadcrumb"
breadcrumb.Visible = renderer.Dimension == "3D"
breadcrumb.ClipsDescendants = true

if gizmoFrame then
	gizmoFrame.Visible = not hasDocument
end

local editor = CodeEditor.new(scriptRoot)

local GIZMO_SIZE = 96
local GIZMO_DISTANCE = 6.5
local gizmoFrame, gizmoCamera

-- Orientation gizmo (3D only): mirrors workspace.CurrentCamera rotation, no text.
local GIZMO_SIZE = 112
local GIZMO_DISTANCE = 10
local gizmoFrame, gizmoCamera

if renderer.Dimension == "3D" then
	gizmoFrame = Instance.new("ViewportFrame")
	gizmoFrame.Name = "AxisGizmo"
	gizmoFrame.AnchorPoint = Vector2.new(1, 1)
	gizmoFrame.Position = UDim2.new(1, -8, 1, -36) -- sits above the breadcrumb
	gizmoFrame.Size = UDim2.fromOffset(GIZMO_SIZE, GIZMO_SIZE)
	gizmoFrame.BackgroundTransparency = 1
	gizmoFrame.Ambient = Color3.fromRGB(150, 150, 150)
	gizmoFrame.LightColor = Color3.new(1, 1, 1)
	gizmoFrame.LightDirection = Vector3.new(-1, -1.5, -0.8)
	gizmoFrame.Active = false
	gizmoFrame.ZIndex = 10
	gizmoFrame.Parent = viewportOverlay

	gizmoCamera = Instance.new("Camera")
	gizmoCamera.FieldOfView = 30
	gizmoCamera.Parent = gizmoFrame
	gizmoFrame.CurrentCamera = gizmoCamera

	local SHAFT_LENGTH = 1.6
	local SHAFT_RADIUS = 0.06
	local CONE_LENGTH = 0.75
	local CONE_RADIUS = 0.22
	local CONE_STEPS = 8 -- stacked discs approximate a smooth cone
	local COLLAR_RADIUS = 0.1
	local NEG_LENGTH = 1.0
	local NEG_RADIUS = 0.035
	local RING_RADIUS = 2.0
	local RING_SEGMENTS = 48

	local function makePart(size, shape, color, cframe, transparency)
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.Size = size
		part.Shape = shape
		part.Color = color
		part.Material = Enum.Material.SmoothPlastic
		part.CFrame = cframe
		part.Transparency = transparency or 0
		part.Parent = gizmoFrame
		return part
	end

	local function ball(diameter, color, position, transparency)
		return makePart(Vector3.one * diameter, Enum.PartType.Ball, color, CFrame.new(position), transparency)
	end

	-- Cylinders run along their local X axis, so build a basis whose X points down the axis.
	local function cylinder(basis, distance, length, radius, color, transparency)
		local cframe = CFrame.fromMatrix(basis.dir * distance, basis.dir, basis.up)
		return makePart(
			Vector3.new(length, radius * 2, radius * 2),
			Enum.PartType.Cylinder,
			color,
			cframe,
			transparency
		)
	end

	local function darken(color, amount)
		return color:Lerp(Color3.new(0, 0, 0), amount)
	end

	local function fade(color, amount)
		return color:Lerp(Color3.fromRGB(120, 120, 130), amount)
	end

	local axes = {
		{ dir = Vector3.xAxis, up = Vector3.yAxis, color = Color3.fromRGB(235, 70, 70) },
		{ dir = Vector3.yAxis, up = Vector3.xAxis, color = Color3.fromRGB(80, 200, 90) },
		{ dir = Vector3.zAxis, up = Vector3.yAxis, color = Color3.fromRGB(70, 120, 255) },
	}

	for _, axis in ipairs(axes) do
		local color = axis.color

		-- Positive shaft
		cylinder(axis, SHAFT_LENGTH / 2, SHAFT_LENGTH, SHAFT_RADIUS, color)

		-- Tick bands along the shaft
		for _, t in ipairs({ 0.4, 0.8, 1.2 }) do
			cylinder(axis, t, 0.04, SHAFT_RADIUS * 1.35, darken(color, 0.35))
		end

		-- Collar where the shaft meets the cone
		cylinder(axis, SHAFT_LENGTH, 0.08, COLLAR_RADIUS, darken(color, 0.2))

		-- Tapered cone arrowhead built from stacked discs
		local stepLength = CONE_LENGTH / CONE_STEPS
		for i = 1, CONE_STEPS do
			local t = (i - 1) / CONE_STEPS
			local radius = math.max(CONE_RADIUS * (1 - t), 0.015)
			cylinder(axis, SHAFT_LENGTH + 0.04 + (i - 0.5) * stepLength, stepLength * 1.02, radius, color)
		end

		-- Negative stub: thinner, dimmer, with a small bead on the end
		local dimmed = fade(color, 0.55)
		local negBasis = { dir = -axis.dir, up = axis.up }
		cylinder(negBasis, NEG_LENGTH / 2, NEG_LENGTH, NEG_RADIUS, dimmed, 0.15)
		ball(0.16, dimmed, -axis.dir * NEG_LENGTH, 0.15)
	end

	-- Hub: solid core plus a translucent shell
	ball(0.28, Color3.fromRGB(230, 230, 235), Vector3.zero)
	ball(0.42, Color3.fromRGB(255, 255, 255), Vector3.zero, 0.75)

	-- Ground-plane (XZ) disc and rim for depth cues
	makePart(
		Vector3.new(0.01, RING_RADIUS * 2, RING_RADIUS * 2),
		Enum.PartType.Cylinder,
		Color3.fromRGB(200, 205, 215),
		CFrame.Angles(0, 0, math.rad(90)),
		0.92
	)

	local segmentLength = 2 * math.pi * RING_RADIUS / RING_SEGMENTS
	for i = 0, RING_SEGMENTS - 1 do
		local angle = (i / RING_SEGMENTS) * math.pi * 2
		local position = Vector3.new(math.cos(angle) * RING_RADIUS, 0, math.sin(angle) * RING_RADIUS)
		makePart(
			Vector3.new(segmentLength, 0.02, 0.03),
			Enum.PartType.Block,
			Color3.fromRGB(210, 215, 225),
			CFrame.lookAt(position, Vector3.zero) * CFrame.Angles(0, math.rad(90), 0),
			0.55
		)
	end

	-- Small marker beads where each axis crosses the ring
	for _, axis in ipairs(axes) do
		if axis.dir ~= Vector3.yAxis then
			local marker = fade(axis.color, 0.6)
			ball(0.1, marker, axis.dir * RING_RADIUS, 0.3)
			ball(0.1, marker, -axis.dir * RING_RADIUS, 0.3)
		end
	end
end

local function updateAxisGizmo()
	if not gizmoFrame then
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	-- Copy only the rotation, then back the gizmo camera away from the origin along its look vector
	local rotation = camera.CFrame.Rotation
	gizmoCamera.CFrame = CFrame.new(-rotation.LookVector * GIZMO_DISTANCE) * rotation
end

local function rebuildBreadcrumb(path)
	UI.clear(breadcrumb)

	local x = 8
	local items = string.split(path, ".")

	for index, item in ipairs(items) do
		local textSize = TextService:GetTextSize(
			item,
			tokens.type.caption,
			"builtin://fonts/Montserrat-Regular.ttf",
			Vector2.new(10000, 10000)
		)

		local width = math.max(34, math.ceil(textSize.X) + 4)

		local label = UI.label(
			breadcrumb,
			item,
			UDim2.fromOffset(x, 4),
			UDim2.fromOffset(width, 18),
			tokens.type.caption,
			Color3.new(1, 1, 1)
		)

		local shadow = Instance.new("UIShadow")
		shadow.ShowForText = true
		shadow.BlurRadius = UDim.new(0, 2.5)
		shadow.Offset = UDim2.fromOffset(2, 2)
		shadow.Spread = UDim2.fromOffset(0, 5)
		shadow.Color3 = Color3.fromRGB(0, 0, 0)
		shadow.Transparency = 0.8
		shadow.Parent = label

		x += width + 2

		if index < #items then
			local image =
				UI.image(breadcrumb, iconRoot .. "ArrowRight.svg", UDim2.fromOffset(x + 1, 7), UDim2.fromOffset(10, 10))

			local img_shadow = Instance.new("UIShadow")
			img_shadow.ShowForText = false
			img_shadow.BlurRadius = UDim.new(0, 2.5)
			img_shadow.Offset = UDim2.fromOffset(2, 2)
			img_shadow.Spread = UDim2.fromOffset(0, 5)
			img_shadow.Color3 = Color3.fromRGB(0, 0, 0)
			img_shadow.Transparency = 0.8
			img_shadow.Enabled = true
			img_shadow.Parent = image

			x += 17
		end
	end
end

rebuildBreadcrumb("Workspace.Part")

local lastPath = ""

Selection.SelectionChanged:Connect(function()
	lastPath = ""
	updateGizmos()
end)

updateGizmos()

renderer.Pool.new("2d", function()
	theme = StudioThemeService.SelectedTheme

	local outputWindow = UI.getWindow("Output")
	local outputHidden = outputWindow and not outputWindow.Visible

	local viewportSize = getViewportSize()

	local viewportPosition = getViewportPosition()

	viewportRoot.Position = viewportPosition
	viewportRoot.Size = viewportSize

	viewportOverlay.Position = viewportPosition
	viewportOverlay.Size = viewportSize

	if outputHidden and theme.OutputCoordinates then
		viewportSize = UDim2.new(
			viewportSize.X.Scale,
			viewportSize.X.Offset,
			viewportSize.Y.Scale,
			viewportSize.Y.Offset + theme.OutputCoordinates.Size.Y.Offset
		)
	end

	viewportRoot.Position = getViewportPosition()
	viewportRoot.Size = viewportSize

	viewportOverlay.Position = getViewportPosition()
	viewportOverlay.Size = viewportSize

	scriptRoot.Position = getViewportPosition()
	scriptRoot.Size = viewportSize

	panel.Position = theme.ViewportCoordinates.Position
	panel.Size = UDim2.new(
		theme.ViewportCoordinates.Size.X.Scale,
		theme.ViewportCoordinates.Size.X.Offset,
		theme.ViewportCoordinates.Size.Y.Scale,
		theme.ViewportCoordinates.Size.Y.Offset + (outputHidden and theme.OutputCoordinates.Size.Y.Offset or 0)
	)

	local selected = Selection:Get()
	local object = selected and selected[1]

	local path = object and object:GetFullName() or "Workspace"

	if path ~= lastPath then
		lastPath = path
		rebuildBreadcrumb(path)
	end

	if editor:OpenScriptCount() > 0 or toolbar.Visible then
		local relabelled = false
		local doomed = nil

		for _, document in ipairs(editor.documents) do
			local instance = document.instance

			if instance == nil and document.path == nil or instance ~= nil and not UI.isAlive(instance) then
				doomed = doomed or {}
				table.insert(doomed, document)
			elseif instance ~= nil and instance.Name ~= document.name then
				document.name = instance.Name
				relabelled = true
			end
		end

		for _, document in ipairs(doomed or {}) do
			editor:closeDocument(document)
		end

		if relabelled then
			editor:rebuildTabs()
		end

		local hasDocument = editor:hasDocument()

		scriptRoot.Visible = hasDocument
		toolbar.Visible = not hasDocument

		if styleBar then
			styleBar.Visible = not hasDocument
		end

		if hasDocument then
			closeMenus()
		end

		breadcrumb.Visible = not hasDocument and renderer.Dimension == "3D"
		if gizmoFrame then
			gizmoFrame.Visible = not hasDocument
		end

		editor:updateVisibility()
	end
end)

local lastX = -1
local lastY = -1
local lastWidth = -1
local lastHeight = -1

local function getRenderBounds(): (Vector2, Vector2)
	local position = viewportRoot.AbsolutePosition
	local size = viewportRoot.AbsoluteSize
	local top = position.Y
	local topbarBottom = UI.shared().topbarBottom or 0
	if topbarBottom >= top then
		top = topbarBottom + 4
	end
	return Vector2.new(position.X, top), Vector2.new(size.X, position.Y + size.Y - top)
end

-- Camera projection uses viewport pixels; editor input uses window GUI units.
local function screenToViewportPoint(point: Vector2): Vector2?
	local camera = workspace.CurrentCamera
	local position, size = getRenderBounds()
	if not camera or size.X <= 0 or size.Y <= 0 then
		return nil
	end
	local pixels = camera.ViewportSize
	return Vector2.new((point.X - position.X) * pixels.X / size.X, (point.Y - position.Y) * pixels.Y / size.Y)
end

local function viewportToScreenPoint(point: Vector2): Vector2?
	local camera = workspace.CurrentCamera
	local position, size = getRenderBounds()
	if not camera or size.X <= 0 or size.Y <= 0 then
		return nil
	end
	local pixels = camera.ViewportSize
	if pixels.X <= 0 or pixels.Y <= 0 then
		return nil
	end
	return Vector2.new(position.X + point.X * size.X / pixels.X, position.Y + point.Y * size.Y / pixels.Y)
end

renderer.Pool.new("2da", function()
	local dragging = docker.Update(panel, "Viewport")

	updateAxisGizmo()

	if not dragging then
		panel.Position = theme.ViewportCoordinates.Position
		panel.Size = theme.ViewportCoordinates.Size
	end

	frame.Position =
		UDim2.fromOffset(settingsBtn.AbsolutePosition.X, settingsBtn.AbsolutePosition.Y + settingsBtn.AbsoluteSize.Y)

	local absolutePosition = viewportRoot.AbsolutePosition
	local absoluteSize = viewportRoot.AbsoluteSize

	local absoluteX = absolutePosition.X
	local absoluteY = absolutePosition.Y
	local absoluteWidth = absoluteSize.X
	local absoluteHeight = absoluteSize.Y

	if absoluteWidth <= 0 or absoluteHeight <= 0 then
		return
	end

	local renderPosition, renderSize = getRenderBounds()
	local renderTop = renderPosition.Y
	local renderHeight = renderSize.Y

	if renderHeight <= 0 then
		return
	end

	if absoluteX ~= lastX or renderTop ~= lastY or absoluteWidth ~= lastWidth or renderHeight ~= lastHeight then
		lastX = absoluteX
		lastY = renderTop
		lastWidth = absoluteWidth
		lastHeight = renderHeight
	end

	if renderer.Dimension == "3D" then
		if rootOverlay.Enabled then
			renderer:Set3DTexProps(absoluteX, renderTop, absoluteWidth, renderHeight)
		else
			renderer:Set3DTexProps(0, 0, 0, 0)
		end
	end

	local overlayInset = math.max(0, renderTop - absoluteY)

	toolbar.Position = UDim2.fromOffset(renderer.Dimension == "2D" and 22 or 8, 8 + overlayInset)

	if styleBar then
		-- toolbar's height can animate, so follow its live size
		styleBar.Position = UDim2.fromOffset(
			toolbar.Position.X.Offset,
			toolbar.Position.Y.Offset + toolbar.AbsoluteSize.Y + STYLE_BAR_GAP
		)

		placeMenu(colorPicker, "Color")
		placeMenu(materialMenu, "Material")
	end

	for _, object in ipairs(game.StarterGui:GetChildren()) do
		if object:IsA("ScreenGui") then
			object.Size = Vector2.new(absoluteWidth, renderHeight)

			object.RenderOffset = Vector2.new(absoluteX, renderTop)
		end
	end
	uiEditor:SetEnabled(not scriptRoot.Visible)
	uiEditor:Update()
end)

local API = {
	OpenScript = function(instance, line)
		editor:OpenScript(instance, line)
	end,

	CloseScript = function(instance)
		editor:CloseScript(instance)
	end,

	CloseAllScripts = function()
		editor:CloseAllScripts()
	end,

	IsScriptOpen = function(instance)
		return editor:IsScriptOpen(instance)
	end,

	OpenScriptCount = function()
		return editor:OpenScriptCount()
	end,

	ActiveScript = function()
		return editor:ActiveScript()
	end,

	OpenFile = function(path, name)
		editor:OpenFile(path, name)
	end,

	CloseFile = function(path)
		editor:CloseFile(path)
	end,

	IsFileOpen = function(path)
		return editor:IsFileOpen(path)
	end,

	CodeEditor = editor.TextBox,

	GetSource = function()
		return editor:GetSource()
	end,

	SetSnap = function(tool: "handles" | "archandles", num)
		if tool == "handles" then
			handles.Snap = num
		elseif tool == "archandles" then
			arcHandles.Snap = num
		end
	end,

	-- Goes through toolControls so the radio indicator, activeTool, gizmos and
	-- color picker all update via the Changed handler above.
	ActivateTool = function(tool: "select" | "size" | "rotate" | "position")
		local tools = {
			select = "Select",
			size = "Size",
			rotate = "Rotate",
			position = "Move",
		}

		local target = tools[tool]
		if not target then
			return
		end

		toolControls:SetActive(target)
	end,

	ContainsPoint = function(point)
		if scriptRoot.Visible then
			return false, nil
		end

		local position, size = getRenderBounds()

		local inside = point.X >= position.X
			and point.X <= position.X + size.X
			and point.Y >= position.Y
			and point.Y <= position.Y + size.Y

		if not inside then
			return false, nil
		end

		return true, Vector2.new(point.X - position.X, point.Y - position.Y)
	end,

	ScreenToViewportPoint = screenToViewportPoint,
	ViewportToScreenPoint = viewportToScreenPoint,

	SetDropHighlight = function(visible)
		dropHighlight.Visible = visible == true
	end,

	GetUIEditor = function()
		return uiEditor
	end,

	Refresh = function()
		UI.refreshWindow("Viewport")
	end,

	IsVisible = function()
		local panel = UI.getWindow("Viewport")

		return panel ~= nil and panel.Visible
	end,
}

return API

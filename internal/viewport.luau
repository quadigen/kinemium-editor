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

local disable_server_bool = false
local disable_client_bool = false
local single_player_bool = false
local client_count = 0

local _, disable_server = UI.checkbox(frame, "Disable Server", UDim2.fromOffset(8, 8), false, function(value)
	disable_server_bool = value
end)

local _, disable_client = UI.checkbox(frame, "Disable Client", UDim2.fromOffset(8, 8), false, function(value)
	disable_client_bool = value
end)

local _, single_player = UI.checkbox(frame, "Single Player", UDim2.fromOffset(8, 8), false, function(value)
	single_player_bool = value
end)

local field, _, stroke = UI.input(frame, "Client Count", UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 24), {
	text = "Client Count",
	maxLength = 30,
	borderColor = Color3.new(0.2, 0.2, 0.2),
})

field.FocusLost:Connect(function()
	local text = field.Text
	local num = tonumber(text)
	if num then
		client_count = math.max(0, math.floor(num))
		field.Text = tostring(client_count)
	else
		field.Text = tostring(client_count)
	end
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

local GIZMO_SIZE = 110
local GIZMO_DISTANCE = 8
local GIZMO_FOV = 30
local AXIS_LENGTH = 1.6
local POS_SIZE = 22
local NEG_SIZE = 16

local gizmoFrame, gizmoViewport, gizmoCamera
local gizmoAxes = {}

if renderer.Dimension == "3D" then
	gizmoFrame = Instance.new("Frame")
	gizmoFrame.Name = "AxisGizmo"
	gizmoFrame.AnchorPoint = Vector2.new(1, 0)
	gizmoFrame.Position = UDim2.new(1, -8, 0, 8)
	gizmoFrame.Size = UDim2.fromOffset(GIZMO_SIZE, GIZMO_SIZE)
	gizmoFrame.BackgroundTransparency = 1
	gizmoFrame.BorderSizePixel = 0
	gizmoFrame.ZIndex = 10
	gizmoFrame.Parent = viewportOverlay

	gizmoViewport = Instance.new("ViewportFrame")
	gizmoViewport.Name = "AxisShafts"
	gizmoViewport.Size = UDim2.fromScale(1, 1)
	gizmoViewport.BackgroundTransparency = 1
	gizmoViewport.Ambient = Color3.new(1, 1, 1)
	gizmoViewport.LightColor = Color3.new(1, 1, 1)
	gizmoViewport.Active = false
	gizmoViewport.ZIndex = 11
	gizmoViewport.Parent = gizmoFrame

	gizmoCamera = Instance.new("Camera")
	gizmoCamera.FieldOfView = GIZMO_FOV
	gizmoCamera.Parent = gizmoViewport
	gizmoViewport.CurrentCamera = gizmoCamera

	local axisDefs = {
		{ label = "X", dir = Vector3.xAxis, up = Vector3.yAxis, color = Color3.fromRGB(240, 60, 80) },
		{ label = "Y", dir = Vector3.yAxis, up = Vector3.xAxis, color = Color3.fromRGB(140, 205, 30) },
		{ label = "Z", dir = Vector3.zAxis, up = Vector3.yAxis, color = Color3.fromRGB(50, 140, 245) },
	}

	local snapUps = {
		X = Vector3.yAxis,
		Y = Vector3.new(0, 0, -1),
		Z = Vector3.yAxis,
	}

	local function snapCamera(dir, up)
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end

		local cframe = camera.CFrame
		local focus = camera.Focus and camera.Focus.Position or (cframe.Position + cframe.LookVector * 10)
		local distance = math.max((cframe.Position - focus).Magnitude, 1)

		camera.CFrame = CFrame.lookAt(focus + dir * distance, focus, up)
	end

	local function makeCircleButton(text, color, transparency)
		local button = UI.button(gizmoFrame, text, UDim2.fromOffset(0, 0), UDim2.fromOffset(POS_SIZE, POS_SIZE), {
			color = color,
			radius = 30,
		})
		button.AnchorPoint = Vector2.new(0.5, 0.5)
		button.BackgroundColor3 = color
		button.BackgroundTransparency = transparency or 0
		button.TextColor3 = Color3.fromRGB(25, 25, 30)
		button.TextSize = 13
		button.AutoButtonColor = false
		return button
	end

	for _, def in ipairs(axisDefs) do
		local shaft = Instance.new("Part")
		shaft.Anchored = true
		shaft.CanCollide = false
		shaft.Shape = Enum.PartType.Cylinder
		shaft.Size = Vector3.new(AXIS_LENGTH, 0.07, 0.07)
		shaft.Color = def.color
		shaft.Material = Enum.Material.SmoothPlastic
		shaft.CFrame = CFrame.fromMatrix(def.dir * (AXIS_LENGTH / 2), def.dir, def.up)
		shaft.Parent = gizmoViewport

		local positive = makeCircleButton(def.label, def.color)

		local negativeColor = def.color:Lerp(Color3.fromRGB(30, 32, 38), 0.45)
		local negative = makeCircleButton("", negativeColor, 0.1)
		UI.stroke(negative, def.color:Lerp(Color3.new(1, 1, 1), 0.15), 1.5, 0.2)

		positive.MouseButton1Click:Connect(function()
			snapCamera(def.dir, snapUps[def.label])
		end)

		negative.MouseButton1Click:Connect(function()
			snapCamera(-def.dir, snapUps[def.label])
		end)

		table.insert(gizmoAxes, {
			dir = def.dir,
			positive = positive,
			negative = negative,
		})
	end
end

local function projectGizmoPoint(cameraCFrame, worldPoint)
	local local3 = cameraCFrame:PointToObjectSpace(worldPoint)
	local depth = -local3.Z
	local focalLength = (GIZMO_SIZE / 2) / math.tan(math.rad(GIZMO_FOV) / 2)
	local x = GIZMO_SIZE / 2 + (local3.X / depth) * focalLength
	local y = GIZMO_SIZE / 2 - (local3.Y / depth) * focalLength
	return Vector2.new(x, y), depth
end

local function placeGizmoButton(button, baseSize, cameraCFrame, worldPoint)
	local pixel, depth = projectGizmoPoint(cameraCFrame, worldPoint)

	local size = baseSize * (GIZMO_DISTANCE / depth)
	button.Position = UDim2.fromOffset(pixel.X, pixel.Y)
	button.Size = UDim2.fromOffset(size, size)

	button.ZIndex = math.clamp(math.floor(30 - depth * 2), 2, 60)
end

local function updateAxisGizmo()
	if not gizmoFrame then
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local rotation = camera.CFrame.Rotation
	local gizmoCFrame = CFrame.new(-rotation.LookVector * GIZMO_DISTANCE) * rotation
	gizmoCamera.CFrame = gizmoCFrame

	for _, axis in ipairs(gizmoAxes) do
		placeGizmoButton(axis.positive, POS_SIZE, gizmoCFrame, axis.dir * AXIS_LENGTH)
		placeGizmoButton(axis.negative, NEG_SIZE, gizmoCFrame, -axis.dir * AXIS_LENGTH)
	end
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

if IsServer or IsClient then
	return
end

local UI = require("@internal/editor_ui")
local viewport = require("@internal/viewport")

local StudioThemeService = game:GetService("StudioThemeService")
local theme = StudioThemeService.SelectedTheme
local Selection = game:GetService("Selection")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local colors = UI.colors
local tokens = UI.tokens

local panel, content =
	UI.window("Explorer", theme.ExplorerCoordinates.Position, theme.ExplorerCoordinates.Size, "Explorer")

panel.Position =
	UDim2.new(panel.Position.X.Scale, panel.Position.X.Offset, panel.Position.Y.Scale, panel.Position.Y.Offset)

local inset = UI.metrics.panelInset
local events = {}
local searchField =
	UI.input(content, "Search Explorer...", UDim2.fromOffset(inset, 6), UDim2.new(1, -42, 0, UI.metrics.inputHeight))
local expanded = {}

local list = UI.create("ScrollingFrame", {
	Position = UDim2.fromOffset(inset, 36),
	Size = UDim2.new(1, -inset * 2, 1, -42),

	BackgroundColor3 = tokens.color.surface,
	BackgroundTransparency = 0.5,
	BorderSizePixel = 0,

	CanvasPosition = Vector2.new(0, 0),
	CanvasSize = UDim2.new(1, 0, 0, 0),

	ScrollingEnabled = true,

	VirtualizedScrolling = true,

	ScrollSpeed = 38,

	SmoothScrollingEnabled = true,
	ScrollSmoothness = 18,

	ScrollBarThickness = 5,
	ScrollBarImageColor3 = tokens.color.subtext,
	ScrollBarImageTransparency = 0.4,
	ScrollBarAutoHide = true,
	ScrollBarFadeDelay = 0.45,
	ScrollBarFadeSpeed = 12,
	ScrollBarMinimumHandleSize = 24,

	ClipsDescendants = true,

	Active = true,
	InputSink = true,
}, content)

UI.corner(list, tokens.radius.md)

local function selectedObject()
	local selection = Selection:Get()
	return selection and selection[1]
end

local classIcons = {
	ArcHandles = "Handles",
	Atmosphere = "Atmosphere",
	BlurEffect = "BlurEffect",
	BloomEffect = "BloomEffect",
	BoolValue = "BoolValue",
	Camera = "Camera",
	ColorCorrectionEffect = "ColorCorrectionEffect",
	Decal = "Decal",
	DepthOfFieldEffect = "DepthOfFieldEffect",
	Folder = "Folder",
	Frame = "Frame",
	Handles = "Handles",
	ImageButton = "ImageButton",
	ImageLabel = "ImageLabel",
	MeshPart = "MeshPart",
	Model = "Model",
	ModuleScript = "ModuleScript",
	NumberValue = "NumberValue",
	Part = "Part",
	PointLight = "PointLight",
	ScreenGui = "ScreenGui",
	Script = "Script",
	LocalScript = "LocalScript",
	ScrollingFrame = "ScrollingFrame",
	Sound = "Sound",
	SpotLight = "SpotLight",
	SurfaceLight = "SurfaceLight",
	SyntaxHighlighter = "SyntaxHighlighter",
	TextBox = "TextBox",
	TextButton = "TextButton",
	TextLabel = "TextLabel",
	UIBackdrop = "UIBackdrop",
	UICorner = "UICorner",
	RemoteEvent = "RemoteEvent",
	RemoteFunction = "RemoteFunction",
	UIGradient = "UIGradient",
	UIShadow = "UIShadow",
	UIStroke = "UIStroke",
}

local creatableClasses = {
	"ArcHandles",
	"Atmosphere",
	"BinaryStringValue",
	"BlurEffect",
	"BloomEffect",
	"BoolValue",
	"BrickColorValue",
	"Camera",
	"RemoteEvent",
	"RemoteFunction",
	"CFrameValue",
	"Color3Value",
	"ColorCorrectionEffect",
	"Decal",
	"DepthOfFieldEffect",
	"DoubleConstrainedValue",
	"Folder",
	"Frame",
	"LocalScript",
	"Handles",
	"ImageButton",
	"ImageLabel",
	"IntConstrainedValue",
	"IntValue",
	"MeshPart",
	"Model",
	"ModuleScript",
	"NumberValue",
	"ObjectValue",
	"Part",
	"PointLight",
	"RayValue",
	"ScreenGui",
	"Script",
	"ScrollingFrame",
	"Sound",
	"SpotLight",
	"SSAOEffect",
	"StringValue",
	"SurfaceLight",
	"SunRaysEffect",
	"SyntaxHighlighter",
	"TextBox",
	"TextButton",
	"TextLabel",
	"UIBackdrop",
	"UICorner",
	"UIGradient",
	"UIShadow",
	"UIStroke",
	"Vector3Value",
}

local classItems = {}

for _, className in ipairs(creatableClasses) do
	table.insert(classItems, {
		value = className,
		label = className,
		icon = "builtin://icons/" .. (classIcons[className] or className) .. ".svg",
	})
end

table.sort(classItems, function(a, b)
	return a.label < b.label
end)

local categories = {
	{
		name = "Containers",
		items = {},
	},
	{
		name = "Parts & Models",
		items = {},
	},
	{
		name = "Scripts & Values",
		items = {},
	},
	{
		name = "Networking",
		items = {},
	},
	{
		name = "UI",
		items = {},
	},
	{
		name = "Lighting & Effects",
		items = {},
	},
	{
		name = "Handles",
		items = {},
	},
}

local categoryByClass = {
	Folder = "Containers",
	Model = "Containers",

	Part = "Parts & Models",
	MeshPart = "Parts & Models",
	Decal = "Parts & Models",
	Camera = "Parts & Models",

	RemoteEvent = "Networking",
	RemoteFunction = "Networking",

	Script = "Scripts & Values",
	LocalScript = "Scripts & Values",
	ModuleScript = "Scripts & Values",
	BinaryStringValue = "Scripts & Values",
	BrickColorValue = "Scripts & Values",
	CFrameValue = "Scripts & Values",
	Color3Value = "Scripts & Values",
	DoubleConstrainedValue = "Scripts & Values",
	IntConstrainedValue = "Scripts & Values",
	IntValue = "Scripts & Values",
	ObjectValue = "Scripts & Values",
	RayValue = "Scripts & Values",
	StringValue = "Scripts & Values",
	Vector3Value = "Scripts & Values",
	NumberValue = "Scripts & Values",

	Frame = "UI",
	ImageButton = "UI",
	ImageLabel = "UI",
	ScreenGui = "UI",
	ScrollingFrame = "UI",
	TextBox = "UI",
	SyntaxHighlighter = "UI",
	TextButton = "UI",
	TextLabel = "UI",
	UIBackdrop = "UI",
	UICorner = "UI",
	UIGradient = "UI",
	UIShadow = "UI",
	UIStroke = "UI",

	Atmosphere = "Lighting & Effects",
	BlurEffect = "Lighting & Effects",
	BloomEffect = "Lighting & Effects",
	ColorCorrectionEffect = "Lighting & Effects",
	DepthOfFieldEffect = "Lighting & Effects",
	SSAOEffect = "Lighting & Effects",
	SunRaysEffect = "Lighting & Effects",
	PointLight = "Lighting & Effects",
	SpotLight = "Lighting & Effects",
	SurfaceLight = "Lighting & Effects",

	Handles = "Handles",
	ArcHandles = "Handles",
}

for _, item in ipairs(classItems) do
	item.shortcut = item.value == "Part" and "Ctrl+P" or nil

	local categoryName = categoryByClass[item.value]

	if categoryName then
		for _, category in ipairs(categories) do
			if category.name == categoryName then
				table.insert(category.items, item)

				break
			end
		end
	end
end

local dropdown = UI.dropdown(content, "", UDim2.new(1, -32, 0, 6), UDim2.fromOffset(26, UI.metrics.inputHeight), nil, {
	items = classItems,
	categories = categories,

	searchPlaceholder = "Search classes...",

	icon = "builtin://icons/Plus.svg",
	iconSize = 14,
	backdrop = true,

	color = tokens.color.input,
	hoverColor = tokens.color.hover,
	closeOnOutsideClick = false,
	menuWidth = 190,
	menuSide = "left",
	itemBgTransparency = 1,
	BackgroundTransparency = 0.5,
	menuPosition = function()
		local coordinates = theme.ExplorerCoordinates

		return UDim2.new(
			coordinates.Position.X.Scale,
			coordinates.Position.X.Offset - 196,
			coordinates.Position.Y.Scale,
			coordinates.Position.Y.Offset + 5 + UI.metrics.windowHeader + 6
		)
	end,

	maxVisibleItems = 10,
	itemHeight = UI.metrics.inputHeight,

	onChanged = function(className)
		local parent = selectedObject() or workspace

		local ok, object = pcall(Instance.new, className)

		if not ok or not object then
			return
		end

		object.Name = className
		object.Parent = parent

		expanded[parent] = true

		Selection:Set({
			object,
		})
	end,
})

local serviceOrder = {
	Workspace = 1,
	Players = 2,
	Lighting = 3,
	ReplicatedFirst = 4,
	ReplicatedStorage = 5,
	ServerScriptService = 6,
	ServerStorage = 7,
	StarterGui = 8,
	StarterPack = 9,
	StarterPlayer = 10,
	Teams = 11,
	SoundService = 12,
}

local function sortedChildren(parent)
	local children = parent:GetChildren()

	table.sort(children, function(a, b)
		local ao = serviceOrder[a.Name] or math.huge

		local bo = serviceOrder[b.Name] or math.huge

		if ao ~= bo then
			return ao < bo
		end

		return a.Name < b.Name
	end)

	return children
end

local function treeHash(parent)
	local pieces = {}

	for _, child in ipairs(sortedChildren(parent)) do
		table.insert(pieces, child.Name .. ":" .. child.ClassName)

		if expanded[child] then
			table.insert(pieces, treeHash(child))
		end
	end

	return table.concat(pieces, "|")
end

local lastHash = ""
local rebuilding = false
local rebuild

local fallbackIcons = {
	ReplicatedFirst = "ReplicatedStorage",
	StarterPack = "Backpack",
	Teams = "Players",
	Chat = "ChatService",
	TextChatService = "ChatService",
	MaterialService = "Texture",
	TestService = "StudioService",
	TaskScheduler = "RunService",
	ExampleService = "StudioService",
}

local function iconPathFor(instance)
	return "builtin://icons/" .. (fallbackIcons[instance.ClassName] or instance.ClassName) .. ".svg"
end

local rowIndex = 0

local rowRegistry = {}
local drag = nil
local dragLayer = nil

local function isDescendantOf(candidate, ancestor)
	local current = candidate

	while current ~= nil do
		if current == ancestor then
			return true
		end

		current = current.Parent
	end

	return false
end

local function canReparent(instance, newParent)
	if instance == nil or newParent == nil then
		return false
	end

	if instance:IsA("DataModel") or newParent:IsA("DataModel") then
		return false
	end

	if instance == newParent then
		return false
	end

	-- Dropping a node into its own subtree would detach the branch entirely.
	if isDescendantOf(newParent, instance) then
		return false
	end

	return true
end

local function clearDropHighlight()
	for _, entry in pairs(rowRegistry) do
		local row = entry.row

		if UI.isAlive(row) then
			row.BackgroundTransparency = entry.baseTransparency
		end

		entry.dropTarget = false
	end
end

local function disposeDrag()
	if dragLayer ~= nil and UI.isAlive(dragLayer) then
		dragLayer:Destroy()
	end

	dragLayer = nil
	drag = nil
end

local function finishDrop(reparent)
	local source = drag.source
	local target = drag.target

	disposeDrag()
	clearDropHighlight()

	if reparent and source ~= nil and target ~= nil and canReparent(source, target) then
		source.Parent = target

		expanded[target] = true

		Selection:Set({
			source,
		})

		lastHash = ""
	end
end

local function addRow(instance, depth, y)
	local children = sortedChildren(instance)

	local isSelected = selectedObject() == instance

	rowIndex += 1

	local rowColor = rowIndex % 2 == 0 and tokens.color.rowEven or tokens.color.rowOdd

	local row = UI.button(list, "", UDim2.fromOffset(1, y), UDim2.new(1, -2, 0, UI.metrics.treeRow), function()
		Selection:Set({
			instance,
		})

		if #children > 0 then
			expanded[instance] = not expanded[instance]

			lastHash = ""
		end
	end, {
		color = isSelected and colors.selection or rowColor,

		hoverColor = isSelected and colors.selection or colors.hover,

		radius = isSelected and tokens.radius.sm or 0,

		border = false,
	})

	row.Activated:Connect(function(input, clickCount)
		-- double click
		if clickCount == 2 then
			if instance:IsA("Script") or instance:IsA("ModuleScript") or instance:IsA("LocalScript") then
				viewport.OpenScript(instance)
			else
				viewport.CloseAllScripts()
			end
		end
	end)

	row.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end

		drag = {
			source = instance,
			target = nil,
			startX = input.Position.X,
			startY = input.Position.Y,
			active = false,
		}
	end)

	row.BackgroundTransparency = isSelected and 0 or 0.12

	rowRegistry[instance] = {
		row = row,
		depth = depth,
		y = y,
		baseTransparency = row.BackgroundTransparency,
		dropTarget = false,
	}

	local indent = 7 + depth * 16

	if #children > 0 then
		UI.image(
			row,
			"builtin://icons/" .. (expanded[instance] and "ArrowDown.svg" or "ArrowRight.svg"),
			UDim2.fromOffset(indent, 4),
			UDim2.fromOffset(12, 12)
		)
	end

	UI.image(row, iconPathFor(instance), UDim2.fromOffset(indent + 16, 3), UDim2.fromOffset(14, 14))

	UI.label(
		row,
		instance.Name,
		UDim2.fromOffset(indent + 31, 2),
		UDim2.new(1, -(indent + 34), 0, 17),
		tokens.type.small,
		isSelected and tokens.color.text or colors.text
	)

	return y + UI.metrics.treeRow
end

local function walk(parent, depth, y)
	for _, child in ipairs(sortedChildren(parent)) do
		y = addRow(child, depth, y)

		if expanded[child] then
			y = walk(child, depth + 1, y)
		end
	end

	return y
end

rebuild = function()
	if rebuilding then
		return
	end

	rebuilding = true

	local oldCanvasPosition = list.CanvasPosition

	UI.clear(list)

	rowIndex = 0

	rowRegistry = {}

	local finalY = walk(game, 0, 1)

	list.CanvasSize = UDim2.new(1, 0, 0, finalY + 4)

	list.CanvasPosition = oldCanvasPosition

	rebuilding = false
end

Selection.SelectionChanged:Connect(function()
	lastHash = ""
end)

local DRAG_THRESHOLD = 4

local function mouseInList()
	local mouse = UserInputService:GetMouseLocation()
	local position = list.AbsolutePosition
	local size = list.AbsoluteSize

	return mouse.X >= position.X
		and mouse.X <= position.X + size.X
		and mouse.Y >= position.Y
		and mouse.Y <= position.Y + size.Y
end

local function updateDragTarget()
	local best = nil
	local bestDistance = math.huge

	for instance, entry in pairs(rowRegistry) do
		local row = entry.row

		if UI.isAlive(row) and canReparent(drag.source, instance) then
			local position = row.AbsolutePosition
			local size = row.AbsoluteSize

			-- The top half reparents as a sibling, the bottom half as a child,
			-- which is the behaviour the Roblox explorer uses.
			local offset = UserInputService:GetMouseLocation().Y - position.Y
			local target = offset > size.Y / 2 and instance or instance.Parent

			if target ~= nil and canReparent(drag.source, target) then
				local distance = math.abs(offset - size.Y / 2)

				if distance < bestDistance then
					bestDistance = distance
					best = target
				end
			end
		end
	end

	if best ~= drag.target then
		clearDropHighlight()

		drag.target = best

		local entry = best and rowRegistry[best]

		if entry ~= nil and UI.isAlive(entry.row) then
			entry.row.BackgroundTransparency = 0
			entry.dropTarget = true
		end
	end
end

local function beginDragVisual()
	if dragLayer ~= nil then
		return
	end

	dragLayer = UI.create("Frame", {
		Position = UDim2.fromOffset(drag.startX + 10, drag.startY),
		Size = UDim2.fromOffset(180, UI.metrics.treeRow),
		BackgroundColor3 = colors.selection,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Active = false,
		ZIndex = 5000,
	}, UI.root())

	UI.corner(dragLayer, tokens.radius.sm)

	UI.label(dragLayer, drag.source.Name, UDim2.fromOffset(8, 2), UDim2.new(1, -16, 0, 16), tokens.type.small, tokens.color.text)
end

local function moveDragVisual()
	if dragLayer == nil then
		return
	end

	local mouse = UserInputService:GetMouseLocation()

	TweenService:Create(
		dragLayer,
		TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Position = UDim2.fromOffset(mouse.X + 10, mouse.Y),
		}
	):Play()
end

local function animateDrop(reparent)
	if dragLayer == nil then
		finishDrop(reparent)
		return
	end

	local layer = dragLayer

	local tween = TweenService:Create(
		layer,
		TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{
			BackgroundTransparency = 1,
		}
	)

	tween.Completed:Once(function()
		finishDrop(reparent)
	end)

	tween:Play()
end

UserInputService.InputChanged:Connect(function(input: InputObject)
	if drag == nil then
		return
	end

	if input.UserInputType ~= Enum.UserInputType.MouseMovement then
		return
	end

	local dx = input.Position.X - drag.startX
	local dy = input.Position.Y - drag.startY

	if not drag.active then
		if math.sqrt(dx * dx + dy * dy) < DRAG_THRESHOLD then
			return
		end

		drag.active = true

		Selection:Set({
			drag.source,
		})

		beginDragVisual()
	end

	if mouseInList() then
		updateDragTarget()
	else
		clearDropHighlight()
		drag.target = nil
	end

	moveDragVisual()
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if drag == nil or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end

	if not drag.active then
		drag = nil
		return
	end

	animateDrop(drag.target ~= nil)
end)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end

	if input.KeyCode == Enum.KeyCode.Escape then
		if drag ~= nil then
			finishDrop(false)
		else
			Selection:Set({})
		end

		return
	end

	if input.KeyCode == Enum.KeyCode.Delete or input.KeyCode == Enum.KeyCode.Backspace then
		if UserInputService:GetFocusedTextBox() ~= nil then
			return
		end

		local selected = selectedObject()

		if selected ~= nil and not selected:IsA("DataModel") then
			viewport.CloseScript(selected)
			expanded[selected] = nil

			Selection:Set({})

			selected:Destroy()

			lastHash = ""
		end

		return
	end

	if input.KeyCode == Enum.KeyCode.D then
		local ctrlDown = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)

		if ctrlDown then
			local selected = selectedObject()

			if selected then
				local clone = selected:Clone()

				if clone then
					clone.Parent = selected.Parent

					Selection:Set({
						clone,
					})

					lastHash = ""
				end
			end
		end
	end
end)

rebuild()

renderer.Pool.new("2d", function()
	panel.Size = theme.ExplorerCoordinates.Size
	panel.Position = theme.ExplorerCoordinates.Position

	local selected = selectedObject()

	local hash = treeHash(game) .. "#" .. (selected and selected:GetFullName() or "")

	if hash ~= lastHash then
		lastHash = hash
		rebuild()
	end
end)

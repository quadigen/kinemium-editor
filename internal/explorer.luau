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
local filter = ""

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
local hashClock = 0

-- Rebuilding the whole tree every frame is only needed when its *shape* could
-- have changed. Sampling the hash a few times a second keeps structural edits
-- feeling instant while removing a full tree walk from every frame.
local HASH_INTERVAL = 6
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
local visibleRows = {}

local rowRegistry = {}
local highlightedInstance = nil
local drag = nil
local dragLayer = nil
local clipboard = nil
local renaming = nil
local renamedInstance = nil
local renameCommit = nil
local pendingRebuild = false
local openContextMenu
local commitRename
local cancelRename
local closeContextMenu

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

local function isRoot(instance)
	return instance ~= nil and instance:IsA("DataModel")
end

-- Services and the DataModel root cannot be renamed, deleted, duplicated or
-- moved. They can, however, still be drop targets: a Part may be parented into
-- Lighting, it just may not be parented *from* there.
local function isProtected(instance)
	if instance == nil then
		return true
	end

	return isRoot(instance) or instance:IsA("Service")
end

local function canReparent(instance, newParent)
	if instance == nil or newParent == nil then
		return false
	end

	-- A service can never be the thing being moved, and nothing can go into the
	-- DataModel root.
	if isProtected(instance) or isRoot(newParent) then
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

local function applyRowSelection(row, record, isSelected)
	-- Route through the shared helper so the button record's own colour and
	-- hover colour stay in sync; setting BackgroundColor3 alone left the record
	-- holding a stale colour that hover would restore on mouse-leave.
	UI.setButtonState(record, isSelected and "selected" or "default")

	row.BackgroundTransparency = isSelected and 0 or 0.12
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
		-- Always the striped base colour: UI.button stores this as the record's
		-- defaultColor, and hover restores it on mouse-leave. Baking the
		-- selection colour in here made the orange stick after hovering away.
		color = rowColor,

		hoverColor = colors.hover,

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
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			-- Commit any in-flight rename and dismiss the previous menu before
			-- opening a new one, so neither outlives the interaction.
			commitRename()
			closeContextMenu()

			Selection:Set({
				instance,
			})

			openContextMenu(instance, input.Position)

			return
		end

		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end

		-- Clicking any row dismisses an open context menu and commits an
		-- in-flight rename; neither should survive the interaction.
		closeContextMenu()

		if UI.isAlive(renaming) and not isDescendantOf(instance, renamedInstance) then
			commitRename()
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

	if isSelected then
		applyRowSelection(row, record, true)
	end

	rowRegistry[instance] = {
		row = row,
		record = record,
		depth = depth,
		y = y,
		rowColor = rowColor,
		selected = isSelected,
		baseTransparency = row.BackgroundTransparency,
		dropTarget = false,
	}

	visibleRows[#visibleRows + 1] = instance

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

-- True when `instance` or anything beneath it matches the active search, so a
-- filtered tree keeps the ancestors of a hit visible for context.
local function subtreeMatches(instance, depth)
	if filter == "" then
		return true
	end

	if depth > 0 and string.find(string.lower(instance.Name), filter, 1, true) then
		return true
	end

	if depth > 0 and #instance:GetChildren() > 0 then
		return subtreeMatches(instance, depth - 1)
	end

	return false
end

local function walk(parent, depth, y)
	for _, child in ipairs(sortedChildren(parent)) do
		if subtreeMatches(child, 1) then
			y = addRow(child, depth, y)

			if expanded[child] or filter ~= "" then
				y = walk(child, depth + 1, y)
			end
		end
	end

	return y
end

rebuild = function()
	if rebuilding then
		return
	end

	-- A live rename box lives inside a row, so rebuilding would destroy the
	-- field mid-edit. Defer until the rename finishes.
	if UI.isAlive(renaming) then
		pendingRebuild = true
		return
	end

	rebuilding = true

	local oldCanvasPosition = list.CanvasPosition

	UI.clear(list)

	rowIndex = 0

	rowRegistry = {}

	visibleRows = {}

	local finalY = walk(game, 0, 1)

	list.CanvasSize = UDim2.new(1, 0, 0, finalY + 4)

	list.CanvasPosition = oldCanvasPosition

	rebuilding = false
end

Selection.SelectionChanged:Connect(function()
	-- Repainting just the two affected rows avoids tearing down and rebuilding
	-- every row in the tree, which is what made selecting an object spike.
	local selected = selectedObject()

	for _, instance in ipairs({ highlightedInstance, selected }) do
		local entry = instance and rowRegistry[instance]

		if entry ~= nil and UI.isAlive(entry.row) then
			local isSelected = instance == selected

			if isSelected ~= entry.selected then
				entry.selected = isSelected
				entry.baseTransparency = isSelected and 0 or 0.12

				applyRowSelection(entry.row, entry.record, isSelected)
			end
		end
	end

	highlightedInstance = selected
end)

searchField.TextChanged:Connect(function()
	filter = string.lower(searchField.Text or "")
	lastHash = ""
	rebuild()
end)

local function deleteInstance(instance)
	if isProtected(instance) then
		return
	end

	viewport.CloseScript(instance)

	expanded[instance] = nil
	renaming = nil

	Selection:Set({})

	instance:Destroy()

	lastHash = ""
end

local function duplicateInstance(instance)
	if isProtected(instance) then
		return
	end

	local ok, clone = pcall(function()
		return instance:Clone()
	end)

	if ok and clone then
		clone.Name = instance.Name
		clone.Parent = instance.Parent

		Selection:Set({
			clone,
		})

		lastHash = ""
	end
end

local function beginRename(instance, row)
	if isProtected(instance) then
		return
	end

	if UI.isAlive(renaming) then
		return
	end

	local entry = rowRegistry[instance]

	if entry == nil or not UI.isAlive(entry.row) then
		return
	end

	local indent = 7 + entry.depth * 16

	renaming = UI.input(
		entry.row,
		instance.Name,
		UDim2.fromOffset(indent + 31, 1),
		UDim2.new(1, -(indent + 36), 0, 18),
		{ textSize = tokens.type.small, color = tokens.color.input, selectAllOnFocus = true }
	)

	renaming.Text = instance.Name

	-- Preselecting is cosmetic; a runtime that rejects the native call must not
	-- take the whole rename down with it.
	pcall(function()
		renaming:SelectAll()
	end)

	renamedInstance = instance

	local committed = false

	local function finish(apply)
		if committed then
			return
		end

		committed = true

		renameCommit = nil
		renamedInstance = nil

		local text = renaming.Text

		if renaming ~= nil and UI.isAlive(renaming) then
			renaming:Destroy()
		end

		renaming = nil

		if apply and text ~= nil and text ~= "" and text ~= instance.Name then
			instance.Name = text
		end

		lastHash = ""

		if pendingRebuild then
			pendingRebuild = false

			rebuild()
		end
	end

	renameCommit = finish

	renaming.FocusLost:Connect(function()
		finish(true)
	end)

	renaming.TextSubmitted:Connect(function()
		finish(true)
	end)
end

-- Applies the pending rename, if any. Clicking elsewhere in the tree should
-- keep whatever was typed rather than silently discarding it.
commitRename = function()
	local commit = renameCommit

	if commit ~= nil then
		commit(true)
	end
end

cancelRename = function()
	local commit = renameCommit

	if commit ~= nil then
		commit(false)
	end
end

local function rowIndexOf(instance)
	for index, candidate in ipairs(visibleRows) do
		if candidate == instance then
			return index
		end
	end

	return nil
end

local function selectAndReveal(index)
	local instance = visibleRows[index]

	if instance == nil then
		return
	end

	Selection:Set({
		instance,
	})

	local entry = rowRegistry[instance]

	if entry ~= nil then
		local target = math.max(0, entry.y - list.AbsoluteSize.Y / 2)

		list.CanvasPosition = Vector2.new(0, target)
	end
end

local contextMenu
local contextMenuOptions
local contextTarget = nil

openContextMenu = function(instance, screenPoint)
	if instance == nil or instance:IsA("DataModel") then
		return
	end

	contextTarget = instance

	if contextMenu == nil then
		-- An offscreen dropdown that exists only to borrow the shared popup
		-- styling, search field and outside-click dismissal.
		contextMenuOptions = {
				items = {},
				menuWidth = 168,
				itemHeight = UI.metrics.inputHeight,
				maxVisibleItems = 6,
				itemBgTransparency = 1,
			-- No filter field: this is a short fixed action list.
			showSearch = false,
			-- Outside-click dismissal only listens for left-click, which would
			-- leave the menu stuck open after a right-click elsewhere.
			closeOnOutsideClick = false,
				menuPosition = function()
					return UDim2.fromOffset(0, 0)
				end,
				onChanged = function(action)
					local target = contextTarget
					contextTarget = nil

					if target == nil then
						return
					end

					if action == "rename" then
						local entry = rowRegistry[target]

						if entry ~= nil then
							beginRename(target, entry.row)
						end
					elseif action == "duplicate" then
						duplicateInstance(target)
					elseif action == "delete" then
						deleteInstance(target)
					elseif action == "copy" then
						clipboard = target
					elseif action == "paste" then
						local source = clipboard

						if source ~= nil and UI.isAlive(source) then
							local ok, clone = pcall(function()
								return source:Clone()
							end)

							if ok and clone then
								clone.Parent = target
								Selection:Set({ clone })
								lastHash = ""
							end
						end
					end
				end,
		}

		local _, _, controller = UI.dropdown(
			content,
			"",
			UDim2.fromOffset(-400, -400),
			UDim2.fromOffset(1, 1),
			nil,
			contextMenuOptions
		)

		contextMenu = controller
	end

	-- SetItems, not options.items: the dropdown snapshots `options.items` into a
	-- local at construction time, so reassigning the options table afterwards
	-- would leave the menu permanently empty.
	contextMenu:SetItems({
		{ label = "Rename", value = "rename", icon = "builtin://icons/pencil.svg" },
		{ label = "Duplicate", value = "duplicate", icon = "builtin://icons/Plus.svg" },
		{ label = "Delete", value = "delete", icon = "builtin://icons/x.svg" },
		{ label = "Copy", value = "copy" },
		{ label = "Paste", value = "paste" },
	})

	contextMenuOptions.menuPosition = function()
		return UDim2.fromOffset(screenPoint.X, screenPoint.Y)
	end

	contextMenu:Open()
end

closeContextMenu = function()
	if contextMenu ~= nil then
		contextMenu:Close()
	end

	contextTarget = nil
end

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
	-- Read the cursor once. The previous version called GetMouseLocation() (and
	-- ran a full canReparent ancestry walk) for every visible row on every
	-- mouse-move, which made dragging crawl on large trees.
	local mouse = UserInputService:GetMouseLocation()

	local best = nil
	local bestDistance = math.huge
	local source = drag.source

	for instance, entry in pairs(rowRegistry) do
		local row = entry.row

		if not UI.isAlive(row) then
			continue
		end

		local position = row.AbsolutePosition
		local size = row.AbsoluteSize
		local offset = mouse.Y - position.Y

		-- Cheap vertical reject before any ancestry work: only rows the cursor
		-- is actually near can win.
		if offset < -size.Y or offset > size.Y * 2 then
			continue
		end

		if not canReparent(source, instance) then
			continue
		end

		-- The top half reparents as a sibling, the bottom half as a child,
		-- which is the behaviour the Roblox explorer uses.
		local target = offset > size.Y / 2 and instance or instance.Parent

		if target ~= nil and canReparent(source, target) then
			local distance = math.abs(offset - size.Y / 2)

			if distance < bestDistance then
				bestDistance = distance
				best = target
			end
		end
	end

	if best ~= drag.target then
		-- Only the previously highlighted row needs resetting, rather than
		-- walking the whole registry.
		local previous = drag.target and rowRegistry[drag.target]

		if previous ~= nil and UI.isAlive(previous.row) then
			previous.row.BackgroundTransparency = previous.baseTransparency
			previous.dropTarget = false
		end

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

	-- Follow the cursor directly. Tweening the ghost spawned a new TweenService
	-- tween on every mouse-move, each one stepping the VM for the rest of its
	-- duration, which made dragging visibly laggy. The drop still animates, so
	-- the gesture keeps its polish without the per-frame cost.
	local mouse = UserInputService:GetMouseLocation()

	dragLayer.Position = UDim2.fromOffset(mouse.X + 10, mouse.Y)
end

local function animateDrop(reparent)
	-- Capture the drag now: finishDrop runs from the tween's Completed callback
	-- ~0.12s later, by which point `drag` may describe a different gesture.
	local source = drag.source
	local target = drag.target

	local function apply()
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

	if dragLayer == nil then
		apply()
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
		apply()
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

	-- Keystrokes aimed at a field (search, rename box, script editor) belong to
	-- that field, not to the tree.
	local typing = UserInputService:GetFocusedTextBox() ~= nil

	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		-- A right-click outside the tree dismisses the context menu, since the
		-- shared outside-click handling only listens for the left button.
		if not mouseInList() then
			closeContextMenu()
		end

		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		-- A left-click that did not land on a row (the row handler opens and
		-- dismisses its own menu) still dismisses the menu and any rename.
		if not mouseInList() then
			closeContextMenu()
			commitRename()
		end

		-- A mouse InputObject carries no meaningful KeyCode, so letting clicks
		-- fall through to the keyboard handling below could match whatever
		-- garbage KeyCode it held -- including Delete, which was destroying the
		-- selected object on every click.
		return
	end

	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end

	if input.KeyCode == Enum.KeyCode.Escape then
		if drag ~= nil then
			finishDrop(false)
		elseif UI.isAlive(renaming) then
			cancelRename()
		elseif contextMenu ~= nil then
			closeContextMenu()
		elseif typing then
			searchField.Text = ""
		else
			Selection:Set({})
		end

		return
	end

	if typing then
		return
	end

	local selected = selectedObject()
	local index = selected and rowIndexOf(selected) or nil

	if input.KeyCode == Enum.KeyCode.Up or input.KeyCode == Enum.KeyCode.Down then
		if #visibleRows == 0 then
			return
		end

		local next_ = index or 0

		if input.KeyCode == Enum.KeyCode.Up then
			next_ = next_ - 1
		else
			next_ = next_ + 1
		end

		selectAndReveal(math.clamp(next_, 1, #visibleRows))

		return
	end

	if input.KeyCode == Enum.KeyCode.Home then
		selectAndReveal(1)
		return
	end

	if input.KeyCode == Enum.KeyCode.End then
		selectAndReveal(#visibleRows)
		return
	end

	if input.KeyCode == Enum.KeyCode.Right then
		if selected ~= nil and not expanded[selected] and #selected:GetChildren() > 0 then
			expanded[selected] = true

			lastHash = ""
		end

		return
	end

	if input.KeyCode == Enum.KeyCode.Left then
		if selected ~= nil then
			if expanded[selected] then
				expanded[selected] = nil

				lastHash = ""
			elseif selected.Parent ~= nil and selected.Parent ~= game then
				local parentIndex = rowIndexOf(selected.Parent)

				if parentIndex ~= nil then
					selectAndReveal(parentIndex)
				end
			end
		end

		return
	end

	if input.KeyCode == Enum.KeyCode.F2 then
		if selected ~= nil then
			local entry = rowRegistry[selected]

			if entry ~= nil then
				beginRename(selected, entry.row)
			end
		end

		return
	end

	if input.KeyCode == Enum.KeyCode.C then
		local ctrlDown = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)

		if ctrlDown and selected ~= nil then
			clipboard = selected
		end

		return
	end

	if input.KeyCode == Enum.KeyCode.V then
		local ctrlDown = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)

		local destination = selected or workspace

		if ctrlDown and clipboard ~= nil and UI.isAlive(clipboard) and destination ~= clipboard then
			local ok, clone = pcall(function()
				return clipboard:Clone()
			end)

			if ok and clone then
				clone.Parent = destination

				Selection:Set({
					clone,
				})

				lastHash = ""
			end
		end

		return
	end

	if input.KeyCode == Enum.KeyCode.Delete or input.KeyCode == Enum.KeyCode.Backspace then
		deleteInstance(selectedObject())

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

	-- Structural changes (add/remove/rename/reparent/expand) are the only thing
	-- that needs a rebuild. Selection is repainted in place by
	-- SelectionChanged, so it deliberately stays out of this signature.
	hashClock += 1

	if hashClock >= HASH_INTERVAL then
		hashClock = 0

		local hash = treeHash(game)

		if hash ~= lastHash then
			lastHash = hash
			rebuild()
		end
	end
end)

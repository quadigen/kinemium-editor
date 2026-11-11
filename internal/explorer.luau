if (IsServer or IsClient) or IsPlaytest then
	return nil
end
local UI = require("@internal/editor_ui")
local util = require("@internal/util")
local picker = require("@internal/picker")
local viewport = require("@internal/viewport")
local export_service = game:GetService("ExportService")
local dialog = game:GetService("DialogService")
local docker = require("@internal/docker")
local files = require("@internal/files")
local package_upload = require("@internal/package_upload")
local StudioThemeService = game:GetService("StudioThemeService")
local theme = StudioThemeService.SelectedTheme
local Selection = game:GetService("Selection")
local Project = game:GetService("Project")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReflectionService = game:GetService("ReflectionService")
local DiscordRPC = game:GetService("DiscordRPC")
local colors = UI.colors
local tokens = UI.tokens
local gui = UI.widgetOverlay()
local panel, tabContent, _, windowControls =
	UI.window("Explorer", theme.ExplorerCoordinates.Position, theme.ExplorerCoordinates.Size, "Explorer", {
		tabs = {
			"Explorer",
			"Files",
		},
		backgroundImage = "builtin://global-icons/giphy.gif",
		selectedTab = "Explorer",
	})
panel.Parent = gui
local content = windowControls.pages.Explorer
local filesPage = windowControls.pages.Files
local tabBounds = Instance.new("Frame")
tabBounds.Name = "ExplorerFloatingBounds"
tabBounds.Size = UDim2.fromScale(1, 1)
tabBounds.BackgroundTransparency = 1
tabBounds.Active = false
tabBounds.InputSink = false
tabBounds.Parent = gui
local floating = {}
local pendingTab
local movingTab
local keyboardTab
local dragThreshold = 8
local function tabActive(name)
	local window = floating[name]
	return gui.Enabled and (window and window.Visible or panel.Visible and windowControls.getSelectedTab() == name)
end
local function explorerTabActive()
	return tabActive("Explorer") and (keyboardTab or windowControls.getSelectedTab()) == "Explorer"
end
local filesController = files(filesPage, {
	getSelectedTab = function()
		return tabActive("Files") and "Files" or nil
	end,
	isKeyboardActive = function()
		return tabActive("Files") and (keyboardTab or windowControls.getSelectedTab()) == "Files"
	end,
})
local function dockTab(name)
	local window = floating[name]
	if not window then
		return
	end
	floating[name] = nil
	keyboardTab = name
	windowControls.pages[name].Parent = tabContent
	windowControls.setTabDetached(name, false)
	panel.Visible = true
	window:Destroy()
end
local function floatTab(name, point)
	local size = panel.AbsoluteSize
	local bounds = tabBounds.AbsoluteSize
	if bounds.X <= 0 or bounds.Y <= 0 then
		return
	end
	local width = math.min(math.max(size.X, 280), math.max(bounds.X, 1))
	local height = math.min(math.max(size.Y, 260), math.max(bounds.Y, 1))
	local x = math.clamp(point.X - 24, 0, math.max(0, bounds.X - width))
	local y = math.clamp(point.Y - 14, 0, math.max(0, bounds.Y - 30))
	local window, pageHolder, _, controls =
		UI.window("Detached" .. name, UDim2.fromOffset(x, y), UDim2.fromOffset(width, height), name, {
			closable = true,
			onClose = function()
				dockTab(name)
			end,
		})
	window.Parent = gui
	floating[name] = window
	keyboardTab = name
	windowControls.setTabDetached(name, true)
	local page = windowControls.pages[name]
	page.Parent = pageHolder
	page.Visible = true
	controls.dragHandle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			movingTab = { name = name, start = UserInputService:GetMouseLocation() }
		end
	end)
end
for name, tab in pairs(windowControls.tabs) do
	tab.button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			pendingTab = { name = name, start = UserInputService:GetMouseLocation() }
		end
	end)
end
UserInputService.InputBegan:Connect(function(input)
	if not gui.Enabled or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end
	local point = UserInputService:GetMouseLocation()
	for name, window in pairs(floating) do
		if window.Visible and UI.pointInside(window, point) then
			keyboardTab = name
			return
		end
	end
	if panel.Visible and UI.pointInside(panel, point) then
		keyboardTab = nil
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end
	local pending, moving = pendingTab, movingTab
	pendingTab, movingTab = nil, nil
	if not gui.Enabled or not panel.Visible then
		return
	end
	local point = UserInputService:GetMouseLocation()
	local overExplorer = UI.pointInside(panel, point)
	if pending and (point - pending.start).Magnitude >= dragThreshold and not overExplorer then
		floatTab(pending.name, point)
	elseif moving and (point - moving.start).Magnitude >= dragThreshold and overExplorer then
		dockTab(moving.name)
	end
end)
panel.Position =
	UDim2.new(panel.Position.X.Scale, panel.Position.X.Offset, panel.Position.Y.Scale, panel.Position.Y.Offset)
local inset = UI.metrics.panelInset
local events = {}
local searchField =
	UI.input(content, "Search Explorer...", UDim2.fromOffset(inset, 6), UDim2.new(1, -42, 0, UI.metrics.inputHeight))
local expanded = {}
local filter = ""
local requestModelRefresh
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
local anchor = nil
local function ctrlHeld()
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
end
local function shiftHeld()
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end
local function isInSelection(instance)
	for _, object in ipairs(Selection:Get() or {}) do
		if object == instance then
			return true
		end
	end
	return false
end
local function selectObject(data)
	local obj = data[1]
	Selection:Set(data)
	if not obj then
		return
	end
	local project = Project:GetActiveProject()
	local details = `In {project and project.Name or _RUNTIME.version.display}`
	local state = #data > 1 and ("Editing " .. #data .. " objects") or ("Editing " .. obj.Name)
	DiscordRPC:SetPresence({
		Details = details,
		State = state,
		LargeText = _RUNTIME.url,
	})
end
local categoriesByName = {}
for _, classInfo in ipairs(ReflectionService:GetClasses()) do
	if classInfo.Permits and classInfo.Permits.New then
		local categoryName = classInfo.Display and classInfo.Display.Category or "General"
		if not categoriesByName[categoryName] then
			categoriesByName[categoryName] = {
				name = categoryName,
				items = {},
			}
		end
	end
end
local categories = {}
local classItems = {}
for _, classInfo in ipairs(ReflectionService:GetClasses()) do
	if classInfo.Permits and classInfo.Permits.New then
		local categoryName = classInfo.Display and classInfo.Display.Category or "General"
		local iconName = classInfo.Display and classInfo.Display.Icon or classInfo.Name
		local item = {
			value = classInfo.Name,
			label = classInfo.Name,
			icon = "builtin://icons/" .. iconName .. ".svg",
		}
		table.insert(classItems, item)
		table.insert(categoriesByName[categoryName].items, item)
	end
end
table.sort(classItems, function(a, b)
	return a.label < b.label
end)
for _, category in ipairs(categories) do
	table.sort(category.items, function(a, b)
		return a.label < b.label
	end)
end
for _, category in pairs(categoriesByName) do
	table.insert(categories, category)
end
table.sort(categories, function(a, b)
	return a.name < b.name
end)
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
local dropdown, label, ctrl =
	UI.dropdown(content, "", UDim2.new(1, -32, 0, 6), UDim2.fromOffset(26, UI.metrics.inputHeight), nil, {
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
			selectObject({
				object,
			})
			if requestModelRefresh then
				requestModelRefresh()
			end
		end,
	})
dropdown.MouseButton1Click:Connect(function()
	ctrl.SearchBox:CaptureFocus()
end)
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
local indexedNodes = {}
local visibleDepths = {}
local visibleChildCounts = {}
local visibleIndex = {}
local modelJob = nil
local modelDirty = true
local modelRevision = 0
local modelReadyAt = 0
local firstModelChange = nil
local layoutJob = nil
local layoutDirty = true
local layoutRevision = 0
local layoutReadyAt = 0
local nameScanCursor = 1
local INDEX_FRAME_BUDGET = 0.004
local LAYOUT_FRAME_BUDGET = 0.004
local SEARCH_DEBOUNCE = 0.09
local NAME_SCAN_BATCH = 256
local VIEW_OVERSCAN = 5
local rebuild

local function invalidateLayout(delay)
	layoutRevision += 1
	layoutDirty = true
	layoutJob = nil
	layoutReadyAt = os.clock() + (delay or 0)
end

local function invalidateTree()
	local now = os.clock()
	if not firstModelChange then
		firstModelChange = now
	end
	modelRevision += 1
	modelDirty = true
	modelJob = nil
	modelReadyAt = math.min(now + 0.07, firstModelChange + 0.28)
	invalidateLayout()
end
requestModelRefresh = invalidateTree

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
local visibleRows = {}
local rowRegistry = {}
local rowPool = {}
local lastViewportStart = -1
local lastViewportHeight = -1
local lastViewportWidth = -1
local lastViewportCount = -1
local drag = nil
local selectedSet = {}
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
local rowIndexOf -- assigned later
local function toggleSelection(instance)
	local result, found = {}, false
	for _, object in ipairs(Selection:Get() or {}) do
		if object == instance then
			found = true
		else
			table.insert(result, object)
		end
	end
	if not found then
		table.insert(result, 1, instance)
	end
	selectObject(result)
end
local function selectRange(from, to)
	local a, b = rowIndexOf(from), rowIndexOf(to)
	if a == nil or b == nil then
		anchor = to
		selectObject({ to })
		return
	end
	-- `to` goes first so it stays the primary (keyboard cursor) item.
	local result = { to }
	for i = math.min(a, b), math.max(a, b) do
		if visibleRows[i] ~= to then
			table.insert(result, visibleRows[i])
		end
	end
	selectObject(result)
end
local function handleRowClick(instance, childCount)
	if ctrlHeld() then
		anchor = instance
		toggleSelection(instance)
		return
	end
	if shiftHeld() and anchor ~= nil then
		selectRange(anchor, instance)
		return
	end
	anchor = instance
	selectObject({ instance })
	if childCount > 0 then
		expanded[instance] = not expanded[instance]
		invalidateLayout()
	end
end
local function selectionRoots()
	local selection = Selection:Get() or {}
	local set = {}
	for _, object in ipairs(selection) do
		set[object] = true
	end
	local roots = {}
	for _, object in ipairs(selection) do
		if isProtected(object) then
			continue
		end
		local covered = false
		local ancestor = object.Parent
		while ancestor ~= nil do
			if set[ancestor] then
				covered = true
				break
			end
			ancestor = ancestor.Parent
		end
		if not covered then
			table.insert(roots, object)
		end
	end
	return roots
end
local function targetsFor(target)
	local roots = selectionRoots()
	if #roots > 0 and isInSelection(target) then
		return roots
	end
	return { target }
end
local function canDropAny(sources, target)
	for _, source in ipairs(sources) do
		if canReparent(source, target) then
			return true
		end
	end
	return false
end
local function reparentAll(sources, target)
	local moved = {}
	for _, source in ipairs(sources) do
		if canReparent(source, target) then
			source.Parent = target
			table.insert(moved, source)
		end
	end
	if #moved > 0 then
		expanded[target] = true
		selectObject(moved)
		invalidateTree()
	end
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
	local sources = drag.sources or { drag.source }
	local target = drag.target
	disposeDrag()
	clearDropHighlight()
	if reparent and target ~= nil then
		reparentAll(sources, target)
	end
end
local function createRowSlot()
	local slot = { instance = nil, childCount = 0 }
	local row, _, button = UI.button(
		list,
		"",
		UDim2.fromOffset(1, 0),
		UDim2.new(1, -2, 0, UI.metrics.treeRow),
		nil,
		{ color = tokens.color.rowOdd, hoverColor = colors.hover, radius = 0, border = false }
	)
	slot.row = row
	slot.button = button
	slot.corner = UI.corner(row, 0)
	slot.arrow = UI.image(row, "builtin://icons/ArrowRight.svg", UDim2.fromOffset(7, 4), UDim2.fromOffset(12, 12))
	slot.icon = UI.image(row, "builtin://icons/Folder.svg", UDim2.fromOffset(23, 3), UDim2.fromOffset(14, 14))
	slot.label = UI.label(row, "", UDim2.fromOffset(38, 2), UDim2.new(1, -41, 0, 17), tokens.type.small, colors.text)
	slot.entry = {
		row = row,
		button = button,
		corner = slot.corner,
		label = slot.label,
		depth = 0,
		y = 0,
		baseTransparency = 0.12,
		dropTarget = false,
	}
	slot.arrow.Visible = false
	row.Name = "ExplorerRow"
	row.Visible = false

	row.Activated:Connect(function(input, clickCount)
		local instance = slot.instance
		if instance == nil then
			return
		end
		if picker.isActive() then
			picker.submit(instance)
			return
		end
		handleRowClick(instance, slot.childCount)
		if clickCount == 2 then
			if
				instance:IsA("Script")
				or instance:IsA("ModuleScript")
				or instance:IsA("LocalScript")
				or instance:IsA("PostProcess")
				or instance:IsA("RuntimeShader")
				or instance:IsA("UIShader")
				or instance:IsA("MaterialVariant")
			then
				viewport.OpenScript(instance)
			else
				viewport.CloseAllScripts()
			end
		end
	end)

	row.InputBegan:Connect(function(input)
		local instance = slot.instance
		if instance == nil or picker.isActive() then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			commitRename()
			closeContextMenu()
			if not isInSelection(instance) then
				anchor = instance
				selectObject({ instance })
			end
			openContextMenu(instance, input.Position)
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
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
	return slot
end

local function updateViewport(force)
	if UI.isAlive(renaming) then
		return
	end
	local rowHeight = UI.metrics.treeRow
	local height = list.AbsoluteSize.Y
	local width = list.AbsoluteSize.X
	local count = #visibleRows
	local overscan = VIEW_OVERSCAN
	local first = math.max(1, math.floor(list.CanvasPosition.Y / rowHeight) + 1 - overscan)
	first = math.min(first, math.max(1, count))
	local last = math.min(count, first + math.ceil(height / rowHeight) + overscan * 2 + 2)

	if
		not force
		and first == lastViewportStart
		and height == lastViewportHeight
		and width == lastViewportWidth
		and count == lastViewportCount
	then
		return
	end
	lastViewportStart = first
	lastViewportHeight = height
	lastViewportWidth = width
	lastViewportCount = count

	table.clear(rowRegistry)
	local slotIndex = 0
	for index = first, last do
		slotIndex += 1
		local slot = rowPool[slotIndex]
		if slot == nil then
			slot = createRowSlot()
			rowPool[slotIndex] = slot
		end
		local instance = visibleRows[index]
		local depth = visibleDepths[index]
		local childCount = visibleChildCounts[index]
		local selected = selectedSet[instance] == true
		local indent = 7 + depth * 16
		local row = slot.row
		slot.instance = instance
		slot.childCount = childCount
		row.Position = UDim2.fromOffset(1, 1 + (index - 1) * rowHeight)
		row.BackgroundColor3 = index % 2 == 0 and tokens.color.rowEven or tokens.color.rowOdd
		row.BackgroundTransparency = selected and 0 or 0.12
		UI.setButtonState(slot.button, selected and "selected" or nil)
		slot.corner.CornerRadius = UDim.new(0, selected and tokens.radius.sm or 0)
		slot.arrow.Visible = childCount > 0
		if childCount > 0 then
			slot.arrow.Image = "builtin://icons/"
				.. ((expanded[instance] or filter ~= "") and "ArrowDown.svg" or "ArrowRight.svg")
		end
		slot.arrow.Position = UDim2.fromOffset(indent, 4)
		slot.icon.Image = iconPathFor(instance)
		slot.icon.Position = UDim2.fromOffset(indent + 16, 3)
		slot.label.Text = instance.Name
		slot.label.Position = UDim2.fromOffset(indent + 31, 2)
		slot.label.Size = UDim2.new(1, -(indent + 34), 0, 17)
		slot.label.TextColor3 = selected and tokens.color.text or colors.text
		row.Visible = true
		local entry = slot.entry
		entry.depth = depth
		entry.y = 1 + (index - 1) * rowHeight
		entry.baseTransparency = row.BackgroundTransparency
		entry.dropTarget = false
		rowRegistry[instance] = entry
	end
	for i = slotIndex + 1, #rowPool do
		local slot = rowPool[i]
		slot.instance = nil
		slot.row.Visible = false
	end
end

local function startModelBuild()
	modelDirty = false
	firstModelChange = nil
	modelJob = {
		revision = modelRevision,
		nodes = {},
		stack = { { parent = game, children = sortedChildren(game), next = 1, depth = 0, owner = nil } },
	}
end

local function advanceModelBuild(deadline)
	local job = modelJob
	local steps = 0
	while #job.stack > 0 do
		steps += 1
		if steps % 64 == 0 and os.clock() >= deadline then
			return
		end
		local frame = job.stack[#job.stack]
		if frame.next > #frame.children then
			if frame.owner then
				frame.owner.last = #job.nodes
			end
			job.stack[#job.stack] = nil
		else
			local instance = frame.children[frame.next]
			frame.next += 1
			local children = sortedChildren(instance)
			local entry = {
				instance = instance,
				parent = frame.parent,
				depth = frame.depth,
				childCount = #children,
				name = instance.Name,
				lowerName = string.lower(instance.Name),
			}
			job.nodes[#job.nodes + 1] = entry
			if #children == 0 then
				entry.last = #job.nodes
			else
				job.stack[#job.stack + 1] = {
					parent = instance,
					children = children,
					next = 1,
					depth = frame.depth + 1,
					owner = entry,
				}
			end
		end
	end
	if job.revision == modelRevision then
		indexedNodes = job.nodes
		nameScanCursor = 1
		invalidateLayout()
	end
	modelJob = nil
end

local function startLayoutBuild()
	layoutDirty = false
	local query = filter
	layoutJob = {
		revision = layoutRevision,
		query = query,
		phase = query ~= "" and 1 or 3,
		i = 1,
		keep = {},
		rows = {},
		depths = {},
		counts = {},
		indices = {},
	}
end

local function advanceLayoutBuild(deadline)
	local job = layoutJob
	local nodes = indexedNodes
	local n = #nodes
	local steps = 0
	while true do
		steps += 1
		if steps % 128 == 0 and os.clock() >= deadline then
			return
		end
		if job.phase == 1 then
			if job.i > n then
				job.phase = 2
				job.i = n
			else
				local entry = nodes[job.i]
				if string.find(entry.lowerName, job.query, 1, true) then
					job.keep[entry.instance] = true
				end
				job.i += 1
			end
		elseif job.phase == 2 then
			if job.i == 0 then
				job.phase = 3
				job.i = 1
			else
				local entry = nodes[job.i]
				if job.keep[entry.instance] and entry.parent ~= game then
					job.keep[entry.parent] = true
				end
				job.i -= 1
			end
		else
			if job.i > n then
				if job.revision == layoutRevision then
					visibleRows = job.rows
					visibleDepths = job.depths
					visibleChildCounts = job.counts
					visibleIndex = job.indices
					local canvasHeight = #visibleRows * UI.metrics.treeRow + 5
					list.CanvasSize = UDim2.new(1, 0, 0, canvasHeight)
					list.CanvasPosition =
						Vector2.new(0, math.min(list.CanvasPosition.Y, math.max(0, canvasHeight - list.AbsoluteSize.Y)))
					updateViewport(true)
				end
				layoutJob = nil
				return
			end
			local entry = nodes[job.i]
			if job.query == "" or job.keep[entry.instance] then
				local rowNumber = #job.rows + 1
				job.rows[rowNumber] = entry.instance
				job.depths[rowNumber] = entry.depth
				job.counts[rowNumber] = entry.childCount
				job.indices[entry.instance] = rowNumber
				if job.query == "" and not expanded[entry.instance] then
					job.i = entry.last + 1
				else
					job.i += 1
				end
			else
				job.i = entry.last + 1
			end
		end
	end
end

rebuild = function()
	if UI.isAlive(renaming) then
		pendingRebuild = true
		return
	end
	invalidateLayout()
end

local function updateRowSelection(instance, selected)
	local entry = rowRegistry[instance]
	if not entry or not UI.isAlive(entry.row) then
		return
	end
	UI.setButtonState(entry.button, selected and "selected" or nil)
	entry.corner.CornerRadius = UDim.new(0, selected and tokens.radius.sm or 0)
	entry.label.TextColor3 = selected and tokens.color.text or colors.text
	entry.baseTransparency = selected and 0 or 0.12
	if not entry.dropTarget then
		entry.row.BackgroundTransparency = entry.baseTransparency
	end
end
Selection.SelectionChanged:Connect(function()
	local nextSelected = {}
	for _, instance in ipairs(Selection:Get()) do
		nextSelected[instance] = true
		if not selectedSet[instance] then
			updateRowSelection(instance, true)
		end
	end
	for instance in pairs(selectedSet) do
		if not nextSelected[instance] then
			updateRowSelection(instance, false)
		end
	end
	selectedSet = nextSelected
end)
searchField.TextChanged:Connect(function()
	filter = string.lower(searchField.Text or "")
	invalidateLayout(filter ~= "" and SEARCH_DEBOUNCE or 0)
end)
local function deleteInstance(instance)
	if isProtected(instance) then
		return
	end
	viewport.CloseScript(instance)
	expanded[instance] = nil
	renaming = nil
	selectObject({})
	instance:Destroy()
	invalidateTree()
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
		selectObject({
			clone,
		})
		invalidateTree()
	end
end
local function deleteInstances(list)
	for _, instance in ipairs(list) do
		deleteInstance(instance)
	end
	anchor = nil
end
local function duplicateInstances(list)
	local clones = {}
	for _, instance in ipairs(list) do
		if not isProtected(instance) then
			local ok, clone = pcall(function()
				return instance:Clone()
			end)
			if ok and clone then
				clone.Name = instance.Name
				clone.Parent = instance.Parent
				table.insert(clones, clone)
			end
		end
	end
	if #clones > 0 then
		selectObject(clones)
		invalidateTree()
	end
end
local function pasteInto(destination)
	if destination == nil or clipboard == nil then
		return
	end
	local clones = {}
	for _, source in ipairs(clipboard) do
		if UI.isAlive(source) then
			local ok, clone = pcall(function()
				return source:Clone()
			end)
			if ok and clone then
				clone.Parent = destination
				table.insert(clones, clone)
			end
		end
	end
	if #clones > 0 then
		selectObject(clones)
		invalidateTree()
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
	renaming:CaptureFocus()
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
			invalidateTree()
		end
		if pendingRebuild then
			pendingRebuild = false
			rebuild()
		end
		updateViewport(true)
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
rowIndexOf = function(instance)
	return visibleIndex[instance]
end
local function selectAndReveal(index, extend)
	local instance = visibleRows[index]
	if instance == nil then
		return
	end
	if extend and anchor ~= nil then
		selectRange(anchor, instance)
	else
		anchor = instance
		selectObject({ instance })
	end
	local target = math.max(0, (index - 1) * UI.metrics.treeRow - list.AbsoluteSize.Y / 2)
	list.CanvasPosition = Vector2.new(0, target)
	updateViewport(true)
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
		contextMenuOptions = {
			items = {},
			menuWidth = 168,
			itemHeight = UI.metrics.inputHeight,
			maxVisibleItems = 6,
			itemBgTransparency = 1,
			showSearch = false,
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
				elseif action == "import" then
					local file = dialog:PickFile()
					if file then
						local imported = export_service:ImportFile(file)
						if imported then
							util.parent(imported, target)
						end
					end
				elseif action == "upload_package" then
					if not shared.CurrentSession then
						UI.toast("import", {
							type = "error",
							title = "Error!",
							message = `You are not logged in.`,
							details = ``,
							detailsTitle = "",
							backgroundTransparency = 0.4,
							blur = true,
							duration = 5,
						})
						return
					end
					package_upload.open(target)
				elseif action == "export" then
					local file = dialog:PickFile()
					if file then
						local success = export_service:Export(target, file)
						if success then
							UI.toast("import", {
								type = "success",
								title = "Exported successfully!",
								message = `Exported KINE file to {file}`,
								details = ``,
								detailsTitle = "",
								backgroundTransparency = 0.4,
								blur = true,
								duration = 5,
							})
						end
					end
				elseif action == "duplicate" then
					duplicateInstances(targetsFor(target))
				elseif action == "delete" then
					deleteInstances(targetsFor(target))
				elseif action == "copy" then
					clipboard = targetsFor(target)
				elseif action == "paste" then
					pasteInto(target)
				end
			end,
		}
		local controller = UI.contextMenu(
			UI.contextMenuOverlay(),
			"",
			UDim2.fromOffset(-400, -400),
			UDim2.fromOffset(1, 1),
			nil,
			contextMenuOptions
		)
		contextMenu = controller
	end
	contextMenu:SetItems({
		{ label = "Rename", value = "rename", icon = "builtin://global-icons/pencil.svg" },
		{ label = "Duplicate", value = "duplicate", icon = "builtin://global-icons/plus.svg" },
		{ label = "Delete", value = "delete", icon = "builtin://global-icons/x.svg" },
		{ label = "Copy", value = "copy" },
		{ label = "Import Object..", value = "import" },
		{ label = "Export Object..", value = "export" },
		{ label = "Upload as Package..", value = "upload_package" },
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
	local mouse = UserInputService:GetMouseLocation()
	local best = nil
	local bestDistance = math.huge
	local sources = drag.sources or { drag.source }
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
		if not canDropAny(sources, instance) then -- was canReparent(source, instance)
			continue
		end
		-- The top half reparents as a sibling, the bottom half as a child,
		-- which is the behaviour the Roblox explorer uses.
		local target = offset > size.Y / 2 and instance or instance.Parent
		if target ~= nil and canDropAny(sources, target) then
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
	}, UI.widgetOverlay())
	UI.corner(dragLayer, tokens.radius.sm)
	UI.label(
		dragLayer,
		#(drag.sources or {}) > 1 and (#drag.sources .. " items") or drag.source.Name,
		UDim2.fromOffset(8, 2),
		UDim2.new(1, -16, 0, 16),
		tokens.type.small,
		tokens.color.text
	)
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
	local sources = drag.sources or { drag.source }
	local target = drag.target
	local function apply()
		disposeDrag()
		clearDropHighlight()
		if reparent and target ~= nil then
			reparentAll(sources, target)
		end
	end
	if dragLayer == nil then
		apply()
		return
	end
	local layer = dragLayer
	if UI.shared and UI.shared().reduceMotion then
		layer.BackgroundTransparency = 1
		apply()
		return
	end
	local tween = TweenService:Create(layer, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		BackgroundTransparency = 1,
	})
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
		if not isInSelection(drag.source) then
			anchor = drag.source
			selectObject({ drag.source })
		end
		drag.sources = selectionRoots()
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
local function focusOn(target: Instance)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local center, radius
	if target:IsA("BasePart") then
		center = target.CFrame.Position
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
UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed or picker.isActive() then
		return
	end
	local typing = UserInputService:GetFocusedTextBox() ~= nil
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		if not mouseInList() then
			closeContextMenu()
		end
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local mouse = UserInputService:GetMouseLocation()
		local overMenu = contextMenu ~= nil and contextMenu:ContainsPoint(mouse.X, mouse.Y)
		if not mouseInList() and not overMenu then
			closeContextMenu()
			commitRename()
		end
		return
	end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end
	if not explorerTabActive() then
		return
	end
	if input.KeyCode == Enum.KeyCode.F and not gameProcessed then
		local selection = Selection:Get()[1]
		if selection then
			focusOn(selection)
		end
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
			selectObject({})
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
		selectAndReveal(math.clamp(next_, 1, #visibleRows), shiftHeld())
		return
	end
	if input.KeyCode == Enum.KeyCode.Home then
		selectAndReveal(1, shiftHeld())
		return
	end
	if input.KeyCode == Enum.KeyCode.End then
		selectAndReveal(#visibleRows, shiftHeld())
		return
	end
	if input.KeyCode == Enum.KeyCode.Right then
		if selected ~= nil and not expanded[selected] and #selected:GetChildren() > 0 then
			expanded[selected] = true
			invalidateLayout()
		end
		return
	end
	if input.KeyCode == Enum.KeyCode.Left then
		if selected ~= nil then
			if expanded[selected] then
				expanded[selected] = nil
				invalidateLayout()
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
			if entry == nil then
				local selectedIndex = rowIndexOf(selected)
				if selectedIndex then
					selectAndReveal(selectedIndex, false)
					entry = rowRegistry[selected]
				end
			end
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
			clipboard = selectionRoots()
		end
		return
	end
	if input.KeyCode == Enum.KeyCode.V then
		if ctrlHeld() then
			pasteInto(selected or workspace)
		end
		return
	end
	if input.KeyCode == Enum.KeyCode.A then
		if ctrlHeld() and #visibleRows > 0 then
			local all = {}
			for _, instance in ipairs(visibleRows) do
				table.insert(all, instance)
			end
			selectObject(all)
		end
		return
	end
	if input.KeyCode == Enum.KeyCode.Delete or input.KeyCode == Enum.KeyCode.Backspace then
		deleteInstances(selectionRoots())
		return
	end
	if input.KeyCode == Enum.KeyCode.D then
		if ctrlHeld() then
			duplicateInstances(selectionRoots())
		end
	end
end)
local function watchModelSignals()
	pcall(function()
		game.DescendantAdded:Connect(invalidateTree)
	end)
	pcall(function()
		game.DescendantRemoving:Connect(invalidateTree)
	end)
end
watchModelSignals()

for _, object in ipairs(Selection:Get() or {}) do
	selectedSet[object] = true
end

if filter == "" then
	for _, instance in ipairs(sortedChildren(game)) do
		local index = #visibleRows + 1
		visibleRows[index] = instance
		visibleDepths[index] = 0
		visibleChildCounts[index] = #instance:GetChildren()
		visibleIndex[instance] = index
	end
	list.CanvasSize = UDim2.new(1, 0, 0, #visibleRows * UI.metrics.treeRow + 5)
	updateViewport(true)
end

local function scanForRenames()
	if modelDirty or modelJob ~= nil or #indexedNodes == 0 then
		return
	end
	local count = #indexedNodes
	for _ = 1, math.min(NAME_SCAN_BATCH, count) do
		local entry = indexedNodes[nameScanCursor]
		if entry.name ~= entry.instance.Name then
			invalidateTree()
			return
		end
		nameScanCursor += 1
		if nameScanCursor > count then
			nameScanCursor = 1
		end
	end
end

docker.HiddenSignal:Connect(function()
	IsDockingMode = false
end)
renderer.Pool.new("2d", function()
	local dragging = docker.Update(panel, "Explorer")
	if not dragging then
		panel.Size = theme.ExplorerCoordinates.Size
		panel.Position = theme.ExplorerCoordinates.Position
	end

	if not gui.Enabled or not tabActive("Explorer") then
		return
	end

	local now = os.clock()
	if modelDirty and modelJob == nil and now >= modelReadyAt then
		startModelBuild()
	end
	if modelJob ~= nil then
		advanceModelBuild(os.clock() + INDEX_FRAME_BUDGET)
	elseif not modelDirty then
		if layoutDirty and layoutJob == nil and now >= layoutReadyAt and not UI.isAlive(renaming) then
			startLayoutBuild()
		end
		if layoutJob ~= nil then
			advanceLayoutBuild(os.clock() + LAYOUT_FRAME_BUDGET)
		end
		scanForRenames()
	end
	updateViewport(false)
end)
return {
	filesController = filesController,
	Refresh = function()
		invalidateTree()
		if filesController and filesController.Refresh then
			filesController.Refresh()
		end
		UI.refreshWindow("Explorer")
	end,
	Show = function()
		local panel = UI.getWindow("Explorer")
		if panel then
			panel.Visible = true
		end
	end,
	Hide = function()
		local panel = UI.getWindow("Explorer")
		if panel then
			panel.Visible = false
		end
	end,
	IsVisible = function()
		local panel = UI.getWindow("Explorer")
		return panel ~= nil and panel.Visible
	end,
}

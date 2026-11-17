if IsServer or IsClient or IsPlaytest then
	return nil
end

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")
local UI = require("@internal/editor_ui")
local viewport = require("@internal/viewport")
local tokens = UI.tokens

local MAX_SCRIPTS = 750
local MAX_EDGES = 2700
local MAX_SOURCE_BYTES = 2 * 1024 * 1024
local MAX_TOKENS_PER_SOURCE = 45000
local MAX_RESOLVE_CALLS_PER_SOURCE = 2500
local MAX_SOURCE_CPU_SECONDS = 0.70
local PHYSICS_MAX_NODES = 260
local PHYSICS_STEPS = 240
local SCAN_TIME_BUDGET = 0.004
local SIDEBAR_WIDTH = 280
local ROW_HEIGHT = UI.metrics.treeRow
local OVERSCAN = 6
local SEARCH_DELAY = 0.12
local GOLDEN_ANGLE = 2.399963229728653
local MIN_ZOOM, MAX_ZOOM = 0.18, 3.6

local colors = tokens.color
local INSET = UI.metrics.panelInset
local GAP = tokens.space.xs
local HEADER = UI.metrics.sectionRow
local TOOLBAR_HEIGHT = UI.metrics.buttonHeight + INSET * 2 + GAP * 2
local STATUS_HEIGHT = UI.metrics.treeRow + INSET
local SEARCH_HEIGHT = UI.metrics.inputHeight
local DETAIL_HEIGHT = UI.metrics.propertyRow * 7 + INSET * 2
local ICON_SIZE = 14
local ICONS = {
	Script = "builtin://icons/Script.svg",
	LocalScript = "builtin://icons/LocalScript.svg",
	ModuleScript = "builtin://icons/ModuleScript.svg",
	warning = "builtin://global-icons/Warning.svg",
	info = "builtin://global-icons/Info.svg",
	error = "builtin://global-icons/Error.svg",
	refresh = "builtin://global-icons/refresh.svg",
}

-- Graph colors are data marks, not control chrome. Resolve them from the
-- live theme each time a theme change invalidates the graph.
local function graphColor(kind)
	if kind == "Script" then
		return colors.accent
	elseif kind == "LocalScript" then
		return colors.subtext
	end
	return colors.text
end

local panel, content = UI.window(
	"ScriptDependencyExplorer",
	UDim2.fromScale(0.5, 0.5),
	UDim2.fromOffset(1000, 620),
	"Script Dependency Explorer",
	{ closable = true, closeIcon = "builtin://global-icons/x.svg" }
)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
local overlay = UI.widgetOverlay()
panel.Parent = overlay
panel.Visible = false
panel.ClipsDescendants = true
content.ClipsDescendants = true
-- UI.window defaults: contentColor = colors.panel, activeTabColor = contentColor.
-- Keep the window-owned content opaque; structural children must not repaint it.

local connections = {}
local destroyed = false
local function connect(signal, callback)
	local connection = signal:Connect(callback)
	connections[#connections + 1] = connection
	return connection
end

local function surface(parent, name, position, size, color, transparent)
	local object = UI.frame(parent, position, size, color)
	object.Name = name
	object.BorderSizePixel = 0
	object.BackgroundTransparency = transparent and 1 or 0
	return object
end

local function label(parent, text, position, size, font, color)
	local object = UI.label(parent, text, position, size, font or tokens.type.small, color or colors.text)
	object.TextTruncate = Enum.TextTruncate.AtEnd
	return object
end

local function icon(parent, path, position, size, tint)
	local image = UI.image(parent, path, position, size)
	image.ImageColor3 = tint or colors.subtext
	return image
end

local toolbar =
	surface(content, "Toolbar", UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, TOOLBAR_HEIGHT), colors.panel, true)
UI.separator(content, UDim2.fromOffset(0, TOOLBAR_HEIGHT - 1), UDim2.new(1, 0, 0, 1))
local bodyHeight = -(TOOLBAR_HEIGHT + STATUS_HEIGHT)
local view = surface(
	content,
	"GraphView",
	UDim2.fromOffset(0, TOOLBAR_HEIGHT),
	UDim2.new(1, -SIDEBAR_WIDTH, 1, bodyHeight),
	colors.panel,
	true
)
view.ClipsDescendants = true
view.Active = true
local sidebar = surface(
	content,
	"Sidebar",
	UDim2.new(1, -SIDEBAR_WIDTH, 0, TOOLBAR_HEIGHT),
	UDim2.new(0, SIDEBAR_WIDTH, 1, bodyHeight),
	colors.panel,
	true
)
UI.separator(content, UDim2.new(1, -SIDEBAR_WIDTH, 0, TOOLBAR_HEIGHT), UDim2.new(0, 1, 1, bodyHeight))

local edgeLayer = surface(view, "Edges", UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), colors.panel, true)
local nodeLayer = surface(view, "Nodes", UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), colors.panel, true)
edgeLayer.ClipsDescendants = true
nodeLayer.ClipsDescendants = true

local statusBar = surface(
	content,
	"StatusBar",
	UDim2.new(0, 0, 1, -STATUS_HEIGHT),
	UDim2.new(1, 0, 0, STATUS_HEIGHT),
	colors.panel,
	true
)
UI.separator(statusBar, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 1))
local statusIcon = icon(
	statusBar,
	ICONS.info,
	UDim2.fromOffset(INSET, (STATUS_HEIGHT - ICON_SIZE) / 2),
	UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
)
local status = label(
	statusBar,
	"Refresh to scan the game's scripts",
	UDim2.fromOffset(INSET + ICON_SIZE + GAP, 0),
	UDim2.new(1, -(INSET * 2 + ICON_SIZE + GAP), 1, 0),
	tokens.type.caption,
	colors.subtext
)

local cycleBanner = UI.group(
	view,
	UDim2.fromOffset(INSET, INSET),
	UDim2.new(1, -INSET * 2, 0, HEADER),
	{ color = colors.panel, radius = tokens.radius.sm }
)
cycleBanner.ZIndex = 12
UI.stroke(cycleBanner, colors.border, 1, 0)
local cycleIcon = icon(
	cycleBanner,
	ICONS.warning,
	UDim2.fromOffset(INSET, (HEADER - ICON_SIZE) / 2),
	UDim2.fromOffset(ICON_SIZE, ICON_SIZE),
	colors.error
)
cycleIcon.ZIndex = 13
local cycleWarning = label(
	cycleBanner,
	"",
	UDim2.fromOffset(INSET + ICON_SIZE + GAP, 0),
	UDim2.new(1, -(INSET * 2 + ICON_SIZE + GAP), 1, 0),
	tokens.type.caption,
	colors.error
)
cycleWarning.ZIndex = 13
cycleBanner.Visible = false

local emptyGraph = UI.group(
	view,
	UDim2.fromScale(0.5, 0.5),
	UDim2.fromOffset(280, ROW_HEIGHT * 2 + INSET * 2),
	{ color = colors.panel, radius = tokens.radius.md }
)
emptyGraph.AnchorPoint = Vector2.new(0.5, 0.5)
emptyGraph.ZIndex = 10
UI.stroke(emptyGraph, colors.border, 1, 0)
local emptyIcon = icon(
	emptyGraph,
	ICONS.info,
	UDim2.fromOffset(INSET, INSET + ROW_HEIGHT / 2),
	UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
)
emptyIcon.ZIndex = 11
local emptyText = label(
	emptyGraph,
	"Refresh to index project scripts.",
	UDim2.fromOffset(INSET * 2 + ICON_SIZE, INSET),
	UDim2.new(1, -(INSET * 3 + ICON_SIZE), 1, -INSET * 2),
	tokens.type.small,
	colors.subtext
)
emptyText.TextWrapped = true
emptyText.ZIndex = 11

local queryInput =
	UI.input(sidebar, "Search scripts...", UDim2.fromOffset(INSET, INSET), UDim2.new(1, -INSET * 2, 0, SEARCH_HEIGHT), {
		selectAllOnFocus = false,
		focusColor = colors.focus,
		caretColor = colors.accent,
		selectionColor = colors.selection,
	})
queryInput.Name = "DependencyGraphSearch"
local countLabel = label(
	sidebar,
	"No scripts indexed",
	UDim2.fromOffset(INSET, INSET + SEARCH_HEIGHT + GAP),
	UDim2.new(1, -INSET * 2, 0, ROW_HEIGHT),
	tokens.type.caption,
	colors.subtext
)
local LIST_HEADER_Y = INSET + SEARCH_HEIGHT + GAP + ROW_HEIGHT
local listHeader = label(
	sidebar,
	"Scripts",
	UDim2.fromOffset(INSET, LIST_HEADER_Y),
	UDim2.new(1, -INSET * 2, 0, HEADER),
	tokens.type.small,
	colors.text
)
local function scrolling(name, position, size)
	return UI.create("ScrollingFrame", {
		Name = name,
		Position = position,
		Size = size,
		BackgroundColor3 = colors.panel,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasPosition = Vector2.new(0, 0),
		CanvasSize = UDim2.new(1, 0, 0, 0),
		ScrollingEnabled = true,
		ScrollSpeed = 38,
		SmoothScrollingEnabled = true,
		ScrollSmoothness = 18,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = colors.subtext,
		ScrollBarImageTransparency = 0.4,
		ScrollBarAutoHide = true,
		ScrollBarFadeDelay = 0.45,
		ScrollBarFadeSpeed = 12,
		ScrollBarMinimumHandleSize = 24,
		ClipsDescendants = true,
		Active = true,
		InputSink = true,
	}, sidebar)
end
local LIST_TOP = LIST_HEADER_Y + HEADER + GAP
local scriptList = scrolling(
	"Scripts",
	UDim2.fromOffset(INSET, LIST_TOP),
	UDim2.new(1, -INSET * 2, 1, -(LIST_TOP + DETAIL_HEIGHT + GAP))
)
local scriptEmpty = label(
	scriptList,
	"No scripts to display.",
	UDim2.fromOffset(INSET, GAP),
	UDim2.new(1, -INSET * 2, 0, ROW_HEIGHT),
	tokens.type.caption,
	colors.subtext
)

local cycleHeader = label(
	sidebar,
	"Circular requires (0)",
	UDim2.new(0, INSET + ICON_SIZE + GAP, 1, -DETAIL_HEIGHT - HEADER),
	UDim2.new(1, -(INSET * 2 + ICON_SIZE + GAP), 0, HEADER),
	tokens.type.small,
	colors.error
)
local sidebarCycleIcon = icon(
	sidebar,
	ICONS.warning,
	UDim2.new(0, INSET, 1, -DETAIL_HEIGHT - HEADER + (HEADER - ICON_SIZE) / 2),
	UDim2.fromOffset(ICON_SIZE, ICON_SIZE),
	colors.error
)
local cycleList = scrolling("DependencyCycles", UDim2.new(0, INSET, 1, -DETAIL_HEIGHT), UDim2.new(1, -INSET * 2, 0, 0))
cycleHeader.Visible = false
sidebarCycleIcon.Visible = false
cycleList.Visible = false

local details = UI.group(
	sidebar,
	UDim2.new(0, INSET, 1, -DETAIL_HEIGHT + GAP),
	UDim2.new(1, -INSET * 2, 0, DETAIL_HEIGHT - INSET - GAP),
	{ color = colors.panel, radius = tokens.radius.sm }
)
details.BackgroundTransparency = 1
UI.stroke(details, colors.border, 1, 0)
local detailsTitle = label(
	details,
	"Selected script",
	UDim2.fromOffset(INSET, GAP),
	UDim2.new(1, -INSET * 2, 0, HEADER),
	tokens.type.caption,
	colors.subtext
)
UI.tooltip(detailsTitle, "Drag to pan. Scroll to zoom. Double-click a script to open it. Press F to fit the graph.")
local selectedIcon = icon(
	details,
	ICONS.info,
	UDim2.fromOffset(INSET, HEADER + GAP + (ROW_HEIGHT - ICON_SIZE) / 2),
	UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
)
local selectedName = label(
	details,
	"Nothing selected",
	UDim2.fromOffset(INSET + ICON_SIZE + GAP, HEADER + GAP),
	UDim2.new(1, -(INSET * 2 + ICON_SIZE + GAP), 0, ROW_HEIGHT),
	tokens.type.body,
	colors.text
)
local selectedPath = label(
	details,
	"Select a bubble or script to inspect it.",
	UDim2.fromOffset(INSET, HEADER + ROW_HEIGHT + GAP),
	UDim2.new(1, -INSET * 2, 0, ROW_HEIGHT * 2),
	tokens.type.caption,
	colors.subtext
)
selectedPath.TextWrapped = true
local selectedStats = label(
	details,
	"",
	UDim2.fromOffset(INSET, HEADER + ROW_HEIGHT * 3 + GAP),
	UDim2.new(1, -INSET * 2, 0, ROW_HEIGHT * 3),
	tokens.type.caption,
	colors.subtext
)
selectedStats.TextWrapped = true

local revision = 0
local graphNodes = {}
local graphEdges = {}
local nodeByObject = {}
local cycleGroups = {}
local cyclicNodeCount = 0
local cyclicEdgeCount = 0
local chosen = nil
local sceneOffset = Vector2.new(0, 0)
local zoom = 1
local showIsolated = true
local showCyclesOnly = false
local physicsEnabled = true
local simulationLeft = 0
local currentMessage = "Refresh to scan the game's scripts"
local currentSeverity = "info"
local currentQuery, pendingQuery = "", ""
local searchDeadline = -1
local sortedNodes = {}
local rowsDirty = true
local warningCount = 0
local scannedCount = 0
local unresolvedCount = 0
local unreadableCount = 0
local lastDraw = 0
local drawDirty = true
local skippedBudgetCount = 0
local skippedTokenCount = 0
local completedSources = 0
local scanInProgress = false
local dragging = nil
local lastClickNode = nil
local lastClickTime = 0
local scanStarted = false
local graphReady = false
local filteredRows = {}
local rowSlots = {}
local cycleRowSlots = {}
local updateDetails
local updateRowViewport
local updateCycleViewport
local updateCycleList
local focusCycleGroup

local function setStatus(message, severity)
	if destroyed then
		return
	end
	currentMessage = message
	currentSeverity = severity or "info"
	status.Text = message
	statusIcon.Image = ICONS[severity or "info"] or ICONS.info
	statusIcon.ImageColor3 = severity == "error" and colors.error
		or (severity == "warning" and colors.warning or colors.subtext)
	status.TextColor3 = severity == "error" and colors.error or colors.subtext
end

local startScan
local fitGraph
local refreshVisible
local drawGraph
local focusNode
local cancelScan
local enable
local disable

local toolbarX = INSET
local function control(caption, width, onClick, options)
	local button, _, record = UI.button(
		toolbar,
		caption,
		UDim2.fromOffset(toolbarX, INSET + GAP),
		UDim2.fromOffset(width, UI.metrics.buttonHeight),
		onClick,
		options or {}
	)
	toolbarX += width + GAP
	return button, record
end
control("Refresh", 92, function()
	if startScan then
		startScan()
	end
end, { icon = ICONS.refresh, iconSize = ICON_SIZE })
local cancelButton = control("Cancel", 64, function()
	if cancelScan then
		cancelScan("Scan cancelled.")
	end
end)
cancelButton.Visible = false
control("Fit graph", 78, function()
	if fitGraph then
		fitGraph()
	end
end)
local physicsControl
local _
_, physicsControl = control("Physics", 74, function()
	physicsEnabled = not physicsEnabled
	if physicsEnabled and not UI.shared().reduceMotion then
		simulationLeft = PHYSICS_STEPS
	else
		simulationLeft = 0
	end
	UI.setButtonState(physicsControl, physicsEnabled and "selected" or nil)
	drawDirty = true
end)
UI.setButtonState(physicsControl, "selected")
local isolatedControl
_, isolatedControl = control("Isolated", 74, function()
	showIsolated = not showIsolated
	UI.setButtonState(isolatedControl, showIsolated and "selected" or nil)
	if refreshVisible then
		refreshVisible()
	end
	if fitGraph then
		fitGraph()
	end
end)
UI.setButtonState(isolatedControl, "selected")
local cyclesControl
_, cyclesControl = control("Cycles", 68, function()
	showCyclesOnly = not showCyclesOnly
	UI.setButtonState(cyclesControl, showCyclesOnly and "selected" or nil)
	if refreshVisible then
		refreshVisible()
	end
	if fitGraph then
		fitGraph()
	end
end)

local legendWidth = 0
for _, kind in ipairs({ "Script", "LocalScript", "ModuleScript" }) do
	local width = #kind * 7 + ICON_SIZE + GAP + INSET
	legendWidth += width
end
local legend = surface(
	toolbar,
	"Legend",
	UDim2.new(1, -legendWidth - INSET, 0, 0),
	UDim2.fromOffset(legendWidth, TOOLBAR_HEIGHT),
	colors.panel,
	true
)
local legendX = 0
for _, kind in ipairs({ "Script", "LocalScript", "ModuleScript" }) do
	local width = #kind * 7 + ICON_SIZE + GAP + INSET
	icon(
		legend,
		ICONS[kind],
		UDim2.fromOffset(legendX, (TOOLBAR_HEIGHT - ICON_SIZE) / 2),
		UDim2.fromOffset(ICON_SIZE, ICON_SIZE),
		graphColor(kind)
	)
	label(
		legend,
		kind,
		UDim2.fromOffset(legendX + ICON_SIZE + GAP, 0),
		UDim2.fromOffset(width - ICON_SIZE - GAP, TOOLBAR_HEIGHT),
		tokens.type.caption,
		colors.subtext
	)
	legendX += width
end
local function updateToolbar()
	legend.Visible = toolbar.AbsoluteSize.X >= toolbarX + legendWidth + INSET * 2
end
connect(toolbar:GetPropertyChangedSignal("AbsoluteSize"), updateToolbar)
updateToolbar()

local function safeGetChildren(object)
	local ok, children = pcall(function()
		return object:GetChildren()
	end)
	return ok and children or nil
end

local function safePath(object)
	local ok, result = pcall(function()
		return object:GetFullName()
	end)
	return ok and result or tostring(object.Name)
end

local function safeSource(object)
	local ok, source = pcall(function()
		return object.Source
	end)
	return ok and type(source) == "string" and source or nil
end

local function isScript(object)
	return object.ClassName == "Script" or object.ClassName == "LocalScript" or object.ClassName == "ModuleScript"
end

local function isVisibleNode(node)
	if showCyclesOnly and not node.cycleGroup then
		return false
	end
	return showIsolated or node.degree > 0
end

local function nearViewport(localPosition)
	return localPosition.X >= 0
		and localPosition.Y >= 0
		and localPosition.X <= view.AbsoluteSize.X
		and localPosition.Y <= view.AbsoluteSize.Y
end

local function eventPosition(event)
	return Vector2.new(event.Position.X, event.Position.Y)
end

local function toLocal(point)
	return point - view.AbsolutePosition
end

local function worldToScreen(x, y)
	local s = view.AbsoluteSize
	return Vector2.new(s.X * 0.5 + (x + sceneOffset.X) * zoom, s.Y * 0.5 + (y + sceneOffset.Y) * zoom)
end

local function resetVisuals()
	graphReady = false
	simulationLeft = 0
	dragging = nil
	lastClickNode, lastClickTime = nil, 0
	UI.clear(nodeLayer)
	UI.clear(edgeLayer)
	graphNodes, graphEdges, nodeByObject = {}, {}, {}
	cycleGroups = {}
	cyclicNodeCount, cyclicEdgeCount = 0, 0
	warningCount, scannedCount, unresolvedCount, unreadableCount = 0, 0, 0, 0
	skippedBudgetCount, skippedTokenCount, completedSources = 0, 0, 0
	cycleBanner.Visible = false
	cycleWarning.Text = ""
	chosen = nil
	filteredRows, sortedNodes = {}, {}
	rowsDirty = true
	for _, slot in ipairs(rowSlots) do
		slot.node, slot.lastNode, slot.lastClick = nil, nil, nil
		slot.row.Visible = false
	end
	for _, slot in ipairs(cycleRowSlots) do
		slot.group = nil
		slot.row.Visible = false
	end
	scriptList.CanvasPosition = Vector2.new(0, 0)
	scriptList.CanvasSize = UDim2.new(1, 0, 0, 0)
	cycleList.CanvasPosition = Vector2.new(0, 0)
	cycleList.CanvasSize = UDim2.new(1, 0, 0, 0)
	countLabel.Text = "No scripts indexed"
	updateCycleList()
	updateDetails()
	listHeader.Text = "Scripts (0)"
	scriptEmpty.Visible = true
	emptyGraph.Visible = true
	emptyText.Text = "Scanning project scripts..."
	sceneOffset = Vector2.new(0, 0)
	zoom = 1
	drawDirty = true
end

-- Graph nodes and links are data geometry, not clickable controls. Their
-- interaction is handled by the canvas, so structural UI.frame is sufficient.
local function makeNodeVisual(node)
	local dot =
		surface(nodeLayer, "ScriptBubble", UDim2.fromOffset(0, 0), UDim2.fromOffset(12, 12), graphColor(node.kind))
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.ZIndex = 5
	UI.corner(dot, 100) -- circular data mark, not a chrome radius
	dot.Visible = false
	node.visual = dot
	local caption = label(
		nodeLayer,
		node.name,
		UDim2.fromOffset(0, 0),
		UDim2.fromOffset(100, ROW_HEIGHT),
		tokens.type.small,
		colors.text
	)
	caption.Name = "BubbleLabel"
	caption.ZIndex = 6
	caption.Visible = false
	node.caption = caption
end

local function makeEdgeVisual(edge)
	if edge.from == edge.to then
		-- A zero-length link needs a visible status image rather than a glyph.
		local image =
			icon(edgeLayer, ICONS.warning, UDim2.fromOffset(0, 0), UDim2.fromOffset(ICON_SIZE, ICON_SIZE), colors.error)
		image.Name = "SelfRequireWarning"
		image.ZIndex = 3
		image.Visible = false
		edge.visual = image
		return
	end
	local line = surface(edgeLayer, "DependencyLink", UDim2.fromOffset(0, 0), UDim2.fromOffset(0, 1), colors.subtext)
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.BackgroundTransparency = 0.67
	line.ZIndex = 2
	line.Visible = false
	edge.visual = line
end

updateDetails = function()
	if not chosen then
		selectedIcon.Image = ICONS.info
		selectedIcon.ImageColor3 = colors.subtext
		selectedName.Text = "Nothing selected"
		selectedPath.Text = "Select a bubble to inspect it"
		selectedStats.Text = ""
		return
	end
	selectedIcon.Image = ICONS[chosen.kind]
	selectedIcon.ImageColor3 = chosen.cycleGroup and colors.error or graphColor(chosen.kind)
	selectedName.Text = chosen.name
	selectedPath.Text = chosen.path
	selectedStats.Text = string.format(
		"Requires: %d    Required by: %d\n%s%s",
		chosen.outCount,
		chosen.inCount,
		chosen.kind,
		chosen.cycleGroup and string.format("  |  Cycle #%d (%d)", chosen.cycleGroup.id, #chosen.cycleGroup.nodes) or ""
	)
	if chosen.scanWarning then
		selectedStats.Text = selectedStats.Text .. "\n" .. chosen.scanWarning
	end
end

local function selectNode(node)
	chosen = node
	if node and node.object and node.object.Parent then
		pcall(function()
			Selection:Set({ node.object })
		end)
	end
	updateDetails()
	updateRowViewport(true)
	if updateCycleViewport then
		updateCycleViewport(true)
	end
	drawDirty = true
end

local function openNode(node)
	if not node or not node.object or not node.object.Parent then
		setStatus("Cannot open: script was removed", "warning")
		return
	end
	local ok, err = pcall(function()
		viewport.OpenScript(node.object)
	end)
	if not ok then
		setStatus("Unable to open " .. node.name .. ": " .. tostring(err), "error")
	end
end

-- Canonical Explorer-style row pooling. Each slot owns a class/status image,
-- caption, and controller. Rebinding never registers a new button.
local function makeRowSlot(scroll, isCycle)
	local slot = {}
	local row, builtinLabel, record =
		UI.button(scroll, "", UDim2.fromOffset(1, 0), UDim2.new(1, -2, 0, ROW_HEIGHT), nil, {
			color = colors.rowOdd,
			hoverColor = colors.hover,
			pressedColor = colors.pressed,
			bgTransparency = 0.12,
			radius = 0,
			border = false,
		})
	builtinLabel.Visible = false
	row.Name = isCycle and "CycleRow" or "ScriptRow"
	slot.row, slot.controller = row, record
	slot.icon = icon(
		row,
		isCycle and ICONS.warning or ICONS.Script,
		UDim2.fromOffset(INSET, (ROW_HEIGHT - ICON_SIZE) / 2),
		UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
	)
	slot.caption = label(
		row,
		"",
		UDim2.fromOffset(INSET + ICON_SIZE + GAP, 1),
		UDim2.new(1, -(INSET * 2 + ICON_SIZE * 2 + GAP * 2), 0, ROW_HEIGHT - 2),
		tokens.type.small,
		colors.text
	)
	slot.warning = icon(
		row,
		ICONS.warning,
		UDim2.new(1, -INSET - ICON_SIZE, 0.5, -ICON_SIZE / 2),
		UDim2.fromOffset(ICON_SIZE, ICON_SIZE),
		colors.warning
	)
	slot.warning.Visible = false
	connect(row.Activated, function(_, clickCount)
		if isCycle then
			local group = slot.group
			if not group or not group.nodes[1] then
				return
			end
			selectNode(group.nodes[1])
			focusCycleGroup(group)
			setStatus(string.format("Cycle #%d: %d affected scripts", group.id, #group.nodes), "warning")
		else
			local node = slot.node
			if not node then
				return
			end
			selectNode(node)
			focusNode(node)
			if clickCount == 2 or (slot.lastNode == node and os.clock() - (slot.lastClick or 0) < 0.37) then
				openNode(node)
				slot.lastNode = nil
			else
				slot.lastNode, slot.lastClick = node, os.clock()
			end
		end
	end)
	row.Visible = false
	return slot
end

local listRanges = { scripts = {}, cycles = {} }
local function renderRows(scroll, pool, items, range, isCycle, force)
	local height = scroll.AbsoluteSize.Y
	local first = math.max(1, math.floor(scroll.CanvasPosition.Y / ROW_HEIGHT) + 1 - OVERSCAN)
	local last = height > 0 and math.min(#items, first + math.ceil(height / ROW_HEIGHT) + OVERSCAN * 2 + 1) or 0
	if not force and first == range.first and last == range.last then
		return
	end
	range.first, range.last = first, last
	local used = 0
	for index = first, last do
		used += 1
		local slot = pool[used]
		if not slot then
			slot = makeRowSlot(scroll, isCycle)
			pool[used] = slot
		end
		local item = items[index]
		local selected
		if isCycle then
			slot.group = item
			slot.icon.Image = ICONS.warning
			slot.icon.ImageColor3 = colors.error
			slot.caption.Text = item.label
			slot.caption.TextColor3 = colors.error
			slot.warning.Visible = false
			selected = chosen and chosen.cycleGroup == item
		else
			slot.node = item
			slot.icon.Image = ICONS[item.kind]
			slot.icon.ImageColor3 = graphColor(item.kind)
			slot.caption.Text = item.name
			slot.caption.TextColor3 = colors.text
			slot.warning.Visible = item.cycleGroup ~= nil or item.scanWarning ~= nil
			slot.warning.ImageColor3 = item.cycleGroup and colors.error or colors.warning
			selected = chosen == item
		end
		slot.row.Position = UDim2.fromOffset(1, (index - 1) * ROW_HEIGHT)
		slot.controller.defaultColor = index % 2 == 0 and colors.rowEven or colors.rowOdd
		UI.setButtonState(slot.controller, selected and "selected" or nil)
		slot.row.Visible = true
	end
	for i = used + 1, #pool do
		pool[i].node, pool[i].group = nil, nil
		pool[i].row.Visible = false
	end
end

updateRowViewport = function(force)
	renderRows(scriptList, rowSlots, filteredRows, listRanges.scripts, false, force)
end
updateCycleViewport = function(force)
	renderRows(cycleList, cycleRowSlots, cycleGroups, listRanges.cycles, true, force)
end

updateCycleList = function()
	local hasCycles = #cycleGroups > 0
	local height = hasCycles and math.min(ROW_HEIGHT * 5, #cycleGroups * ROW_HEIGHT) or 0
	local reserved = hasCycles and (height + HEADER + GAP * 2) or 0
	cycleHeader.Text = "Circular requires (" .. #cycleGroups .. ")"
	cycleHeader.Visible = hasCycles
	sidebarCycleIcon.Visible = hasCycles
	cycleList.Visible = hasCycles
	cycleHeader.Position = UDim2.new(0, INSET + ICON_SIZE + GAP, 1, -DETAIL_HEIGHT - reserved + GAP)
	sidebarCycleIcon.Position = UDim2.new(0, INSET, 1, -DETAIL_HEIGHT - reserved + GAP + (HEADER - ICON_SIZE) / 2)
	cycleList.Position = UDim2.new(0, INSET, 1, -DETAIL_HEIGHT - height - GAP)
	cycleList.Size = UDim2.new(1, -INSET * 2, 0, height)
	cycleList.CanvasSize = UDim2.new(1, 0, 0, #cycleGroups * ROW_HEIGHT)
	if not hasCycles then
		cycleList.CanvasPosition = Vector2.new(0, 0)
	end
	scriptList.Size = UDim2.new(1, -INSET * 2, 1, -(LIST_TOP + DETAIL_HEIGHT + reserved + GAP))
	updateCycleViewport(true)
	cycleBanner.Visible = hasCycles
	cycleWarning.Text = string.format(
		"%d circular require group%s (%d affected scripts)",
		#cycleGroups,
		#cycleGroups == 1 and "" or "s",
		cyclicNodeCount
	)
end

local function updateRows(resetPosition)
	if rowsDirty then
		sortedNodes = table.clone(graphNodes)
		table.sort(sortedNodes, function(a, b)
			if a.degree ~= b.degree then
				return a.degree > b.degree
			end
			return a.path < b.path
		end)
		rowsDirty = false
	end
	filteredRows = {}
	for _, node in ipairs(sortedNodes) do
		if isVisibleNode(node) and (currentQuery == "" or string.find(node.searchKey, currentQuery, 1, true)) then
			filteredRows[#filteredRows + 1] = node
		end
	end
	listHeader.Text = string.format("Scripts (%d)", #filteredRows)
	scriptList.CanvasSize = UDim2.new(1, 0, 0, #filteredRows * ROW_HEIGHT)
	if resetPosition then
		scriptList.CanvasPosition = Vector2.new(0, 0)
	end
	scriptEmpty.Visible = #filteredRows == 0
	scriptEmpty.Text = scanInProgress and "Indexing scripts..." or "No matching scripts."
	updateRowViewport(true)
end

connect(scriptList:GetPropertyChangedSignal("CanvasPosition"), function()
	updateRowViewport(false)
end)
connect(scriptList:GetPropertyChangedSignal("AbsoluteSize"), function()
	updateRowViewport(true)
end)
connect(cycleList:GetPropertyChangedSignal("CanvasPosition"), function()
	updateCycleViewport(false)
end)
connect(cycleList:GetPropertyChangedSignal("AbsoluteSize"), function()
	updateCycleViewport(true)
end)

-- Tokenizer: ignores comments and string contents, retaining quoted strings
-- as tokens so a safe subset of static require() expressions can be resolved.
local function isLetter(c)
	return c ~= nil and ((c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95)
end
local function isDigit(c)
	return c ~= nil and c >= 48 and c <= 57
end
local function countNewlines(source, first, last, checkpoint)
	local count = 0
	local p = first
	while p <= last do
		local at = source:find("\n", p, true)
		if not at or at > last then
			break
		end
		count += 1
		p = at + 1
		if count % 256 == 0 and checkpoint and not checkpoint() then
			return nil
		end
	end
	return count
end
local function longBracket(source, p, length)
	if source:byte(p) ~= 91 then
		return nil
	end
	local i = p + 1
	while i <= length and source:byte(i) == 61 do
		i += 1
	end
	if source:byte(i) ~= 91 then
		return nil
	end
	local eq = i - p - 1
	local delimiter = "]" .. string.rep("=", eq) .. "]"
	local closeStart, closeFinish = source:find(delimiter, i + 1, true)
	return i + 1, closeStart, closeFinish or length, delimiter
end

-- Budgeted tokenizer: handles huge, generated, or malformed scripts without
-- blocking the rest of the graph. Returns tokens, error (nil / "cancelled" /
-- "budget" / "tokens"). No Lua code is executed by the scanner.
local function tokenize(source, token, reportProgress)
	local result = {}
	local length, p, line = #source, 1, 1
	local lastPosition = 1
	local lastClock = os.clock()
	local lastYield = lastClock
	local cpuSeconds = 0

	local function checkpoint()
		if token ~= revision then
			return false, "cancelled"
		end
		local now = os.clock()
		cpuSeconds += math.max(0, now - lastClock)
		lastClock = now
		if cpuSeconds > MAX_SOURCE_CPU_SECONDS then
			return false, "budget"
		end
		if now - lastYield >= SCAN_TIME_BUDGET then
			if reportProgress then
				reportProgress(p, length)
			end
			task.wait()
			lastClock = os.clock()
			lastYield = lastClock
			if token ~= revision then
				return false, "cancelled"
			end
		end
		return true
	end

	while p <= length do
		if #result >= MAX_TOKENS_PER_SOURCE then
			return result, "tokens"
		end
		if p - lastPosition >= 2048 then
			local ok, reason = checkpoint()
			if not ok then
				return nil, reason
			end
			lastPosition = p
		end
		local c, nextC = source:byte(p), source:byte(p + 1)
		if c == 10 then
			line += 1
			p += 1
		elseif c == 45 and nextC == 45 then
			local bodyStart, _, closeFinish = longBracket(source, p + 2, length)
			if bodyStart then
				local n = countNewlines(source, p, closeFinish, checkpoint)
				if n == nil then
					return nil, token == revision and "budget" or "cancelled"
				end
				line += n
				p = closeFinish + 1
			else
				local ending = source:find("\n", p + 2, true)
				p = ending or (length + 1)
			end
		elseif c == 34 or c == 39 then
			local startLine, begin, quote = line, p + 1, c
			p += 1
			local parts, partStart, hasEscape = nil, p, false
			while p <= length do
				if p - lastPosition >= 2048 then
					local ok, reason = checkpoint()
					if not ok then
						return nil, reason
					end
					lastPosition = p
				end
				local k = source:byte(p)
				if k == quote then
					break
				end
				if k == 92 and p < length then
					hasEscape = true
					if p - begin <= 512 then
						parts = parts or {}
						parts[#parts + 1] = source:sub(partStart, p - 1)
						local escape = source:sub(p + 1, p + 1)
						local mapped = ({ n = "\n", r = "\r", t = "\t" })[escape]
						parts[#parts + 1] = mapped or escape
					end
					p += 2
					partStart = p
				elseif k == 10 then
					line += 1
					p += 1
				else
					p += 1
				end
			end
			local value = ""
			if p - begin <= 512 then
				if hasEscape and parts then
					parts[#parts + 1] = source:sub(partStart, p - 1)
					value = table.concat(parts)
				elseif not hasEscape then
					value = source:sub(begin, p - 1)
				end
			end
			result[#result + 1] = { k = "str", v = value, line = startLine }
			if source:byte(p) == quote then
				p += 1
			end
		elseif c == 91 then
			local bodyStart, closeStart, closeFinish = longBracket(source, p, length)
			if bodyStart then
				local startLine = line
				local value = closeStart and closeStart - bodyStart <= 512 and source:sub(bodyStart, closeStart - 1)
					or ""
				result[#result + 1] = { k = "str", v = value, line = startLine }
				local n = countNewlines(source, p, closeFinish, checkpoint)
				if n == nil then
					return nil, token == revision and "budget" or "cancelled"
				end
				line += n
				p = closeFinish + 1
			else
				result[#result + 1] = { k = "sym", v = "[", line = line }
				p += 1
			end
		elseif isLetter(c) then
			local begin = p
			p += 1
			while isLetter(source:byte(p)) or isDigit(source:byte(p)) do
				p += 1
				if p - lastPosition >= 2048 then
					local ok, reason = checkpoint()
					if not ok then
						return nil, reason
					end
					lastPosition = p
				end
			end
			-- Identifiers this long are irrelevant to static module paths.
			local name = p - begin <= 512 and source:sub(begin, p - 1) or ""
			result[#result + 1] = { k = "id", v = name, line = line }
		elseif isDigit(c) then
			p += 1
			while isDigit(source:byte(p)) do
				p += 1
				if p - lastPosition >= 2048 then
					local ok, reason = checkpoint()
					if not ok then
						return nil, reason
					end
					lastPosition = p
				end
			end
			result[#result + 1] = { k = "num", v = "", line = line }
		else
			if c > 32 then
				result[#result + 1] = { k = "sym", v = string.char(c), line = line }
			end
			p += 1
		end
	end
	return result, nil
end

local function tokenIs(tokensArray, index, value)
	local item = tokensArray[index]
	return item ~= nil and item.k == "sym" and item.v == value
end

local function childOf(object, name)
	if not object or not name then
		return nil
	end
	local ok, item = pcall(function()
		return object:FindFirstChild(name)
	end)
	return ok and item or nil
end

local function getService(name)
	local ok, item = pcall(function()
		return game:GetService(name)
	end)
	return ok and item or nil
end

-- Returns resolved Instance and index of token following the expression.
local function resolveReference(t, first, owner, aliases)
	local base = t[first]
	if not base or base.k ~= "id" then
		return nil, first
	end
	local object
	if base.v == "script" then
		object = owner
	elseif base.v == "game" then
		object = game
	elseif base.v == "workspace" then
		object = getService("Workspace")
	else
		object = aliases[base.v]
	end
	if not object then
		return nil, first
	end

	local i = first + 1
	local steps = 0
	while t[i] and steps < 64 do
		steps += 1
		if tokenIs(t, i, ".") and t[i + 1] and t[i + 1].k == "id" then
			local member = t[i + 1].v
			if member == "Parent" then
				object = object.Parent
			else
				object = childOf(object, member)
			end
			i += 2
		elseif tokenIs(t, i, "[") and t[i + 1] and t[i + 1].k == "str" and tokenIs(t, i + 2, "]") then
			object = childOf(object, t[i + 1].v)
			i += 3
		elseif
			tokenIs(t, i, ":")
			and t[i + 1]
			and t[i + 1].k == "id"
			and tokenIs(t, i + 2, "(")
			and t[i + 3]
			and t[i + 3].k == "str"
			and tokenIs(t, i + 4, ")")
		then
			local method, arg = t[i + 1].v, t[i + 3].v
			if method == "GetService" and object == game then
				object = getService(arg)
			elseif method == "WaitForChild" or method == "FindFirstChild" then
				-- Resolve statically: never yield while looking for missing children.
				object = childOf(object, arg)
			else
				break
			end
			i += 5
		else
			break
		end
		if not object then
			return nil, i
		end
	end
	return object, i
end

local function addDependency(fromNode, targetObject, line, edgeSeen)
	local toNode = nodeByObject[targetObject]
	if not toNode or targetObject.ClassName ~= "ModuleScript" then
		return false
	end
	local group = edgeSeen[fromNode]
	if not group then
		group = {}
		edgeSeen[fromNode] = group
	end
	if group[toNode] then
		return true
	end
	if #graphEdges >= MAX_EDGES then
		return true
	end
	group[toNode] = true
	local edge = { from = fromNode, to = toNode, line = line, cyclic = false }
	graphEdges[#graphEdges + 1] = edge
	fromNode.outgoing[#fromNode.outgoing + 1] = edge
	if fromNode == toNode then
		fromNode.selfRequires = true
	end
	rowsDirty = true
	fromNode.outCount += 1
	toNode.inCount += 1
	fromNode.degree += 1
	toNode.degree += 1
	fromNode.neighbors[toNode] = true
	toNode.neighbors[fromNode] = true
	return true
end

-- Parse only scripts containing possible require calls. Most projects have
-- large UI modules/assets that need no dependency tokenization at all.
local function processSource(node, source, edgeSeen, token, progress)
	if #source > MAX_SOURCE_BYTES then
		warningCount += 1
		node.scanWarning = "Source exceeds 2 MiB limit"
		return true
	end
	if not source:find("require", 1, true) then
		return true
	end

	local t, reason = tokenize(source, token, progress)
	if reason == "cancelled" or token ~= revision then
		return false
	end
	if reason == "budget" then
		node.scanWarning = "Tokenizer exceeded per-script CPU budget"
		skippedBudgetCount += 1
		warningCount += 1
		return true
	end
	if reason == "tokens" then
		node.scanWarning = "Source exceeded 45,000-token limit; analyzed prefix only"
		skippedTokenCount += 1
		warningCount += 1
	end
	if not t then
		return true
	end

	local aliases = {}
	local calls = 0
	local lastYield = os.clock()
	local cpuSeconds = 0
	for i = 1, #t do
		if i % 512 == 0 then
			if token ~= revision then
				return false
			end
			local now = os.clock()
			cpuSeconds += math.max(0, now - lastYield)
			if cpuSeconds > MAX_SOURCE_CPU_SECONDS then
				node.scanWarning = "Dependency resolution exceeded per-script CPU budget"
				skippedBudgetCount += 1
				warningCount += 1
				return true
			end
			task.wait()
			if token ~= revision then
				return false
			end
			lastYield = os.clock()
		end
		local tok = t[i]
		if tok.k == "id" and tok.v == "local" and t[i + 1] and t[i + 1].k == "id" and tokenIs(t, i + 2, "=") then
			local resolved = resolveReference(t, i + 3, node.object, aliases)
			aliases[t[i + 1].v] = resolved
		elseif
			tok.k == "id"
			and tok.v == "require"
			and tokenIs(t, i + 1, "(")
			and not tokenIs(t, i - 1, ".")
			and not tokenIs(t, i - 1, ":")
		then
			calls += 1
			if calls > MAX_RESOLVE_CALLS_PER_SOURCE then
				node.scanWarning = "Dependency call limit reached"
				warningCount += 1
				return true
			end
			local target, ending = resolveReference(t, i + 2, node.object, aliases)
			if not target or not tokenIs(t, ending, ")") then
				unresolvedCount += 1
			elseif not addDependency(node, target, tok.line, edgeSeen) then
				unresolvedCount += 1
			end
		end
	end
	return true
end

-- Iterative Tarjan strongly connected components (O(V + E)). Avoids
-- recursive call stacks for long require chains. Only edges within an SCC
-- are marked red; a single node is cyclic only if it explicitly requires itself.
local function detectCycles(token)
	cycleGroups = {}
	cyclicNodeCount, cyclicEdgeCount = 0, 0
	local nextIndex, steps = 0, 0
	local stack = {}
	local frames = {}
	for _, node in ipairs(graphNodes) do
		node.cycleGroup = nil
		node._tarjanIndex = nil
		node._tarjanLow = nil
		node._tarjanOnStack = nil
	end
	for _, edge in ipairs(graphEdges) do
		edge.cyclic = false
	end

	local function enter(node, parent)
		nextIndex += 1
		node._tarjanIndex = nextIndex
		node._tarjanLow = nextIndex
		node._tarjanOnStack = true
		stack[#stack + 1] = node
		frames[#frames + 1] = { node = node, parent = parent, nextEdge = 1 }
	end

	for _, root in ipairs(graphNodes) do
		if token ~= revision then
			return false
		end
		if root._tarjanIndex == nil then
			enter(root, nil)
			while #frames > 0 do
				steps += 1
				if steps % 1024 == 0 then
					if token ~= revision then
						return false
					end
					task.wait()
					if token ~= revision then
						return false
					end
				end
				local frame = frames[#frames]
				local node = frame.node
				local edge = node.outgoing[frame.nextEdge]
				if edge then
					frame.nextEdge += 1
					local target = edge.to
					if target._tarjanIndex == nil then
						enter(target, node)
					elseif target._tarjanOnStack then
						node._tarjanLow = math.min(node._tarjanLow, target._tarjanIndex)
					end
				else
					table.remove(frames)
					if frame.parent then
						frame.parent._tarjanLow = math.min(frame.parent._tarjanLow, node._tarjanLow)
					end
					if node._tarjanLow == node._tarjanIndex then
						local members = {}
						while true do
							local member = table.remove(stack)
							member._tarjanOnStack = false
							members[#members + 1] = member
							if member == node then
								break
							end
						end
						if #members > 1 or members[1].selfRequires then
							table.sort(members, function(a, b)
								return a.path < b.path
							end)
							local group = { nodes = members, edgeCount = 0 }
							for _, member in ipairs(members) do
								member.cycleGroup = group
							end
							cycleGroups[#cycleGroups + 1] = group
							cyclicNodeCount += #members
						end
					end
				end
			end
		end
	end

	table.sort(cycleGroups, function(a, b)
		if #a.nodes ~= #b.nodes then
			return #a.nodes > #b.nodes
		end
		return a.nodes[1].path < b.nodes[1].path
	end)
	for i, group in ipairs(cycleGroups) do
		group.id = i
		group.label = string.format(
			"#%d: %d script%s (%s)",
			i,
			#group.nodes,
			#group.nodes == 1 and "" or "s",
			group.nodes[1].name
		)
	end
	for _, edge in ipairs(graphEdges) do
		local group = edge.from.cycleGroup
		if group and group == edge.to.cycleGroup then
			edge.cyclic = true
			group.edgeCount += 1
			cyclicEdgeCount += 1
		end
	end
	for _, node in ipairs(graphNodes) do
		node._tarjanIndex = nil
		node._tarjanLow = nil
		node._tarjanOnStack = nil
	end
	return token == revision
end

local function positionNodes()
	-- Stable seeded initial placement; force simulation clusters connected scripts.
	for i, node in ipairs(graphNodes) do
		local angle = i * GOLDEN_ANGLE
		local radius = 38 * math.sqrt(i)
		node.x = math.cos(angle) * radius
		node.y = math.sin(angle) * radius
		node.vx = 0
		node.vy = 0
	end
end

local function physicsStep()
	if
		not graphReady
		or not physicsEnabled
		or simulationLeft <= 0
		or #graphNodes > PHYSICS_MAX_NODES
		or UI.shared().reduceMotion
	then
		if UI.shared().reduceMotion or #graphNodes > PHYSICS_MAX_NODES then
			simulationLeft = 0
		end
		return
	end
	simulationLeft -= 1
	local active = graphNodes
	for _, node in ipairs(active) do
		node.fx = -node.x * 0.003
		node.fy = -node.y * 0.003
	end
	-- Repulsion; bounded to small/medium graphs to protect editor FPS.
	for i = 1, #active - 1 do
		local a = active[i]
		for j = i + 1, #active do
			local b = active[j]
			if isVisibleNode(a) and isVisibleNode(b) then
				local dx, dy = b.x - a.x, b.y - a.y
				local d2 = math.max(120, dx * dx + dy * dy)
				local inv = 1 / math.sqrt(d2)
				local f = 14000 / d2
				local fx, fy = dx * inv * f, dy * inv * f
				a.fx -= fx
				a.fy -= fy
				b.fx += fx
				b.fy += fy
			end
		end
	end
	-- Springs draw linked scripts into the same constellation.
	for _, edge in ipairs(graphEdges) do
		local a, b = edge.from, edge.to
		if a ~= b and isVisibleNode(a) and isVisibleNode(b) then
			local dx, dy = b.x - a.x, b.y - a.y
			local distance = math.max(1, math.sqrt(dx * dx + dy * dy))
			local f = (distance - 126) * 0.022
			local fx, fy = dx / distance * f, dy / distance * f
			a.fx += fx
			a.fy += fy
			b.fx -= fx
			b.fy -= fy
		end
	end
	for _, node in ipairs(active) do
		if node ~= (dragging and dragging.node) and isVisibleNode(node) then
			node.vx = (node.vx + node.fx) * 0.81
			node.vy = (node.vy + node.fy) * 0.81
			node.x += math.clamp(node.vx, -25, 25)
			node.y += math.clamp(node.vy, -25, 25)
		end
	end
	drawDirty = true
end

refreshVisible = function()
	local visibleCount = 0
	for _, node in ipairs(graphNodes) do
		if isVisibleNode(node) then
			visibleCount += 1
		end
		if not isVisibleNode(node) then
			if node.visual then
				node.visual.Visible = false
			end
			if node.caption then
				node.caption.Visible = false
			end
		end
	end
	emptyGraph.Visible = not graphReady or visibleCount == 0
	emptyText.Text = scanInProgress and "Indexing project scripts..."
		or (
			showCyclesOnly and "No circular requires found in indexed scripts."
			or "No scripts match the active filters."
		)
	updateRows()
	updateDetails()
	drawDirty = true
end

fitGraph = function()
	local left, top, right, bottom
	for _, node in ipairs(graphNodes) do
		if isVisibleNode(node) then
			left = left and math.min(left, node.x) or node.x
			top = top and math.min(top, node.y) or node.y
			right = right and math.max(right, node.x) or node.x
			bottom = bottom and math.max(bottom, node.y) or node.y
		end
	end
	if not left then
		zoom = 1
		sceneOffset = Vector2.new(0, 0)
	else
		local s = view.AbsoluteSize
		local w = math.max(1, right - left + 160)
		local h = math.max(1, bottom - top + 150)
		zoom = math.clamp(math.min((s.X - 32) / w, (s.Y - 70) / h), MIN_ZOOM, 1.6)
		sceneOffset = Vector2.new(-(left + right) / 2, -(top + bottom) / 2)
	end
	drawDirty = true
end

focusCycleGroup = function(group)
	if not group or #group.nodes == 0 then
		return
	end
	local left, top, right, bottom
	for _, node in ipairs(group.nodes) do
		left = left and math.min(left, node.x) or node.x
		top = top and math.min(top, node.y) or node.y
		right = right and math.max(right, node.x) or node.x
		bottom = bottom and math.max(bottom, node.y) or node.y
	end
	local s = view.AbsoluteSize
	local w = math.max(1, right - left + 170)
	local h = math.max(1, bottom - top + 170)
	zoom = math.clamp(math.min((s.X - 32) / w, (s.Y - 75) / h), MIN_ZOOM, 1.5)
	sceneOffset = Vector2.new(-(left + right) / 2, -(top + bottom) / 2)
	drawDirty = true
end

focusNode = function(node)
	if not node then
		return
	end
	sceneOffset = Vector2.new(-node.x, -node.y)
	zoom = math.max(zoom, 0.8)
	drawDirty = true
end

drawGraph = function()
	if not panel.Visible or not graphReady then
		return
	end
	local size = view.AbsoluteSize
	if size.X < 5 or size.Y < 5 then
		return
	end
	local highlighted = chosen and chosen.neighbors
	local chosenGroup = chosen and chosen.cycleGroup
	local query = currentQuery
	local rootX = size.X * 0.5 + sceneOffset.X * zoom
	local rootY = size.Y * 0.5 + sceneOffset.Y * zoom
	local zoomRoot = math.sqrt(zoom)
	for _, node in ipairs(graphNodes) do
		local point = Vector2.new(rootX + node.x * zoom, rootY + node.y * zoom)
		node.screenPoint = point
		node.screenVisible = isVisibleNode(node)
		local selected = node == chosen
		local related = (highlighted and highlighted[node]) or (chosenGroup and node.cycleGroup == chosenGroup)
		local match = query ~= "" and string.find(node.searchKey, query, 1, true) ~= nil
		local diameter = math.clamp((9 + math.sqrt(node.degree) * 3) * zoomRoot, 5, 36)
		if selected then
			diameter += 5
		end
		local inView = point.X > -100 and point.X < size.X + 100 and point.Y > -50 and point.Y < size.Y + 50
		local visible = node.screenVisible and inView
		local dot = node.visual
		dot.Visible = visible
		if visible then
			dot.Position = UDim2.fromOffset(point.X, point.Y)
			dot.Size = UDim2.fromOffset(diameter, diameter)
			dot.BackgroundColor3 = node.cycleGroup and colors.error
				or (selected and colors.accent or graphColor(node.kind))
			dot.BackgroundTransparency = chosen and not (selected or related) and 0.56 or 0
		end
		local text = node.caption
		local showLabel = zoom > 0.65 or selected or related or match
		text.Visible = visible and showLabel
		if text.Visible then
			text.Position = UDim2.fromOffset(point.X + diameter / 2 + tokens.space.sm, point.Y - ROW_HEIGHT / 2)
			text.Size = UDim2.fromOffset(math.clamp(#node.name * 7.5 + tokens.space.md, 55, 166), ROW_HEIGHT)
			text.TextColor3 = node.cycleGroup and colors.error or (selected and colors.accent or colors.text)
			text.TextTransparency = chosen and not (selected or related) and 0.62
				or (query ~= "" and not match and 0.55 or 0)
		end
	end
	for _, edge in ipairs(graphEdges) do
		local a, b = edge.from, edge.to
		local drawable = a.screenVisible and b.screenVisible
		local line = edge.visual
		if not line then
			continue
		end
		if drawable and a == b then
			local p = a.screenPoint
			drawable = p.X >= -30 and p.X <= size.X + 30 and p.Y >= -30 and p.Y <= size.Y + 30
			if drawable then
				line.Position = UDim2.fromOffset(p.X + 9, p.Y - 26)
				line.ImageColor3 = colors.error
				line.ImageTransparency = chosen and chosen ~= a and 0.85 or 0
			end
		elseif drawable then
			local p1, p2 = a.screenPoint, b.screenPoint
			local dx, dy = p2.X - p1.X, p2.Y - p1.Y
			local length = math.sqrt(dx * dx + dy * dy)
			drawable = length > 0.5
				and not (
					math.max(p1.X, p2.X) < 0
					or math.min(p1.X, p2.X) > size.X
					or math.max(p1.Y, p2.Y) < 0
					or math.min(p1.Y, p2.Y) > size.Y
				)
			if drawable then
				line.Position = UDim2.fromOffset((p1.X + p2.X) / 2, (p1.Y + p2.Y) / 2)
				local selectedEdge = chosen
					and (
						a == chosen
						or b == chosen
						or (chosenGroup and a.cycleGroup == chosenGroup and b.cycleGroup == chosenGroup)
					)
				line.Size = UDim2.fromOffset(length, edge.cyclic and 2 or (selectedEdge and 2 or 1))
				line.Rotation = math.deg(math.atan2(dy, dx))
				line.BackgroundColor3 = edge.cyclic and colors.error
					or (selectedEdge and colors.accent or colors.subtext)
				line.BackgroundTransparency = chosen and not selectedEdge and 0.91
					or (selectedEdge and 0.08 or (edge.cyclic and 0.10 or 0.66))
			end
		end
		line.Visible = drawable
	end
	drawDirty = false
end

local function buildGraph(documentList, token)
	local edgeSeen = {}
	positionNodes()

	-- Show bubbles BEFORE resolving, rather than an empty graph for the
	-- entire parse. This is especially important for large projects.
	for i, node in ipairs(graphNodes) do
		if token ~= revision then
			return false
		end
		makeNodeVisual(node)
		if i % 24 == 0 then
			setStatus(string.format("Preparing graph... %d / %d", i, #graphNodes))
			task.wait()
			if token ~= revision then
				return false
			end
		end
	end
	graphReady = true
	refreshVisible()
	fitGraph()
	countLabel.Text = string.format("%d scripts  |  resolving links...", #graphNodes)

	local lastProgress = 0
	for i, entry in ipairs(documentList) do
		if token ~= revision then
			return false
		end
		local node = nodeByObject[entry.object]
		if node then
			-- Identify the precise source in the status bar if one is slow.
			setStatus(string.format("Resolving %d / %d  |  %s", i, #documentList, node.name))
			local source = safeSource(entry.object)
			if source then
				local function progress(offset, total)
					local now = os.clock()
					if now - lastProgress >= 0.10 then
						lastProgress = now
						setStatus(
							string.format(
								"Resolving %d / %d  |  %s  |  %d%%",
								i,
								#documentList,
								node.name,
								math.floor(offset / math.max(1, total) * 100)
							)
						)
					end
				end
				local previousEdges = #graphEdges
				-- Luau pcall is yieldable. A malformed/unexpected engine object can
				-- fail independently without aborting the entire graph build.
				local ok, complete = pcall(processSource, node, source, edgeSeen, token, progress)
				if token ~= revision then
					return false
				end
				if not ok then
					warningCount += 1
					node.scanWarning = "Source parsing error: " .. tostring(complete)
					setStatus(string.format("Skipped %s (source parsing error)", node.name))
				elseif not complete then
					return false
				end
				for j = previousEdges + 1, #graphEdges do
					makeEdgeVisual(graphEdges[j])
					if j % 32 == 0 then
						if token ~= revision then
							return false
						end
						task.wait()
						if token ~= revision then
							return false
						end
					end
				end
			else
				node.scanWarning = "Source was unreadable"
				unreadableCount += 1
			end
		end
		completedSources = i
		if i % 4 == 0 then
			countLabel.Text = string.format("%d scripts  |  %d links", #graphNodes, #graphEdges)
			drawDirty = true
			task.wait()
			if token ~= revision then
				return false
			end
		end
		if i % 32 == 0 then
			updateRows()
			updateDetails()
		end
	end

	if token ~= revision then
		return false
	end
	setStatus("Detecting circular requires...")
	if not detectCycles(token) then
		return false
	end
	updateCycleList()
	refreshVisible()
	return true
end

startScan = function()
	if destroyed then
		return
	end
	revision += 1
	local token = revision
	resetVisuals()
	warningCount, scannedCount, unresolvedCount, unreadableCount = 0, 0, 0, 0
	skippedBudgetCount, skippedTokenCount, completedSources = 0, 0, 0
	scanStarted = true
	scanInProgress = true
	cancelButton.Visible = true
	setStatus("Scanning all game descendants...")
	task.spawn(function()
		local ok, err = pcall(function()
			local startedAt = os.clock()
			local stack = { game }
			local inspected = 0
			local lastYield = os.clock()
			local documents = {}
			local exceeded = false
			while #stack > 0 do
				if token ~= revision then
					return
				end
				local object = table.remove(stack)
				inspected += 1
				if object ~= game and isScript(object) then
					scannedCount += 1
					if #graphNodes < MAX_SCRIPTS then
						local node = {
							object = object,
							name = object.Name,
							path = safePath(object),
							kind = object.ClassName,
							outCount = 0,
							inCount = 0,
							degree = 0,
							neighbors = {},
							outgoing = {},
							selfRequires = false,
							cycleGroup = nil,
							x = 0,
							y = 0,
							vx = 0,
							vy = 0,
						}
						node.searchKey = string.lower(node.name .. " " .. node.path)
						graphNodes[#graphNodes + 1] = node
						rowsDirty = true
						nodeByObject[object] = node
						documents[#documents + 1] = { object = object }
					else
						exceeded = true
					end
				end
				local children = safeGetChildren(object)
				if children then
					for i = #children, 1, -1 do
						stack[#stack + 1] = children[i]
					end
				end
				if inspected % 90 == 0 or os.clock() - lastYield >= SCAN_TIME_BUDGET then
					setStatus(string.format("Scanning... %d objects, %d scripts", inspected, scannedCount))
					task.wait()
					lastYield = os.clock()
				end
			end
			if token ~= revision then
				return
			end
			countLabel.Text = string.format("%d scripts discovered", #graphNodes)
			setStatus("Preparing script graph...")
			if not buildGraph(documents, token) then
				return
			end
			if token ~= revision then
				return
			end
			countLabel.Text =
				string.format("%d nodes  |  %d links  |  %d cycles", #graphNodes, #graphEdges, #cycleGroups)
			simulationLeft = physicsEnabled
					and not UI.shared().reduceMotion
					and #graphNodes <= PHYSICS_MAX_NODES
					and PHYSICS_STEPS
				or 0
			fitGraph()
			local suffix = exceeded and "; script cap reached" or ""
			if #graphEdges >= MAX_EDGES then
				suffix ..= "; edge cap reached"
			end
			if #graphNodes > PHYSICS_MAX_NODES then
				suffix ..= "; physics auto-limited"
			end
			if skippedBudgetCount > 0 then
				suffix ..= "; " .. skippedBudgetCount .. " source time-limited"
			end
			if skippedTokenCount > 0 then
				suffix ..= "; " .. skippedTokenCount .. " token-limited"
			end
			local cycleNotice = #cycleGroups > 0
					and string.format("%d circular require groups (%d scripts); ", #cycleGroups, cyclicNodeCount)
				or ""
			setStatus(
				string.format(
					"%s%d scripts; %d links; %d unresolved; %d unreadable; %d limited; %.2fs%s",
					cycleNotice,
					#graphNodes,
					#graphEdges,
					unresolvedCount,
					unreadableCount,
					warningCount,
					os.clock() - startedAt,
					suffix
				),
				(
					#cycleGroups > 0
					or warningCount > 0
					or unreadableCount > 0
					or exceeded
					or #graphEdges >= MAX_EDGES
					or unresolvedCount > 0
				)
						and "warning"
					or nil
			)
		end)
		if token ~= revision or destroyed then
			return
		end
		scanInProgress = false
		cancelButton.Visible = false
		if not ok then
			setStatus("Scan failed: " .. tostring(err), "error")
			scanStarted = false
			resetVisuals()
			emptyText.Text = "Scan failed. Refresh to retry."
		else
			refreshVisible()
		end
	end)
end

cancelScan = function(message)
	if not scanInProgress then
		return
	end
	revision += 1
	scanInProgress = false
	scanStarted = false
	cancelButton.Visible = false
	resetVisuals()
	emptyText.Text = "Scan cancelled. Refresh to retry."
	setStatus(message or "Scan cancelled.")
end

local function nodeAt(localPoint)
	local nearest, best = nil, math.huge
	for _, node in ipairs(graphNodes) do
		if isVisibleNode(node) then
			local point = worldToScreen(node.x, node.y)
			local distance = (point - localPoint).Magnitude
			local radius = math.clamp((9 + math.sqrt(node.degree) * 3) * math.sqrt(zoom), 5, 36) * 0.5
			if distance < radius + 7 and distance < best then
				nearest, best = node, distance
			end
		end
	end
	return nearest
end

local function handlePointerDown(event, processed)
	if destroyed or not panel.Visible or not overlay.Enabled or not graphReady then
		return
	end
	if
		event.UserInputType ~= Enum.UserInputType.MouseButton1
		and event.UserInputType ~= Enum.UserInputType.MouseButton2
	then
		return
	end
	local point = toLocal(eventPosition(event))
	if not nearViewport(point) then
		return
	end
	local node = event.UserInputType == Enum.UserInputType.MouseButton1 and nodeAt(point) or nil
	dragging = {
		node = node,
		start = point,
		previous = point,
		moved = false,
		button = event.UserInputType,
	}
	if node then
		selectNode(node)
	end
end

local function handlePointerMove(event)
	if event.UserInputType == Enum.UserInputType.MouseWheel then
		if not panel.Visible or not overlay.Enabled or not graphReady then
			return
		end
		local mouse = UserInputService:GetMouseLocation()
		local localPoint = toLocal(mouse)
		if not nearViewport(localPoint) then
			return
		end
		local previousZoom = zoom
		local multiplier = event.Position.Z > 0 and 1.15 or (1 / 1.15)
		zoom = math.clamp(zoom * multiplier, MIN_ZOOM, MAX_ZOOM)
		local center = view.AbsoluteSize * 0.5
		local worldUnderCursor = (localPoint - center) / previousZoom - sceneOffset
		sceneOffset = (localPoint - center) / zoom - worldUnderCursor
		drawDirty = true
		return
	end
	if not dragging or event.UserInputType ~= Enum.UserInputType.MouseMovement then
		return
	end
	local point = toLocal(eventPosition(event))
	local change = point - dragging.previous
	if (point - dragging.start).Magnitude > 4 then
		dragging.moved = true
	end
	if dragging.node then
		dragging.node.x += change.X / zoom
		dragging.node.y += change.Y / zoom
		dragging.node.vx = 0
		dragging.node.vy = 0
		simulationLeft = math.max(simulationLeft, 65)
	else
		sceneOffset += change / zoom
	end
	dragging.previous = point
	drawDirty = true
end

local function handlePointerUp(event)
	if not dragging or event.UserInputType ~= dragging.button then
		return
	end
	local gesture = dragging
	dragging = nil
	if gesture.node and not gesture.moved then
		local now = os.clock()
		if lastClickNode == gesture.node and now - lastClickTime < 0.37 then
			openNode(gesture.node)
			lastClickNode = nil
		else
			lastClickNode = gesture.node
			lastClickTime = now
		end
	elseif not gesture.node and not gesture.moved and gesture.button == Enum.UserInputType.MouseButton1 then
		selectNode(nil)
	end
end

connect(UserInputService.InputBegan, handlePointerDown)
connect(UserInputService.InputChanged, handlePointerMove)
connect(UserInputService.InputEnded, handlePointerUp)

connect(UserInputService.InputBegan, function(event, processed)
	if event.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end
	if processed or UserInputService:GetFocusedTextBox() ~= nil then
		return
	end
	if event.KeyCode == Enum.KeyCode.G then
		local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
		local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		if ctrl and shift then
			if panel.Visible then
				disable()
			else
				enable()
			end
		end
	elseif panel.Visible then
		if event.KeyCode == Enum.KeyCode.Escape then
			selectNode(nil)
		elseif event.KeyCode == Enum.KeyCode.F then
			fitGraph()
		elseif event.KeyCode == Enum.KeyCode.Return or event.KeyCode == Enum.KeyCode.KeypadEnter then
			if chosen then
				openNode(chosen)
			end
		end
	end
end)

connect(queryInput:GetPropertyChangedSignal("Text"), function()
	pendingQuery = string.lower(queryInput.Text or "")
	searchDeadline = os.clock() + SEARCH_DELAY
end)
connect(view:GetPropertyChangedSignal("AbsoluteSize"), function()
	drawDirty = true
end)

connect(RunService.Heartbeat, function()
	if destroyed or not panel.Visible then
		return
	end
	local now = os.clock()
	if searchDeadline >= 0 and now >= searchDeadline then
		searchDeadline = -1
		if currentQuery ~= pendingQuery then
			currentQuery = pendingQuery
			updateRows(true)
			drawDirty = true
		end
	end
	if physicsEnabled and simulationLeft > 0 then
		physicsStep()
	end
	if drawDirty and now - lastDraw > (scanInProgress and 1 / 12 or 1 / 30) then
		lastDraw = now
		drawGraph()
	end
end)

-- Observe visibility, including the library close button and topbar routes.
connect(panel:GetPropertyChangedSignal("Visible"), function()
	if destroyed then
		return
	end
	if panel.Visible then
		if not scanStarted then
			startScan()
		end
		drawDirty = true
	else
		dragging = nil
		if scanInProgress then
			cancelScan("Scan cancelled while hidden.")
		end
	end
end)

connections[#connections + 1] = UI.onThemeChanged(function()
	if destroyed then
		return
	end
	updateRowViewport(true)
	updateCycleViewport(true)
	updateDetails()
	setStatus(currentMessage, currentSeverity)
	drawDirty = true
end)

enable = function()
	if destroyed then
		return
	end
	panel.Visible = true
	if not scanStarted then
		startScan()
	end
	drawDirty = true
end

disable = function()
	if destroyed then
		return
	end
	panel.Visible = false
	dragging = nil
	if scanInProgress then
		cancelScan("Scan cancelled while hidden.")
	end
end

local function destroy()
	if destroyed then
		return
	end
	destroyed = true
	revision += 1
	simulationLeft = 0
	scanInProgress = false
	searchDeadline = -1
	dragging, chosen, lastClickNode = nil, nil, nil
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
	UI.forgetButtons(panel)
	graphNodes, graphEdges, nodeByObject = {}, {}, {}
	cycleGroups, filteredRows, sortedNodes = {}, {}, {}
	rowSlots, cycleRowSlots = {}, {}
end
panel.Destroying:Connect(destroy)
updateCycleList()
updateRows()
scriptEmpty.Text = "Refresh to index project scripts."

return {
	window = panel,
	Enable = enable,
	Disable = disable,
	Show = enable,
	Hide = disable,
	Toggle = function()
		if destroyed then
			return
		end
		if panel.Visible then
			disable()
		else
			enable()
		end
	end,
	Cancel = function()
		cancelScan("Scan cancelled.")
	end,
	Destroy = function()
		if not destroyed then
			destroy()
			panel:Destroy()
		end
	end,
	Refresh = function()
		if destroyed then
			return
		end
		UI.refreshWindow("ScriptDependencyExplorer")
		startScan()
	end,
	Fit = function()
		if not destroyed then
			fitGraph()
		end
	end,
	Focus = function(object)
		local node = nodeByObject[object]
		if not node then
			return false
		end
		enable()
		selectNode(node)
		focusNode(node)
		return true
	end,
	GetGraph = function()
		return graphNodes, graphEdges
	end,
	FocusCycle = function(id)
		local group = cycleGroups[tonumber(id) or 0]
		if not group or not group.nodes[1] then
			return false
		end
		enable()
		selectNode(group.nodes[1])
		focusCycleGroup(group)
		return true
	end,
	GetDiagnostics = function()
		local limited = {}
		for _, node in ipairs(graphNodes) do
			if node.scanWarning then
				limited[#limited + 1] = { path = node.path, reason = node.scanWarning }
			end
		end
		local cycles = {}
		for _, group in ipairs(cycleGroups) do
			local members = {}
			for _, node in ipairs(group.nodes) do
				members[#members + 1] = node.path
			end
			cycles[#cycles + 1] = {
				id = group.id,
				size = #members,
				edges = group.edgeCount,
				members = members,
				selfRequire = #members == 1,
			}
		end
		return {
			scanning = scanInProgress,
			found = scannedCount,
			indexed = #graphNodes,
			resolved = completedSources,
			links = #graphEdges,
			unresolved = unresolvedCount,
			unreadable = unreadableCount,
			limited = limited,
			cycleCount = #cycleGroups,
			cyclicScripts = cyclicNodeCount,
			cyclicEdges = cyclicEdgeCount,
			cycles = cycles,
			cyclesMayBeIncomplete = scanInProgress
				or not scanStarted
				or scannedCount > #graphNodes
				or #graphEdges >= MAX_EDGES
				or unreadableCount > 0
				or warningCount > 0
				or unresolvedCount > 0,
		}
	end,
	IsVisible = function()
		return not destroyed and panel.Visible
	end,
}

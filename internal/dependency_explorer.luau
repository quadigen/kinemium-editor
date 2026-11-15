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
local SIDEBAR_WIDTH = 224
local ROW_HEIGHT = 25
local GOLDEN_ANGLE = 2.399963229728653
local MIN_ZOOM, MAX_ZOOM = 0.18, 3.6

local colors = tokens.color
local PALETTE = {
	background = colors.background or colors.surface,
	panel = colors.surface,
	border = colors.border or colors.rowEven,
	muted = colors.subtext,
	text = colors.text,
	edge = colors.subtext,
	Script = colors.accent or colors.text,
	LocalScript = colors.success or colors.hover,
	ModuleScript = colors.info or colors.warning or colors.subtext,
	selected = colors.accent or colors.text,
}

local panel, content = UI.window(
	"ScriptDependencyExplorer",
	UDim2.fromOffset(108, 74),
	UDim2.fromOffset(1020, 655),
	"Script Dependency Explorer",
	{ closable = true }
)
panel.Parent = UI.widgetOverlay()
panel.Visible = false
panel.ClipsDescendants = true
content.BackgroundTransparency = 1
content.ClipsDescendants = true

local function frame(parent, name, properties)
	properties.Name = name
	return UI.create("Frame", properties, parent)
end

local toolbar = frame(content, "Toolbar", {
	Position = UDim2.fromOffset(0, 0),
	Size = UDim2.new(1, 0, 0, 41),
	BorderSizePixel = 0,
	BackgroundColor3 = PALETTE.panel,
})
local sidebar = frame(content, "Sidebar", {
	Position = UDim2.fromOffset(0, 41),
	Size = UDim2.new(0, SIDEBAR_WIDTH, 1, -41),
	BorderSizePixel = 0,
	BackgroundColor3 = PALETTE.panel,
})
local sidebarDivider = frame(content, "SidebarDivider", {
	Position = UDim2.fromOffset(SIDEBAR_WIDTH - 1, 41),
	Size = UDim2.new(0, 1, 1, -41),
	BorderSizePixel = 0,
	BackgroundColor3 = PALETTE.border,
})
local view = frame(content, "GraphView", {
	Position = UDim2.fromOffset(SIDEBAR_WIDTH, 41),
	Size = UDim2.new(1, -SIDEBAR_WIDTH, 1, -41),
	BorderSizePixel = 0,
	BackgroundColor3 = PALETTE.background,
	ClipsDescendants = true,
	Active = true,
})

local edgeLayer = frame(view, "Edges", {
	Size = UDim2.fromScale(1, 1),
	BorderSizePixel = 0,
	BackgroundTransparency = 1,
	ClipsDescendants = true,
})
local nodeLayer = frame(view, "Nodes", {
	Size = UDim2.fromScale(1, 1),
	BorderSizePixel = 0,
	BackgroundTransparency = 1,
	ClipsDescendants = true,
})

local status = UI.label(
	view,
	"Refresh to scan the game's scripts",
	UDim2.new(0, 12, 1, -27),
	UDim2.new(1, -24, 0, 19),
	tokens.type.caption,
	PALETTE.muted
)
status.ZIndex = 12
status.TextTruncate = Enum.TextTruncate.AtEnd

local function label(parent, text, y, size, color)
	return UI.label(
		parent,
		text,
		UDim2.fromOffset(12, y),
		UDim2.new(1, -24, 0, 20),
		size or tokens.type.small,
		color or PALETTE.text
	)
end

label(sidebar, "SEARCH SCRIPTS", 14, tokens.type.caption, PALETTE.muted)
local queryInput = UI.input(
	sidebar,
	"Filter by script name...",
	UDim2.fromOffset(12, 40),
	UDim2.new(1, -24, 0, UI.metrics.inputHeight),
	{ selectAllOnFocus = false }
)
queryInput.Name = "DependencyGraphSearch"

local countLabel = label(sidebar, "No scripts indexed", 85, tokens.type.caption, PALETTE.muted)
local detailsTitle = label(sidebar, "SELECTED SCRIPT", 122, tokens.type.caption, PALETTE.muted)
local selectedName = label(sidebar, "Nothing selected", 146, tokens.type.small, PALETTE.text)
selectedName.TextTruncate = Enum.TextTruncate.AtEnd
local selectedPath = label(sidebar, "Select a bubble to inspect it", 168, tokens.type.caption, PALETTE.muted)
selectedPath.TextWrapped = true
selectedPath.Size = UDim2.new(1, -24, 0, 46)
local selectedStats = label(sidebar, "", 220, tokens.type.caption, PALETTE.muted)
selectedStats.Size = UDim2.new(1, -24, 0, 34)
selectedStats.TextWrapped = true

local listHeader = label(sidebar, "SCRIPTS", 265, tokens.type.caption, PALETTE.muted)
local scriptList = UI.create("ScrollingFrame", {
	Name = "ScriptList",
	Position = UDim2.fromOffset(8, 292),
	Size = UDim2.new(1, -16, 1, -344),
	CanvasSize = UDim2.fromOffset(0, 0),
	BorderSizePixel = 0,
	BackgroundTransparency = 1,
	ScrollBarThickness = 4,
	ScrollBarImageColor3 = colors.subtext,
	VirtualizedScrolling = true,
	ScrollingEnabled = true,
	ClipsDescendants = true,
}, sidebar)

local sidebarFooter =
	label(sidebar, "Drag to pan · Wheel zoom\nDouble-click bubble to open", 0, tokens.type.caption, PALETTE.muted)
sidebarFooter.Position = UDim2.new(0, 12, 1, -43)
sidebarFooter.Size = UDim2.new(1, -24, 0, 36)
sidebarFooter.TextWrapped = true

local revision = 0
local graphNodes = {}
local graphEdges = {}
local nodeByObject = {}
local chosen = nil
local sceneOffset = Vector2.new(0, 0)
local zoom = 1
local showIsolated = true
local physicsEnabled = true
local simulationLeft = 0
local currentMessage = "Ready"
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
local updateDetails
local updateRowViewport

local function setStatus(message)
	currentMessage = message
	status.Text = message
end

local function control(caption, x, width, onClick)
	return UI.button(
		toolbar,
		caption,
		UDim2.fromOffset(x, 7),
		UDim2.fromOffset(width, UI.metrics.inputHeight),
		onClick,
		{ radius = tokens.radius.sm }
	)
end

local startScan
local fitGraph
local refreshVisible
local drawGraph
local focusNode

control("Refresh", 10, 80, function()
	if startScan then
		startScan()
	end
end)
control("Fit graph", 98, 84, function()
	if fitGraph then
		fitGraph()
	end
end)
local physicsControl
_, _, physicsControl = control("Physics", 190, 90, function()
	physicsEnabled = not physicsEnabled
	if physicsEnabled then
		simulationLeft = PHYSICS_STEPS
	end
	UI.setButtonState(physicsControl, physicsEnabled and "selected" or nil)
	setStatus(physicsEnabled and "Physics enabled" or "Physics paused")
	drawDirty = true
end)
UI.setButtonState(physicsControl, "selected")
local isolatedControl
_, _, isolatedControl = control("Isolated", 288, 95, function()
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

local legend = UI.label(
	toolbar,
	"Script  ·  LocalScript  ·  ModuleScript",
	UDim2.new(1, -350, 0, 12),
	UDim2.fromOffset(340, 18),
	tokens.type.caption,
	PALETTE.muted
)
legend.TextXAlignment = Enum.TextXAlignment.Right

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
	for _, node in ipairs(graphNodes) do
		if node.visual then
			node.visual:Destroy()
		end
		if node.caption then
			node.caption:Destroy()
		end
	end
	for _, edge in ipairs(graphEdges) do
		if edge.visual then
			edge.visual:Destroy()
		end
	end
	graphNodes = {}
	graphEdges = {}
	nodeByObject = {}
	chosen = nil
	filteredRows = {}
	for _, slot in ipairs(rowSlots) do
		slot.node = nil
		slot.row.Visible = false
	end
	scriptList.CanvasSize = UDim2.fromOffset(0, 0)
	countLabel.Text = "No scripts indexed"
	updateDetails()
	sceneOffset = Vector2.new(0, 0)
	zoom = 1
	drawDirty = true
end

local function makeNodeVisual(node)
	local dot = UI.create("Frame", {
		Name = "ScriptBubble",
		Size = UDim2.fromOffset(12, 12),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BorderSizePixel = 0,
		BackgroundColor3 = PALETTE[node.kind],
		ZIndex = 5,
	}, nodeLayer)
	UI.corner(dot, 100)
	node.visual = dot
	local caption = UI.label(
		nodeLayer,
		node.name,
		UDim2.fromOffset(0, 0),
		UDim2.fromOffset(100, 20),
		tokens.type.small,
		PALETTE.text
	)
	caption.Name = "BubbleLabel"
	caption.TextTruncate = Enum.TextTruncate.AtEnd
	caption.ZIndex = 6
	node.caption = caption
end

local function makeEdgeVisual(edge)
	edge.visual = UI.create("Frame", {
		Name = "DependencyLink",
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = PALETTE.edge,
		BackgroundTransparency = 0.67,
		ZIndex = 2,
	}, edgeLayer)
end

updateDetails = function()
	if not chosen then
		selectedName.Text = "Nothing selected"
		selectedPath.Text = "Select a bubble to inspect it"
		selectedStats.Text = ""
		return
	end
	selectedName.Text = chosen.name
	selectedPath.Text = chosen.path
	selectedStats.Text =
		string.format("Requires: %d    Required by: %d\nType: %s", chosen.outCount, chosen.inCount, chosen.kind)
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
	drawDirty = true
end

local function openNode(node)
	if not node or not node.object or not node.object.Parent then
		setStatus("Cannot open: script was removed")
		return
	end
	local ok, err = pcall(function()
		viewport.OpenScript(node.object)
	end)
	if not ok then
		setStatus("Unable to open " .. node.name .. ": " .. tostring(err))
	end
end

-- Virtualized sidebar rows share the same editor_UI.button pattern as FIP.
-- Updating the search no longer destroys and recreates hundreds of buttons.
local lastRowStart, lastRowWidth, lastRowHeight = -1, -1, -1

local function createRowSlot()
	local slot = { node = nil }
	local row, _, controller = UI.button(
		scriptList,
		"",
		UDim2.fromOffset(0, 0),
		UDim2.new(1, -5, 0, ROW_HEIGHT),
		nil,
		{ color = colors.rowOdd, hoverColor = colors.hover, radius = 0, border = false }
	)
	row.Name = "DependencyExplorerListRow"
	local caption =
		UI.label(row, "", UDim2.fromOffset(8, 2), UDim2.new(1, -14, 0, ROW_HEIGHT - 4), tokens.type.small, colors.text)
	caption.TextTruncate = Enum.TextTruncate.AtEnd
	row.Activated:Connect(function(_, clickCount)
		local node = slot.node
		if not node then
			return
		end
		selectNode(node)
		if focusNode then
			focusNode(node)
		end
		if clickCount == 2 then
			openNode(node)
		end
	end)
	slot.row = row
	slot.caption = caption
	slot.controller = controller
	row.Visible = false
	return slot
end

updateRowViewport = function(force)
	local height, width = scriptList.AbsoluteSize.Y, scriptList.AbsoluteSize.X
	local first = math.max(1, math.floor(scriptList.CanvasPosition.Y / ROW_HEIGHT) + 1 - 5)
	if not force and first == lastRowStart and width == lastRowWidth and height == lastRowHeight then
		return
	end
	lastRowStart, lastRowWidth, lastRowHeight = first, width, height
	local last = math.min(#filteredRows, first + math.ceil(height / ROW_HEIGHT) + 12)
	local used = 0
	for index = first, last do
		used += 1
		local slot = rowSlots[used]
		if not slot then
			slot = createRowSlot()
			rowSlots[used] = slot
		end
		local node = filteredRows[index]
		slot.node = node
		slot.row.Visible = true
		slot.row.Position = UDim2.fromOffset(0, (index - 1) * ROW_HEIGHT)
		slot.row.BackgroundColor3 = index % 2 == 0 and colors.rowEven or colors.rowOdd
		slot.caption.Text = "●  " .. node.name
		slot.caption.TextColor3 = PALETTE[node.kind]
		UI.setButtonState(slot.controller, node == chosen and "selected" or nil)
	end
	for i = used + 1, #rowSlots do
		rowSlots[i].node = nil
		rowSlots[i].row.Visible = false
	end
end

local function updateRows()
	local query = string.lower(queryInput.Text or "")
	local sorted = table.clone(graphNodes)
	table.sort(sorted, function(a, b)
		if a.degree ~= b.degree then
			return a.degree > b.degree
		end
		return a.path < b.path
	end)
	filteredRows = {}
	for _, node in ipairs(sorted) do
		if isVisibleNode(node) and (query == "" or string.find(node.searchKey, query, 1, true)) then
			filteredRows[#filteredRows + 1] = node
		end
	end
	listHeader.Text = "SCRIPTS  (" .. #filteredRows .. ")"
	scriptList.CanvasSize = UDim2.new(0, 0, 0, #filteredRows * ROW_HEIGHT)
	lastRowStart = -1
	updateRowViewport(true)
end

scriptList:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
	updateRowViewport(false)
end)
scriptList:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	updateRowViewport(true)
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
			end
			-- Identifiers this long are irrelevant to static module paths.
			local name = p - begin <= 512 and source:sub(begin, p - 1) or ""
			result[#result + 1] = { k = "id", v = name, line = line }
		elseif isDigit(c) then
			p += 1
			while isDigit(source:byte(p)) do
				p += 1
			end
		else
			if c == 40 or c == 41 or c == 46 or c == 58 or c == 61 or c == 93 or c == 44 or c == 59 then
				result[#result + 1] = { k = "sym", v = string.char(c), line = line }
			end
			p += 1
		end
	end
	return result, nil
end

local function tokenIs(tokensArray, index, value)
	return tokensArray[index] and tokensArray[index].v == value
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
	if fromNode == toNode then
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
	group[toNode] = true
	if #graphEdges >= MAX_EDGES then
		return true
	end
	local edge = { from = fromNode, to = toNode, line = line }
	graphEdges[#graphEdges + 1] = edge
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
			lastYield = os.clock()
		end
		local tok = t[i]
		if tok.v == "local" and t[i + 1] and t[i + 1].k == "id" and tokenIs(t, i + 2, "=") then
			local resolved = resolveReference(t, i + 3, node.object, aliases)
			if resolved then
				aliases[t[i + 1].v] = resolved
			end
		elseif
			tok.v == "require"
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
	if not graphReady or not physicsEnabled or simulationLeft <= 0 or #graphNodes > PHYSICS_MAX_NODES then
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
		if isVisibleNode(a) and isVisibleNode(b) then
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
	for _, node in ipairs(graphNodes) do
		if node.visual then
			node.visual.Visible = isVisibleNode(node)
		end
		if node.caption then
			node.caption.Visible = isVisibleNode(node)
		end
	end
	updateRows()
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
	local query = string.lower(queryInput.Text or "")
	for _, node in ipairs(graphNodes) do
		local point = worldToScreen(node.x, node.y)
		local selected = node == chosen
		local related = highlighted and highlighted[node]
		local match = query ~= "" and string.find(node.searchKey, query, 1, true) ~= nil
		local diameter = math.clamp((9 + math.sqrt(node.degree) * 3) * math.sqrt(zoom), 5, 36)
		if selected then
			diameter += 5
		end
		local inView = point.X > -100 and point.X < size.X + 100 and point.Y > -50 and point.Y < size.Y + 50
		local visible = isVisibleNode(node) and inView
		local dot = node.visual
		dot.Visible = visible
		if visible then
			dot.Position = UDim2.fromOffset(point.X, point.Y)
			dot.Size = UDim2.fromOffset(diameter, diameter)
			dot.BackgroundColor3 = selected and PALETTE.selected or PALETTE[node.kind]
			dot.BackgroundTransparency = chosen and not (selected or related) and 0.56 or 0
		end
		local text = node.caption
		local showLabel = zoom > 0.65 or selected or related or match
		text.Visible = visible and showLabel
		if text.Visible then
			text.Position = UDim2.fromOffset(point.X + diameter / 2 + 5, point.Y - 10)
			text.Size = UDim2.fromOffset(math.clamp(#node.name * 7.5 + 8, 55, 166), 20)
			text.TextColor3 = selected and PALETTE.selected or PALETTE.text
			text.TextTransparency = chosen and not (selected or related) and 0.62
				or (query ~= "" and not match and 0.55 or 0)
		end
	end
	for _, edge in ipairs(graphEdges) do
		local a, b = edge.from, edge.to
		local drawable = isVisibleNode(a) and isVisibleNode(b)
		local line = edge.visual
		if drawable then
			local p1, p2 = worldToScreen(a.x, a.y), worldToScreen(b.x, b.y)
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
				line.Size = UDim2.fromOffset(length, chosen and (a == chosen or b == chosen) and 2 or 1)
				line.Rotation = math.deg(math.atan2(dy, dx))
				local selectedEdge = chosen and (a == chosen or b == chosen)
				line.BackgroundColor3 = selectedEdge and PALETTE.selected or PALETTE.edge
				line.BackgroundTransparency = chosen and not selectedEdge and 0.91 or (selectedEdge and 0.08 or 0.66)
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
		if i % 50 == 0 then
			setStatus(string.format("Preparing graph... %d / %d", i, #graphNodes))
			task.wait()
		end
	end
	graphReady = true
	refreshVisible()
	fitGraph()
	countLabel.Text = string.format("%d scripts  ·  resolving links...", #graphNodes)

	local lastProgress = 0
	for i, entry in ipairs(documentList) do
		if token ~= revision then
			return false
		end
		local node = nodeByObject[entry.object]
		if node then
			-- Identify the precise source in the status bar if one is slow.
			setStatus(string.format("Resolving %d / %d  ·  %s", i, #documentList, node.name))
			local source = safeSource(entry.object)
			if source then
				local function progress(offset, total)
					local now = os.clock()
					if now - lastProgress >= 0.10 then
						lastProgress = now
						setStatus(
							string.format(
								"Resolving %d / %d  ·  %s  ·  %d%%",
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
				if not ok then
					warningCount += 1
					node.scanWarning = "Source parsing error: " .. tostring(complete)
					setStatus(string.format("Skipped %s (source parsing error)", node.name))
				elseif not complete then
					return false
				end
				for j = previousEdges + 1, #graphEdges do
					makeEdgeVisual(graphEdges[j])
					if j % 70 == 0 then
						if token ~= revision then
							return false
						end
						task.wait()
					end
				end
			else
				node.scanWarning = "Source was unreadable"
				unreadableCount += 1
			end
		end
		completedSources = i
		if i % 4 == 0 then
			countLabel.Text = string.format("%d scripts  ·  %d links", #graphNodes, #graphEdges)
			drawDirty = true
			task.wait()
		end
		if i % 32 == 0 then
			updateRows()
		end
	end

	if token ~= revision then
		return false
	end
	refreshVisible()
	return true
end

startScan = function()
	revision += 1
	local token = revision
	resetVisuals()
	warningCount, scannedCount, unresolvedCount, unreadableCount = 0, 0, 0, 0
	skippedBudgetCount, skippedTokenCount, completedSources = 0, 0, 0
	scanStarted = true
	scanInProgress = true
	setStatus("Scanning all game descendants...")
	task.spawn(function()
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
						x = 0,
						y = 0,
						vx = 0,
						vy = 0,
					}
					node.searchKey = string.lower(node.name .. " " .. node.path)
					graphNodes[#graphNodes + 1] = node
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
		countLabel.Text = string.format("%d nodes  ·  %d links", #graphNodes, #graphEdges)
		simulationLeft = #graphNodes <= PHYSICS_MAX_NODES and PHYSICS_STEPS or 0
		fitGraph()
		local suffix = exceeded and " · script cap reached" or ""
		if #graphEdges >= MAX_EDGES then
			suffix ..= " · edge cap reached"
		end
		if #graphNodes > PHYSICS_MAX_NODES then
			suffix ..= " · physics auto-limited"
		end
		if skippedBudgetCount > 0 then
			suffix ..= " · " .. skippedBudgetCount .. " source time-limited"
		end
		if skippedTokenCount > 0 then
			suffix ..= " · " .. skippedTokenCount .. " token-limited"
		end
		setStatus(
			string.format(
				"%d scripts · %d links · %d unresolved · %d unreadable · %d limited · %.2fs%s",
				#graphNodes,
				#graphEdges,
				unresolvedCount,
				unreadableCount,
				warningCount,
				os.clock() - startedAt,
				suffix
			)
		)
		scanInProgress = false
	end)
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
	if not panel.Visible or not UI.widgetOverlay().Enabled then
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
		if not panel.Visible then
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

UserInputService.InputBegan:Connect(handlePointerDown)
UserInputService.InputChanged:Connect(handlePointerMove)
UserInputService.InputEnded:Connect(handlePointerUp)

UserInputService.InputBegan:Connect(function(event, processed)
	if event.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end
	if event.KeyCode == Enum.KeyCode.G then
		local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
		local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		if ctrl and shift then
			panel.Visible = not panel.Visible
			if panel.Visible and not scanStarted then
				startScan()
			end
			drawDirty = true
		end
	elseif panel.Visible and not processed and UserInputService:GetFocusedTextBox() == nil then
		if event.KeyCode == Enum.KeyCode.Escape then
			selectNode(nil)
		elseif event.KeyCode == Enum.KeyCode.F then
			fitGraph()
		elseif event.KeyCode == Enum.KeyCode.Return or event.KeyCode == Enum.KeyCode.KeypadEnter then
			openNode(chosen)
		end
	end
end)

queryInput.TextChanged:Connect(function()
	updateRows()
	drawDirty = true
end)

view:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	drawDirty = true
end)

RunService.Heartbeat:Connect(function()
	if not panel.Visible then
		return
	end
	if physicsEnabled and simulationLeft > 0 then
		physicsStep()
	end
	if drawDirty and os.clock() - lastDraw > (scanInProgress and (1 / 12) or (1 / 30)) then
		lastDraw = os.clock()
		drawGraph()
	end
end)

local function enable()
	panel.Visible = true
	if not scanStarted then
		startScan()
	end
	drawDirty = true
end
local function disable()
	panel.Visible = false
	dragging = nil
end

return {
	Enable = enable,
	Disable = disable,
	Show = enable,
	Hide = disable,
	Toggle = function()
		if panel.Visible then
			disable()
		else
			enable()
		end
	end,
	Refresh = function()
		UI.refreshWindow("ScriptDependencyExplorer")
		startScan()
	end,
	Fit = function()
		fitGraph()
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
	GetDiagnostics = function()
		local limited = {}
		for _, node in ipairs(graphNodes) do
			if node.scanWarning then
				limited[#limited + 1] = { path = node.path, reason = node.scanWarning }
			end
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
		}
	end,
	IsVisible = function()
		return panel.Visible
	end,
}

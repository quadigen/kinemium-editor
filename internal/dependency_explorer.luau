if IsServer or IsClient or IsPlaytest then
	return nil
end

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")
local UI = require("@internal/editor_ui")
local viewport = require("@internal/viewport")
local tokens = UI.tokens

local MAX_SCRIPTS = 500
local MAX_EDGES = 1800
local MAX_SOURCE_BYTES = 2 * 1024 * 1024
local MAX_TOKENS_PER_SOURCE = 130000
local PHYSICS_MAX_NODES = 260
local PHYSICS_STEPS = 240
local SCAN_TIME_BUDGET = 0.004
local SIDEBAR_WIDTH = 224
local ROW_HEIGHT = 25
local GOLDEN_ANGLE = 2.399963229728653
local MIN_ZOOM, MAX_ZOOM = 0.18, 3.6

local PALETTE = {
	background = Color3.fromRGB(17, 19, 25),
	panel = Color3.fromRGB(23, 26, 33),
	border = Color3.fromRGB(43, 48, 58),
	muted = Color3.fromRGB(146, 153, 169),
	text = Color3.fromRGB(225, 229, 239),
	edge = Color3.fromRGB(105, 119, 140),
	Script = Color3.fromRGB(113, 158, 249),
	LocalScript = Color3.fromRGB(95, 197, 180),
	ModuleScript = Color3.fromRGB(171, 145, 242),
	selected = Color3.fromRGB(245, 206, 126),
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
	ScrollBarThickness = 3,
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
local dragging = nil
local lastClickNode = nil
local lastClickTime = 0
local createdRows = {}
local scanStarted = false
local graphReady = false

local function setStatus(message)
	currentMessage = message
	status.Text = message
end

local function control(caption, x, width, onClick)
	return UI.button(
		toolbar,
		caption,
		UDim2.fromOffset(x, 7),
		UDim2.fromOffset(width, 27),
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
control("Toggle physics", 190, 111, function()
	physicsEnabled = not physicsEnabled
	if physicsEnabled then
		simulationLeft = PHYSICS_STEPS
	end
	setStatus(physicsEnabled and "Physics enabled" or "Physics paused")
	drawDirty = true
end)
control("Toggle isolated", 309, 122, function()
	showIsolated = not showIsolated
	if refreshVisible then
		refreshVisible()
	end
	if fitGraph then
		fitGraph()
	end
end)

local legend = UI.label(
	toolbar,
	"● Script     ● LocalScript     ● ModuleScript",
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
	for _, row in ipairs(createdRows) do
		row:Destroy()
	end
	createdRows = {}
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
	local caption = UI.create("TextLabel", {
		Name = "BubbleLabel",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = node.name,
		TextColor3 = PALETTE.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Font = Enum.Font.Code,
		TextSize = 12,
		ZIndex = 6,
	}, nodeLayer)
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

local function updateDetails()
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

local function clearRows()
	for _, row in ipairs(createdRows) do
		row:Destroy()
	end
	createdRows = {}
end

local function updateRows()
	clearRows()
	local query = string.lower(queryInput.Text or "")
	local sorted = table.clone(graphNodes)
	table.sort(sorted, function(a, b)
		if a.degree ~= b.degree then
			return a.degree > b.degree
		end
		return a.path < b.path
	end)
	local shown, matches = 0, 0
	for _, node in ipairs(sorted) do
		if
			isVisibleNode(node)
			and (query == "" or string.find(string.lower(node.name .. " " .. node.path), query, 1, true))
		then
			matches += 1
			if shown < 150 then
				shown += 1
				local item = UI.create("TextButton", {
					Name = "ScriptListItem",
					Position = UDim2.fromOffset(0, (shown - 1) * ROW_HEIGHT),
					Size = UDim2.new(1, -5, 0, ROW_HEIGHT),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Text = "  ●  " .. node.name,
					Font = Enum.Font.Code,
					TextSize = 12,
					TextTruncate = Enum.TextTruncate.AtEnd,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextColor3 = PALETTE[node.kind],
					AutoButtonColor = false,
				}, scriptList)
				item.Activated:Connect(function(_, clickCount)
					selectNode(node)
					if focusNode then
						focusNode(node)
					end
					if clickCount == 2 then
						openNode(node)
					end
				end)
				createdRows[#createdRows + 1] = item
			end
		end
	end
	listHeader.Text = "SCRIPTS  (" .. matches .. (matches > shown and "; first 150" or "") .. ")"
	scriptList.CanvasSize = UDim2.new(0, 0, 0, shown * ROW_HEIGHT)
end

-- Tokenizer: ignores comments and string contents, retaining quoted strings
-- as tokens so a safe subset of static require() expressions can be resolved.
local function isLetter(c)
	return c ~= nil and ((c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95)
end
local function isDigit(c)
	return c ~= nil and c >= 48 and c <= 57
end
local function countNewlines(source, first, last)
	local count = 0
	local p = first
	while p <= last do
		local at = source:find("\n", p, true)
		if not at or at > last then
			break
		end
		count += 1
		p = at + 1
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

local function tokenize(source)
	local result = {}
	local length, p, line = #source, 1, 1
	local lastYieldPosition = 1
	while p <= length and #result < MAX_TOKENS_PER_SOURCE do
		if p - lastYieldPosition > 32768 then
			task.wait()
			lastYieldPosition = p
		end
		local c, nextC = source:byte(p), source:byte(p + 1)
		if c == 10 then
			line += 1
			p += 1
		elseif c == 45 and nextC == 45 then
			local bodyStart, _, closeFinish = longBracket(source, p + 2, length)
			if bodyStart then
				line += countNewlines(source, p, closeFinish)
				p = closeFinish + 1
			else
				local ending = source:find("\n", p + 2, true)
				p = ending or (length + 1)
			end
		elseif c == 34 or c == 39 then
			local startLine = line
			p += 1
			local closed = false
			local parts = {}
			local partStart = p
			while p <= length do
				local k = source:byte(p)
				if k == c then
					parts[#parts + 1] = source:sub(partStart, p - 1)
					p += 1
					closed = true
					break
				elseif k == 92 and p < length then
					parts[#parts + 1] = source:sub(partStart, p - 1)
					local escape = source:sub(p + 1, p + 1)
					local mapped = ({ n = "\n", r = "\r", t = "\t" })[escape]
					parts[#parts + 1] = mapped or escape
					p += 2
					partStart = p
				elseif k == 10 then
					line += 1
					p += 1
				else
					p += 1
				end
			end
			if not closed then
				parts[#parts + 1] = source:sub(partStart, length)
			end
			result[#result + 1] = { k = "str", v = table.concat(parts), line = startLine }
		elseif c == 91 then
			local bodyStart, closeStart, closeFinish = longBracket(source, p, length)
			if bodyStart then
				local startLine = line
				local value = closeStart and source:sub(bodyStart, closeStart - 1) or ""
				result[#result + 1] = { k = "str", v = value, line = startLine }
				line += countNewlines(source, p, closeFinish)
				p = closeFinish + 1
			else
				result[#result + 1] = { k = "sym", v = "[", line = line }
				p += 1
			end
		elseif isLetter(c) then
			local start = p
			p += 1
			while isLetter(source:byte(p)) or isDigit(source:byte(p)) do
				p += 1
			end
			result[#result + 1] = { k = "id", v = source:sub(start, p - 1), line = line }
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
	return result, #result >= MAX_TOKENS_PER_SOURCE
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
	while t[i] do
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

local function processSource(node, source, edgeSeen, token)
	if #source > MAX_SOURCE_BYTES then
		warningCount += 1
		return
	end
	local t, overLimit = tokenize(source)
	if token ~= revision then
		return false
	end
	if overLimit then
		warningCount += 1
	end
	local aliases = {}
	for i = 1, #t do
		if i % 4096 == 0 then
			if token ~= revision then
				return false
			end
			task.wait()
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
			local target, ending = resolveReference(t, i + 2, node.object, aliases)
			if not target or not tokenIs(t, ending, ")") then
				unresolvedCount += 1
			elseif not addDependency(node, target, tok.line, edgeSeen) then
				-- Valid static expression, but not an indexed ModuleScript.
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
		local match = query ~= "" and string.find(string.lower(node.name .. " " .. node.path), query, 1, true) ~= nil
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
	for i, entry in ipairs(documentList) do
		if token ~= revision then
			return false
		end
		local node = nodeByObject[entry.object]
		if node then
			local source = safeSource(entry.object)
			if source then
				if not processSource(node, source, edgeSeen, token) then
					return false
				end
			else
				unreadableCount += 1
			end
		end
		if i % 8 == 0 then
			setStatus(string.format("Resolving dependencies... %d / %d", i, #documentList))
			task.wait()
		end
	end
	if token ~= revision then
		return false
	end
	positionNodes()
	for i, edge in ipairs(graphEdges) do
		makeEdgeVisual(edge)
		if i % 120 == 0 then
			task.wait()
			if token ~= revision then
				return false
			end
		end
	end
	for i, node in ipairs(graphNodes) do
		makeNodeVisual(node)
		if i % 120 == 0 then
			task.wait()
			if token ~= revision then
				return false
			end
		end
	end
	graphReady = true
	refreshVisible()
	return true
end

startScan = function()
	revision += 1
	local token = revision
	resetVisuals()
	warningCount, scannedCount, unresolvedCount, unreadableCount = 0, 0, 0, 0
	scanStarted = true
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
		setStatus("Resolving static require() references...")
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
		setStatus(
			string.format(
				"%d scripts · %d links · %d unresolved · %d unreadable · %d oversized · %.2fs%s",
				#graphNodes,
				#graphEdges,
				unresolvedCount,
				unreadableCount,
				warningCount,
				os.clock() - startedAt,
				suffix
			)
		)
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
	if drawDirty and os.clock() - lastDraw > (1 / 30) then
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
	IsVisible = function()
		return panel.Visible
	end,
}

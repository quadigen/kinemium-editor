if IsServer or IsClient or IsPlaytest then
	return
end

local UserInputService = game:GetService("UserInputService")
local Selection = game:GetService("Selection")
local UI = require("@internal/editor_ui")
local colors = UI.tokens.color

local function isWord(char)
	return char ~= nil
		and ((char >= 48 and char <= 57) or (char >= 65 and char <= 90) or (char >= 97 and char <= 122) or char == 95)
end

local function asciiLower(value)
	if value >= 65 and value <= 90 then
		return value + 32
	end
	return value
end

local function asciiUpper(value)
	if value >= 97 and value <= 122 then
		return value - 32
	end
	return value
end

local function matchesCategory(category, char)
	if category == "d" then
		return char >= 48 and char <= 57
	end
	if category == "w" then
		return isWord(char)
	end
	if category == "s" then
		return char == 9 or char == 10 or char == 11 or char == 12 or char == 13 or char == 32
	end
	return false
end

local function escapedChar(char)
	if char == "n" then
		return 10
	end
	if char == "r" then
		return 13
	end
	if char == "t" then
		return 9
	end
	if char == "0" then
		return 0
	end
	return string.byte(char)
end

local function compileRegex(pattern, ignoreCase)
	local pos, count, length = 1, 0, #pattern
	local parseAlternation

	local function errorAt(message)
		error(message .. " (at character " .. tostring(pos) .. ")", 0)
	end

	local function node(kind, data)
		count += 1
		if count > 300 then
			errorAt("Regular expression is too complex")
		end
		data = data or {}
		data.kind = kind
		return data
	end

	local function take()
		local char = pattern:sub(pos, pos)
		pos += 1
		return char
	end

	local function peek()
		return pattern:sub(pos, pos)
	end

	local function parseClass()
		local inverted = false
		if peek() == "^" then
			inverted = true
			take()
		end

		local parts = {}
		local first = true
		local closed = false

		local function getItem()
			if pos > length then
				errorAt("Unclosed character class")
			end
			local char = take()
			if char ~= "\\" then
				return { type = "char", value = string.byte(char) }
			end
			if pos > length then
				errorAt("Incomplete escape")
			end
			char = take()
			local lower = char:lower()
			if lower == "d" or lower == "w" or lower == "s" then
				return { type = "category", value = lower, inverted = char ~= lower }
			end
			if char:match("%a") and char ~= "t" and char ~= "n" and char ~= "r" and char ~= "0" then
				errorAt("Unsupported escape \\" .. char)
			end
			return { type = "char", value = escapedChar(char) }
		end

		while pos <= length do
			if peek() == "]" and not first then
				take()
				closed = true
				break
			end
			first = false
			local startItem = getItem()
			if startItem.type == "char" and peek() == "-" and pos < length and pattern:sub(pos + 1, pos + 1) ~= "]" then
				take()
				local endItem = getItem()
				if endItem.type ~= "char" or startItem.value > endItem.value then
					errorAt("Invalid character range")
				end
				parts[#parts + 1] = { type = "range", first = startItem.value, last = endItem.value }
			else
				parts[#parts + 1] = startItem
			end
		end
		if not closed then
			errorAt("Unclosed character class")
		end
		return node("class", { parts = parts, inverted = inverted })
	end

	local function parseAtom()
		local char = take()
		if char == "" then
			errorAt("Unexpected end of regex")
		end
		if char == "(" then
			if peek() == "?" then
				take()
				if take() ~= ":" then
					errorAt("Only (?:...) groups are supported after (? ")
				end
			end
			local inner = parseAlternation()
			if take() ~= ")" then
				errorAt("Unclosed group")
			end
			return inner
		elseif char == "[" then
			return parseClass()
		elseif char == "." then
			return node("any")
		elseif char == "^" then
			return node("start")
		elseif char == "$" then
			return node("end")
		elseif char == "\\" then
			if pos > length then
				errorAt("Incomplete escape")
			end
			char = take()
			local lower = char:lower()
			if lower == "d" or lower == "w" or lower == "s" then
				return node("category", { category = lower, inverted = lower ~= char })
			elseif char == "b" or char == "B" then
				return node("boundary", { inverted = char == "B" })
			elseif char:match("%a") and char ~= "t" and char ~= "n" and char ~= "r" then
				errorAt("Unsupported escape \\" .. char)
			end
			return node("char", { value = escapedChar(char) })
		elseif char == ")" or char == "|" or char == "*" or char == "+" or char == "?" or char == "{" then
			errorAt("Unexpected token " .. char)
		end
		return node("char", { value = string.byte(char) })
	end

	local function parseNumber()
		local start = pos
		while peek():match("%d") do
			take()
		end
		if start == pos then
			return nil
		end
		local value = tonumber(pattern:sub(start, pos - 1))
		if value > 128 then
			errorAt("Repeat counts must be at most 128")
		end
		return value
	end

	local function parseRepeat()
		local atom = parseAtom()
		local char = peek()
		if char == "*" or char == "+" or char == "?" then
			take()
			if char == "*" then
				atom = node("repeat", { item = atom, min = 0 })
			elseif char == "+" then
				atom = node("repeat", { item = atom, min = 1 })
			else
				atom = node("repeat", { item = atom, min = 0, max = 1 })
			end
		elseif char == "{" then
			take()
			local minimum = parseNumber()
			if minimum == nil then
				errorAt("Expected a repeat count")
			end
			local maximum = minimum
			if peek() == "," then
				take()
				maximum = parseNumber()
				if maximum ~= nil and maximum < minimum then
					errorAt("Invalid repeat range")
				end
			end
			if take() ~= "}" then
				errorAt("Unclosed repeat")
			end
			atom = node("repeat", { item = atom, min = minimum, max = maximum })
		end
		if peek() == "*" or peek() == "+" or peek() == "?" or peek() == "{" then
			errorAt("Nested quantifiers are unsupported")
		end
		return atom
	end

	local function parseSequence()
		local entries = {}
		while pos <= length and peek() ~= "|" and peek() ~= ")" do
			entries[#entries + 1] = parseRepeat()
		end
		if #entries == 0 then
			return node("empty")
		end
		if #entries == 1 then
			return entries[1]
		end
		return node("sequence", { entries = entries })
	end

	parseAlternation = function()
		local alternatives = { parseSequence() }
		while peek() == "|" do
			take()
			alternatives[#alternatives + 1] = parseSequence()
		end
		if #alternatives == 1 then
			return alternatives[1]
		end
		return node("alternation", { alternatives = alternatives })
	end

	local root = parseAlternation()
	if pos <= length then
		errorAt("Unexpected closing bracket or group")
	end

	local states = {}
	local function state(kind, properties)
		if #states >= 3000 then
			error("Regex produces too many states", 0)
		end
		properties = properties or {}
		properties.kind = kind
		states[#states + 1] = properties
		return #states
	end
	local function patch(edges, destination)
		for _, edge in ipairs(edges) do
			states[edge[1]][edge[2]] = destination
		end
	end
	local function combine(a, b)
		for _, edge in ipairs(b) do
			a[#a + 1] = edge
		end
		return a
	end

	local emit
	emit = function(ast)
		local kind = ast.kind
		if kind == "sequence" then
			local result = nil
			for _, item in ipairs(ast.entries) do
				local nextPart = emit(item)
				if result then
					patch(result.edges, nextPart.start)
					result.edges = nextPart.edges
				else
					result = nextPart
				end
			end
			return result
		elseif kind == "alternation" then
			local result = emit(ast.alternatives[1])
			for i = 2, #ast.alternatives do
				local other = emit(ast.alternatives[i])
				local split = state("split", { out1 = result.start, out2 = other.start })
				result = { start = split, edges = combine(result.edges, other.edges) }
			end
			return result
		elseif kind == "repeat" then
			local result = nil
			local function append(fragment)
				if result then
					patch(result.edges, fragment.start)
					result.edges = fragment.edges
				else
					result = fragment
				end
			end
			for _ = 1, ast.min do
				append(emit(ast.item))
			end
			if ast.max == nil then
				local inner = emit(ast.item)
				local split = state("split", { out1 = inner.start })
				patch(inner.edges, split)
				append({ start = split, edges = { { split, "out2" } } })
			else
				for _ = ast.min + 1, ast.max do
					local inner = emit(ast.item)
					local split = state("split", { out1 = inner.start })
					append({ start = split, edges = combine(inner.edges, { { split, "out2" } }) })
				end
			end
			if not result then
				local empty = state("jump")
				result = { start = empty, edges = { { empty, "out1" } } }
			end
			return result
		else
			local id = state(kind, {
				value = ast.value,
				parts = ast.parts,
				inverted = ast.inverted,
				category = ast.category,
			})
			return { start = id, edges = { { id, "out1" } } }
		end
	end

	local fragment = emit(root)
	local endState = state("match")
	patch(fragment.edges, endState)

	local function charMatches(entry, byte)
		local kind = entry.kind
		if kind == "any" then
			return true
		end
		if kind == "char" then
			return byte == entry.value or (ignoreCase and asciiLower(byte) == asciiLower(entry.value))
		elseif kind == "category" then
			local yes = matchesCategory(entry.category, byte)
			return entry.inverted and not yes or (not entry.inverted and yes)
		elseif kind == "class" then
			local yes = false
			for _, part in ipairs(entry.parts) do
				local hit = false
				if part.type == "char" then
					hit = byte == part.value or (ignoreCase and asciiLower(byte) == asciiLower(part.value))
				elseif part.type == "range" then
					hit = byte >= part.first and byte <= part.last
					if not hit and ignoreCase then
						local lower, upper = asciiLower(byte), asciiUpper(byte)
						hit = (lower >= part.first and lower <= part.last)
							or (upper >= part.first and upper <= part.last)
					end
				elseif part.type == "category" then
					hit = matchesCategory(part.value, byte)
					if part.inverted then
						hit = not hit
					end
				end
				if hit then
					yes = true
					break
				end
			end
			return entry.inverted and not yes or (not entry.inverted and yes)
		end
		return false
	end

	local function findFrom(line, firstPos, budget)
		local lineLength = #line
		local active = {}
		local bestStart, bestEnd
		local work = 0

		local function closure(target, origins, list, id, origin, position)
			if id == nil then
				return
			end
			local old = origins[id]
			if old and old <= origin then
				return
			end
			origins[id] = origin
			work += 1
			if work > budget then
				error("regex-budget", 0)
			end

			local current = states[id]
			local kind = current.kind
			if kind == "split" then
				closure(target, origins, list, current.out1, origin, position)
				closure(target, origins, list, current.out2, origin, position)
			elseif kind == "jump" or kind == "empty" then
				closure(target, origins, list, current.out1, origin, position)
			elseif kind == "start" then
				if position == 1 then
					closure(target, origins, list, current.out1, origin, position)
				end
			elseif kind == "end" then
				if position == lineLength + 1 then
					closure(target, origins, list, current.out1, origin, position)
				end
			elseif kind == "boundary" then
				local before = position > 1 and isWord(line:byte(position - 1))
				local after = position <= lineLength and isWord(line:byte(position))
				local boundary = before ~= after
				if boundary ~= current.inverted then
					closure(target, origins, list, current.out1, origin, position)
				end
			else
				if old == nil then
					list[#list + 1] = id
				end
			end
		end

		local origins = {}
		for position = firstPos, lineLength + 1 do
			if not bestStart then
				closure(active, origins, active, fragment.start, position, position)
			end

			for _, id in ipairs(active) do
				if states[id].kind == "match" then
					local origin = origins[id]
					if not bestStart or origin < bestStart or (origin == bestStart and position - 1 > bestEnd) then
						bestStart, bestEnd = origin, position - 1
					end
				end
			end

			if bestStart then
				local canExtend = false
				for _, id in ipairs(active) do
					if states[id].kind ~= "match" and origins[id] <= bestStart then
						canExtend = true
						break
					end
				end
				if not canExtend then
					return bestStart, bestEnd
				end
			end

			if position <= lineLength then
				local nextActive, nextOrigins = {}, {}
				local byte = line:byte(position)
				for _, id in ipairs(active) do
					local entry = states[id]
					if entry.out1 and charMatches(entry, byte) then
						closure(nextActive, nextOrigins, nextActive, entry.out1, origins[id], position + 1)
					end
				end
				active, origins = nextActive, nextOrigins
			end
		end
		return bestStart, bestEnd
	end

	return function(line, from)
		return findFrom(line, from, 200000)
	end
end

local function makeFinder(query, regex, matchCase, wholeWord)
	local regexFinder
	if regex then
		local ok, result = pcall(compileRegex, query, not matchCase)
		if not ok then
			return nil, tostring(result)
		end
		regexFinder = result
	end

	local literal = matchCase and query or string.lower(query)
	return function(line, from)
		if from > #line + 1 then
			return nil
		end
		local lower = not matchCase and not regex and string.lower(line) or nil
		local offset = from
		while offset <= #line + 1 do
			local startPos, endPos
			if regexFinder then
				startPos, endPos = regexFinder(line, offset)
			else
				startPos, endPos = string.find(lower or line, literal, offset, true)
			end
			if not startPos then
				return nil
			end
			if not wholeWord or (not isWord(line:byte(startPos - 1)) and not isWord(line:byte(endPos + 1))) then
				return startPos, endPos
			end
			offset = startPos + 1
		end
	end
end

local viewport = require("@internal/viewport")
local tokens = UI.tokens

local ROW_HEIGHT = UI.metrics.treeRow
local MAX_MATCHES = 25000
local MAX_PER_SOURCE = 4000
local MAX_REGEX_LINE = 60000
local VIEW_OVERSCAN = 6
local SEARCH_DEBOUNCE = 0.12
local SCAN_FRAME_BUDGET = 0.004

local scriptClasses = { Script = true, LocalScript = true, ModuleScript = true }
local classes = { Script = true, LocalScript = true, ModuleScript = true }

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

local panel, content = UI.window(
	"FindInPlace",
	UDim2.fromOffset(120, 120),
	UDim2.fromOffset(380, 540),
	"Find in Place",
	{ closable = true }
)

local overlay = UI.widgetOverlay()
panel.Parent = overlay
panel.Visible = false
panel.ClipsDescendants = true
-- UI.window owns the matching active title tab/content fill. Leave it opaque.
content.ClipsDescendants = true

local inset = UI.metrics.panelInset
local inputHeight = UI.metrics.inputHeight
local gap = tokens.space.xs
local statusHeight = ROW_HEIGHT
local buttonWidth = 52
local filterWidth = inputHeight + 4
local connections = {}
local destroyed = false
local function connect(signal, callback)
	local connection = signal:Connect(callback)
	connections[#connections + 1] = connection
	return connection
end

local regex, matchCase, wholeWord, selectedOnly = false, false, false, false
local includePath, excludePath = "", ""
local requestSearch, runSearch, cancelSearch, closeFilters, openFilters
local filterOpen = false
local popup, backdrop, popupLayer
local popupConnections = {}
local filterRecord, filterIcon
local jobActive = false

-- A trailing filter icon is part of the search row. It does not overlay the
-- editable text, so long queries cannot run underneath the hit target.
local searchRow =
	UI.frame(content, UDim2.fromOffset(inset, inset), UDim2.new(1, -inset * 2, 0, inputHeight), colors.panel)
searchRow.BackgroundTransparency = 1
local input = UI.input(
	searchRow,
	"Search all code...",
	UDim2.fromOffset(0, 0),
	UDim2.new(1, -(buttonWidth + filterWidth + gap * 2), 1, 0),
	{ selectAllOnFocus = false, animate = not UI.shared().reduceMotion }
)
input.Name = "FindInPlaceQuery"

local filterButton
filterButton, filterRecord, filterIcon = UI.iconButton(
	searchRow,
	"builtin://global-icons/filter.svg",
	UDim2.new(1, -(buttonWidth + filterWidth + gap), 0, 0),
	UDim2.fromOffset(filterWidth, inputHeight),
	function()
		if filterOpen then
			closeFilters()
		else
			openFilters()
		end
	end,
	{ color = colors.input, hoverColor = colors.hover, iconSize = 14, radius = tokens.radius.sm }
)
UI.tooltip(filterButton, "Search filters and options", { placement = "below" })

local queryButton, queryCaption = UI.button(
	searchRow,
	"Find",
	UDim2.new(1, -buttonWidth, 0, 0),
	UDim2.fromOffset(buttonWidth, inputHeight),
	function()
		if jobActive then
			cancelSearch()
		elseif runSearch then
			runSearch()
		end
	end,
	{ radius = tokens.radius.sm }
)

local function updateFilterState()
	local active = regex
		or matchCase
		or wholeWord
		or selectedOnly
		or includePath ~= ""
		or excludePath ~= ""
		or not classes.Script
		or not classes.LocalScript
		or not classes.ModuleScript
	UI.setButtonState(filterRecord, (filterOpen or active) and "selected" or nil)
	filterIcon.ImageColor3 = (filterOpen or active) and colors.text or colors.subtext
end

local function changeFilters()
	updateFilterState()
	if requestSearch then
		requestSearch()
	end
end

local function popupConnect(signal, callback)
	local connection = signal:Connect(callback)
	popupConnections[#popupConnections + 1] = connection
	return connection
end

closeFilters = function()
	if not filterOpen then
		return
	end
	filterOpen = false
	for _, connection in ipairs(popupConnections) do
		connection:Disconnect()
	end
	table.clear(popupConnections)
	if popupLayer then
		UI.forgetButtons(popupLayer)
		popupLayer:Destroy()
	end
	popup, backdrop, popupLayer = nil, nil, nil
	if not destroyed then
		updateFilterState()
	end
end

-- This is a compound filter popup (not a single-choice UI.dropdown).
-- Use the documented popup pattern with an outside-click backdrop; the
-- result tree keeps its original bounds and scroll position when it opens.
openFilters = function()
	if filterOpen or destroyed or not panel.Visible then
		return
	end
	filterOpen = true
	updateFilterState()
	local menus = UI.contextMenuOverlay()
	local z = 100050
	popupLayer = UI.frame(menus, UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), colors.panel)
	popupLayer.Name = "FindInPlaceFilterLayer"
	popupLayer.BackgroundTransparency = 1
	popupLayer.ZIndex = z - 1
	backdrop = UI.button(popupLayer, "", UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), closeFilters, {
		color = colors.panel,
		hoverColor = colors.panel,
		pressedColor = colors.panel,
		bgTransparency = 1,
		radius = 0,
		border = false,
	})
	backdrop.ZIndex = z

	local margin = tokens.space.sm
	local width, height = 320, 348
	local anchor = filterButton.AbsolutePosition
	local screenW, screenH =
		panel.AbsolutePosition.X + panel.AbsoluteSize.X + margin,
		panel.AbsolutePosition.Y + panel.AbsoluteSize.Y + height + margin
	local ok, dimensions, second = pcall(function()
		return workspace:GetWindowDimensions()
	end)
	if ok and dimensions then
		local valid, x, y = pcall(function()
			if type(dimensions) == "number" then
				return dimensions, second
			end
			return dimensions.X, dimensions.Y
		end)
		if valid and type(x) == "number" and type(y) == "number" and x > 0 and y > 0 then
			screenW, screenH = x, y
		end
	end
	width = math.max(1, math.min(width, screenW - margin * 2))
	height = math.max(1, math.min(height, screenH - margin * 2))
	local x =
		math.clamp(anchor.X + filterButton.AbsoluteSize.X - width, margin, math.max(margin, screenW - width - margin))
	local y = anchor.Y + filterButton.AbsoluteSize.Y + gap
	if y + height > screenH - margin and anchor.Y - height - gap >= margin then
		y = anchor.Y - height - gap
	end
	y = math.clamp(y, margin, math.max(margin, screenH - height - margin))
	popup = UI.frame(
		popupLayer,
		UDim2.fromOffset(x, y),
		UDim2.fromOffset(width, height),
		colors.panelRaised,
		tokens.radius.md
	)
	popup.Name = "FindInPlaceFilters"
	popup.ZIndex = z + 10
	popup.Active = true
	popup.ClipsDescendants = true
	UI.stroke(popup, colors.borderStrong, 1, 0)
	local title = UI.label(
		popup,
		"Search filters",
		UDim2.fromOffset(10, 0),
		UDim2.new(1, -100, 0, 30),
		tokens.type.body,
		colors.text
	)
	local reset = UI.button(popup, "Reset", UDim2.new(1, -88, 0, 3), UDim2.fromOffset(54, 24), function()
		regex, matchCase, wholeWord, selectedOnly = false, false, false, false
		includePath, excludePath = "", ""
		classes.Script, classes.LocalScript, classes.ModuleScript = true, true, true
		closeFilters()
		changeFilters()
		openFilters()
	end, { color = colors.panelRaised, border = false })
	local close = UI.iconButton(
		popup,
		"builtin://global-icons/x.svg",
		UDim2.new(1, -29, 0, 3),
		UDim2.fromOffset(24, 24),
		closeFilters,
		{ color = colors.panelRaised, border = false, iconSize = 12 }
	)
	UI.tooltip(close, "Close filters", { placement = "below" })
	UI.separator(popup, UDim2.fromOffset(0, 30), UDim2.new(1, 0, 0, 1), colors.border)
	local scroll = UI.create("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 31),
		Size = UDim2.new(1, 0, 1, -31),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, 308),
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = colors.subtext,
		ScrollBarImageTransparency = 0.4,
		ScrollBarAutoHide = true,
		ScrollBarFadeDelay = 0.45,
		ScrollBarFadeSpeed = 12,
		ScrollBarMinimumHandleSize = 24,
		ScrollingEnabled = true,
		ScrollSpeed = 38,
		ClipsDescendants = true,
		Active = true,
		InputSink = true,
	}, popup)
	local function caption(text, at)
		UI.label(scroll, text, UDim2.fromOffset(10, at), UDim2.new(1, -20, 0, 18), tokens.type.caption, colors.subtext)
	end
	local function check(text, at, value, changed, half)
		UI.checkbox(scroll, text, UDim2.new(half and 0.5 or 0, half and 0 or 10, 0, at), value, function(enabled)
			changed(enabled)
			changeFilters()
		end, {
			size = UDim2.new(0.5, -10, 0, 22),
			boxSize = 16,
			markSize = 11,
			textSize = tokens.type.small,
			animate = not UI.shared().reduceMotion,
		})
	end
	caption("MATCH OPTIONS", 4)
	check("Match case", 24, matchCase, function(v)
		matchCase = v
	end)
	check("Whole word", 24, wholeWord, function(v)
		wholeWord = v
	end, true)
	check("Regular expression", 48, regex, function(v)
		regex = v
	end)
	check("Selection only", 48, selectedOnly, function(v)
		selectedOnly = v
	end, true)
	UI.separator(scroll, UDim2.fromOffset(10, 77), UDim2.new(1, -20, 0, 1), colors.border)
	caption("SCRIPT TYPES", 82)
	check("Script", 102, classes.Script, function(v)
		classes.Script = v
	end)
	check("LocalScript", 102, classes.LocalScript, function(v)
		classes.LocalScript = v
	end, true)
	check("ModuleScript", 126, classes.ModuleScript, function(v)
		classes.ModuleScript = v
	end)
	UI.separator(scroll, UDim2.fromOffset(10, 154), UDim2.new(1, -20, 0, 1), colors.border)
	caption("Include paths (separate with semicolons)", 160)
	local include = UI.input(
		scroll,
		"e.g. ServerScriptService;Shared",
		UDim2.fromOffset(10, 182),
		UDim2.new(1, -20, 0, inputHeight),
		{ text = includePath, selectAllOnFocus = false }
	)
	caption("Exclude paths (separate with semicolons)", 214)
	local exclude = UI.input(
		scroll,
		"e.g. Vendor;Generated",
		UDim2.fromOffset(10, 236),
		UDim2.new(1, -20, 0, inputHeight),
		{ text = excludePath, selectAllOnFocus = false }
	)
	caption("Path filters match substrings, ignoring case.", 272)
	popupConnect(include.TextChanged, function()
		includePath = include.Text or ""
		changeFilters()
	end)
	popupConnect(exclude.TextChanged, function()
		excludePath = exclude.Text or ""
		changeFilters()
	end)
	-- Match the editor dropdown layer even under global ZIndex ordering.
	for _, child in ipairs(popup:GetDescendants()) do
		if child:IsA("GuiObject") then
			local depth, parent = 1, child.Parent
			while parent and parent ~= popup do
				depth += 1
				parent = parent.Parent
			end
			child.ZIndex = z + 10 + depth * 4 + math.clamp(child.ZIndex, 0, 3)
		end
	end
end

local statusY = inset + inputHeight + gap
local listY = statusY + statusHeight + gap
local statusLabel = UI.label(
	content,
	"Search text in scripts to see matches",
	UDim2.fromOffset(inset + 3, statusY),
	UDim2.new(1, -inset * 2 - 6, 0, statusHeight),
	tokens.type.caption,
	colors.subtext
)
statusLabel.TextTruncate = Enum.TextTruncate.AtEnd
UI.separator(content, UDim2.fromOffset(inset, listY - 1), UDim2.new(1, -inset * 2, 0, 1), colors.border)

local list = UI.create("ScrollingFrame", {
	Position = UDim2.fromOffset(inset, listY),
	Size = UDim2.new(1, -inset * 2, 1, -(listY + inset)),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasPosition = Vector2.new(0, 0),
	CanvasSize = UDim2.new(1, 0, 0, 0),
	VirtualizedScrolling = true,
	ScrollingEnabled = true,
	ScrollSpeed = 38,
	SmoothScrollingEnabled = not UI.shared().reduceMotion,
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
}, content)

local function safePath(object)
	local ok, path = pcall(function()
		return object:GetFullName()
	end)
	return ok and path or tostring(object.Name)
end

local function getSource(object)
	local ok, value = pcall(function()
		return object.Source
	end)
	if ok and type(value) == "string" then
		return value
	end
	return nil
end

local function pathTerms(raw)
	local terms = {}
	for fragment in string.gmatch(string.lower(raw), "[^;]+") do
		local word = fragment:match("^%s*(.-)%s*$")
		if word ~= "" then
			terms[#terms + 1] = word
		end
	end
	return terms
end

local function allowedPath(path, inclusions, exclusions)
	local low = string.lower(path)
	if #inclusions > 0 then
		local found = false
		for _, needle in ipairs(inclusions) do
			if low:find(needle, 1, true) then
				found = true
				break
			end
		end
		if not found then
			return false
		end
	end
	for _, needle in ipairs(exclusions) do
		if low:find(needle, 1, true) then
			return false
		end
	end
	return true
end

local function excerpt(text, column)
	local start = math.max(1, column - 36)
	local ending = math.min(#text, column + 138)
	local segment = text:sub(start, ending):gsub("\t", "    "):gsub("%c", " ")
	return (start > 1 and "…" or "") .. segment .. (ending < #text and "…" or "")
end

local documents = {}
local matchCount = 0
local selectedNode = nil
local roots = {}
local visibleRows = {}
local visibleDepths = {}
local expanded = {}
local rowPool = {}
local revision = 0
local updateViewport
local rebuildVisible

local knownIcons = {}
for name in
	string.gmatch(
		[=[
Accessory Actor Add AlignOrientation AlignPosition AngularVelocity Animation Animator ArcHandles
ArrowDown ArrowRight Atmosphere Attachment Attachment2D Backpack Badge BallSocketConstraint Beam
BillboardGui BinaryStringValue BindableEvent BindableFunction BlobLoader BloomEffect BlurEffect Body2D BodyColors
BodyGyro Bone BoolValue Box2DService BoxCollider2D BrickColorValue CFrameValue Camera Camera2D
CanvasGroup ChangeHistoryService Character CharacterAnimator CharacterCamera CharacterController CharacterInput CharacterMesh CharacterMotor
ChatService Checkbox CircleCollider2D Class ClickDetector Cloth Clouds CollectionService CollisionController
Color3Value ColorCorrectionEffect ColorEffect ColorPicker ConfigService Configuration ContentProvider ContentService CoreGui
CornerWedgePart Cursor CylindricalConstraint DOFEffect DataModel Debris DebugOverlay Decal Dialog
DialogChoice Divider DoubleConstrainedValue Dropdown EditableImage EditableMesh EncodingService Enum EnumItem
Explosion File FileDialogService Fire FluidSimulation FogEffect Folder FolderOpen Font
ForceField Frame GeometryService GetTextBoundsParams GroundDetector GuiObject HUDService Handles Highlight
HingeConstraint HingeConstraint2D HttpService Humanoid IKControl ImageButton ImageLabel InputActionService IntConstrainedValue
IntValue InternalStorage IntersectOperation JoltPhysicsService KineFileService KinemiumFFI KinemiumFontService KinemiumIconLoader KinemiumModService
KinemiumShaderService Layer2D LegIK Lighting LineForce LinearVelocity LocalScript LocalizationService LogService
MCPService MaterialVariant MeshPart Method Model ModuleScript Motor6D Mouse Move
MovementController MultipleDevices NegateOperation NetworkController NetworkService NoCollisionConstraint NotFound NumberValue ObjectValue
Pants Part Part2D ParticleEmitter ParticleEmitter2D PathfindingModifier PathfindingService Pause Physics
PlaneConstraint Play Player PlayerGui Players PlaytestService Plugin PluginGuiService PluginLoader
Plus PointLight Poll PolygonCollider2D PostProcess PrismaticConstraint Process ProfilerService ProjectLoaderService
ProjectSyncService Property ProximityPrompt RadioButton RayValue RemoteData RemoteEvent RemoteFunction ReplicatedStorage
ReplicatorService RigidConstraint RodConstraint RopeConstraint RopeConstraint2D Rotate RotationController RunService SQLiteService
SSAOEffect SSEffect SSGIEffect SSILEffect SSREffect ScreenGui Script ScriptContext ScrollingFrame
Seat SeatPart Selection SelectionBox SelectionSphere SerializationService ServerScriptService ServerStorage Settings
ShaderFrame Shirt ShirtGraphic Size Sky Slider Smoke Snap SoftBody
Sound SoundService Sparkles SpawnLocation SpecialMesh SpotLight SpringConstraint SpringConstraint2D StarterGui
StarterPlayer StateMachine Stepper Stop StringValue Studio StudioService StudioTheme StudioThemeService
SunRaysEffect SurfaceGui SurfaceLight Switch SyntaxHighlighter Tabs Terrain TextBox TextButton
TextLabel TextService Texture Tilemap Toggle TonemapEffect Tool TorsionSpringConstraint Trail
TrussPart TweenService UIAnchorLayout UIAspectRatioConstraint UIBackdrop UICellList UICorner UIDragDetector UIGradient
UIGridLayout UIListLayout UIMask UINotificationLayout UIPadding UIPageLayout UIRipple UIScale UIScaleDetector
UIShader UIShadow UISizeConstraint UISquircle UIStackLayout UIStroke UITableLayout UITextSizeConstraint UITilt
UITooltip UIVignette Union UnionOperation UniversalConstraint UnreliableRemoteEvent UserInputService ValueBase Variable
Vector3Value VectorForce VehicleSeat VideoFrame ViewportFrame VignetteEffect WedgePart Weld WeldConstraint
WeldConstraint2D Workspace Workspace2D World2D WorldObject2D clipboard
]=],
		"%S+"
	)
do
	knownIcons[name] = true
end
local fallbackIcons = {
	ReplicatedFirst = "ReplicatedStorage",
	StarterPack = "Backpack",
	Teams = "Players",
	TextChatService = "ChatService",
}
local iconCache = {}
local function iconFor(node)
	if node.kind == "match" then
		return "builtin://icons/TextBox.svg"
	end
	if node.kind == "property" then
		return "builtin://icons/Property.svg"
	end
	local class = node.object.ClassName
	if not iconCache[class] then
		local name = knownIcons[class] and class or fallbackIcons[class] or "File"
		iconCache[class] = "builtin://icons/" .. name .. ".svg"
	end
	return iconCache[class]
end

local function nodeName(node)
	if node.kind == "match" then
		local hit = node.hit
		return string.format("%d:%d   %s", hit.line, hit.column, hit.snippet)
	end
	if node.kind == "property" then
		return node.name .. "  (" .. node.count .. ")"
	end
	return node.name .. "  (" .. node.count .. ")"
end

local function sortChildren(a, b)
	if a.kind == "match" or b.kind == "match" then
		if a.kind ~= b.kind then
			return a.kind ~= "match"
		end
		if a.hit.line ~= b.hit.line then
			return a.hit.line < b.hit.line
		end
		return a.hit.column < b.hit.column
	end
	local ao, bo = serviceOrder[a.name] or math.huge, serviceOrder[b.name] or math.huge
	if ao ~= bo then
		return ao < bo
	end
	if a.kind == "property" or b.kind == "property" then
		if a.kind ~= b.kind then
			return a.kind ~= "property"
		end
	end
	return a.name < b.name
end

local function buildTree()
	local top = { kind = "root", children = {}, lookup = {} }
	for _, doc in ipairs(documents) do
		local hierarchy = {}
		local cursor = doc.object
		while cursor and cursor ~= game do
			table.insert(hierarchy, 1, cursor)
			cursor = cursor.Parent
		end
		local parent = top
		for _, object in ipairs(hierarchy) do
			local child = parent.lookup[object]
			if not child then
				child = {
					kind = "object",
					object = object,
					name = object.Name,
					count = 0,
					children = {},
					lookup = {},
					parent = parent,
				}
				parent.lookup[object] = child
				parent.children[#parent.children + 1] = child
			end
			child.count += #doc.hits
			parent = child
		end
		if doc.property ~= "Source" then
			local propertyKey = doc.property
			local child = parent.lookup[propertyKey]
			if not child then
				child = {
					kind = "property",
					object = doc.object,
					property = doc.property,
					name = doc.property,
					count = 0,
					children = {},
					lookup = {},
					parent = parent,
				}
				parent.lookup[propertyKey] = child
				parent.children[#parent.children + 1] = child
			end
			child.count += #doc.hits
			parent = child
		end
		for _, hit in ipairs(doc.hits) do
			parent.children[#parent.children + 1] = {
				kind = "match",
				object = doc.object,
				property = doc.property,
				name = tostring(hit.line),
				hit = hit,
				parent = parent,
			}
		end
	end
	roots = top.children
	local stack = { top }
	while #stack > 0 do
		local node = table.remove(stack)
		if node.children then
			table.sort(node.children, sortChildren)
			for _, child in ipairs(node.children) do
				if child.children then
					stack[#stack + 1] = child
				end
			end
		end
	end
end

local function selectNode(node, reveal)
	selectedNode = node
	if node and node.kind == "match" then
		pcall(function()
			Selection:Set({ node.object })
		end)
	elseif node and node.object then
		pcall(function()
			Selection:Set({ node.object })
		end)
	end
	if reveal and node then
		for index, row in ipairs(visibleRows) do
			if row == node then
				local targetY = math.max(0, (index - 1) * ROW_HEIGHT - list.AbsoluteSize.Y * 0.4)
				list.CanvasPosition = Vector2.new(0, targetY)
				break
			end
		end
	end
	updateViewport(true)
end

local function physicalLine(text, lineNumber)
	local start = 1
	for _ = 2, lineNumber do
		local newline = text:find("\n", start, true)
		if not newline then
			return ""
		end
		start = newline + 1
	end
	local newline = text:find("\n", start, true)
	local finish = newline and newline - 1 or #text
	if finish >= start and text:byte(finish) == 13 then
		finish -= 1
	end
	return text:sub(start, finish)
end

local function characterCount(text)
	if text == "" then
		return 0
	end
	local count = utf8.len(text)
	return count or #text
end

local function openScriptAt(object, line, column, selectionLength)
	if not object or not object.Parent then
		return false, "The script was removed"
	end

	local ok, err = pcall(function()
		viewport.OpenScript(object)

		if viewport.ActiveScript and viewport.ActiveScript() ~= object then
			error("The script editor did not activate the requested script")
		end

		local editor = viewport.CodeEditor
		if not editor then
			viewport.OpenScript(object, line)
			return
		end

		editor:GoToLine(line, column or 1, selectionLength or 0, true)
	end)
	return ok, err
end

local function openMatch(node)
	local object, hit = node.object, node.hit
	if not object or not object.Parent then
		return false, "The script was removed"
	end

	local ok, err = pcall(function()
		viewport.OpenScript(object)
		if viewport.ActiveScript and viewport.ActiveScript() ~= object then
			error("The script editor did not activate the requested script")
		end

		local editor = viewport.CodeEditor
		if not editor then
			viewport.OpenScript(object, hit.line)
			return
		end

		-- Search positions are byte offsets; TextBox:GoToLine takes 1-based
		-- UTF-8 character columns and a character-based selection length.
		-- Read the opened editor buffer so unsaved text does not get replaced.
		local lineText = physicalLine(editor.Text or "", hit.line)
		local byteColumn = math.clamp(hit.column, 1, #lineText + 1)
		local byteLength = math.min(hit.length, math.max(0, #lineText - byteColumn + 1))

		-- If the code changed since searching, do not highlight unrelated text.
		if hit.sample and lineText:sub(byteColumn, byteColumn + #hit.sample - 1) ~= hit.sample then
			byteLength = 0
		end

		local column = characterCount(lineText:sub(1, byteColumn - 1)) + 1
		local length = characterCount(lineText:sub(byteColumn, byteColumn + byteLength - 1))
		editor:GoToLine(hit.line, column, length, true)
	end)
	return ok, err
end

local function openNode(node)
	if not node then
		return
	end
	if node.kind ~= "match" then
		expanded[node] = expanded[node] == false
		rebuildVisible()
		return
	end
	selectNode(node, false)
	local ok, err = openMatch(node)
	if not ok then
		UI.toast("find-in-place", {
			type = "error",
			title = "Unable to open search result",
			message = tostring(err),
			duration = 5,
		})
	end
end

local function createRowSlot()
	local slot = { node = nil }
	local row, _, button = UI.button(
		list,
		"",
		UDim2.fromOffset(1, 0),
		UDim2.new(1, -2, 0, ROW_HEIGHT),
		nil,
		{ color = tokens.color.rowOdd, hoverColor = colors.hover, radius = 0, border = false }
	)
	slot.row = row
	slot.button = button
	slot.corner = UI.corner(row, 0)
	slot.arrow = UI.image(row, "builtin://icons/ArrowRight.svg", UDim2.fromOffset(7, 4), UDim2.fromOffset(12, 12))
	slot.icon = UI.image(row, "builtin://icons/Folder.svg", UDim2.fromOffset(23, 3), UDim2.fromOffset(14, 14))
	slot.label = UI.label(row, "", UDim2.fromOffset(38, 2), UDim2.new(1, -41, 0, 17), tokens.type.small, colors.text)
	slot.label.TextTruncate = Enum.TextTruncate.AtEnd
	slot.arrow.ImageColor3 = colors.subtext
	slot.icon.ImageColor3 = colors.text
	slot.arrow.Visible = false
	row.Visible = false
	row.Name = "FindInPlaceRow"
	connect(row.Activated, function(_, clickCount)
		local node = slot.node
		if not node then
			return
		end
		selectNode(node, false)
		if node.kind ~= "match" then
			expanded[node] = expanded[node] == false
			rebuildVisible()
		elseif clickCount == 2 then
			openNode(node)
		end
	end)
	return slot
end

local lastStart, lastHeight, lastWidth, lastCount = -1, -1, -1, -1
updateViewport = function(force)
	local height = list.AbsoluteSize.Y
	local width = list.AbsoluteSize.X
	local total = #visibleRows
	local first = math.max(1, math.floor(list.CanvasPosition.Y / ROW_HEIGHT) + 1 - VIEW_OVERSCAN)
	local last = math.min(total, first + math.ceil(height / ROW_HEIGHT) + VIEW_OVERSCAN * 2 + 2)
	if not force and first == lastStart and height == lastHeight and width == lastWidth and total == lastCount then
		return
	end
	lastStart, lastHeight, lastWidth, lastCount = first, height, width, total
	local used = 0
	for index = first, last do
		used += 1
		local slot = rowPool[used]
		if not slot then
			slot = createRowSlot()
			rowPool[used] = slot
		end
		local node = visibleRows[index]
		local depth = visibleDepths[index]
		local hasChildren = node.children and #node.children > 0
		local selected = node == selectedNode
		local indent = 7 + depth * 16
		local row = slot.row
		slot.node = node
		row.Position = UDim2.fromOffset(1, 1 + (index - 1) * ROW_HEIGHT)
		slot.button.defaultColor = index % 2 == 0 and tokens.color.rowEven or tokens.color.rowOdd
		row.BackgroundTransparency = selected and 0 or 0.12
		UI.setButtonState(slot.button, selected and "selected" or nil)
		slot.corner.CornerRadius = UDim.new(0, selected and tokens.radius.sm or 0)
		slot.arrow.Visible = hasChildren or false
		if hasChildren then
			slot.arrow.Image = "builtin://icons/" .. (expanded[node] == false and "ArrowRight.svg" or "ArrowDown.svg")
		end
		slot.arrow.Position = UDim2.fromOffset(indent, 4)
		slot.icon.Image = iconFor(node)
		slot.icon.Position = UDim2.fromOffset(indent + 16, 3)
		slot.label.Position = UDim2.fromOffset(indent + 31, 2)
		slot.label.Size = UDim2.new(1, -(indent + 34), 0, 17)
		slot.label.TextColor3 = colors.text
		slot.label.Text = nodeName(node)
		row.Visible = true
	end
	for i = used + 1, #rowPool do
		local slot = rowPool[i]
		slot.node = nil
		slot.row.Visible = false
	end
end

rebuildVisible = function()
	local nextRows, nextDepths = {}, {}
	local stack = {}
	for i = #roots, 1, -1 do
		stack[#stack + 1] = { root = roots[i], depth = 0 }
	end
	while #stack > 0 do
		local frame = table.remove(stack)
		local node = frame.root
		nextRows[#nextRows + 1] = node
		nextDepths[#nextDepths + 1] = frame.depth
		if node.children and expanded[node] ~= false then
			for i = #node.children, 1, -1 do
				stack[#stack + 1] = { root = node.children[i], depth = frame.depth + 1 }
			end
		end
	end
	visibleRows, visibleDepths = nextRows, nextDepths
	list.CanvasSize = UDim2.new(1, 0, 0, #visibleRows * ROW_HEIGHT + 5)
	local maxScroll = math.max(0, #visibleRows * ROW_HEIGHT - list.AbsoluteSize.Y)
	if list.CanvasPosition.Y > maxScroll then
		list.CanvasPosition = Vector2.new(0, maxScroll)
	end
	updateViewport(true)
end

connect(list:GetPropertyChangedSignal("CanvasPosition"), function()
	updateViewport(false)
end)
connect(list:GetPropertyChangedSignal("AbsoluteSize"), function()
	updateViewport(true)
end)

local function setStatus(message, isError)
	statusLabel.Text = message
	statusLabel.TextColor3 = isError and tokens.color.error or tokens.color.subtext
end

local function scanSource(object, property, source, finder, token, matchesLeft, useRegex)
	local hits = {}
	local lineStart, lineNo = 1, 0
	local maxHits = math.min(MAX_PER_SOURCE, matchesLeft)
	local deadline = os.clock() + SCAN_FRAME_BUDGET
	local skippedLongLine = false
	while lineStart <= #source + 1 and #hits < maxHits do
		if revision ~= token then
			return nil
		end
		lineNo += 1
		local lineEnd = source:find("\n", lineStart, true)
		local lineText = source:sub(lineStart, lineEnd and lineEnd - 1 or #source)
		if lineText:sub(-1) == "\r" then
			lineText = lineText:sub(1, -2)
		end
		if #lineText <= MAX_REGEX_LINE or not useRegex then
			local from = 1
			while from <= #lineText + 1 and #hits < maxHits do
				if revision ~= token then
					return nil
				end
				local ok, first, last = pcall(finder, lineText, from)
				if not ok then
					-- An unusually complex regex is bounded to avoid hanging the editor.
					return hits, "Regex evaluation limit reached near line " .. lineNo
				end
				if not first then
					break
				end
				hits[#hits + 1] = {
					line = lineNo,
					column = first,
					length = last - first + 1,
					sample = lineText:sub(first, math.min(last, first + 63)),
					snippet = excerpt(lineText, first),
				}
				from = math.max(first + 1, last + 1)
				if os.clock() >= deadline then
					task.wait()
					if revision ~= token then
						return nil
					end
					deadline = os.clock() + SCAN_FRAME_BUDGET
				end
			end
		else
			skippedLongLine = true
		end
		if not lineEnd then
			break
		end
		lineStart = lineEnd + 1
		-- Cooperative scheduling keeps the UI responsive with very large files.
		if lineNo % 128 == 0 or os.clock() >= deadline then
			task.wait()
			if revision ~= token then
				return nil
			end
			deadline = os.clock() + SCAN_FRAME_BUDGET
		end
	end
	return hits, (skippedLongLine or #hits >= maxHits) and "Source search limit reached" or nil
end

local function setJobActive(value)
	jobActive = value
	if queryCaption then
		queryCaption.Text = value and "Stop" or "Find"
	end
end

cancelSearch = function()
	if not jobActive then
		return
	end
	revision += 1
	setJobActive(false)
	buildTree()
	rebuildVisible()
	setStatus(string.format("Search stopped: %d matches so far", matchCount))
end

local function startSearch()
	if destroyed or not panel.Visible or not overlay.Enabled then
		return
	end
	revision += 1
	local token = revision
	documents = {}
	roots = {}
	expanded = {}
	selectedNode = nil
	matchCount = 0
	setJobActive(false)
	list.CanvasPosition = Vector2.new(0, 0)
	rebuildVisible()

	local query = input.Text or ""
	if query == "" then
		setStatus("Search text in scripts to see matches")
		return
	end

	local finder, failure = makeFinder(query, regex, matchCase, wholeWord)
	if not finder then
		setStatus("Invalid regex: " .. tostring(failure), true)
		return
	end

	local included = pathTerms(includePath)
	local excluded = pathTerms(excludePath)
	local useRegex = regex
	local selected = selectedOnly
	local includedClasses = table.clone(classes)
	if not includedClasses.Script and not includedClasses.LocalScript and not includedClasses.ModuleScript then
		setStatus("No script types selected")
		return
	end
	setJobActive(true)
	setStatus(selected and "Searching selected objects..." or "Searching all scripts in game...")

	task.spawn(function()
		local started = os.clock()
		-- Traverse the whole game hierarchy, including nested folders/models
		-- and scripts inside services. A stack avoids a single expensive
		-- game:GetDescendants() allocation and permits yielding while scanning.
		local stack = {}
		if selected then
			for _, object in ipairs(Selection:Get() or {}) do
				stack[#stack + 1] = object
			end
		else
			stack[1] = game
		end

		local seen = {}
		local inspected, scriptsFound, sources, unreadable, limited = 0, 0, 0, 0, 0
		local lastYield = os.clock()

		while #stack > 0 and matchCount < MAX_MATCHES do
			if token ~= revision then
				return
			end
			local object = table.remove(stack)
			if object and not seen[object] then
				seen[object] = true
				if object ~= game then
					inspected += 1
					local className = object.ClassName
					if scriptClasses[className] then
						scriptsFound += 1
						if includedClasses[className] then
							local path = safePath(object)
							if allowedPath(path, included, excluded) then
								local source = getSource(object)
								if source == nil then
									unreadable += 1
								else
									sources += 1
									if source ~= "" then
										local hits, warning = scanSource(
											object,
											"Source",
											source,
											finder,
											token,
											MAX_MATCHES - matchCount,
											useRegex
										)
										if not hits then
											return
										end
										if warning then
											limited += 1
										end
										if #hits > 0 then
											documents[#documents + 1] = {
												object = object,
												property = "Source",
												hits = hits,
												path = path,
											}
											matchCount += #hits
										end
									end
								end
							end
						end
					end
				end

				-- Do not restrict the traversal to particular services:
				-- visit every descendant of game (or the selected roots).
				-- Even excluded parents must be traversed to reach scripts.
				local ok, children = pcall(function()
					return object:GetChildren()
				end)
				if ok then
					for i = #children, 1, -1 do
						stack[#stack + 1] = children[i]
					end
				end
			end

			if os.clock() - lastYield > SCAN_FRAME_BUDGET then
				setStatus(
					string.format(
						"Searching... %d objects · %d scripts · %d matches",
						inspected,
						scriptsFound,
						matchCount
					)
				)
				task.wait()
				lastYield = os.clock()
			end
		end

		if token ~= revision then
			return
		end
		table.sort(documents, function(a, b)
			if a.path ~= b.path then
				return a.path < b.path
			end
			return a.property < b.property
		end)
		buildTree()
		rebuildVisible()
		local limit = matchCount >= MAX_MATCHES and " · result limit reached" or ""
		local warnings = (unreadable > 0 and (" · " .. unreadable .. " unreadable") or "")
			.. (limited > 0 and (" · " .. limited .. " limited sources") or "")
		setStatus(
			string.format(
				"%d matches · %d scripts found · %d sources searched · %.2fs%s%s",
				matchCount,
				scriptsFound,
				sources,
				os.clock() - started,
				limit,
				warnings
			)
		)
		setJobActive(false)
	end)
end

runSearch = startSearch
requestSearch = function()
	if destroyed or not panel.Visible or not overlay.Enabled then
		return
	end
	revision += 1
	setJobActive(false)
	local token = revision
	task.delay(SEARCH_DEBOUNCE, function()
		if not destroyed and panel.Visible and overlay.Enabled and token == revision then
			startSearch()
		end
	end)
end

connect(input.TextChanged, requestSearch)
connect(input.FocusLost, function(enterPressed)
	if enterPressed then
		startSearch()
	end
end)

local function ctrlDown()
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
end
local function shiftDown()
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end
local function selectedIndex()
	for index, row in ipairs(visibleRows) do
		if row == selectedNode then
			return index
		end
	end
	return nil
end
local function revealIndex(index)
	local node = visibleRows[index]
	if node then
		selectNode(node, true)
	end
end

connect(UserInputService.InputBegan, function(event, processed)
	if event.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end
	if event.KeyCode == Enum.KeyCode.F and ctrlDown() and shiftDown() then
		closeFilters()
		panel.Visible = true
		pcall(function()
			input:CaptureFocus()
		end)
		return
	end
	if not panel.Visible or not overlay.Enabled then
		return
	end
	if event.KeyCode == Enum.KeyCode.Escape then
		if filterOpen then
			closeFilters()
		elseif UserInputService:GetFocusedTextBox() == nil then
			panel.Visible = false
		end
		return
	end
	if filterOpen or UserInputService:GetFocusedTextBox() ~= nil or processed then
		return
	end
	local key = event.KeyCode
	if key == Enum.KeyCode.Up or key == Enum.KeyCode.Down then
		if #visibleRows == 0 then
			return
		end
		local index = selectedIndex() or (key == Enum.KeyCode.Up and #visibleRows + 1 or 0)
		revealIndex(math.clamp(index + (key == Enum.KeyCode.Up and -1 or 1), 1, #visibleRows))
	elseif key == Enum.KeyCode.Home then
		revealIndex(1)
	elseif key == Enum.KeyCode.End then
		revealIndex(#visibleRows)
	elseif key == Enum.KeyCode.Right then
		if selectedNode and selectedNode.children then
			expanded[selectedNode] = nil
			rebuildVisible()
		end
	elseif key == Enum.KeyCode.Left then
		if selectedNode then
			if selectedNode.children and expanded[selectedNode] ~= false then
				expanded[selectedNode] = false
				rebuildVisible()
			elseif selectedNode.parent and selectedNode.parent.kind ~= "root" then
				selectNode(selectedNode.parent, true)
			end
		end
	elseif key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter then
		openNode(selectedNode)
	end
end)

local function enable()
	panel.Visible = true
	pcall(function()
		input:CaptureFocus()
	end)
end
local function disable()
	panel.Visible = false
	revision += 1
	setJobActive(false)
	closeFilters()
end

-- Also handle the native window close button, external UI.toggleWindow,
-- theme updates, and disposal of the module while a scan is still yielding.
connect(panel:GetPropertyChangedSignal("Visible"), function()
	if not panel.Visible then
		revision += 1
		setJobActive(false)
		closeFilters()
	elseif input.Text ~= "" then
		requestSearch()
	end
end)
connect(overlay:GetPropertyChangedSignal("Enabled"), function()
	if not overlay.Enabled then
		revision += 1
		setJobActive(false)
		closeFilters()
	elseif panel.Visible and input.Text ~= "" then
		requestSearch()
	end
end)
connect(panel:GetPropertyChangedSignal("AbsolutePosition"), closeFilters)
connect(panel:GetPropertyChangedSignal("AbsoluteSize"), closeFilters)
connections[#connections + 1] = UI.onThemeChanged(function()
	if destroyed then
		return
	end
	updateFilterState()
	list.SmoothScrollingEnabled = not UI.shared().reduceMotion
	updateViewport(true)
end)
connect(panel.Destroying, function()
	destroyed = true
	revision += 1
	closeFilters()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
	UI.forgetButtons(content)
	table.clear(rowPool)
	table.clear(documents)
	table.clear(roots)
	table.clear(visibleRows)
	table.clear(visibleDepths)
	table.clear(expanded)
end)

return {
	Enable = enable,
	Disable = disable,
	Toggle = function()
		if panel.Visible then
			disable()
		else
			enable()
		end
	end,
	Show = enable,
	Hide = disable,
	Refresh = function()
		UI.refreshWindow("FindInPlace")
		if panel.Visible then
			startSearch()
		end
	end,
	IsVisible = function()
		return panel.Visible
	end,
	Search = function(query)
		input.Text = tostring(query or "")
		enable()
		startSearch()
	end,
	GoToLine = function(script, line, column, selectionLength)
		local ok, err = openScriptAt(
			script,
			math.max(1, math.floor(tonumber(line) or 1)),
			math.max(1, math.floor(tonumber(column) or 1)),
			math.max(0, math.floor(tonumber(selectionLength) or 0))
		)
		if not ok then
			UI.toast("find-in-place", {
				type = "error",
				title = "Unable to navigate",
				message = tostring(err),
				duration = 5,
			})
		end
		return ok
	end,
}

if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local UI = require("@internal/editor_ui")

local Project = game:GetService("Project")
local dialog = game:GetService("DialogService")
local UserInputService = game:GetService("UserInputService")

local colors = UI.colors
local tokens = UI.tokens
local inset = UI.metrics.panelInset

local TAB_NAME = "UI Editor"
local TREE_W, INSPECTOR_W = 150, 190
local HANDLE = 7
local MIN_SIZE = 4
local MIN_ZOOM, MAX_ZOOM = 0.25, 4
local HISTORY_LIMIT = 100
local SCENE_EXT = ".uiscene"
local LUA_EXT = ".ui.luau"

local CLASSES = {
	Frame = { w = 120, h = 80, color = "#3A3F4B", transparency = 0, icon = "builtin://icons/File.svg" },
	TextLabel = {
		w = 120,
		h = 24,
		color = "#000000",
		transparency = 1,
		hasText = true,
		text = "Label",
		icon = "builtin://icons/Script.svg",
	},
	TextButton = {
		w = 100,
		h = 28,
		color = "#4B5563",
		transparency = 0,
		hasText = true,
		text = "Button",
		icon = "builtin://icons/Script.svg",
	},
	ImageLabel = {
		w = 64,
		h = 64,
		color = "#3A3F4B",
		transparency = 0,
		hasImage = true,
		icon = "builtin://icons/ImageLabel.svg",
	},
}

local CLASS_ORDER = { "Frame", "TextLabel", "TextButton", "ImageLabel" }

local NUMBER_KEYS = { "x", "y", "w", "h", "transparency", "radius", "textSize" }
local STRING_KEYS = { "color", "text", "textColor", "image" }

local json = {}

local ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function escapeString(s)
	return '"' .. (s:gsub('[%c"\\]', function(c)
		return ESCAPES[c] or string.format("\\u%04x", c:byte())
	end)) .. '"'
end

function json.encode(value)
	local kind = type(value)

	if kind == "string" then
		return escapeString(value)
	elseif kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			return "0"
		end

		return string.format("%.14g", value)
	elseif kind == "boolean" then
		return tostring(value)
	elseif kind == "table" then
		if #value > 0 or next(value) == nil then
			local out = {}

			for index, item in ipairs(value) do
				out[index] = json.encode(item)
			end

			return "[" .. table.concat(out, ",") .. "]"
		end

		local keys = {}

		for key in pairs(value) do
			keys[#keys + 1] = key
		end

		table.sort(keys)

		local out = {}

		for _, key in ipairs(keys) do
			out[#out + 1] = escapeString(key) .. ":" .. json.encode(value[key])
		end

		return "{" .. table.concat(out, ",") .. "}"
	end

	return "null"
end

function json.decode(text)
	local pos = 1
	local parseValue

	local function skip()
		pos = text:find("%S", pos) or #text + 1
	end

	local function parseString()
		pos += 1

		local out = {}

		while true do
			local c = text:sub(pos, pos)

			if c == "" then
				error("unterminated string")
			end

			if c == '"' then
				pos += 1
				break
			end

			if c == "\\" then
				local n = text:sub(pos + 1, pos + 1)

				if n == "u" then
					out[#out + 1] = utf8.char(tonumber(text:sub(pos + 2, pos + 5), 16) or 63)
					pos += 6
				else
					out[#out + 1] = ({ n = "\n", r = "\r", t = "\t", b = "\b", f = "\f" })[n] or n
					pos += 2
				end
			else
				out[#out + 1] = c
				pos += 1
			end
		end

		return table.concat(out)
	end

	parseValue = function()
		skip()

		local c = text:sub(pos, pos)

		if c == "{" then
			pos += 1

			local object = {}

			skip()

			if text:sub(pos, pos) == "}" then
				pos += 1
				return object
			end

			while true do
				skip()

				local key = parseString()

				skip()

				if text:sub(pos, pos) ~= ":" then
					error("expected ':'")
				end

				pos += 1
				object[key] = parseValue()

				skip()

				local d = text:sub(pos, pos)

				pos += 1

				if d == "}" then
					return object
				elseif d ~= "," then
					error("expected ',' or '}'")
				end
			end
		elseif c == "[" then
			pos += 1

			local array = {}

			skip()

			if text:sub(pos, pos) == "]" then
				pos += 1
				return array
			end

			while true do
				array[#array + 1] = parseValue()

				skip()

				local d = text:sub(pos, pos)

				pos += 1

				if d == "]" then
					return array
				elseif d ~= "," then
					error("expected ',' or ']'")
				end
			end
		elseif c == '"' then
			return parseString()
		elseif text:sub(pos, pos + 3) == "true" then
			pos += 4
			return true
		elseif text:sub(pos, pos + 4) == "false" then
			pos += 5
			return false
		elseif text:sub(pos, pos + 3) == "null" then
			pos += 4
			return nil
		end

		local number = text:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)

		if number == nil or number == "" then
			error("unexpected character at " .. pos)
		end

		pos += #number

		return tonumber(number)
	end

	return parseValue()
end

local function hexToColor(hex)
	local r, g, b = tostring(hex):match("^#?(%x%x)(%x%x)(%x%x)$")

	if r == nil then
		return nil
	end

	return Color3.fromRGB(tonumber(r, 16), tonumber(g, 16), tonumber(b, 16))
end

local function normalizeHex(text)
	local r, g, b = tostring(text):match("^%s*#?(%x%x)(%x%x)(%x%x)%s*$")

	if r == nil then
		return nil
	end

	return string.upper("#" .. r .. g .. b)
end

local function fmt(number)
	return string.format("%g", math.floor(number * 100 + 0.5) / 100)
end

local function joinPath(parent, name)
	local last = parent:sub(-1)

	if last == "/" or last == "\\" then
		return parent .. name
	end

	return parent .. (parent:find("\\") and "\\" or "/") .. name
end

local function toastMessage(kind, title, message)
	pcall(function()
		UI.toast("uieditor", {
			type = kind,
			title = title,
			message = message,
			details = "",
			detailsTitle = "",
			backgroundTransparency = 0.4,
			blur = true,
			duration = 5,
		})
	end)
end

local function setProps(gui, props)
	for key, value in pairs(props) do
		pcall(function()
			gui[key] = value
		end)
	end
end

local function newNode(id, class, name)
	local def = CLASSES[class]

	return {
		id = id,
		class = class,
		name = name,
		x = 0,
		y = 0,
		w = def.w,
		h = def.h,
		color = def.color,
		transparency = def.transparency,
		radius = 0,
		text = def.text or "",
		textColor = "#FFFFFF",
		textSize = 14,
		image = "",
		children = {},
		parent = nil,
	}
end

local function toData(node)
	local data = { id = node.id, class = node.class, name = node.name, children = {} }

	for _, key in ipairs(NUMBER_KEYS) do
		data[key] = node[key]
	end

	for _, key in ipairs(STRING_KEYS) do
		data[key] = node[key]
	end

	for index, child in ipairs(node.children) do
		data.children[index] = toData(child)
	end

	return data
end

local function fromData(data, parent)
	local class = CLASSES[data.class] and data.class or "Frame"
	local node = newNode(tonumber(data.id) or 0, class, tostring(data.name or class))

	for _, key in ipairs(NUMBER_KEYS) do
		node[key] = tonumber(data[key]) or node[key]
	end

	for _, key in ipairs(STRING_KEYS) do
		if type(data[key]) == "string" then
			node[key] = data[key]
		end
	end

	node.parent = parent

	for _, childData in ipairs(data.children or {}) do
		node.children[#node.children + 1] = fromData(childData, node)
	end

	return node
end

local function absolutePosition(node)
	local x, y = 0, 0
	local current = node

	while current.parent ~= nil do
		x += current.x
		y += current.y
		current = current.parent
	end

	return x, y
end

local function findById(node, id)
	if node.id == id then
		return node
	end

	for _, child in ipairs(node.children) do
		local found = findById(child, id)

		if found ~= nil then
			return found
		end
	end

	return nil
end

local function maxId(node)
	local highest = node.id

	for _, child in ipairs(node.children) do
		highest = math.max(highest, maxId(child))
	end

	return highest
end

local function hitTest(node, ox, oy, px, py)
	for index = #node.children, 1, -1 do
		local child = node.children[index]
		local hit = hitTest(child, ox + child.x, oy + child.y, px, py)

		if hit ~= nil then
			return hit
		end
	end

	if px >= ox and px <= ox + node.w and py >= oy and py <= oy + node.h then
		return node
	end

	return nil
end

local function colorLiteral(hex)
	local r, g, b = tostring(hex):match("^#(%x%x)(%x%x)(%x%x)$")

	return string.format(
		"Color3.fromRGB(%d, %d, %d)",
		tonumber(r or "0", 16),
		tonumber(g or "0", 16),
		tonumber(b or "0", 16)
	)
end

local function generateLua(sceneRoot)
	local lines = {
		"return function(parent)",
		"\tlocal function make(class, props, parent)",
		"\t\tlocal object = Instance.new(class)",
		"\t\tfor key, value in pairs(props) do",
		"\t\t\tobject[key] = value",
		"\t\tend",
		"\t\tobject.Parent = parent",
		"\t\treturn object",
		"\tend",
		"",
	}

	local function emit(node, parentVar, depth)
		local def = CLASSES[node.class]
		local isRoot = node.parent == nil
		local var = isRoot and "root" or ("node" .. depth)
		local pad = string.rep("\t", depth)

		local props = {
			string.format("Name = %q", node.name),
			string.format("Size = UDim2.fromOffset(%s, %s)", fmt(node.w), fmt(node.h)),
			"BackgroundColor3 = " .. colorLiteral(node.color),
			"BackgroundTransparency = " .. fmt(node.transparency),
			"BorderSizePixel = 0",
		}

		if not isRoot then
			table.insert(props, 2, string.format("Position = UDim2.fromOffset(%s, %s)", fmt(node.x), fmt(node.y)))
		end

		if def.hasText then
			props[#props + 1] = string.format("Text = %q", node.text)
			props[#props + 1] = "TextColor3 = " .. colorLiteral(node.textColor)
			props[#props + 1] = "TextSize = " .. fmt(node.textSize)
		end

		if def.hasImage then
			props[#props + 1] = string.format("Image = %q", node.image)
		end

		if not isRoot then
			lines[#lines + 1] = pad .. "do"
			pad ..= "\t"
		end

		lines[#lines + 1] = string.format(
			"%slocal %s = make(%q, { %s }, %s)",
			pad,
			var,
			node.class,
			table.concat(props, ", "),
			parentVar
		)

		if node.radius > 0 and not isRoot then
			lines[#lines + 1] =
				string.format('%smake("UICorner", { CornerRadius = UDim.new(0, %s) }, %s)', pad, fmt(node.radius), var)
		end

		for _, child in ipairs(node.children) do
			emit(child, var, depth + 1)
		end

		if not isRoot then
			lines[#lines + 1] = string.rep("\t", depth) .. "end"
		end
	end

	emit(sceneRoot, "parent", 1)

	lines[#lines + 1] = "\treturn root"
	lines[#lines + 1] = "end"

	return table.concat(lines, "\n") .. "\n"
end

local function writeText(path, text)
	local attempts = {
		function()
			return Project:WriteFile(path, text)
		end,
		function()
			return Project:SetFileContents(path, text)
		end,
	}

	for _, attempt in ipairs(attempts) do
		local ok, result = pcall(attempt)

		if ok and result ~= false then
			return true
		end
	end

	return false
end

local function readText(path)
	local attempts = {
		function()
			return Project:ReadFile(path)
		end,
		function()
			return Project:GetFileContents(path)
		end,
	}

	for _, attempt in ipairs(attempts) do
		local ok, result = pcall(attempt)

		if ok and type(result) == "string" then
			return result
		end
	end

	return nil
end

local function ensureFile(directory, name)
	local ok, entries = pcall(function()
		return Project:GetProjectEntries(directory)
	end)

	if ok and type(entries) == "table" then
		for _, entry in ipairs(entries) do
			if entry.Name == name then
				return joinPath(directory, name)
			end
		end
	end

	local created
	ok, created = pcall(function()
		return Project:CreateFile(directory, name)
	end)

	if ok and type(created) == "string" and created ~= "" then
		return created
	end

	return nil
end

local function always()
	return true
end

local function notRoot(node)
	return node.parent ~= nil
end

local function hasText(node)
	return CLASSES[node.class].hasText == true
end

local function hasImage(node)
	return CLASSES[node.class].hasImage == true
end

local FIELDS = {
	{ key = "name", label = "Name", kind = "string", applies = always },
	{ key = "x", label = "X", kind = "number", applies = notRoot },
	{ key = "y", label = "Y", kind = "number", applies = notRoot },
	{ key = "w", label = "Width", kind = "number", min = MIN_SIZE, applies = always },
	{ key = "h", label = "Height", kind = "number", min = MIN_SIZE, applies = always },
	{ key = "color", label = "Color", kind = "color", applies = always },
	{ key = "transparency", label = "Transparency", kind = "number", min = 0, max = 1, applies = always },
	{ key = "radius", label = "Corner", kind = "number", min = 0, applies = notRoot },
	{ key = "text", label = "Text", kind = "string", applies = hasText },
	{ key = "textSize", label = "Text Size", kind = "number", min = 1, applies = hasText },
	{ key = "textColor", label = "Text Color", kind = "color", applies = hasText },
	{ key = "image", label = "Image", kind = "string", applies = hasImage },
}

local function formatValue(field, value)
	if field.kind == "number" then
		return fmt(value)
	end

	return tostring(value)
end

return function(content, windowControls)
	local root = newNode(0, "Frame", "Screen")

	root.w, root.h = 640, 360
	root.color = "#1F2229"

	local nextId = 1
	local selected = nil
	local sceneName = "Scene"

	local zoom, panX, panY = 1, 20, 20

	local undoStack, redoStack = {}, {}
	local drag = nil

	local treeDirty, inspectorDirty = true, true
	local inspectorFields = {}

	local handleRects = {}
	local HANDLE_DIRS = {
		{ -1, -1 },
		{ 0, -1 },
		{ 1, -1 },
		{ 1, 0 },
		{ 1, 1 },
		{ 0, 1 },
		{ -1, 1 },
		{ -1, 0 },
	}

	local applyNode
	local rebuildCanvas
	local updateOverlay
	local selectNode

	local function tabActive()
		if windowControls == nil or windowControls.getSelectedTab == nil then
			return true
		end

		return windowControls.getSelectedTab() == TAB_NAME
	end

	local function snap(value)
		return math.floor(value + 0.5)
	end

	local function markTree()
		treeDirty = true
	end

	local function markInspector()
		inspectorDirty = true
	end

	local rowHeight = UI.metrics.inputHeight
	local row1Y = 6
	local row2Y = row1Y + rowHeight + 4
	local bodyTop = row2Y + rowHeight + 6

	local function makeScroll(position, size)
		local l = UI.create("ScrollingFrame", {
			Position = position,
			Size = size,

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
			ScrollBarMinimumHandleSize = 24,

			ClipsDescendants = true,
			Active = true,
			InputSink = true,
		}, content)

		UI.corner(l, tokens.radius.md)

		return l
	end

	local treeList = makeScroll(UDim2.fromOffset(inset, bodyTop), UDim2.new(0, TREE_W, 1, -(bodyTop + 6)))

	local inspectorList =
		makeScroll(UDim2.new(1, -(inset + INSPECTOR_W), 0, bodyTop), UDim2.new(0, INSPECTOR_W, 1, -(bodyTop + 6)))

	local viewFrame = UI.create("Frame", {
		Position = UDim2.fromOffset(inset + TREE_W + 4, bodyTop),
		Size = UDim2.new(1, -(inset * 2 + TREE_W + INSPECTOR_W + 8), 1, -(bodyTop + 6)),
		BackgroundColor3 = tokens.color.input,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Active = true,
	}, content)

	UI.corner(viewFrame, tokens.radius.md)

	local screenFrame = UI.create("Frame", {
		Position = UDim2.fromOffset(panX, panY),
		Size = UDim2.fromOffset(root.w, root.h),
		BackgroundColor3 = hexToColor(root.color),
		BorderSizePixel = 0,
		Active = false,
	}, viewFrame)

	root.gui = screenFrame

	local edges, handles = {}, {}

	for index = 1, 4 do
		edges[index] = UI.create("Frame", {
			BackgroundColor3 = colors.selection,
			BorderSizePixel = 0,
			Active = false,
			ZIndex = 5000,
			Visible = false,
			Size = UDim2.fromOffset(2, 2),
		}, viewFrame)
	end

	for index = 1, 8 do
		handles[index] = UI.create("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Active = false,
			ZIndex = 5001,
			Visible = false,
			Size = UDim2.fromOffset(HANDLE, HANDLE),
		}, viewFrame)
	end

	local zoomLabel = UI.label(
		content,
		"100%",
		UDim2.new(1, -(inset + 56), 0, row2Y + 2),
		UDim2.fromOffset(56, 16),
		tokens.type.small,
		tokens.color.muted
	)

	applyNode = function(node)
		local gui = node.gui

		if gui == nil or not UI.isAlive(gui) then
			return
		end

		local def = CLASSES[node.class]

		if node.parent == nil then
			setProps(gui, {
				Position = UDim2.fromOffset(panX, panY),
				Size = UDim2.fromOffset(node.w * zoom, node.h * zoom),
			})
		else
			setProps(gui, {
				Position = UDim2.fromOffset(node.x * zoom, node.y * zoom),
				Size = UDim2.fromOffset(node.w * zoom, node.h * zoom),
			})
		end

		setProps(gui, {
			BackgroundColor3 = hexToColor(node.color) or Color3.new(0, 0, 0),
			BackgroundTransparency = node.transparency,
			BorderSizePixel = 0,
			Active = false,
		})

		if def.hasText then
			setProps(gui, {
				Text = node.text,
				TextColor3 = hexToColor(node.textColor) or Color3.new(1, 1, 1),
				TextSize = math.max(1, math.floor(node.textSize * zoom + 0.5)),
				TextWrapped = true,
			})
		end

		if def.hasImage then
			setProps(gui, { Image = node.image })
		end

		if node.corner ~= nil then
			setProps(node.corner, { CornerRadius = UDim.new(0, node.radius * zoom) })
		end
	end

	local function realize(node, parentGui, depth, index)
		local gui = UI.create(node.class, { ZIndex = depth * 50 + index }, parentGui)

		node.gui = gui
		node.corner = nil

		local ok, corner = pcall(function()
			local c = Instance.new("UICorner")

			c.Name = "EditorCorner"
			c.Parent = gui

			return c
		end)

		if ok then
			node.corner = corner
		end

		applyNode(node)

		for childIndex, child in ipairs(node.children) do
			realize(child, gui, depth + 1, childIndex)
		end
	end

	rebuildCanvas = function()
		UI.clear(screenFrame)

		root.gui = screenFrame
		root.corner = nil

		applyNode(root)

		for index, child in ipairs(root.children) do
			realize(child, screenFrame, 1, index)
		end

		updateOverlay()

		zoomLabel.Text = string.format("%d%%", math.floor(zoom * 100 + 0.5))
	end

	updateOverlay = function()
		local node = selected

		if node == nil then
			for _, piece in ipairs(edges) do
				piece.Visible = false
			end

			for _, piece in ipairs(handles) do
				piece.Visible = false
			end

			return
		end

		local ax, ay = absolutePosition(node)

		local x = panX + ax * zoom
		local y = panY + ay * zoom
		local w = node.w * zoom
		local h = node.h * zoom

		local rects = {
			{ x, y, w, 2 },
			{ x, y + h - 2, w, 2 },
			{ x, y, 2, h },
			{ x + w - 2, y, 2, h },
		}

		for index, rect in ipairs(rects) do
			edges[index].Visible = true
			edges[index].Position = UDim2.fromOffset(rect[1], rect[2])
			edges[index].Size = UDim2.fromOffset(math.max(2, rect[3]), math.max(2, rect[4]))
		end

		local anchors = {
			{ x, y },
			{ x + w / 2, y },
			{ x + w, y },
			{ x + w, y + h / 2 },
			{ x + w, y + h },
			{ x + w / 2, y + h },
			{ x, y + h },
			{ x, y + h / 2 },
		}

		for index, anchor in ipairs(anchors) do
			handleRects[index] = anchor

			handles[index].Visible = node.parent ~= nil
			handles[index].Position = UDim2.fromOffset(anchor[1] - HANDLE / 2, anchor[2] - HANDLE / 2)
		end
	end

	local function checkpoint()
		undoStack[#undoStack + 1] = json.encode(toData(root))

		if #undoStack > HISTORY_LIMIT then
			table.remove(undoStack, 1)
		end

		redoStack = {}
	end

	local function restore(state, selectedId)
		local ok, data = pcall(json.decode, state)

		if not ok or type(data) ~= "table" then
			toastMessage("error", "Could not restore", "The saved scene state was invalid.")
			return false
		end

		root = fromData(data, nil)
		nextId = maxId(root) + 1
		selected = selectedId and findById(root, selectedId) or nil

		rebuildCanvas()
		markTree()
		markInspector()

		return true
	end

	local function undo()
		if #undoStack == 0 then
			return
		end

		redoStack[#redoStack + 1] = json.encode(toData(root))

		restore(table.remove(undoStack), selected and selected.id or nil)
	end

	local function redo()
		if #redoStack == 0 then
			return
		end

		undoStack[#undoStack + 1] = json.encode(toData(root))

		restore(table.remove(redoStack), selected and selected.id or nil)
	end

	selectNode = function(node)
		selected = node

		updateOverlay()
		markTree()
		markInspector()
	end

	local function refreshTree()
		local oldPosition = treeList.CanvasPosition

		UI.clear(treeList)

		local y = 1

		local function walk(node, depth)
			local isSelected = node == selected

			local row = UI.button(
				treeList,
				"",
				UDim2.fromOffset(1, y),
				UDim2.new(1, -2, 0, UI.metrics.treeRow),
				function()
					selectNode(node)
				end,
				{
					color = isSelected and colors.selection or tokens.color.rowEven,
					hoverColor = isSelected and colors.selection or colors.hover,
					radius = isSelected and tokens.radius.sm or 0,
					border = false,
				}
			)

			row.BackgroundTransparency = isSelected and 0 or 0.12

			local indent = 6 + depth * 14

			UI.image(row, CLASSES[node.class].icon, UDim2.fromOffset(indent, 3), UDim2.fromOffset(14, 14))

			UI.label(
				row,
				node.name,
				UDim2.fromOffset(indent + 19, 2),
				UDim2.new(1, -(indent + 22), 0, 17),
				tokens.type.small,
				isSelected and tokens.color.text or colors.text
			)

			y += UI.metrics.treeRow

			for _, child in ipairs(node.children) do
				walk(child, depth + 1)
			end
		end

		walk(root, 0)

		treeList.CanvasSize = UDim2.new(1, 0, 0, y + 4)
		treeList.CanvasPosition = oldPosition
	end

	local function refreshInspectorValues()
		if selected == nil then
			return
		end

		for _, field in ipairs(FIELDS) do
			local box = inspectorFields[field.key]

			if box ~= nil and UI.isAlive(box) then
				local focused = false

				pcall(function()
					focused = box:IsFocused()
				end)

				if not focused then
					box.Text = formatValue(field, selected[field.key])
				end
			end
		end
	end

	local function commitField(field, box, input)
		local node = selected

		if node == nil then
			return
		end

		local function revert()
			box.Text = formatValue(field, node[field.key])
		end

		if input ~= nil and input.KeyCode == Enum.KeyCode.Escape then
			revert()
			return
		end

		local value

		if field.kind == "number" then
			value = tonumber(box.Text)

			if value == nil then
				revert()
				return
			end

			if field.min ~= nil then
				value = math.max(field.min, value)
			end

			if field.max ~= nil then
				value = math.min(field.max, value)
			end
		elseif field.kind == "color" then
			value = normalizeHex(box.Text)

			if value == nil then
				toastMessage("warning", "Invalid color", "Use a hex color like #3A3F4B.")
				revert()
				return
			end
		else
			value = box.Text

			if field.key == "name" and value == "" then
				revert()
				return
			end
		end

		if value == node[field.key] then
			revert()
			return
		end

		checkpoint()

		node[field.key] = value

		applyNode(node)
		updateOverlay()

		box.Text = formatValue(field, value)

		if field.key == "name" then
			markTree()
		end
	end

	local function refreshInspector()
		UI.clear(inspectorList)

		inspectorFields = {}

		if selected == nil then
			UI.label(
				inspectorList,
				"Nothing selected",
				UDim2.fromOffset(8, 8),
				UDim2.new(1, -16, 0, 18),
				tokens.type.small,
				tokens.color.muted
			)

			inspectorList.CanvasSize = UDim2.new(1, 0, 0, 40)

			return
		end

		local y = 6

		UI.label(
			inspectorList,
			selected.class,
			UDim2.fromOffset(6, y),
			UDim2.new(1, -12, 0, 16),
			tokens.type.small,
			tokens.color.muted
		)

		y += 22

		for _, field in ipairs(FIELDS) do
			if field.applies(selected) then
				UI.label(
					inspectorList,
					field.label,
					UDim2.fromOffset(6, y + 3),
					UDim2.fromOffset(64, 16),
					tokens.type.small,
					tokens.color.subtext
				)

				local box = UI.input(
					inspectorList,
					"",
					UDim2.fromOffset(72, y),
					UDim2.new(1, -80, 0, rowHeight),
					{ textSize = tokens.type.small, color = tokens.color.input }
				)

				box.Text = formatValue(field, selected[field.key])

				inspectorFields[field.key] = box

				box.FocusLost:Connect(function(_, input)
					commitField(field, box, input)
				end)

				y += rowHeight + 4
			end
		end

		inspectorList.CanvasSize = UDim2.new(1, 0, 0, y + 6)
	end

	local function indexInParent(node)
		if node.parent == nil then
			return nil
		end

		return table.find(node.parent.children, node)
	end

	local function uniqueName(parent, base)
		local used = {}

		for _, child in ipairs(parent.children) do
			used[child.name] = true
		end

		if not used[base] then
			return base
		end

		for index = 2, 999 do
			local candidate = base .. index

			if not used[candidate] then
				return candidate
			end
		end

		return base
	end

	local function addNode(class)
		if CLASSES[class] == nil then
			return
		end

		local parent = selected or root

		if parent.class ~= "Frame" then
			parent = parent.parent or root
		end

		checkpoint()

		local node = newNode(nextId, class, uniqueName(parent, class))

		nextId += 1

		local offset = (#parent.children % 8) * 10

		node.x = 12 + offset
		node.y = 12 + offset
		node.parent = parent

		table.insert(parent.children, node)

		rebuildCanvas()
		selectNode(node)
	end

	local function deleteSelected()
		if selected == nil or selected.parent == nil then
			return
		end

		checkpoint()

		local parent = selected.parent
		local index = indexInParent(selected)

		if index ~= nil then
			table.remove(parent.children, index)
		end

		rebuildCanvas()
		selectNode(parent)
	end

	local function duplicateSelected()
		if selected == nil or selected.parent == nil then
			return
		end

		checkpoint()

		local parent = selected.parent
		local copy = fromData(toData(selected), parent)

		local function reassign(node)
			node.id = nextId
			nextId += 1

			for _, child in ipairs(node.children) do
				reassign(child)
			end
		end

		reassign(copy)

		copy.name = uniqueName(parent, selected.name)
		copy.x += 8
		copy.y += 8

		table.insert(parent.children, (indexInParent(selected) or #parent.children) + 1, copy)

		rebuildCanvas()
		selectNode(copy)
	end

	local function reorderSelected(delta)
		if selected == nil or selected.parent == nil then
			return
		end

		local siblings = selected.parent.children
		local index = indexInParent(selected)
		local target = index + delta

		if target < 1 or target > #siblings then
			return
		end

		checkpoint()

		siblings[index], siblings[target] = siblings[target], siblings[index]

		rebuildCanvas()
		markTree()
	end

	local function indentSelected()
		if selected == nil or selected.parent == nil then
			return
		end

		local siblings = selected.parent.children
		local index = indexInParent(selected)

		if index <= 1 then
			return
		end

		local newParent = siblings[index - 1]

		checkpoint()

		table.remove(siblings, index)

		selected.x -= newParent.x
		selected.y -= newParent.y
		selected.parent = newParent

		table.insert(newParent.children, selected)

		rebuildCanvas()
		markTree()
		markInspector()
	end

	local function outdentSelected()
		if selected == nil or selected.parent == nil or selected.parent.parent == nil then
			return
		end

		local parent = selected.parent
		local grandparent = parent.parent

		checkpoint()

		table.remove(parent.children, indexInParent(selected))

		selected.x += parent.x
		selected.y += parent.y
		selected.parent = grandparent

		table.insert(grandparent.children, (indexInParent(parent) or #grandparent.children) + 1, selected)

		rebuildCanvas()
		markTree()
		markInspector()
	end

	local function nudgeSelected(dx, dy)
		if selected == nil or selected.parent == nil then
			return
		end

		checkpoint()

		selected.x += dx
		selected.y += dy

		applyNode(selected)
		updateOverlay()
		refreshInspectorValues()
	end

	local function projectRoot()
		local project = Project:GetActiveProject()

		return project and project.Path or nil
	end

	local function saveScene()
		local directory = projectRoot()

		if directory == nil then
			toastMessage("warning", "No active project", "Open a project before saving a scene.")
			return
		end

		local path = ensureFile(directory, sceneName .. SCENE_EXT)

		if path ~= nil and writeText(path, json.encode(toData(root))) then
			toastMessage("success", "Scene saved", sceneName .. SCENE_EXT)
		else
			toastMessage(
				"error",
				"Could not save",
				"Project has no working write API. Adapt writeText() at the top of the file."
			)
		end
	end

	local function exportLua()
		local directory = projectRoot()

		if directory == nil then
			toastMessage("warning", "No active project", "Open a project before exporting.")
			return
		end

		local path = ensureFile(directory, sceneName .. LUA_EXT)

		if path ~= nil and writeText(path, generateLua(root)) then
			toastMessage("success", "Exported", sceneName .. LUA_EXT)
		else
			toastMessage(
				"error",
				"Could not export",
				"Project has no working write API. Adapt writeText() at the top of the file."
			)
		end
	end

	local function loadScene(path)
		local text = path and readText(path)

		if text == nil then
			toastMessage("error", "Could not open", "Failed to read the scene file.")
			return
		end

		local ok, data = pcall(json.decode, text)

		if not ok or type(data) ~= "table" then
			toastMessage("error", "Could not open", "That file is not a valid .uiscene.")
			return
		end

		checkpoint()

		root = fromData(data, nil)
		nextId = maxId(root) + 1
		selected = nil

		local name = path:match("([^/\\]+)$") or "Scene"

		sceneName = name:gsub("%.uiscene$", "")

		panX, panY, zoom = 20, 20, 1

		rebuildCanvas()
		markTree()
		markInspector()
	end

	local function openDialog()
		local file = dialog:PickFile()

		if file then
			loadScene(file)
		end
	end

	local buttonOptions = {
		color = tokens.color.input,
		hoverColor = tokens.color.hover,
		radius = tokens.radius.sm,
		border = false,
	}

	local nameBox = UI.input(
		content,
		"Scene name",
		UDim2.fromOffset(inset, row1Y),
		UDim2.new(1, -(inset * 2 + 44 + 4 + 44 + 4 + 52 + 4), 0, rowHeight)
	)

	nameBox.Text = sceneName

	nameBox.FocusLost:Connect(function()
		local cleaned = nameBox.Text:gsub("[^%w_%-]", "")

		sceneName = cleaned ~= "" and cleaned or "Scene"
		nameBox.Text = sceneName
	end)

	UI.button(
		content,
		"Save",
		UDim2.new(1, -(inset + 44), 0, row1Y),
		UDim2.fromOffset(44, rowHeight),
		saveScene,
		buttonOptions
	)

	UI.button(
		content,
		"Open",
		UDim2.new(1, -(inset + 44 + 4 + 44), 0, row1Y),
		UDim2.fromOffset(44, rowHeight),
		openDialog,
		buttonOptions
	)

	UI.button(
		content,
		"Export",
		UDim2.new(1, -(inset + 44 + 4 + 44 + 4 + 52), 0, row1Y),
		UDim2.fromOffset(52, rowHeight),
		exportLua,
		buttonOptions
	)

	local addItems = {}

	for _, class in ipairs(CLASS_ORDER) do
		addItems[#addItems + 1] = { label = class, value = class, icon = CLASSES[class].icon }
	end

	UI.dropdown(content, "", UDim2.fromOffset(inset, row2Y), UDim2.fromOffset(26, rowHeight), nil, {
		items = addItems,
		searchPlaceholder = "Add node...",

		icon = "builtin://global-icons/plus.svg",
		iconSize = 14,
		backdrop = true,

		color = tokens.color.input,
		hoverColor = tokens.color.hover,
		closeOnOutsideClick = false,
		menuWidth = 150,
		itemBgTransparency = 1,
		BackgroundTransparency = 0.5,

		menuPosition = function()
			local mouse = UserInputService:GetMouseLocation()

			return UDim2.fromOffset(mouse.X, mouse.Y)
		end,

		maxVisibleItems = #addItems,
		itemHeight = rowHeight,

		onChanged = function(value)
			addNode(value)
		end,
	})

	local toolbar = {
		{ "Del", 32, deleteSelected },
		{ "Dup", 32, duplicateSelected },
		{
			"Up",
			30,
			function()
				reorderSelected(-1)
			end,
		},
		{
			"Down",
			40,
			function()
				reorderSelected(1)
			end,
		},
		{ "In", 26, indentSelected },
		{ "Out", 30, outdentSelected },
		{ "Undo", 38, undo },
		{ "Redo", 38, redo },
	}

	local toolbarX = inset + 26 + 4

	for _, item in ipairs(toolbar) do
		UI.button(
			content,
			item[1],
			UDim2.fromOffset(toolbarX, row2Y),
			UDim2.fromOffset(item[2], rowHeight),
			item[3],
			buttonOptions
		)

		toolbarX += item[2] + 4
	end

	local function mouseLocal()
		local mouse = UserInputService:GetMouseLocation()
		local origin = viewFrame.AbsolutePosition

		return mouse.X - origin.X, mouse.Y - origin.Y
	end

	local function toDesign(mx, my)
		return (mx - panX) / zoom, (my - panY) / zoom
	end

	local function handleAt(mx, my)
		for index, anchor in ipairs(handleRects) do
			if math.abs(mx - anchor[1]) <= HANDLE / 2 + 2 and math.abs(my - anchor[2]) <= HANDLE / 2 + 2 then
				return index
			end
		end

		return nil
	end

	local function releaseTextFocus()
		pcall(function()
			local focused = UserInputService:GetFocusedTextBox()

			if focused ~= nil then
				focused:ReleaseFocus()
			end
		end)
	end

	viewFrame.InputBegan:Connect(function(input)
		local kind = input.UserInputType

		releaseTextFocus()

		local mx, my = mouseLocal()

		if kind == Enum.UserInputType.MouseButton2 or kind == Enum.UserInputType.MouseButton3 then
			drag = { mode = "pan", sx = mx, sy = my, panX = panX, panY = panY, moved = true }
			return
		end

		if kind ~= Enum.UserInputType.MouseButton1 then
			return
		end

		if selected ~= nil and selected.parent ~= nil then
			local handle = handleAt(mx, my)

			if handle ~= nil then
				drag = {
					mode = "resize",
					node = selected,
					handle = handle,
					sx = mx,
					sy = my,
					rect = { x = selected.x, y = selected.y, w = selected.w, h = selected.h },
					moved = false,
				}

				return
			end
		end

		local px, py = toDesign(mx, my)
		local hit = hitTest(root, 0, 0, px, py)

		selectNode(hit)

		if hit ~= nil and hit.parent ~= nil then
			drag = {
				mode = "move",
				node = hit,
				sx = mx,
				sy = my,
				rect = { x = hit.x, y = hit.y, w = hit.w, h = hit.h },
				moved = false,
			}
		end
	end)

	viewFrame.InputChanged:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseWheel then
			return
		end

		local mx, my = mouseLocal()
		local px, py = toDesign(mx, my)

		local factor = input.Position.Z > 0 and 1.1 or 1 / 1.1
		local newZoom = math.clamp(math.floor(zoom * factor * 100 + 0.5) / 100, MIN_ZOOM, MAX_ZOOM)

		if newZoom == zoom then
			return
		end

		zoom = newZoom
		panX = mx - px * zoom
		panY = my - py * zoom

		rebuildCanvas()
	end)

	UserInputService.InputChanged:Connect(function(input)
		if drag == nil or input.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end

		local mx, my = mouseLocal()

		if drag.mode == "pan" then
			panX = drag.panX + (mx - drag.sx)
			panY = drag.panY + (my - drag.sy)

			applyNode(root)
			updateOverlay()

			return
		end

		local dxPx = mx - drag.sx
		local dyPx = my - drag.sy

		if not drag.moved then
			if math.sqrt(dxPx * dxPx + dyPx * dyPx) < 3 then
				return
			end

			drag.moved = true

			checkpoint()
		end

		local dx = dxPx / zoom
		local dy = dyPx / zoom

		local node = drag.node
		local rect = drag.rect

		if drag.mode == "move" then
			node.x = snap(rect.x + dx)
			node.y = snap(rect.y + dy)
		else
			local dir = HANDLE_DIRS[drag.handle]

			local nx, ny, nw, nh = rect.x, rect.y, rect.w, rect.h

			if dir[1] == -1 then
				nw = math.max(MIN_SIZE, snap(rect.w - dx))
				nx = rect.x + rect.w - nw
			elseif dir[1] == 1 then
				nw = math.max(MIN_SIZE, snap(rect.w + dx))
			end

			if dir[2] == -1 then
				nh = math.max(MIN_SIZE, snap(rect.h - dy))
				ny = rect.y + rect.h - nh
			elseif dir[2] == 1 then
				nh = math.max(MIN_SIZE, snap(rect.h + dy))
			end

			node.x, node.y, node.w, node.h = nx, ny, nw, nh
		end

		applyNode(node)
		updateOverlay()
		refreshInspectorValues()
	end)

	UserInputService.InputEnded:Connect(function(input)
		local kind = input.UserInputType

		if
			drag ~= nil
			and (
				kind == Enum.UserInputType.MouseButton1
				or kind == Enum.UserInputType.MouseButton2
				or kind == Enum.UserInputType.MouseButton3
			)
		then
			drag = nil
		end
	end)

	local function ctrlDown()
		return UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
	end

	local function shiftDown()
		return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
	end

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not tabActive() then
			return
		end

		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end

		if UserInputService:GetFocusedTextBox() ~= nil then
			return
		end

		local key = input.KeyCode

		if ctrlDown() then
			if key == Enum.KeyCode.Z then
				if shiftDown() then
					redo()
				else
					undo()
				end
			elseif key == Enum.KeyCode.Y then
				redo()
			elseif key == Enum.KeyCode.S then
				saveScene()
			elseif key == Enum.KeyCode.D then
				duplicateSelected()
			end

			return
		end

		local step = shiftDown() and 10 or 1

		if key == Enum.KeyCode.Delete then
			deleteSelected()
		elseif key == Enum.KeyCode.Escape then
			selectNode(nil)
		elseif key == Enum.KeyCode.Left then
			nudgeSelected(-step, 0)
		elseif key == Enum.KeyCode.Right then
			nudgeSelected(step, 0)
		elseif key == Enum.KeyCode.Up then
			nudgeSelected(0, -step)
		elseif key == Enum.KeyCode.Down then
			nudgeSelected(0, step)
		end
	end)

	rebuildCanvas()

	renderer.Pool.new("2d", function()
		if not tabActive() then
			return
		end

		if treeDirty then
			treeDirty = false
			refreshTree()
		end

		if inspectorDirty then
			inspectorDirty = false
			refreshInspector()
		end
	end)

	return {
		OpenScene = loadScene,

		GetSceneName = function()
			return sceneName
		end,

		Refresh = function()
			rebuildCanvas()
			markTree()
			markInspector()
		end,
	}
end

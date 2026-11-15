if IsServer or IsClient or IsPlaytest then
	return nil
end

local UI = require("@internal/editor_ui")
local UserInputService = game:GetService("UserInputService")
local Selection = game:GetService("Selection")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")

local tokens = UI.tokens
local colors = tokens.color
local ACCENT = Color3.fromRGB(89, 126, 255)
local CANVAS_BG = Color3.fromRGB(28, 30, 36)
local SIDE_BG = colors.panel
local FIELD_H = 29
local ROW_H = 27
local LEFT_W, RIGHT_W = 210, 265
local TOP_H, STATUS_H = 44, 24
local DEFAULT_W, DEFAULT_H = 960, 600
local MIN_ZOOM, MAX_ZOOM = 0.2, 3
local MAX_LAYERS = 600
local supported = {
	Frame = true,
	TextLabel = true,
	TextButton = true,
	TextBox = true,
	ImageLabel = true,
	ImageButton = true,
	ScrollingFrame = true,
}
local decorations = {
	UICorner = true,
	UIStroke = true,
	UIGradient = true,
	UIPadding = true,
	UIAspectRatioConstraint = true,
	UISizeConstraint = true,
	UITextSizeConstraint = true,
	UIListLayout = true,
	UIGridLayout = true,
}
local mirroredProperties = {
	"Position",
	"Size",
	"AnchorPoint",
	"Rotation",
	"Visible",
	"ZIndex",
	"BackgroundColor3",
	"BackgroundTransparency",
	"BorderSizePixel",
	"BorderColor3",
	"ClipsDescendants",
	"LayoutOrder",
	"SizeConstraint",
	"AutomaticSize",
	"Text",
	"TextColor3",
	"TextTransparency",
	"TextSize",
	"TextScaled",
	"TextWrapped",
	"TextXAlignment",
	"TextYAlignment",
	"Font",
	"FontFace",
	"RichText",
	"PlaceholderText",
	"PlaceholderColor3",
	"ClearTextOnFocus",
	"Image",
	"ImageColor3",
	"ImageTransparency",
	"ScaleType",
	"SliceCenter",
	"SliceScale",
	"ScrollBarThickness",
	"CanvasSize",
	"CanvasPosition",
	"ScrollingEnabled",
}

local function make(className, props, parent)
	return UI.create(className, props or {}, parent)
end
local function label(parent, text, position, size, fontSize, color)
	local out = UI.label(parent, text, position, size, fontSize or tokens.type.body, color or colors.text)
	out.TextXAlignment = Enum.TextXAlignment.Left
	return out
end
local function button(parent, text, pos, size, callback, opts)
	return UI.button(parent, text, pos, size, callback, opts or {
		color = colors.surface,
		hoverColor = colors.hover,
		radius = 5,
		border = false,
	})
end
local function inside(frame, point)
	if not frame or not frame.Visible then
		return false
	end
	local p, s = frame.AbsolutePosition, frame.AbsoluteSize
	return point.X >= p.X and point.Y >= p.Y and point.X <= p.X + s.X and point.Y <= p.Y + s.Y
end
local function valid(inst)
	return inst ~= nil and inst.Parent ~= nil
end
local function descendantOf(inst, root)
	while inst ~= nil do
		if inst == root then
			return true
		end
		inst = inst.Parent
	end
	return false
end
local function guiObject(inst)
	if not inst then
		return false
	end
	local ok, result = pcall(function()
		return inst:IsA("GuiObject")
	end)
	return ok and result
end
local function currentScreenGui(inst)
	while inst do
		if inst.ClassName == "ScreenGui" then
			return inst
		end
		inst = inst.Parent
	end
	return nil
end
local function pickScreenGui()
	for _, inst in ipairs(Selection:Get() or {}) do
		local root = currentScreenGui(inst)
		if root then
			return root, inst
		end
	end
	for _, inst in ipairs(StarterGui:GetChildren()) do
		if inst.ClassName == "ScreenGui" then
			return inst, nil
		end
	end
	return nil, nil
end
local function colorHex(c)
	return string.format(
		"#%02X%02X%02X",
		math.floor(c.R * 255 + 0.5),
		math.floor(c.G * 255 + 0.5),
		math.floor(c.B * 255 + 0.5)
	)
end
local function parseColor(s)
	if type(s) ~= "string" then
		return nil
	end
	local h = string.match(s, "^%s*#?(%x%x%x%x%x%x)%s*$")
	if not h then
		return nil
	end
	return Color3.fromRGB(tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16))
end
local function safeGet(inst, property)
	local ok, value = pcall(function()
		return inst[property]
	end)
	return ok and value or nil
end
local function safeSet(inst, property, value)
	local ok = pcall(function()
		inst[property] = value
	end)
	return ok
end
local function clearChildren(frame)
	for _, child in ipairs(frame:GetChildren()) do
		child:Destroy()
	end
end
local function copyScaled(original, preview, scale)
	for _, key in ipairs(mirroredProperties) do
		local v = safeGet(original, key)
		if v ~= nil then
			if key == "Position" or key == "Size" then
				v = UDim2.new(v.X.Scale, v.X.Offset * scale, v.Y.Scale, v.Y.Offset * scale)
			elseif key == "TextSize" or key == "ScrollBarThickness" then
				v *= scale
			elseif key == "CanvasSize" then
				v = UDim2.new(v.X.Scale, v.X.Offset * scale, v.Y.Scale, v.Y.Offset * scale)
			elseif key == "CanvasPosition" then
				v = v * scale
			end
			safeSet(preview, key, v)
		end
	end
	safeSet(preview, "Active", false)
	safeSet(preview, "InputSink", false)
	if original.ClassName == "TextBox" then
		safeSet(preview, "TextEditable", false)
	end
	if original.ClassName == "ScrollingFrame" then
		safeSet(preview, "ScrollingEnabled", false)
	end
end

local overlay = UI.widgetOverlay()
local connections = {}
local panel, content = UI.window(
	"GUIDesigner",
	UDim2.fromOffset(65, 45),
	UDim2.fromOffset(1190, 735),
	"Interface Designer",
	{ closable = true }
)
panel.Parent = UI.widgetOverlay()
panel.Visible = false
panel.BackgroundTransparency = 0.5
panel.ClipsDescendants = true
content.BackgroundTransparency = 1

UI.backdrop(panel, 15, Color3.new(0, 0, 0))

local windowBounds = make("Frame", {
	Name = "GUIDesignerWindowBounds",
	BackgroundTransparency = 1,
	Active = false,
	InputSink = false,
	Size = UDim2.fromScale(1, 1),
}, overlay)
local function fitWindow()
	local s = windowBounds.AbsoluteSize
	if s.X < 100 or s.Y < 100 then
		return
	end
	local w = math.min(1190, math.max(360, s.X - 20))
	local h = math.min(735, math.max(300, s.Y - 20))
	panel.Size = UDim2.fromOffset(w, h)
	local p = panel.Position
	panel.Position = UDim2.fromOffset(
		math.clamp(p.X.Offset, 0, math.max(0, s.X - w)),
		math.clamp(p.Y.Offset, 0, math.max(0, s.Y - h))
	)
end
connections[#connections + 1] = windowBounds:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitWindow)
fitWindow()

local toolbar = make("Frame", {
	Name = "Toolbar",
	Position = UDim2.fromOffset(0, 0),
	Size = UDim2.new(1, 0, 0, TOP_H),
	BorderSizePixel = 0,
	BackgroundColor3 = colors.panel,
}, content)
local left = make("Frame", {
	Name = "Layers",
	Position = UDim2.fromOffset(0, TOP_H),
	Size = UDim2.new(0, LEFT_W, 1, -(TOP_H + STATUS_H)),
	BackgroundColor3 = SIDE_BG,
	BorderSizePixel = 0,
}, content)
local right = make("Frame", {
	Name = "Inspector",
	Position = UDim2.new(1, -RIGHT_W, 0, TOP_H),
	Size = UDim2.new(0, RIGHT_W, 1, -(TOP_H + STATUS_H)),
	BackgroundColor3 = SIDE_BG,
	BorderSizePixel = 0,
}, content)
local stage = make("Frame", {
	Name = "CanvasViewport",
	Position = UDim2.fromOffset(LEFT_W, TOP_H),
	Size = UDim2.new(1, -(LEFT_W + RIGHT_W), 1, -(TOP_H + STATUS_H)),
	BorderSizePixel = 0,
	BackgroundColor3 = CANVAS_BG,
	ClipsDescendants = true,
	Active = true,
	InputSink = true,
}, content)
local status = make("Frame", {
	Position = UDim2.new(0, 0, 1, -STATUS_H),
	Size = UDim2.new(1, 0, 0, STATUS_H),
	BackgroundColor3 = colors.panel,
	BorderSizePixel = 0,
}, content)
local function relayoutPanels()
	local available = content.AbsoluteSize.X
	if available <= 0 then
		return
	end
	local lw = math.min(LEFT_W, math.max(115, math.floor(available * 0.22)))
	local rw = math.min(RIGHT_W, math.max(130, math.floor(available * 0.27)))
	left.Size = UDim2.new(0, lw, 1, -(TOP_H + STATUS_H))
	right.Position = UDim2.new(1, -rw, 0, TOP_H)
	right.Size = UDim2.new(0, rw, 1, -(TOP_H + STATUS_H))
	stage.Position = UDim2.fromOffset(lw, TOP_H)
	stage.Size = UDim2.new(1, -lw - rw, 1, -(TOP_H + STATUS_H))
end
connections[#connections + 1] = content:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayoutPanels)
relayoutPanels()
local statusLabel = label(
	status,
	"Choose a ScreenGui or create a new one",
	UDim2.fromOffset(12, 2),
	UDim2.new(1, -24, 1, -4),
	tokens.type.small,
	colors.subtext
)

local ruler = make("Frame", {
	Name = "Artboard",
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BorderSizePixel = 0,
	ZIndex = 4,
	ClipsDescendants = false,
	Size = UDim2.fromOffset(DEFAULT_W, DEFAULT_H),
}, stage)
local paper = make("Frame", {
	Name = "LivePreview",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 1),
	ClipsDescendants = true,
	ZIndex = 4,
}, ruler)
local empty = label(
	stage,
	"No ScreenGui selected. Use New GUI or Use Selection.",
	UDim2.new(0, 22, 0.5, -25),
	UDim2.new(1, -44, 0, 50),
	tokens.type.title,
	colors.subtext
)
empty.TextXAlignment = Enum.TextXAlignment.Center
empty.TextWrapped = true
empty.ZIndex = 7

local gridLines = {}
for i = 1, 30 do
	gridLines[#gridLines + 1] = make("Frame", {
		BackgroundColor3 = Color3.fromRGB(55, 58, 64),
		BackgroundTransparency = 0.62,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(1, 1),
		ZIndex = 1,
	}, stage)
end
local hit = make("Frame", {
	Name = "PointerCapture",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Active = true,
	InputSink = true,
	ZIndex = 1000,
}, stage)
local outline = make("Frame", {
	Name = "SelectionOutline",
	BackgroundTransparency = 1,
	BorderColor3 = ACCENT,
	BorderSizePixel = 1,
	ZIndex = 1004,
	Active = false,
	InputSink = false,
	Visible = false,
}, stage)
local sizeBadge = make("TextLabel", {
	Name = "SizeBadge",
	Position = UDim2.new(0, 0, 1, 7),
	Size = UDim2.fromOffset(100, 19),
	BackgroundColor3 = ACCENT,
	TextColor3 = Color3.fromRGB(255, 255, 255),
	BorderSizePixel = 0,
	TextSize = 11,
	ZIndex = 1005,
	Text = "",
	Visible = true,
}, outline)
UI.corner(sizeBadge, 4)
local handleSpecs = {
	{ "nw", 0, 0 },
	{ "n", 0.5, 0 },
	{ "ne", 1, 0 },
	{ "e", 1, 0.5 },
	{ "se", 1, 1 },
	{ "s", 0.5, 1 },
	{ "sw", 0, 1 },
	{ "w", 0, 0.5 },
}
local handles = {}
for _, entry in ipairs(handleSpecs) do
	local h = make("TextButton", {
		Name = "Handle_" .. entry[1],
		Text = "",
		Position = UDim2.new(entry[2], -4, entry[3], -4),
		Size = UDim2.fromOffset(9, 9),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 1,
		BorderColor3 = ACCENT,
		ZIndex = 1006,
		Active = true,
		InputSink = true,
	}, outline)
	handles[entry[1]] = h
end

local draft = make("Frame", {
	Name = "CreationGuide",
	Visible = false,
	BackgroundColor3 = ACCENT,
	BackgroundTransparency = 0.78,
	BorderSizePixel = 1,
	BorderColor3 = ACCENT,
	ZIndex = 1002,
	Active = false,
	InputSink = false,
}, stage)

label(left, "LAYERS", UDim2.fromOffset(12, 10), UDim2.fromOffset(100, 22), tokens.type.small, colors.subtext)
local layerFilter =
	UI.input(left, "Filter layers...", UDim2.fromOffset(9, 35), UDim2.new(1, -18, 0, UI.metrics.inputHeight))
local layerList = make("ScrollingFrame", {
	Name = "LayerItems",
	Position = UDim2.fromOffset(3, 70),
	Size = UDim2.new(1, -6, 1, -114),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollBarThickness = 4,
	ScrollBarImageColor3 = colors.subtext,
	ScrollingEnabled = true,
	Active = true,
	ClipsDescendants = true,
}, left)
local layerAdd = button(left, "+ Layer", UDim2.new(0, 8, 1, -38), UDim2.new(0.5, -12, 0, 29), nil)
local layerDuplicate = button(left, "Duplicate", UDim2.new(0.5, 4, 1, -38), UDim2.new(0.5, -12, 0, 29), nil)

label(right, "PROPERTIES", UDim2.fromOffset(12, 10), UDim2.fromOffset(200, 22), tokens.type.small, colors.subtext)
local inspectorScroll = make("ScrollingFrame", {
	Name = "PropertyFields",
	Position = UDim2.fromOffset(3, 37),
	Size = UDim2.new(1, -6, 1, -43),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollBarThickness = 4,
	ScrollBarImageColor3 = colors.subtext,
	ScrollingEnabled = true,
	Active = true,
	ClipsDescendants = true,
}, right)

local document = nil
local selected = nil
local width, height = DEFAULT_W, DEFAULT_H
local zoom = 1
local pan = Vector2.new(0, 0)
local tool = "Select"
local drag = nil
local drawingClass = nil
local expanded = {}
local locked = {}
local previewMap = {}
local hitEntries = {}
local viewConnections = {}
local dirtyRefresh = false
local drawingCount = 0
local history, historyIndex = {}, 0
local inspectorBuiltFor = nil

local refreshAll, renderScene, renderLayers, renderInspector, updateOutline, setSelected, selectDocument
local undo, redo, createAt, deleteSelected, duplicateSelected

local function emitStatus(message)
	statusLabel.Text = message
end
local function undoable(labelText, undoFn, redoFn)
	for i = #history, historyIndex + 1, -1 do
		history[i] = nil
	end
	history[#history + 1] = { name = labelText, undo = undoFn, redo = redoFn }
	historyIndex = #history
	if #history > 80 then
		table.remove(history, 1)
		historyIndex -= 1
	end
end
local function liveApply(target, key, value)
	if not target then
		return false
	end
	if not safeSet(target, key, value) then
		return false
	end
	local mirror = previewMap[target]
	if mirror then
		copyScaled(target, mirror, zoom)
	end
	if updateOutline then
		updateOutline()
	end
	return true
end
local function changeValue(target, key, oldValue, newValue)
	if oldValue == newValue then
		return
	end
	undoable("Change " .. key, function()
		safeSet(target, key, oldValue)
	end, function()
		safeSet(target, key, newValue)
	end)
	refreshAll()
end
local function screenToCanvas(point)
	local origin = ruler.AbsolutePosition
	return Vector2.new((point.X - origin.X) / zoom, (point.Y - origin.Y) / zoom)
end
local function canvasToStage(point)
	return Vector2.new(pan.X + point.X * zoom, pan.Y + point.Y * zoom)
end
local function updateGrid()
	local space = math.max(18, 32 * zoom)
	local size = stage.AbsoluteSize
	local countX = math.min(15, math.ceil(size.X / space) + 1)
	local countY = math.min(15, math.ceil(size.Y / space) + 1)
	for i, line in ipairs(gridLines) do
		if i <= 15 then
			line.Visible = i <= countX
			line.Position = UDim2.fromOffset((pan.X % space) + (i - 1) * space, 0)
			line.Size = UDim2.new(0, 1, 1, 0)
		else
			line.Visible = i - 15 <= countY
			line.Position = UDim2.fromOffset(0, (pan.Y % space) + (i - 16) * space)
			line.Size = UDim2.new(1, 0, 0, 1)
		end
	end
end
local function updatePaper()
	ruler.Size = UDim2.fromOffset(math.floor(width * zoom + 0.5), math.floor(height * zoom + 0.5))
	ruler.Position = UDim2.fromOffset(math.floor(pan.X + 0.5), math.floor(pan.Y + 0.5))
	ruler.Visible = document ~= nil
	empty.Visible = document == nil
	updateGrid()
	if updateOutline then
		updateOutline()
	end
end
local function setZoom(newZoom, atPoint)
	newZoom = math.clamp(newZoom, MIN_ZOOM, MAX_ZOOM)
	local pivot = atPoint or Vector2.new(stage.AbsoluteSize.X / 2, stage.AbsoluteSize.Y / 2)
	local relative = (pivot - pan) / zoom
	zoom = newZoom
	pan = pivot - relative * zoom
	updatePaper()
	renderScene()
end
local function fitView()
	local s = stage.AbsoluteSize
	if s.X <= 0 or s.Y <= 0 then
		return
	end
	zoom = math.clamp(math.min((s.X - 74) / width, (s.Y - 74) / height, 1), MIN_ZOOM, MAX_ZOOM)
	pan = (s - Vector2.new(width * zoom, height * zoom)) / 2
	updatePaper()
	renderScene()
end

local function decorationCopy(original, parent)
	local ok, copy = pcall(function()
		return original:Clone()
	end)
	if not ok or not copy then
		return
	end
	-- Decorative children are cloned separately from GuiObjects.
	for _, nested in ipairs(copy:GetChildren()) do
		nested:Destroy()
	end
	copy.Parent = parent
	if original.ClassName == "UICorner" then
		local r = safeGet(original, "CornerRadius")
		if r then
			safeSet(copy, "CornerRadius", UDim.new(r.Scale, r.Offset * zoom))
		end
	elseif original.ClassName == "UIPadding" then
		for _, key in ipairs({ "PaddingTop", "PaddingLeft", "PaddingRight", "PaddingBottom" }) do
			local r = safeGet(original, key)
			if r then
				safeSet(copy, key, UDim.new(r.Scale, r.Offset * zoom))
			end
		end
	elseif original.ClassName == "UIStroke" then
		local thickness = safeGet(original, "Thickness")
		if thickness then
			safeSet(copy, "Thickness", thickness * zoom)
		end
	elseif original.ClassName == "UIListLayout" then
		local padding = safeGet(original, "Padding")
		if padding then
			safeSet(copy, "Padding", UDim.new(padding.Scale, padding.Offset * zoom))
		end
	elseif original.ClassName == "UIGridLayout" then
		for _, key in ipairs({ "CellSize", "CellPadding" }) do
			local v = safeGet(original, key)
			if v then
				safeSet(copy, key, UDim2.new(v.X.Scale, v.X.Offset * zoom, v.Y.Scale, v.Y.Offset * zoom))
			end
		end
	end
end
local function renderNodes(parentSource, parentPreview, depth)
	if depth > 24 or #hitEntries >= MAX_LAYERS then
		return
	end
	for _, child in ipairs(parentSource:GetChildren()) do
		if supported[child.ClassName] then
			local ok, copy = pcall(Instance.new, child.ClassName)
			if ok and copy then
				copy.Name = "Preview_" .. child.Name
				copy.Parent = parentPreview
				copyScaled(child, copy, zoom)
				previewMap[child] = copy
				hitEntries[#hitEntries + 1] = { original = child, copy = copy, depth = depth, order = #hitEntries + 1 }
				for _, deco in ipairs(child:GetChildren()) do
					if decorations[deco.ClassName] then
						decorationCopy(deco, copy)
					end
				end
				renderNodes(child, copy, depth + 1)
			end
		end
	end
end
renderScene = function()
	clearChildren(paper)
	table.clear(previewMap)
	table.clear(hitEntries)
	if document then
		renderNodes(document, paper, 0)
	end
	updateOutline()
end
updateOutline = function()
	local preview = selected and previewMap[selected]
	if not document or not preview or not valid(selected) or not selected.Visible then
		outline.Visible = false
		return
	end
	local p, s, base = preview.AbsolutePosition, preview.AbsoluteSize, stage.AbsolutePosition
	outline.Position = UDim2.fromOffset(math.floor(p.X - base.X), math.floor(p.Y - base.Y))
	outline.Size = UDim2.fromOffset(math.max(1, s.X), math.max(1, s.Y))
	outline.Visible = true
	sizeBadge.Text = string.format("%d × %d", math.round(s.X / zoom), math.round(s.Y / zoom))
	sizeBadge.Size = UDim2.fromOffset(math.max(72, #sizeBadge.Text * 7 + 14), 19)
	for _, handle in pairs(handles) do
		handle.Visible = not locked[selected]
	end
end

local function isEditable(inst)
	return inst ~= nil and inst ~= document and descendantOf(inst, document) and guiObject(inst)
end
local function filterPass(item)
	local query = string.lower(layerFilter.Text or "")
	if query == "" then
		return true
	end
	if string.find(string.lower(item.Name), query, 1, true) then
		return true
	end
	for _, descendant in ipairs(item:GetDescendants()) do
		if guiObject(descendant) and string.find(string.lower(descendant.Name), query, 1, true) then
			return true
		end
	end
	return false
end
local function layerIcon(cls)
	if cls == "Frame" or cls == "ScrollingFrame" then
		return "▣"
	end
	if cls == "TextLabel" then
		return "T"
	end
	if cls == "TextButton" then
		return "B"
	end
	if cls == "TextBox" then
		return "⌨"
	end
	if string.find(cls, "Image", 1, true) then
		return "◇"
	end
	return "•"
end
local function layerChildren(source, depth, yref)
	if depth > 24 or yref.count >= MAX_LAYERS then
		return
	end
	for _, child in ipairs(source:GetChildren()) do
		if supported[child.ClassName] and filterPass(child) then
			yref.count += 1
			local localY = yref.count
			local row = button(
				layerList,
				"",
				UDim2.fromOffset(0, (localY - 1) * ROW_H),
				UDim2.new(1, -3, 0, ROW_H),
				function()
					setSelected(child)
				end,
				{
					color = (selected == child) and colors.selection or colors.panel,
					hoverColor = colors.hover,
					radius = 3,
					border = false,
				}
			)
			local indent = math.min(12 + depth * 12, 74)
			local hasChildren = false
			for _, descendant in ipairs(child:GetChildren()) do
				if supported[descendant.ClassName] then
					hasChildren = true
					break
				end
			end
			if hasChildren then
				button(
					row,
					expanded[child] == false and ">" or "v",
					UDim2.fromOffset(indent - 10, 2),
					UDim2.fromOffset(15, 22),
					function()
						expanded[child] = not (expanded[child] ~= false)
						renderLayers()
					end,
					{ color = colors.panel, hoverColor = colors.hover, radius = 2, border = false }
				)
			end
			label(
				row,
				layerIcon(child.ClassName),
				UDim2.fromOffset(indent + 6, 3),
				UDim2.fromOffset(15, 21),
				tokens.type.small,
				selected == child and colors.text or colors.subtext
			)
			local nameLabel = label(
				row,
				child.Name,
				UDim2.fromOffset(indent + 25, 3),
				UDim2.new(1, -indent - 61, 0, 21),
				tokens.type.small,
				colors.text
			)
			nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
			button(
				row,
				locked[child] and "L" or (child.Visible and "●" or "○"),
				UDim2.new(1, -31, 0, 3),
				UDim2.fromOffset(28, 21),
				function()
					safeSet(child, "Visible", not child.Visible)
					refreshAll()
				end,
				{ color = colors.panel, hoverColor = colors.hover, radius = 3, border = false }
			)
			if expanded[child] ~= false then
				layerChildren(child, depth + 1, yref)
			end
		end
	end
end
renderLayers = function()
	clearChildren(layerList)
	local yref = { count = 0 }
	if document then
		layerChildren(document, 0, yref)
	end
	layerList.CanvasSize = UDim2.fromOffset(0, yref.count * ROW_H + 8)
end

local function sectionTitle(y, titleText)
	local row = UI.sectionHeader(inspectorScroll, titleText)
	row.Position = UDim2.fromOffset(7, y)
	row.Size = UDim2.new(1, -18, 0, 24)
	return y + 28
end
local function propertyField(y, name, value, callback, opts)
	local props = { transparent = true }
	if opts then
		for key, v in pairs(opts) do
			props[key] = v
		end
	end
	local row = UI.property(inspectorScroll, name, nil, nil, value, callback, props)
	row.Position = UDim2.fromOffset(8, y)
	row.Size = UDim2.new(1, -19, 0, FIELD_H)
	return y + FIELD_H + 3
end
local function inspectorButton(y, name, fn)
	local b = button(inspectorScroll, name, UDim2.fromOffset(8, y), UDim2.new(1, -19, 0, 28), fn)
	return y + 32, b
end
local function simpleNumber(y, titleText, target, property, min, max)
	local old = safeGet(target, property)
	if type(old) ~= "number" then
		return y
	end
	return propertyField(y, titleText, old, function(value)
		local n = tonumber(value)
		if n == nil then
			return
		end
		n = math.clamp(n, min or -100000, max or 100000)
		if old ~= n then
			liveApply(target, property, n)
			changeValue(target, property, old, n)
			old = n
		end
	end, {
		numeric = true,
		min = min,
		max = max,
		decimals = 1,
		onPreview = function(value)
			local n = tonumber(value)
			if n then
				liveApply(target, property, math.clamp(n, min or -100000, max or 100000))
			end
		end,
	})
end
local function coordinateField(y, titleText, target, key, axis, component, min)
	local v = safeGet(target, key)
	if not v then
		return y
	end
	local function offsetFrom(cur)
		return cur[axis].Offset
	end
	local old = v
	local function makeValue(base, number)
		if key == "Position" or key == "Size" then
			if axis == "X" then
				return UDim2.new(base.X.Scale, number, base.Y.Scale, base.Y.Offset)
			end
			return UDim2.new(base.X.Scale, base.X.Offset, base.Y.Scale, number)
		end
	end
	return propertyField(y, titleText, offsetFrom(old), function(value)
		local n = tonumber(value)
		if not n then
			return
		end
		if min then
			n = math.max(min, n)
		end
		local nextValue = makeValue(old, n)
		liveApply(target, key, nextValue)
		changeValue(target, key, old, nextValue)
		old = nextValue
	end, {
		numeric = true,
		decimals = 0,
		min = min,
		onPreview = function(value)
			local n = tonumber(value)
			if n then
				if min then
					n = math.max(min, n)
				end
				liveApply(target, key, makeValue(old, n))
			end
		end,
	})
end
local function stringField(y, titleText, target, key)
	local old = safeGet(target, key)
	if type(old) ~= "string" then
		return y
	end
	return propertyField(y, titleText, old, function(value)
		if type(value) ~= "string" then
			return
		end
		liveApply(target, key, value)
		changeValue(target, key, old, value)
		old = value
	end, {
		onPreview = function(value)
			if type(value) == "string" then
				liveApply(target, key, value)
			end
		end,
	})
end
local function colorField(y, titleText, target, key)
	local raw = safeGet(target, key)
	if not raw then
		return y
	end
	local old = raw
	local function update(value, final)
		local c = parseColor(value)
		if not c then
			return
		end
		liveApply(target, key, c)
		if final then
			changeValue(target, key, old, c)
			old = c
		end
	end
	return propertyField(y, titleText, colorHex(old), function(value)
		update(value, true)
	end, {
		validate = function(value)
			local c = parseColor(value)
			if not c then
				return false
			end
			return true, colorHex(c)
		end,
		onPreview = function(value)
			update(value, false)
		end,
	})
end
local function offsetField(y, titleText, target, key, axis)
	local old = safeGet(target, key)
	if not old then
		return y
	end
	local component = axis == "X" and old.X or old.Y
	local base = old
	return propertyField(y, titleText, component, function(value)
		local n = tonumber(value)
		if not n then
			return
		end
		local nextValue = axis == "X" and Vector2.new(n, base.Y) or Vector2.new(base.X, n)
		liveApply(target, key, nextValue)
		changeValue(target, key, base, nextValue)
		base = nextValue
	end, {
		numeric = true,
		decimals = 2,
		min = 0,
		max = 1,
		onPreview = function(value)
			local n = tonumber(value)
			if n then
				liveApply(target, key, axis == "X" and Vector2.new(n, base.Y) or Vector2.new(base.X, n))
			end
		end,
	})
end
renderInspector = function()
	clearChildren(inspectorScroll)
	inspectorBuiltFor = selected
	local y = 8
	if not document then
		label(
			inspectorScroll,
			"Create a ScreenGui to begin designing.",
			UDim2.fromOffset(12, y),
			UDim2.new(1, -25, 0, 66),
			tokens.type.body,
			colors.subtext
		).TextWrapped =
			true
		inspectorScroll.CanvasSize = UDim2.fromOffset(0, 90)
		return
	end
	if not isEditable(selected) then
		y = sectionTitle(y, "Canvas")
		y = propertyField(y, "Width", width, function(v)
			local n = tonumber(v)
			if n then
				width = math.clamp(math.round(n), 100, 4096)
				fitView()
			end
		end, { numeric = true, min = 100, max = 4096, decimals = 0 })
		y = propertyField(y, "Height", height, function(v)
			local n = tonumber(v)
			if n then
				height = math.clamp(math.round(n), 100, 4096)
				fitView()
			end
		end, { numeric = true, min = 100, max = 4096, decimals = 0 })
		label(
			inspectorScroll,
			"Select a layer to edit its position, size, appearance and content.",
			UDim2.fromOffset(11, y + 10),
			UDim2.new(1, -25, 0, 65),
			tokens.type.small,
			colors.subtext
		).TextWrapped =
			true
		y += 78
	else
		local target = selected
		local typeLabel = label(
			inspectorScroll,
			target.ClassName,
			UDim2.fromOffset(12, y),
			UDim2.new(1, -22, 0, 21),
			tokens.type.small,
			colors.subtext
		)
		y += 25
		y = stringField(y, "Name", target, "Name")
		y = sectionTitle(y, "Transform")
		y = coordinateField(y, "X", target, "Position", "X")
		y = coordinateField(y, "Y", target, "Position", "Y")
		y = coordinateField(y, "Width", target, "Size", "X", nil, 1)
		y = coordinateField(y, "Height", target, "Size", "Y", nil, 1)
		y = simpleNumber(y, "Rotation", target, "Rotation", -360, 360)
		y = offsetField(y, "Anchor X", target, "AnchorPoint", "X")
		y = offsetField(y, "Anchor Y", target, "AnchorPoint", "Y")
		y = sectionTitle(y, "Appearance")
		y = colorField(y, "Fill", target, "BackgroundColor3")
		y = simpleNumber(y, "Transparency", target, "BackgroundTransparency", 0, 1)
		y = simpleNumber(y, "Z-Index", target, "ZIndex", 0, 10000)
		local corner = nil
		for _, child in ipairs(target:GetChildren()) do
			if child.ClassName == "UICorner" then
				corner = child
				break
			end
		end
		if corner then
			local initial = corner.CornerRadius
			local previous = initial
			y = propertyField(y, "Corner radius", initial.Offset, function(value)
				local n = tonumber(value)
				if not n then
					return
				end
				local nextRadius = UDim.new(previous.Scale, math.clamp(n, 0, 500))
				safeSet(corner, "CornerRadius", nextRadius)
				changeValue(corner, "CornerRadius", previous, nextRadius)
				previous = nextRadius
			end, {
				numeric = true,
				min = 0,
				max = 500,
				decimals = 0,
				onPreview = function(value)
					local n = tonumber(value)
					if n then
						safeSet(corner, "CornerRadius", UDim.new(previous.Scale, math.clamp(n, 0, 500)))
					end
					renderScene()
				end,
			})
		else
			y = inspectorButton(y, "Add rounded corners", function()
				local made = Instance.new("UICorner")
				made.CornerRadius = UDim.new(0, 8)
				made.Parent = target
				undoable("Add corners", function()
					made.Parent = nil
				end, function()
					made.Parent = target
				end)
				refreshAll()
			end)
		end
		y = inspectorButton(y, target.Visible and "Hide layer" or "Show layer", function()
			local old = target.Visible
			safeSet(target, "Visible", not old)
			changeValue(target, "Visible", old, not old)
		end)
		y = inspectorButton(y, locked[target] and "Unlock layer" or "Lock layer", function()
			locked[target] = not locked[target]
			renderInspector()
			renderLayers()
			updateOutline()
		end)
		if target.ClassName:find("Text", 1, true) then
			y = sectionTitle(y, "Typography")
			y = stringField(y, "Text", target, "Text")
			y = simpleNumber(y, "Text size", target, "TextSize", 1, 500)
			y = colorField(y, "Text color", target, "TextColor3")
			y = simpleNumber(y, "Text opacity", target, "TextTransparency", 0, 1)
		end
		if target.ClassName:find("Image", 1, true) then
			y = sectionTitle(y, "Image")
			y = stringField(y, "Asset", target, "Image")
			y = colorField(y, "Tint", target, "ImageColor3")
			y = simpleNumber(y, "Image opacity", target, "ImageTransparency", 0, 1)
		end
		if target.ClassName == "TextBox" then
			y = stringField(y, "Placeholder", target, "PlaceholderText")
		end
		y = sectionTitle(y, "Actions")
		y = inspectorButton(y, "Duplicate", function()
			duplicateSelected()
		end)
		y = inspectorButton(y, "Delete", function()
			deleteSelected()
		end)
		y = inspectorButton(y, "Bring forward", function()
			local before = target.ZIndex
			liveApply(target, "ZIndex", math.min(10000, before + 1))
			changeValue(target, "ZIndex", before, target.ZIndex)
		end)
		y = inspectorButton(y, "Send backward", function()
			local before = target.ZIndex
			liveApply(target, "ZIndex", math.max(0, before - 1))
			changeValue(target, "ZIndex", before, target.ZIndex)
		end)
	end
	inspectorScroll.CanvasSize = UDim2.fromOffset(0, y + 16)
end

setSelected = function(target, sendSelection)
	if target and not isEditable(target) then
		target = nil
	end
	selected = target
	if sendSelection ~= false then
		Selection:Set(target and { target } or {})
	end
	renderLayers()
	renderInspector()
	updateOutline()
	emitStatus(
		target and (target.ClassName .. "  /  " .. target.Name)
			or (document and (document.Name .. "  •  " .. width .. " × " .. height) or "No ScreenGui selected")
	)
end
refreshAll = function()
	if document and not valid(document) then
		document = nil
		selected = nil
	end
	if selected and not isEditable(selected) then
		selected = nil
	end
	updatePaper()
	renderScene()
	renderLayers()
	renderInspector()
	updateOutline()
end
local function scheduleRefresh()
	if dirtyRefresh then
		return
	end
	dirtyRefresh = true
	task.defer(function()
		dirtyRefresh = false
		if panel and panel.Visible then
			refreshAll()
		end
	end)
end
local function disconnectDocument()
	for _, c in ipairs(viewConnections) do
		c:Disconnect()
	end
	table.clear(viewConnections)
end
selectDocument = function(root, selection)
	if root == document then
		setSelected(selection and selection ~= root and selection or nil, false)
		return
	end
	disconnectDocument()
	document = root
	selected = nil
	table.clear(expanded)
	table.clear(locked)
	table.clear(history)
	historyIndex = 0
	if root then
		viewConnections[#viewConnections + 1] = root.DescendantAdded:Connect(scheduleRefresh)
		viewConnections[#viewConnections + 1] = root.DescendantRemoving:Connect(scheduleRefresh)
	end
	fitView()
	refreshAll()
	setSelected(selection and selection ~= root and selection or nil, false)
end

local function newDocument()
	local root = Instance.new("ScreenGui")
	root.Name = "DesignedUI"
	safeSet(root, "ResetOnSpawn", false)
	root.Parent = StarterGui
	width, height = DEFAULT_W, DEFAULT_H
	selectDocument(root, nil)
	Selection:Set({ root })
end
local function addObject(kind, x, y, w, h)
	if not document or not supported[kind] then
		return nil
	end
	drawingCount += 1
	local obj = Instance.new(kind)
	obj.Name = kind .. drawingCount
	obj.Position = UDim2.fromOffset(math.round(x), math.round(y))
	obj.Size = UDim2.fromOffset(math.max(1, math.round(w)), math.max(1, math.round(h)))
	obj.BorderSizePixel = 0
	if kind == "Frame" then
		obj.BackgroundColor3 = Color3.fromRGB(101, 115, 240)
	elseif kind == "TextLabel" then
		obj.BackgroundTransparency = 1
		obj.Text = "Text"
		obj.TextSize = 24
		obj.TextColor3 = Color3.fromRGB(25, 27, 35)
	elseif kind == "TextButton" then
		obj.BackgroundColor3 = Color3.fromRGB(89, 126, 255)
		obj.Text = "Button"
		obj.TextSize = 16
		obj.TextColor3 = Color3.fromRGB(255, 255, 255)
	elseif kind == "TextBox" then
		obj.BackgroundColor3 = Color3.fromRGB(238, 241, 245)
		obj.Text = ""
		obj.PlaceholderText = "Enter text..."
		obj.TextSize = 16
		obj.TextColor3 = Color3.fromRGB(35, 35, 40)
	elseif kind == "ScrollingFrame" then
		obj.BackgroundColor3 = Color3.fromRGB(245, 246, 248)
		obj.CanvasSize = UDim2.fromOffset(0, math.max(300, h * 2))
	else
		obj.BackgroundTransparency = 1
	end
	obj.Parent = document
	local parent = document
	undoable("Add " .. kind, function()
		obj.Parent = nil
	end, function()
		obj.Parent = parent
	end)
	refreshAll()
	setSelected(obj)
	return obj
end
createAt = function(kind)
	if not document then
		newDocument()
	end
	local w, h = 160, 90
	if kind == "TextLabel" then
		w, h = 220, 44
	end
	if kind == "TextButton" then
		w, h = 150, 42
	end
	if kind == "TextBox" then
		w, h = 230, 40
	end
	if kind == "ScrollingFrame" then
		w, h = 260, 180
	end
	local x = math.max(0, math.round((width - w) / 2))
	local y = math.max(0, math.round((height - h) / 2))
	return addObject(kind, x, y, w, h)
end
undo = function()
	if historyIndex <= 0 then
		return
	end
	local entry = history[historyIndex]
	historyIndex -= 1
	entry.undo()
	refreshAll()
	setSelected(nil)
	emitStatus("Undo: " .. entry.name)
end
redo = function()
	if historyIndex >= #history then
		return
	end
	historyIndex += 1
	local entry = history[historyIndex]
	entry.redo()
	refreshAll()
	setSelected(nil)
	emitStatus("Redo: " .. entry.name)
end
deleteSelected = function()
	if not isEditable(selected) or locked[selected] then
		return
	end
	local obj = selected
	local parent = obj.Parent
	obj.Parent = nil
	undoable("Delete " .. obj.Name, function()
		obj.Parent = parent
	end, function()
		obj.Parent = nil
	end)
	refreshAll()
	setSelected(nil)
end
duplicateSelected = function()
	if not isEditable(selected) then
		return
	end
	local source = selected
	local ok, copy = pcall(function()
		return source:Clone()
	end)
	if not ok or not copy then
		emitStatus("Could not duplicate layer (Archivable may be false)")
		return
	end
	copy.Name = source.Name .. " Copy"
	local pos = source.Position
	copy.Position = UDim2.new(pos.X.Scale, pos.X.Offset + 20, pos.Y.Scale, pos.Y.Offset + 20)
	local parent = source.Parent
	copy.Parent = parent
	undoable("Duplicate " .. source.Name, function()
		copy.Parent = nil
	end, function()
		copy.Parent = parent
	end)
	refreshAll()
	setSelected(copy)
end

local toolbarButtons = {}
local function toolbarItem(textValue, x, w, callback)
	local control = button(toolbar, textValue, UDim2.fromOffset(x, 7), UDim2.fromOffset(w, 29), callback)
	toolbarButtons[#toolbarButtons + 1] = control
	return control
end
local xpos = 10
toolbarItem("New GUI", xpos, 78, newDocument)
xpos += 83
toolbarItem("Use Selection", xpos, 104, function()
	local root, obj = pickScreenGui()
	if root then
		selectDocument(root, obj)
	else
		emitStatus("Select a ScreenGui in Explorer first")
	end
end)
xpos += 109
toolbarItem("Select", xpos, 62, function()
	tool = "Select"
	emitStatus("Select tool (V)")
end)
xpos += 67
toolbarItem("Pan", xpos, 47, function()
	tool = "Pan"
	emitStatus("Pan tool (H)")
end)
xpos += 52
for _, spec in ipairs({
	{ "Frame", "Frame", 54 },
	{ "Text", "TextLabel", 48 },
	{ "Button", "TextButton", 62 },
	{ "Input", "TextBox", 53 },
	{ "Image", "ImageLabel", 54 },
	{ "Img Btn", "ImageButton", 62 },
	{ "Scroll", "ScrollingFrame", 56 },
}) do
	local kind = spec[2]
	toolbarItem(spec[1], xpos, spec[3], function()
		if not document then
			newDocument()
		end
		drawingClass = kind
		tool = "Draw"
		emitStatus("Click and drag on the canvas to draw " .. kind .. " (or press Enter to insert centered)")
	end)
	xpos += spec[3] + 5
end

toolbarItem("-", xpos, 25, function()
	setZoom(zoom / 1.2)
end)
xpos += 30
local zoomLabel =
	label(toolbar, "100%", UDim2.fromOffset(xpos, 11), UDim2.fromOffset(48, 22), tokens.type.small, colors.text)
zoomLabel.TextXAlignment = Enum.TextXAlignment.Center
xpos += 50
toolbarItem("+", xpos, 25, function()
	setZoom(zoom * 1.2)
end)
xpos += 30
toolbarItem("Fit", xpos, 37, fitView)

local footerX = 8
local footerButtons = {}
for _, spec in ipairs({ { "Undo", undo }, { "Redo", redo }, {
	"Delete",
	function()
		deleteSelected()
	end,
} }) do
	local w = spec[1] == "Delete" and 53 or 46
	local b = button(status, spec[1], UDim2.new(1, -footerX - w, 0, 2), UDim2.fromOffset(w, 20), spec[2], {
		color = colors.surface,
		hoverColor = colors.hover,
		radius = 3,
		border = false,
	})
	footerButtons[#footerButtons + 1] = b
	footerX += w + 5
end
statusLabel.Size = UDim2.new(1, -footerX - 15, 1, -4)

connections[#connections + 1] = layerAdd.MouseButton1Click:Connect(function()
	createAt("Frame")
end)
connections[#connections + 1] = layerDuplicate.MouseButton1Click:Connect(function()
	duplicateSelected()
end)
connections[#connections + 1] = layerFilter.TextChanged:Connect(function()
	renderLayers()
end)

local function visibleInHierarchy(obj)
	local current = obj
	while current and current ~= document do
		if guiObject(current) and not current.Visible then
			return false
		end
		current = current.Parent
	end
	return true
end
local function hitTest(mouse)
	local best, bestZ, bestOrder, bestDepth = nil, -math.huge, -math.huge, -math.huge
	for _, entry in ipairs(hitEntries) do
		if visibleInHierarchy(entry.original) and inside(entry.copy, mouse) then
			local z = safeGet(entry.original, "ZIndex") or 0
			if
				z > bestZ
				or (z == bestZ and entry.depth > bestDepth)
				or (z == bestZ and entry.depth == bestDepth and entry.order > bestOrder)
			then
				best, bestZ, bestOrder, bestDepth = entry.original, z, entry.order, entry.depth
			end
		end
	end
	return best
end
local function beginMove(mouse, object)
	if not isEditable(object) or locked[object] then
		return
	end
	drag = { mode = "move", start = mouse, object = object, oldPosition = object.Position, oldSize = object.Size }
end
local function beginResize(mouse, handle)
	if not isEditable(selected) or locked[selected] then
		return
	end
	drag = {
		mode = "resize",
		start = mouse,
		object = selected,
		handle = handle,
		oldPosition = selected.Position,
		oldSize = selected.Size,
	}
end
for handle, h in pairs(handles) do
	local which = handle
	connections[#connections + 1] = h.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			beginResize(UserInputService:GetMouseLocation(), which)
		end
	end)
end
connections[#connections + 1] = hit.InputBegan:Connect(function(input)
	if not document then
		return
	end
	local mouse = UserInputService:GetMouseLocation()
	if
		input.UserInputType == Enum.UserInputType.MouseButton3
		or (input.UserInputType == Enum.UserInputType.MouseButton1 and tool == "Pan")
	then
		drag = { mode = "pan", start = mouse, oldPan = pan }
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end
	if not inside(ruler, mouse) then
		setSelected(nil)
		return
	end
	if tool == "Draw" and drawingClass then
		drag = { mode = "draw", start = mouse, kind = drawingClass }
		draft.Visible = true
		draft.Position = UDim2.fromOffset(mouse.X - stage.AbsolutePosition.X, mouse.Y - stage.AbsolutePosition.Y)
		draft.Size = UDim2.fromOffset(1, 1)
		return
	end
	local target = hitTest(mouse)
	setSelected(target)
	if target then
		beginMove(mouse, target)
	end
end)

local function applyDragPosition(obj, x, y)
	local origin = drag.oldPosition
	local nextValue = UDim2.new(origin.X.Scale, origin.X.Offset + x, origin.Y.Scale, origin.Y.Offset + y)
	liveApply(obj, "Position", nextValue)
end
local function applyDragSize(obj, dx, dy)
	local oldP, oldS = drag.oldPosition, drag.oldSize
	local h = drag.handle
	local left = (string.find(h, "w", 1, true) ~= nil)
	local top = (string.find(h, "n", 1, true) ~= nil)
	local right = (string.find(h, "e", 1, true) ~= nil)
	local bottom = (string.find(h, "s", 1, true) ~= nil)
	local px, py = oldP.X.Offset, oldP.Y.Offset
	local sx, sy = oldS.X.Offset, oldS.Y.Offset
	if left then
		px += dx
		sx -= dx
	elseif right then
		sx += dx
	end
	if top then
		py += dy
		sy -= dy
	elseif bottom then
		sy += dy
	end
	if sx < 8 then
		if left then
			px -= 8 - sx
		end
		sx = 8
	end
	if sy < 8 then
		if top then
			py -= 8 - sy
		end
		sy = 8
	end
	liveApply(obj, "Position", UDim2.new(oldP.X.Scale, math.round(px), oldP.Y.Scale, math.round(py)))
	liveApply(obj, "Size", UDim2.new(oldS.X.Scale, math.round(sx), oldS.Y.Scale, math.round(sy)))
end
connections[#connections + 1] = UserInputService.InputChanged:Connect(function(input)
	if not panel.Visible then
		return
	end
	local mouse = UserInputService:GetMouseLocation()
	if input.UserInputType == Enum.UserInputType.MouseWheel and inside(stage, mouse) then
		local amount = input.Position.Z
		local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
		if ctrl then
			setZoom(zoom * (amount > 0 and 1.12 or 1 / 1.12), mouse - stage.AbsolutePosition)
		else
			pan = pan + Vector2.new(0, amount * 32)
			updatePaper()
		end
		return
	end
	if not drag or input.UserInputType ~= Enum.UserInputType.MouseMovement then
		return
	end
	if drag.mode == "pan" then
		pan = drag.oldPan + (mouse - drag.start)
		updatePaper()
	elseif drag.mode == "move" then
		local delta = (mouse - drag.start) / zoom
		local snap = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
		local dx, dy = delta.X, delta.Y
		if snap then
			dx = math.round(dx / 8) * 8
			dy = math.round(dy / 8) * 8
		end
		applyDragPosition(drag.object, math.round(dx), math.round(dy))
	elseif drag.mode == "resize" then
		local delta = (mouse - drag.start) / zoom
		applyDragSize(drag.object, math.round(delta.X), math.round(delta.Y))
	elseif drag.mode == "draw" then
		local ap, bp = drag.start - stage.AbsolutePosition, mouse - stage.AbsolutePosition
		draft.Position = UDim2.fromOffset(math.min(ap.X, bp.X), math.min(ap.Y, bp.Y))
		draft.Size = UDim2.fromOffset(math.abs(bp.X - ap.X), math.abs(bp.Y - ap.Y))
	end
end)
connections[#connections + 1] = UserInputService.InputEnded:Connect(function(input)
	if not drag then
		return
	end
	local mode = drag.mode
	if
		mode == "pan"
		and input.UserInputType ~= Enum.UserInputType.MouseButton1
		and input.UserInputType ~= Enum.UserInputType.MouseButton3
	then
		return
	end
	if mode ~= "pan" and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end
	local completed = drag
	drag = nil
	draft.Visible = false
	if mode == "draw" then
		local a = screenToCanvas(completed.start)
		local b = screenToCanvas(UserInputService:GetMouseLocation())
		local x = math.max(0, math.min(a.X, b.X))
		local y = math.max(0, math.min(a.Y, b.Y))
		local w = math.abs(b.X - a.X)
		local h = math.abs(b.Y - a.Y)
		if w < 8 or h < 8 then
			w, h = 160, 80
		end
		addObject(completed.kind, math.round(x), math.round(y), math.round(w), math.round(h))
		tool = "Select"
	elseif mode == "move" or mode == "resize" then
		local obj = completed.object
		if not obj or not valid(obj) then
			return
		end
		local newP, newS = obj.Position, obj.Size
		if newP ~= completed.oldPosition or newS ~= completed.oldSize then
			undoable(mode == "move" and "Move layer" or "Resize layer", function()
				safeSet(obj, "Position", completed.oldPosition)
				safeSet(obj, "Size", completed.oldSize)
			end, function()
				safeSet(obj, "Position", newP)
				safeSet(obj, "Size", newS)
			end)
		end
		refreshAll()
	end
end)

local function textboxFocused()
	local ok, focused = pcall(function()
		return UserInputService:GetFocusedTextBox()
	end)
	return ok and focused ~= nil
end
connections[#connections + 1] = UserInputService.InputBegan:Connect(function(input)
	if not panel.Visible or not document then
		return
	end
	if textboxFocused() then
		return
	end
	local key = input.KeyCode
	local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
	if ctrl and key == Enum.KeyCode.Z then
		undo()
	elseif ctrl and key == Enum.KeyCode.Y then
		redo()
	elseif ctrl and key == Enum.KeyCode.D then
		duplicateSelected()
	elseif key == Enum.KeyCode.Delete or key == Enum.KeyCode.Backspace then
		deleteSelected()
	elseif key == Enum.KeyCode.V then
		tool = "Select"
	elseif key == Enum.KeyCode.H then
		tool = "Pan"
	elseif key == Enum.KeyCode.F then
		tool = "Draw"
		drawingClass = "Frame"
	elseif key == Enum.KeyCode.T then
		tool = "Draw"
		drawingClass = "TextLabel"
	elseif key == Enum.KeyCode.Escape then
		drag = nil
		draft.Visible = false
		tool = "Select"
	elseif key == Enum.KeyCode.Return and tool == "Draw" and drawingClass then
		createAt(drawingClass)
		tool = "Select"
	end
end)

connections[#connections + 1] = stage:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	updateGrid()
end)
local lastZoom = -1
connections[#connections + 1] = RunService.Heartbeat:Connect(function()
	if not panel.Visible then
		return
	end
	if lastZoom ~= zoom then
		zoomLabel.Text = string.format("%d%%", math.round(zoom * 100))
		lastZoom = zoom
	end
end)

local root, initial = pickScreenGui()
selectDocument(root, initial)

task.defer(function()
	if panel and panel.Parent then
		fitView()
	end
end)

return {
	Enable = function()
		fitWindow()
		panel.Visible = true
		refreshAll()
		if document == nil then
			local root, instance = pickScreenGui()
			if root then
				selectDocument(root, instance)
			end
		end
	end,
	Disable = function()
		panel.Visible = false
		drag = nil
		draft.Visible = false
	end,
	Toggle = function()
		panel.Visible = not panel.Visible
		if panel.Visible then
			refreshAll()
		else
			drag = nil
			draft.Visible = false
		end
	end,
	Refresh = function()
		UI.refreshWindow("GUIDesigner")
		refreshAll()
	end,
	SelectScreenGui = function(root)
		if root and root.ClassName == "ScreenGui" then
			selectDocument(root, nil)
		end
	end,
	GetScreenGui = function()
		return document
	end,
	GetSelected = function()
		return selected
	end,
	Insert = function(className)
		return createAt(className)
	end,
	Destroy = function()
		disconnectDocument()
		for _, conn in ipairs(connections) do
			conn:Disconnect()
		end
		table.clear(connections)
		panel:Destroy()
		windowBounds:Destroy()
	end,
}

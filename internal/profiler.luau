if IsServer or IsClient or IsPlaytest then
	return nil
end

local UI = require("@internal/editor_ui")
local tokens = UI.tokens
local colors = tokens.color
local metrics = UI.metrics
local ProfilerService = game:GetService("ProfilerService")
local RunService = game:GetService("RunService")

-- Layout
local WINDOW_W, WINDOW_H = 1120, 700
local PAD = metrics.panelInset or tokens.space.md
local TOOLBAR_H = metrics.toolbarButton + 6
local GRAPH_Y = PAD + TOOLBAR_H + 8
local GRAPH_H = 232
local TABS_Y = GRAPH_Y + GRAPH_H + 8
local TABS_H = metrics.tabHeight or 28
local STATUS_H = 22
local SIDE_W = 206

local GRAPH_POINTS = 96
local SAMPLE_INTERVAL = 0.10
local PAINT_INTERVAL = 0.15
local MAX_ZONES = 180
local DETAIL_LIVE_INTERVAL = 0.45
local MAX_LANES = 32
local ROW_H = metrics.propertyRow or 22
local OVERSCAN = 5

local R_SM = tokens.radius.sm

local C = {
	panel = colors.panel,
	strip = colors.input,
	rowAlt = colors.rowEven,
	hover = colors.hover,
	pressed = colors.pressed,
	outline = colors.border,
	text = colors.text,
	dim = colors.subtext,
	accent = colors.accent,
	selection = colors.selection,
}
local connections, tooltips = {}, {}
local destroyed = false
local function connect(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(connections, connection)
	return connection
end

local function trackTheme(object, property, role)
	UI.bindTheme(object, property, "color." .. role)
end

local function themeRepaint()
	local palette = UI.tokens.color
	C.panel = palette.panel
	C.strip = palette.input
	C.rowAlt = palette.rowEven
	C.hover = palette.hover
	C.pressed = palette.pressed
	C.outline = palette.border
	C.text = palette.text
	C.dim = palette.subtext
	C.accent = palette.accent
	C.selection = palette.selection
end

local categories = {
	{ key = "UI", label = "UI", color = Color3.fromRGB(147, 100, 185) },
	{ key = "GI", label = "Global Illumination", color = Color3.fromRGB(188, 73, 57) },
	{ key = "GC", label = "GarbageCollector", color = Color3.fromRGB(141, 137, 21) },
	{ key = "Animation", label = "Animation", color = Color3.fromRGB(90, 193, 201) },
	{ key = "Physics", label = "Physics", color = Color3.fromRGB(237, 137, 36) },
	{ key = "Scripts", label = "Scripts", color = Color3.fromRGB(37, 127, 171) },
	{ key = "Rendering", label = "Rendering", color = Color3.fromRGB(117, 168, 21) },
	{ key = "VSync", label = "VSync", color = Color3.fromRGB(217, 178, 16) },
	{ key = "Others", label = "Others / untracked", color = Color3.fromRGB(97, 102, 110) },
}

local categoryByKey = {}
local categoryEnabled = {}
for i, entry in ipairs(categories) do
	categoryByKey[entry.key] = i
	categoryEnabled[entry.key] = true
end

local function categorize(name)
	local n = string.lower(tostring(name or ""))
	if
		n:find("vsync", 1, true)
		or n:find("present", 1, true)
		or n:find("swap", 1, true)
		or n:find("waitfor", 1, true)
		or n:find("idle", 1, true)
	then
		return "VSync"
	elseif n == "gc" or n:find("garbage", 1, true) or n:find("gc ", 1, true) or n:find("collect", 1, true) then
		return "GC"
	elseif
		n:find("global illumination", 1, true)
		or n:find("ssao", 1, true)
		or n:find("light probe", 1, true)
		or n:find("radiance", 1, true)
	then
		return "GI"
	elseif n:find("anim", 1, true) or n:find("skeleton", 1, true) or n:find("bone", 1, true) then
		return "Animation"
	elseif
		n:find("phys", 1, true)
		or n:find("collision", 1, true)
		or n:find("broadphase", 1, true)
		or n:find("rigidbody", 1, true)
	then
		return "Physics"
	elseif
		n:find("luau", 1, true)
		or n:find("script", 1, true)
		or n:find("vm.", 1, true)
		or n:find("resume", 1, true)
	then
		return "Scripts"
	elseif
		n:find("gui", 1, true)
		or n:find("ui ", 1, true)
		or n:find("skia", 1, true)
		or n:find("textlayout", 1, true)
		or n:find("canvas", 1, true)
	then
		return "UI"
	elseif
		n:find("render", 1, true)
		or n:find("draw", 1, true)
		or n:find("filament", 1, true)
		or n:find("vulkan", 1, true)
		or n:find("shadow", 1, true)
		or n:find("gpu", 1, true)
	then
		return "Rendering"
	end
	return "Others"
end

local function zoneColor(zone)
	local raw = tonumber(zone.color)
	if raw and raw > 0 then
		raw = math.floor(raw)
		return Color3.fromRGB(math.floor(raw / 65536) % 256, math.floor(raw / 256) % 256, raw % 256)
	end
	return categories[categoryByKey[categorize(zone.name)]].color
end

-- Use library surfaces for structure and chart marks.
local function surface(parent, position, size, name)
	local f = UI.frame(parent, position, size, colors.panel)
	f.Name = name or "Surface"
	f.BackgroundTransparency = 1
	f.ClipsDescendants = true
	return f
end

-- Opaque custom graph marks only; never use this for a content wrapper.
local function frame(parent, position, size, color, name)
	local f = UI.frame(parent, position, size, color)
	f.Name = name or "DataMark"
	f.ClipsDescendants = true
	return f
end

local function uiTextSize(requested)
	if requested <= 10 then
		return tokens.type.caption
	end
	if requested <= 11 then
		return tokens.type.small
	end
	if requested <= 13 then
		return tokens.type.body
	end
	return tokens.type.title
end

local function label(parent, value, position, size, fontSize, color, align)
	local l = UI.label(parent, tostring(value or ""), position, size, uiTextSize(fontSize or 12), color or C.text)
	l.TextXAlignment = align or Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	return l
end

local buttonLabels = setmetatable({}, { __mode = "k" })
local function button(parent, value, position, size, action, extra)
	local opts = {
		color = C.strip,
		hoverColor = C.hover,
		pressedColor = C.pressed,
		textColor = C.text,
		textSize = tokens.type.small,
		radius = R_SM,
		border = false,
	}
	if extra then
		for key, val in pairs(extra) do
			opts[key] = val
		end
	end
	local b, caption = UI.button(parent, value, position, size, action, opts)
	-- Button chrome follows editor_ui hover / pressed / selected conventions.
	buttonLabels[b] = caption
	return b
end

local function setButtonText(b, value)
	local caption = buttonLabels[b]
	if caption then
		caption.Text = value
	else
		b.Text = value
	end
end

local function scroller(parent, position, size)
	return UI.create("ScrollingFrame", {
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
	}, parent)
end

local function iconButton(parent, path, hint, position, size, callback, rotation)
	local b, _, image = UI.iconButton(parent, path, position, size, callback, {
		color = colors.panel,
		border = false,
		iconSize = 14,
		radius = R_SM,
		bgTransparency = 1,
	})
	if image then
		image.ImageColor3 = colors.subtext
		if rotation then
			image.Rotation = rotation
		end
	end
	table.insert(tooltips, UI.tooltip(b, hint, { placement = "below" }))
	return b
end

local function formatInt(n)
	local s = tostring(math.floor(tonumber(n) or 0))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function safeCall(methodName, ...)
	local args = table.pack(...)
	local ok, result = pcall(function()
		return ProfilerService[methodName](ProfilerService, table.unpack(args, 1, args.n))
	end)
	if ok then
		return result
	end
	return nil
end

-- The native service can report FrameTime before its history ring is populated.
-- Preserve method errors for the diagnostic line instead of silently losing them.
local lastFrameReadError = nil
local function getFrame(index)
	local ok, result = pcall(function()
		return ProfilerService:GetFrameRecord(index)
	end)
	if not ok then
		lastFrameReadError = tostring(result)
		return nil
	end
	lastFrameReadError = nil
	return result
end

local function getFrameCount()
	return math.max(0, tonumber(ProfilerService.FrameCount) or 0)
end

local function getLiveSample()
	local data = getFrame(1)
	if data and (tonumber(data.frameMs) or 0) > 0 then
		return data, "native"
	end

	-- The FPS/FrameTime ring is maintained by frame_tick even when zone history
	-- is not being flushed. Render a *real* total-frame-time bar meanwhile.
	-- Its Others/untracked category is correct: without native zone records
	-- there is no evidence for subsystem attribution.
	local ms = tonumber(ProfilerService.FrameTime) or 0
	if ms > 0 then
		return {
			frameMs = ms,
			fps = tonumber(ProfilerService.FPS) or 0,
			zones = {},
		}, "frame-time"
	end
	return nil, "empty"
end

local function summarize(frameData)
	local bucket = {}
	for _, cat in ipairs(categories) do
		bucket[cat.key] = 0
	end
	local zones = frameData.zones or {}
	local ms = math.max(0, tonumber(frameData.frameMs) or 0)
	local total = 0
	for _, zone in ipairs(zones) do
		local duration = math.max(0, tonumber(zone.ms) or 0)
		local key = categorize(zone.name)
		bucket[key] += duration
		total += duration
	end

	-- Zones can be nested or concurrent. Normalize the inclusive zone durations
	-- to the measured frame time; otherwise a stacked chart would exceed 100%.
	-- This chart is a visual breakdown, NOT exclusive per-subsystem CPU accounting.
	if total > ms and total > 0 then
		local scale = ms / total
		for key, value in pairs(bucket) do
			bucket[key] = value * scale
		end
	else
		bucket.Others += ms - total
	end
	return {
		frameMs = ms,
		fps = tonumber(frameData.fps) or (ms > 0 and 1000 / ms or 0),
		zones = zones,
		bucket = bucket,
		-- Populated for exact historical frames when paused.
		offset = frameData.index,
	}
end

-- Window
local gui = UI.widgetOverlay()
local panel, content = UI.window(
	"Profiler",
	UDim2.fromOffset(70, 58),
	UDim2.fromOffset(WINDOW_W, WINDOW_H),
	"Profiler",
	{ closable = true, closeIcon = "builtin://global-icons/x.svg" }
)
panel.Parent = gui
panel.Visible = false
-- Keep UI.window's opaque content and matching active title tab intact.
content.ClipsDescendants = true

-- Toolbar: flat and continuous with the selected title tab.
local toolbar = surface(content, UDim2.fromOffset(PAD, PAD), UDim2.new(1, -PAD * 2, 0, TOOLBAR_H), "Toolbar")
local liveIcon = UI.image(toolbar, "builtin://icons/Play.svg", UDim2.fromOffset(3, 10), UDim2.fromOffset(14, 14))
local liveLabel = label(toolbar, "LIVE", UDim2.fromOffset(22, 0), UDim2.fromOffset(66, TOOLBAR_H), 11, colors.success)
local readout = label(toolbar, "FPS --    Frame -- ms", UDim2.fromOffset(94, 0), UDim2.new(1, -390, 1, 0), 13)
local pauseButton
local frameCounter = label(
	toolbar,
	"-- / --",
	UDim2.new(1, -290, 0, 0),
	UDim2.fromOffset(82, TOOLBAR_H),
	11,
	C.dim,
	Enum.TextXAlignment.Right
)
UI.separator(content, UDim2.fromOffset(PAD, PAD + TOOLBAR_H), UDim2.new(1, -PAD * 2, 0, 1), colors.border)

-- Graph -
local graphPanel = surface(content, UDim2.fromOffset(PAD, GRAPH_Y), UDim2.new(1, -PAD * 2, 0, GRAPH_H), "GraphPanel")
graphPanel.ClipsDescendants = false

local legend = surface(graphPanel, UDim2.fromOffset(0, 0), UDim2.new(0, SIDE_W, 1, 0), "Legend")
UI.separator(graphPanel, UDim2.fromOffset(SIDE_W, 0), UDim2.new(0, 1, 1, 0), colors.border)
label(legend, "CPU Usage", UDim2.fromOffset(14, 8), UDim2.fromOffset(165, 22), 15)
label(legend, "Normalized named zones", UDim2.fromOffset(14, 30), UDim2.fromOffset(184, 16), 10, C.dim)

local chartArea = surface(graphPanel, UDim2.fromOffset(SIDE_W + 8, 0), UDim2.new(1, -(SIDE_W + 8), 1, 0), "ChartArea")
local graphHeader = label(chartArea, "Frame history", UDim2.fromOffset(12, 4), UDim2.new(1, -24, 0, 22), 11, C.dim)
local chart = surface(chartArea, UDim2.fromOffset(10, 30), UDim2.new(1, -20, 1, -62), "Chart")
UI.stroke(chart, colors.border, 1, 0.35)
local graphFooter = label(chartArea, "", UDim2.new(0, 12, 1, -26), UDim2.new(1, -24, 0, 22), 10, C.dim)

local graphBars = {}
local samples = {}
local selectedFrame = nil
local selectedOffset = 1
local lastSampleSource = "empty"
local paused = false
local activeTab = "Timeline"
local dirtyGraph, dirtyDetail = true, true
local drawGraph
local drawDetail
local setPaused
local selectOffset

local function updateLiveBadge()
	local c = paused and colors.warning or colors.success
	liveIcon.Image = paused and "builtin://icons/Pause.svg" or "builtin://icons/Play.svg"
	liveIcon.ImageColor3 = c
	liveLabel.TextColor3 = c
	liveLabel.Text = paused and "PAUSED" or "LIVE"
end

local function graphSlot(index)
	-- Draw directly inside the chart: editor_ui buttons contain their own
	-- interactive chrome, which is not a reliable parent for graph geometry.
	local columns = {}
	for _, cat in ipairs(categories) do
		local piece = frame(
			chart,
			UDim2.fromOffset(0, 0),
			UDim2.fromOffset(0, 0),
			cat.color,
			"CPU_" .. cat.key .. "_" .. tostring(index)
		)
		piece.ZIndex = 3
		piece.Visible = false
		columns[cat.key] = piece
	end
	-- Selected frame: a soft full-height highlight behind the bars.
	local marker =
		frame(chart, UDim2.fromOffset(0, 0), UDim2.fromOffset(0, 0), C.selection, "SelectedFrame_" .. tostring(index))
	marker.BackgroundTransparency = 0.82
	marker.ZIndex = 2
	marker.Visible = false
	trackTheme(marker, "BackgroundColor3", "selection")
	local hit = UI.button(chart, "", UDim2.fromOffset(0, 0), UDim2.fromOffset(0, 0), function()
		if not paused then
			setPaused(true)
			return
		end
		local n = math.min(#samples, GRAPH_POINTS)
		local firstSlot = GRAPH_POINTS - n + 1
		local row = index >= firstSlot and samples[#samples - n + index - firstSlot + 1] or nil
		if row and row.offset then
			selectOffset(row.offset)
		end
	end, { color = colors.panel, border = false, radius = 0, bgTransparency = 1, hoveringEnabled = false })
	hit.Name = "FrameHit_" .. tostring(index)
	hit.BackgroundTransparency = 1
	hit.ZIndex = 5

	return { button = hit, pieces = columns, marker = marker }
end

for i = 1, GRAPH_POINTS do
	graphBars[i] = graphSlot(i)
end

-- 60 / 30 FPS guide lines with small right-aligned captions.
local chartReference = {}
for _, guide in ipairs({ { ms = 16.667, text = "60 FPS" }, { ms = 33.333, text = "30 FPS" } }) do
	local line =
		frame(chart, UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0, 1), C.outline, "Reference" .. tostring(guide.ms))
	line.BackgroundTransparency = 0.6
	line.ZIndex = 4
	local caption = label(
		chart,
		guide.text,
		UDim2.new(1, -52, 0, 0),
		UDim2.fromOffset(46, 14),
		10,
		C.dim,
		Enum.TextXAlignment.Right
	)
	caption.ZIndex = 6
	table.insert(chartReference, { line = line, caption = caption, ms = guide.ms })
end

-- Legend rows (click to toggle a category) with per-frame milliseconds.
local legendValues, legendVisuals = {}, {}
for i = 1, #categories do
	local cat = categories[#categories - i + 1]
	local row, chip, caption
	row = button(legend, "", UDim2.fromOffset(6, 54 + (i - 1) * 19), UDim2.new(1, -12, 0, 18), function()
		categoryEnabled[cat.key] = not categoryEnabled[cat.key]
		chip.BackgroundTransparency = categoryEnabled[cat.key] and 0 or 0.72
		caption.TextColor3 = categoryEnabled[cat.key] and C.text or C.dim
		dirtyGraph, dirtyDetail = true, true
	end, { color = colors.panel, bgTransparency = 1, radius = 0 })
	row.BackgroundTransparency = 1
	chip = frame(row, UDim2.fromOffset(8, 4), UDim2.fromOffset(10, 10), cat.color)
	UI.corner(chip, tokens.radius.sm)
	caption = label(row, cat.label, UDim2.fromOffset(26, 0), UDim2.new(1, -90, 1, 0), 11, C.text)
	caption.TextTruncate = Enum.TextTruncate.AtEnd
	legendVisuals[cat.key] = { caption = caption, chip = chip }
	legendValues[cat.key] =
		label(row, "--", UDim2.new(1, -62, 0, 0), UDim2.fromOffset(56, 18), 10, C.dim, Enum.TextXAlignment.Right)
end

-- Detail tabs: actual editor_ui tabs, not a custom segmented button strip.
local detailBody
local resetDetailScroll = true
local tabContainer, tabController =
	UI.tabs(content, UDim2.fromOffset(PAD, TABS_Y), UDim2.new(1, -PAD * 2, 1, -(TABS_Y + STATUS_H + PAD + 6)), {
		tabs = {
			{ name = "Timeline", text = "Timeline", width = 90 },
			{ name = "Threads", text = "Threads", width = 90 },
			{ name = "Scripts", text = "Scripts", width = 90 },
		},
		selectedTab = activeTab,
		barHeight = TABS_H,
		startX = 0,
		barColor = content.BackgroundColor3,
		contentColor = content.BackgroundColor3,
		activeTabColor = content.BackgroundColor3,
		inactiveTabColor = content.BackgroundColor3,
		tabAccentColor = colors.accent,
		onTabChanged = function(name, _, page)
			activeTab = name
			if detailBody and page then
				detailBody.Parent = page
			end
			resetDetailScroll = true
			dirtyDetail = true
		end,
	})
local function seamlessTabs()
	local base = content.BackgroundColor3
	tabController.setColors({
		bar = base,
		content = base,
		activeTab = base,
		inactiveTab = base,
		hover = colors.hover,
		pressed = colors.pressed,
		activeText = colors.text,
		inactiveText = colors.subtext,
		accent = colors.accent,
	})
	tabContainer.BackgroundTransparency = 1
	tabController.bar.BackgroundTransparency = 1
	tabController.content.BackgroundTransparency = 1
	for _, page in pairs(tabController.pages) do
		page.BackgroundTransparency = 1
	end
end
seamlessTabs()
local detailHead = tabController.bar
UI.separator(tabController.content, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 1), colors.border)
local zoom = 1
local zoomBox = surface(detailHead, UDim2.new(1, -320, 0, 0), UDim2.fromOffset(200, TABS_H), "Zoom")
local zoomCaption =
	label(zoomBox, "1x", UDim2.fromOffset(77, 0), UDim2.fromOffset(46, TABS_H), 12, C.dim, Enum.TextXAlignment.Center)
button(zoomBox, "Zoom out", UDim2.fromOffset(0, 2), UDim2.fromOffset(76, TABS_H - 4), function()
	zoom = math.max(1, zoom / 2)
	zoomCaption.Text = tostring(zoom) .. "x"
	dirtyDetail = true
end, { color = colors.panel, bgTransparency = 1 })
button(zoomBox, "Zoom in", UDim2.fromOffset(124, 2), UDim2.fromOffset(76, TABS_H - 4), function()
	zoom = math.min(8, zoom * 2)
	zoomCaption.Text = tostring(zoom) .. "x"
	dirtyDetail = true
end, { color = colors.panel, bgTransparency = 1 })
local detailCaption =
	label(detailHead, "", UDim2.new(1, -112, 0, 0), UDim2.fromOffset(106, TABS_H), 10, C.dim, Enum.TextXAlignment.Right)

detailBody = surface(tabController.getPage(activeTab), UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), "DetailBody")
local laneNames = scroller(detailBody, UDim2.fromOffset(0, 0), UDim2.new(0, SIDE_W, 1, 0))
local laneCanvas = scroller(detailBody, UDim2.fromOffset(SIDE_W + 1, 0), UDim2.new(1, -(SIDE_W + 1), 1, 0))
local sideDivider = UI.separator(detailBody, UDim2.fromOffset(SIDE_W, 0), UDim2.new(0, 1, 1, 0), colors.border)
sideDivider.ZIndex = 3
local statusBar =
	surface(content, UDim2.new(0, PAD, 1, -(STATUS_H + PAD)), UDim2.new(1, -PAD * 2, 0, STATUS_H), "StatusBar")
UI.separator(statusBar, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 1), colors.border)
local statusLabel = label(statusBar, "Profiler ready", UDim2.fromOffset(4, 1), UDim2.new(1, -8, 1, -1), 10, C.dim)
statusLabel.TextTruncate = Enum.TextTruncate.AtEnd

-- Retain native chart marks and library labels/buttons. Pool by parent/type;
-- scroll range is virtualized for large thread/script tables and timeline lanes.
local laneObjects = { groups = {} }
local nameObjects = { groups = {} }
local function groupFor(cache, kind)
	local group = cache.groups[kind]
	if not group then
		group = { used = 0, slots = {} }
		cache.groups[kind] = group
	end
	return group
end
local function acquire(cache, kind, create)
	local group = groupFor(cache, kind)
	group.used += 1
	local slot = group.slots[group.used]
	if not slot then
		slot = create()
		group.slots[group.used] = slot
	end
	slot.object.Visible = true
	return slot
end
local function recycleDetails()
	for _, cache in ipairs({ laneObjects, nameObjects }) do
		for _, group in pairs(cache.groups) do
			group.used = 0
		end
	end
	if resetDetailScroll then
		resetDetailScroll = false
		laneCanvas.CanvasPosition = Vector2.new(0, 0)
		laneNames.CanvasPosition = Vector2.new(0, 0)
		laneCanvas.CanvasSize = UDim2.fromOffset(0, 0)
		laneNames.CanvasSize = UDim2.fromOffset(0, 0)
	end
end
local function finishDetails()
	for _, cache in ipairs({ laneObjects, nameObjects }) do
		for _, group in pairs(cache.groups) do
			for i = group.used + 1, #group.slots do
				group.slots[i].object.Visible = false
				group.slots[i].action = nil
			end
		end
	end
end
local function tracked(parent, props, cache)
	local slot = acquire(cache, "frame", function()
		local object = UI.frame(parent, UDim2.fromOffset(0, 0), UDim2.fromOffset(0, 0), colors.panel)
		local corner = UI.corner(object, tokens.radius.xs)
		return { object = object, corner = corner }
	end)
	local element = slot.object
	element.BackgroundTransparency = props.BackgroundTransparency or 0
	element.BorderSizePixel = 0
	element.ZIndex = props.ZIndex or 1
	if slot.corner then
		slot.corner.CornerRadius = UDim.new(0, props.radius or 0)
	end
	for key, val in pairs(props) do
		if key ~= "radius" then
			element[key] = val
		end
	end
	return element
end
local function textRow(parent, value, pos, size, fontSize, color, cache, align)
	local slot = acquire(cache, "label", function()
		local object = UI.label(parent, "", pos, size, uiTextSize(fontSize), C.text)
		object.TextTruncate = Enum.TextTruncate.AtEnd
		return { object = object }
	end)
	local element = slot.object
	element.Text = tostring(value or "")
	element.Position, element.Size = pos, size
	element.TextSize = uiTextSize(fontSize)
	element.TextColor3 = color or C.text
	element.TextXAlignment = align or Enum.TextXAlignment.Left
	element.ZIndex = 2
	return element
end
local function visibleRows(total, offset)
	local y = laneCanvas.CanvasPosition.Y - (offset or 0)
	local first = math.min(math.max(1, total), math.max(1, math.floor(y / ROW_H) + 1 - OVERSCAN))
	local last = math.min(total, math.ceil((y + laneCanvas.AbsoluteSize.Y) / ROW_H) + 1 + OVERSCAN)
	return first, last
end
local function zoneBar(parent, pos, size, color, caption, action)
	local slot = acquire(laneObjects, "zone", function()
		local item = {}
		local b, text, record = UI.button(parent, "", pos, size, function()
			if item.action then
				item.action()
			end
		end, {
			color = color,
			border = false,
			radius = tokens.radius.xs,
			textSize = tokens.type.caption,
			hoveringEnabled = false,
			paddingX = 4,
		})
		item.object, item.caption, item.record = b, text, record
		return item
	end)
	slot.action = action
	slot.object.Position, slot.object.Size = pos, size
	if slot.record then
		slot.record.color = color
		slot.record.defaultColor = color
		slot.record.hoverColor = color
		slot.record.defaultHoverColor = color
		slot.record.pressedColor = color
	end
	slot.object.BackgroundColor3 = color
	slot.object.BackgroundTransparency = 0
	slot.object.ZIndex = 3
	if slot.caption then
		slot.caption.Text = caption
		slot.caption.ZIndex = 4
		slot.caption.TextXAlignment = Enum.TextXAlignment.Left
		-- Contrast against the data-mark color rather than assuming a dark theme.
		local function linear(v)
			return v <= 0.04045 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
		end
		local luminance = 0.2126 * linear(color.R) + 0.7152 * linear(color.G) + 0.0722 * linear(color.B)
		slot.caption.TextColor3 = luminance > 0.179 and Color3.new(0, 0, 0) or Color3.new(1, 1, 1)
		slot.caption.TextTruncate = Enum.TextTruncate.AtEnd
	end
	return slot.object
end

local syncingScroll = false
local lastScrollRow = -1
local function onDetailScroll()
	local row = math.floor(laneCanvas.CanvasPosition.Y / ROW_H)
	if row ~= lastScrollRow then
		lastScrollRow = row
		dirtyDetail = true
	end
end
connect(laneNames:GetPropertyChangedSignal("CanvasPosition"), function()
	if syncingScroll then
		return
	end
	syncingScroll = true
	laneCanvas.CanvasPosition = Vector2.new(laneCanvas.CanvasPosition.X, laneNames.CanvasPosition.Y)
	syncingScroll = false
	onDetailScroll()
end)
connect(laneCanvas:GetPropertyChangedSignal("CanvasPosition"), function()
	if syncingScroll then
		return
	end
	syncingScroll = true
	laneNames.CanvasPosition = Vector2.new(0, laneCanvas.CanvasPosition.Y)
	syncingScroll = false
	onDetailScroll()
end)

local function getSelectedFrame()
	return selectedFrame or samples[#samples]
end

local function refreshHistorical()
	local count = getFrameCount()
	local maxCount = math.min(count, GRAPH_POINTS)
	table.clear(samples)
	for index = maxCount, 1, -1 do
		local data = getFrame(index)
		if data then
			local rec = summarize(data)
			rec.offset = index
			table.insert(samples, rec)
		end
	end
	-- If collection was never flushed, retain the most recent real frame
	-- reading so Pause never makes an otherwise working chart disappear.
	if #samples == 0 then
		local data, source = getLiveSample()
		if data then
			table.insert(samples, summarize(data))
			lastSampleSource = source
		end
	else
		lastSampleSource = "native"
	end
	dirtyGraph = true
end

local function readSelection()
	local count = getFrameCount()
	if count <= 0 then
		selectedFrame = nil
		return
	end
	selectedOffset = math.clamp(selectedOffset, 1, count)
	local data = getFrame(selectedOffset)
	selectedFrame = data and summarize(data) or nil
	if selectedFrame then
		selectedFrame.offset = selectedOffset
	end
end

setPaused = function(value)
	if destroyed then
		return
	end
	value = not not value
	safeCall(value and "Pause" or "Resume")
	-- Void-returning methods yield nil even on success; use the property as truth.
	paused = ProfilerService.Paused == true
	if value ~= paused then
		statusLabel.Text = "Pause/Resume unavailable; check ProfilerService method exposure"
		return
	end
	setButtonText(pauseButton, paused and "Resume" or "Pause")
	updateLiveBadge()
	if paused then
		selectedOffset = 1
		refreshHistorical()
		readSelection()
	else
		selectedOffset = 1
		selectedFrame = nil
		table.clear(samples)
	end
	dirtyGraph, dirtyDetail = true, true
end

selectOffset = function(offset)
	if not paused then
		setPaused(true)
	end
	if not paused then
		return
	end
	selectedOffset = math.clamp(offset, 1, math.max(getFrameCount(), 1))
	readSelection()
	dirtyGraph, dirtyDetail = true, true
end

pauseButton = button(toolbar, "Pause", UDim2.new(1, -86, 0, 5), UDim2.fromOffset(80, metrics.buttonHeight), function()
	setPaused(not paused)
end)
iconButton(
	toolbar,
	"builtin://icons/ArrowRight.svg",
	"Previous (older) frame",
	UDim2.new(1, -202, 0, 5),
	UDim2.fromOffset(32, metrics.buttonHeight),
	function()
		selectOffset(selectedOffset + 1)
	end,
	180
)
iconButton(
	toolbar,
	"builtin://icons/ArrowRight.svg",
	"Next (newer) frame",
	UDim2.new(1, -166, 0, 5),
	UDim2.fromOffset(32, metrics.buttonHeight),
	function()
		selectOffset(selectedOffset - 1)
	end
)

local function drawGraphNow()
	dirtyGraph = false
	local graphWidth = chart.AbsoluteSize.X
	local graphHeight = chart.AbsoluteSize.Y
	if graphWidth <= 0 or graphHeight <= 0 then
		dirtyGraph = true
		return
	end

	local maximum = 33.333
	for _, rec in ipairs(samples) do
		maximum = math.max(maximum, rec.frameMs)
	end
	maximum = math.ceil(maximum / 16.667) * 16.667
	local frameCount = math.min(#samples, GRAPH_POINTS)
	local start = #samples - frameCount
	for i = 1, GRAPH_POINTS do
		local slot = graphBars[i]
		local rec = i > GRAPH_POINTS - frameCount and samples[start + i - (GRAPH_POINTS - frameCount)] or nil
		local x = math.floor((i - 1) * graphWidth / GRAPH_POINTS)
		local nextX = math.floor(i * graphWidth / GRAPH_POINTS)
		-- 2px gutter between bars for a cleaner, less dense look.
		local w = math.max(1, nextX - x - 2)
		local stack = 0
		local selected = rec and paused and selectedFrame and rec.offset == selectedOffset
		slot.marker.Visible = not not selected
		slot.marker.BackgroundColor3 = C.selection
		slot.marker.Size = UDim2.fromOffset(w + 2, graphHeight)
		slot.marker.Position = UDim2.fromOffset(x - 1, 0)
		slot.button.Position = UDim2.fromOffset(x, 0)
		slot.button.Size = UDim2.fromOffset(w, graphHeight)
		for _, cat in ipairs(categories) do
			local segment = slot.pieces[cat.key]
			local value = rec and (rec.bucket[cat.key] or 0) or 0
			segment.BackgroundColor3 = cat.color
			if value > 0 and categoryEnabled[cat.key] then
				local h = math.max(1, math.floor(graphHeight * (value / maximum)))
				segment.Position = UDim2.fromOffset(x, graphHeight - stack - h)
				segment.Size = UDim2.fromOffset(w, h)
				segment.Visible = true
				stack += h
			else
				segment.Visible = false
			end
		end
	end
	for _, ref in ipairs(chartReference) do
		local y = graphHeight - math.floor(graphHeight * ref.ms / maximum)
		ref.line.Position = UDim2.fromOffset(0, y)
		ref.caption.Position = UDim2.new(1, -52, 0, math.max(0, y - 15))
	end

	-- Legend: milliseconds per category for the current / selected frame.
	local current = getSelectedFrame()
	for _, cat in ipairs(categories) do
		local value = current and current.bucket[cat.key]
		legendValues[cat.key].Text = value and string.format("%.1f ms", value) or "--"
	end

	graphFooter.Text = string.format("Guides: 16.67 ms / 60 FPS   |   33.33 ms / 30 FPS   |   scale %.1f ms", maximum)
	local historyCount = getFrameCount()
	local sourceText = lastSampleSource == "native" and "Native zone history"
		or lastSampleSource == "frame-time" and "FrameTime fallback (untracked)"
		or "No frame data"
	graphHeader.Text = string.format("%s  |  %d samples  |  %d native frames", sourceText, #samples, historyCount)
	if lastFrameReadError then
		graphHeader.Text = "GetFrameRecord error: " .. string.sub(lastFrameReadError, 1, 100)
	elseif historyCount == 0 and #samples > 0 then
		-- The bars are valid measured frame times, but the engine has not
		-- delivered frame_flush() records or zone scopes yet.
		graphHeader.Text = graphHeader.Text .. "  |  check frame_flush()"
	end
end

drawGraph = drawGraphNow

-- Detail helpers -
local function titlePair(name, value, y)
	textRow(laneNames, name, UDim2.fromOffset(12, y), UDim2.new(1, -18, 0, ROW_H), 11, C.dim, nameObjects)
	textRow(laneCanvas, value, UDim2.fromOffset(12, y), UDim2.new(1, -24, 0, ROW_H), 11, C.text, laneObjects)
end

local function headerStrip(width)
	tracked(laneNames, {
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 0, ROW_H),
		BackgroundColor3 = C.strip,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
	}, nameObjects)
	tracked(laneCanvas, {
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(width, ROW_H),
		BackgroundColor3 = C.strip,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
	}, laneObjects)
end

local function rowStripe(index, y, width)
	if index % 2 ~= 0 then
		return
	end
	tracked(laneNames, {
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, 0, 0, ROW_H),
		BackgroundColor3 = C.rowAlt,
		BackgroundTransparency = 0.65,
		BorderSizePixel = 0,
	}, nameObjects)
	tracked(laneCanvas, {
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.fromOffset(width, ROW_H),
		BackgroundColor3 = C.rowAlt,
		BackgroundTransparency = 0.65,
		BorderSizePixel = 0,
	}, laneObjects)
end

-- Right-aligned numeric columns, laid out from the right edge of the canvas.
local function columnPositions(widths, contentWidth)
	local total = 0
	for _, w in ipairs(widths) do
		total += w
	end
	local x = contentWidth - total - 8
	local xs = {}
	for i, w in ipairs(widths) do
		xs[i] = x
		x += w
	end
	return xs
end

local function drawHeader(nameText, barText, headers, widths, xs, contentWidth)
	headerStrip(contentWidth)
	textRow(laneNames, nameText, UDim2.fromOffset(12, 0), UDim2.new(1, -18, 0, ROW_H), 10, C.dim, nameObjects)
	textRow(laneCanvas, barText, UDim2.fromOffset(12, 0), UDim2.fromOffset(200, ROW_H), 10, C.dim, laneObjects)
	for i, text in ipairs(headers) do
		textRow(
			laneCanvas,
			text,
			UDim2.fromOffset(xs[i], 0),
			UDim2.fromOffset(widths[i] - 10, ROW_H),
			10,
			C.dim,
			laneObjects,
			Enum.TextXAlignment.Right
		)
	end
end

local function drawCell(value, x, y, w)
	textRow(
		laneCanvas,
		value,
		UDim2.fromOffset(x, y),
		UDim2.fromOffset(w - 10, ROW_H),
		10,
		C.text,
		laneObjects,
		Enum.TextXAlignment.Right
	)
end

local function timeRuler(ms, canvasWidth)
	local step = ms <= 16 and 2 or ms <= 50 and 5 or ms <= 120 and 10 or 20
	step = math.max(step, math.ceil(ms / 80 / step) * step)
	local maxTick = math.floor(ms / step)
	tracked(laneCanvas, {
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(canvasWidth, 24),
		BackgroundColor3 = C.strip,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
	}, laneObjects)
	for i = 0, maxTick do
		local x = math.floor((i * step / ms) * canvasWidth)
		tracked(laneCanvas, {
			Position = UDim2.fromOffset(x, 0),
			Size = UDim2.new(0, 1, 1, 0),
			BorderSizePixel = 0,
			BackgroundColor3 = C.outline,
			BackgroundTransparency = 0.85,
		}, laneObjects)
		textRow(
			laneCanvas,
			tostring(i * step) .. " ms",
			UDim2.fromOffset(x + 4, 0),
			UDim2.fromOffset(60, 24),
			10,
			C.dim,
			laneObjects
		)
	end
end

local function drawTimeline()
	recycleDetails()
	local rec = getSelectedFrame()
	if not rec then
		laneCanvas.CanvasSize = UDim2.fromOffset(0, 0)
		laneNames.CanvasSize = UDim2.fromOffset(0, 0)
		detailCaption.Text = "No capture"
		titlePair("No capture", "Open this window and allow the profiler to collect frames.", 10)
		return
	end
	local zones = {}
	for _, zone in ipairs(rec.zones or {}) do
		if categoryEnabled[categorize(zone.name)] and (tonumber(zone.ms) or 0) > 0 then
			table.insert(zones, zone)
		end
	end
	table.sort(zones, function(a, b)
		local aStart, bStart = tonumber(a.startMs) or 0, tonumber(b.startMs) or 0
		if aStart == bStart then
			return (tonumber(a.ms) or 0) > (tonumber(b.ms) or 0)
		end
		return aStart < bStart
	end)
	if #zones == 0 then
		laneCanvas.CanvasSize = UDim2.fromOffset(0, 0)
		laneNames.CanvasSize = UDim2.fromOffset(0, 0)
		titlePair(
			"No native zones",
			"The frame-time graph can still run. Native history needs collecting + frame_flush().",
			10
		)
		detailCaption.Text = "0 zones"
		statusLabel.Text = "No named native zones in this frame. Instrument engine scopes with profiling.Begin/End."
		return
	end

	local ends = {}
	local laneCount = 0
	local width = math.max(1, laneCanvas.AbsoluteSize.X)
	local maxEnd = math.max(rec.frameMs, 0.1)
	for _, zone in ipairs(zones) do
		maxEnd = math.max(maxEnd, (tonumber(zone.startMs) or 0) + (tonumber(zone.ms) or 0))
	end
	maxEnd = math.max(0.1, maxEnd)
	local canvasWidth = math.max(width, math.floor(width * zoom))
	local n = math.min(#zones, MAX_ZONES)
	local rulerHeight = 28

	timeRuler(maxEnd, canvasWidth)
	tracked(laneNames, {
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundColor3 = C.strip,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
	}, nameObjects)
	textRow(laneNames, "Lane", UDim2.fromOffset(12, 0), UDim2.new(1, -18, 0, 24), 10, C.dim, nameObjects)

	local drawn = 0
	local firstVisibleLane, lastVisibleLane = visibleRows(MAX_LANES, rulerHeight - ROW_H)
	for i = 1, n do
		local zone = zones[i]
		local startTime = math.max(0, tonumber(zone.startMs) or 0)
		local duration = math.max(0, tonumber(zone.ms) or 0)
		local lane = nil
		for j = 1, laneCount do
			if ends[j] <= startTime + 0.0001 then
				lane = j
				break
			end
		end
		if not lane then
			if laneCount >= MAX_LANES then
				break
			end
			laneCount += 1
			lane = laneCount
		end
		ends[lane] = startTime + duration
		local y = rulerHeight + (lane - 1) * ROW_H
		local x = math.floor(startTime / maxEnd * canvasWidth)
		local w = math.max(2, math.floor(duration / maxEnd * canvasWidth))
		drawn += 1
		if lane >= firstVisibleLane and lane <= lastVisibleLane then
			zoneBar(
				laneCanvas,
				UDim2.fromOffset(x, y + 2),
				UDim2.fromOffset(w, ROW_H - 4),
				zoneColor(zone),
				w >= 55 and tostring(zone.name) or "",
				function()
					statusLabel.Text = string.format(
						"%s | %.3f ms | starts at %.3f ms | %s",
						tostring(zone.name),
						duration,
						startTime,
						categorize(zone.name)
					)
				end
			)
		end
	end
	local firstLane, lastLane = visibleRows(laneCount, rulerHeight - ROW_H)
	for i = firstLane, lastLane do
		local y = rulerHeight + (i - 1) * ROW_H
		textRow(
			laneNames,
			"Zone lane " .. i,
			UDim2.fromOffset(12, y),
			UDim2.new(1, -18, 0, ROW_H),
			11,
			C.dim,
			nameObjects
		)
	end
	laneCanvas.CanvasSize = UDim2.fromOffset(canvasWidth, math.max(100, laneCount * ROW_H + 40))
	laneNames.CanvasSize = UDim2.fromOffset(0, math.max(100, laneCount * ROW_H + 40))
	detailCaption.Text = string.format("%d zones", #zones)
	statusLabel.Text = string.format(
		"Zones are relative to the first zone start; overlaps may be concurrent (no thread IDs). Showing %d/%d zones.",
		drawn,
		#zones
	)
end

local function memoryText(bytes)
	return string.format("%.2f MB", (tonumber(bytes) or 0) / (1024 * 1024))
end

local function drawThreads()
	recycleDetails()
	local list = safeCall("GetThreadHistory", paused and selectedOffset or 1)
	local state = safeCall("GetThreadStats") or {}
	local names = {}
	for _, thread in ipairs(safeCall("GetThreads") or {}) do
		names[thread.Id] = thread.Name
	end
	local rows = list and list.threads or {}
	table.sort(rows, function(a, b)
		return (a.totalCpuMs or 0) > (b.totalCpuMs or 0)
	end)
	local maxValue = 0.001
	for _, thread in ipairs(rows) do
		maxValue = math.max(maxValue, tonumber(thread.totalCpuMs) or 0)
	end
	local width = math.max(200, laneCanvas.AbsoluteSize.X)
	local contentWidth = math.max(520, math.floor(width * zoom))
	local shown = math.min(#rows, 100)

	local widths = { 100, 90, 96 }
	local xs = columnPositions(widths, contentWidth)
	local barMax = math.max(40, xs[1] - 28)
	drawHeader("Luau thread", "Per-frame CPU total", { "CPU", "Resumes", "Alloc" }, widths, xs, contentWidth)

	local first, last = visibleRows(shown, 0)
	for i = first, last do
		local thread = rows[i]
		local y = i * ROW_H
		rowStripe(i, y, contentWidth)
		local name = names[thread.id] or ("Thread #" .. tostring(thread.id))
		textRow(laneNames, name, UDim2.fromOffset(12, y), UDim2.new(1, -18, 0, ROW_H), 11, C.text, nameObjects)
		tracked(laneCanvas, {
			Position = UDim2.fromOffset(12, y + 5),
			Size = UDim2.fromOffset(
				math.max(2, math.floor((tonumber(thread.totalCpuMs) or 0) / maxValue * barMax)),
				ROW_H - 10
			),
			BackgroundColor3 = C.accent,
			radius = tokens.radius.xs,
			BorderSizePixel = 0,
		}, laneObjects)
		drawCell(string.format("%.3f ms", tonumber(thread.totalCpuMs) or 0), xs[1], y, widths[1])
		drawCell(formatInt(thread.resumes), xs[2], y, widths[2])
		drawCell(memoryText(thread.allocatedBytes), xs[3], y, widths[3])
	end
	laneNames.CanvasSize = UDim2.fromOffset(0, (shown + 2) * ROW_H)
	laneCanvas.CanvasSize = UDim2.fromOffset(contentWidth, (shown + 2) * ROW_H)
	detailCaption.Text = shown < #rows and string.format("%d/%d threads", shown, #rows) or tostring(#rows) .. " threads"
	statusLabel.Text = string.format(
		"%d live / %d retired threads   |   Luau heap %s   |   allocating %.2f MB/s   |   CPU bars have no scheduling timestamps.",
		tonumber(state.threads) or 0,
		tonumber(state.deadThreads) or 0,
		memoryText(state.heapBytes),
		(tonumber(state.allocationRateBytesPerSecond) or 0) / 1048576
	)
end

local function drawScripts()
	recycleDetails()
	local scripts = safeCall("GetScripts") or {}
	table.sort(scripts, function(a, b)
		return (a.CpuMs or 0) > (b.CpuMs or 0)
	end)
	local width = math.max(200, laneCanvas.AbsoluteSize.X)
	local contentWidth = math.max(520, math.floor(width * zoom))
	local shown = math.min(#scripts, 100)
	local maxValue = 0.001
	for _, scriptStat in ipairs(scripts) do
		maxValue = math.max(maxValue, tonumber(scriptStat.CpuMs) or 0)
	end

	local widths = { 100, 100, 100, 90 }
	local xs = columnPositions(widths, contentWidth)
	local barMax = math.max(40, xs[1] - 28)
	drawHeader("Script", "Cumulative CPU (exclusive)", { "CPU", "Total", "Resumes", "Alloc" }, widths, xs, contentWidth)

	local first, last = visibleRows(shown, 0)
	for i = first, last do
		local item = scripts[i]
		local y = i * ROW_H
		rowStripe(i, y, contentWidth)
		textRow(
			laneNames,
			item.Name or "Unknown",
			UDim2.fromOffset(12, y),
			UDim2.new(1, -18, 0, ROW_H),
			11,
			C.text,
			nameObjects
		)
		tracked(laneCanvas, {
			Position = UDim2.fromOffset(12, y + 5),
			Size = UDim2.fromOffset(
				math.max(2, math.floor((tonumber(item.CpuMs) or 0) / maxValue * barMax)),
				ROW_H - 10
			),
			BackgroundColor3 = categories[categoryByKey.Scripts].color,
			radius = tokens.radius.xs,
			BorderSizePixel = 0,
		}, laneObjects)
		drawCell(string.format("%.2f ms", tonumber(item.CpuMs) or 0), xs[1], y, widths[1])
		drawCell(string.format("%.2f ms", tonumber(item.TotalCpuMs) or 0), xs[2], y, widths[2])
		drawCell(formatInt(item.Resumes), xs[3], y, widths[3])
		drawCell(memoryText(item.AllocatedBytes), xs[4], y, widths[4])
	end
	laneNames.CanvasSize = UDim2.fromOffset(0, (shown + 2) * ROW_H)
	laneCanvas.CanvasSize = UDim2.fromOffset(contentWidth, (shown + 2) * ROW_H)
	detailCaption.Text = shown < #scripts and string.format("%d/%d scripts", shown, #scripts)
		or tostring(#scripts) .. " scripts"
	statusLabel.Text =
		"Script totals are cumulative for the current Luau VM; they are not per-frame historical snapshots."
end

drawDetail = function()
	dirtyDetail = false
	if activeTab == "Timeline" then
		drawTimeline()
	elseif activeTab == "Threads" then
		drawThreads()
	else
		drawScripts()
	end
	finishDetails()
end

local lastSample = 0
local lastPaint = 0
local lastScriptRefresh = 0
local lastDetailRefresh = 0
local wasVisible = false

local function update()
	if destroyed then
		return
	end
	local visible = panel.Visible and gui.Enabled
	if not visible then
		if wasVisible then
			wasVisible = false
			-- Optional native API: release history capture when this inspector
			-- closes, without switching off the separate F2 profiler overlay.
			if not ProfilerService.Enabled then
				safeCall("SetCollectionEnabled", false)
			end
		end
		return
	end

	local now = os.clock()
	if not wasVisible then
		wasVisible = true
		paused = ProfilerService.Paused == true
		setButtonText(pauseButton, paused and "Resume" or "Pause")
		updateLiveBadge()
		-- Request native frame history explicitly (requires Odin namecall
		-- handler), then read FrameCount for older builds with that side effect.
		safeCall("SetCollectionEnabled", true)
		getFrameCount()
		if paused then
			refreshHistorical()
			readSelection()
		end
		dirtyGraph, dirtyDetail = true, true
	end

	if not paused and now - lastSample >= SAMPLE_INTERVAL then
		lastSample = now
		local data, source = getLiveSample()
		lastSampleSource = source
		if data then
			table.insert(samples, summarize(data))
			if #samples > GRAPH_POINTS then
				table.remove(samples, 1)
			end
			dirtyGraph = true
			if activeTab == "Timeline" and now - lastDetailRefresh >= DETAIL_LIVE_INTERVAL then
				lastDetailRefresh = now
				dirtyDetail = true
			end
		end
	end

	if now - lastPaint < PAINT_INTERVAL then
		return
	end
	lastPaint = now

	local rec = getSelectedFrame()
	local fps = paused and rec and rec.fps or tonumber(ProfilerService.FPS) or 0
	local frameMs = paused and rec and rec.frameMs or tonumber(ProfilerService.FrameTime) or 0
	readout.Text = string.format("FPS %.1f     Frame %.2f ms", fps or 0, frameMs or 0)
	frameCounter.Text = paused and string.format("%d / %d", selectedOffset, getFrameCount()) or "LIVE"
	if activeTab == "Scripts" and not paused and now - lastScriptRefresh >= 0.8 then
		lastScriptRefresh = now
		dirtyDetail = true
	elseif activeTab == "Threads" and not paused and now - lastDetailRefresh >= DETAIL_LIVE_INTERVAL then
		lastDetailRefresh = now
		dirtyDetail = true
	end
	if dirtyGraph then
		drawGraph()
	end
	if dirtyDetail then
		drawDetail()
	end
end

local function refreshTheme()
	if destroyed then
		return
	end
	UI.refreshWindow("Profiler")
	themeRepaint()
	seamlessTabs()
	updateLiveBadge()
	for key, visual in pairs(legendVisuals) do
		visual.caption.TextColor3 = categoryEnabled[key] and C.text or C.dim
		visual.chip.BackgroundColor3 = categories[categoryByKey[key]].color
	end
	dirtyGraph, dirtyDetail = true, true
end

connect(RunService.Heartbeat, update)
local themeConnection = UI.onThemeChanged(refreshTheme)
connect(content:GetPropertyChangedSignal("BackgroundColor3"), function()
	if not destroyed then
		seamlessTabs()
	end
end)
connect(chart:GetPropertyChangedSignal("AbsoluteSize"), function()
	dirtyGraph = true
end)
connect(laneCanvas:GetPropertyChangedSignal("AbsoluteSize"), function()
	dirtyDetail = true
end)
connect(panel.Destroying, function()
	if destroyed then
		return
	end
	destroyed = true
	if wasVisible and not ProfilerService.Enabled then
		safeCall("SetCollectionEnabled", false)
	end
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
	if themeConnection then
		themeConnection:Disconnect()
	end
	for _, tip in ipairs(tooltips) do
		tip:Destroy()
	end
	table.clear(tooltips)
	UI.forgetButtons(content)
	tabController.destroy()
	table.clear(laneObjects.groups)
	table.clear(nameObjects.groups)
	table.clear(graphBars)
	table.clear(samples)
end)

return {
	Enable = function()
		panel.Visible = true
		dirtyGraph, dirtyDetail = true, true
	end,
	Disable = function()
		panel.Visible = false
	end,
	Toggle = function()
		panel.Visible = not panel.Visible
		dirtyGraph, dirtyDetail = true, true
	end,
	Refresh = function()
		refreshTheme()
	end,
	IsVisible = function()
		return panel.Visible
	end,
	Pause = function()
		setPaused(true)
	end,
	Resume = function()
		setPaused(false)
	end,
}

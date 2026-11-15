if IsServer or IsClient or IsPlaytest then
	return nil
end

local UI = require("@internal/editor_ui")
local ProfilerService = game:GetService("ProfilerService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local WINDOW_W, WINDOW_H = 1120, 670
local GRAPH_POINTS = 96
local SAMPLE_INTERVAL = 0.10
local PAINT_INTERVAL = 0.15
local MAX_ZONES = 180
local DETAIL_LIVE_INTERVAL = 0.45
local MAX_LANES = 32
local ROW_H = 25

local C = {
	background = Color3.fromRGB(31, 32, 35),
	panel = Color3.fromRGB(42, 43, 46),
	strip = Color3.fromRGB(49, 50, 53),
	row = Color3.fromRGB(44, 45, 49),
	rowAlt = Color3.fromRGB(39, 40, 43),
	hover = Color3.fromRGB(64, 67, 73),
	outline = Color3.fromRGB(70, 72, 77),
	text = Color3.fromRGB(229, 230, 233),
	dim = Color3.fromRGB(161, 164, 171),
	accent = Color3.fromRGB(92, 165, 227),
	selection = Color3.fromRGB(222, 226, 234),
}

-- The names match the reference image. Categories are heuristics based on zone names,
-- not native, exclusive profiler counters.
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

local function make(className, parent, props)
	local object = Instance.new(className)
	for key, value in pairs(props or {}) do
		object[key] = value
	end
	object.Parent = parent
	return object
end

local function frame(parent, position, size, color, name)
	return make("Frame", parent, {
		Name = name or "Frame",
		Position = position,
		Size = size,
		BackgroundColor3 = color or C.panel,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	})
end

local function label(parent, value, position, size, fontSize, color, align)
	return make("TextLabel", parent, {
		Text = tostring(value or ""),
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		TextSize = fontSize or 12,
		TextColor3 = color or C.text,
		TextXAlignment = align or Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	})
end

local function button(parent, value, position, size, action)
	local b = make("TextButton", parent, {
		Text = value,
		Position = position,
		Size = size,
		BorderSizePixel = 0,
		BackgroundColor3 = C.strip,
		TextSize = 12,
		TextColor3 = C.text,
	})
	if action then
		b.MouseButton1Click:Connect(action)
	end
	return b
end

local function scroller(parent, position, size, color)
	return make("ScrollingFrame", parent, {
		Position = position,
		Size = size,
		BackgroundColor3 = color or C.background,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = C.dim,
		CanvasSize = UDim2.fromOffset(0, 0),
		ClipsDescendants = true,
		Active = true,
	})
end

local function safeCall(methodName, ...)
	local args = { ... }
	local ok, result = pcall(function()
		return ProfilerService[methodName](ProfilerService, table.unpack(args))
	end)
	if ok then
		return result
	end
	return nil
end

local function getFrame(index)
	return safeCall("GetFrameRecord", index)
end

local function getFrameCount()
	return math.max(0, tonumber(ProfilerService.FrameCount) or 0)
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

local gui = UI.widgetOverlay()
local panel, content = UI.window(
	"Profiler",
	UDim2.fromOffset(70, 58),
	UDim2.fromOffset(WINDOW_W, WINDOW_H),
	"Profiler",
	{ closable = true }
)
panel.Parent = gui
panel.Visible = false
content.BackgroundColor3 = C.background
content.BackgroundTransparency = 0
content.ClipsDescendants = true

local toolbar = frame(content, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 42), C.panel)
local liveLabel = label(toolbar, "LIVE", UDim2.fromOffset(12, 4), UDim2.fromOffset(52, 33), 12, C.accent)
local readout = label(toolbar, "FPS --    Frame -- ms", UDim2.fromOffset(67, 4), UDim2.new(1, -420, 0, 33), 13)
local pauseButton
local backButton
local nextButton
local frameCounter =
	label(toolbar, "-- / --", UDim2.new(1, -292, 0, 5), UDim2.fromOffset(82, 30), 11, C.dim, Enum.TextXAlignment.Right)

local graphPanel = frame(content, UDim2.fromOffset(0, 43), UDim2.new(1, 0, 0, 218), C.background)
local legend = frame(graphPanel, UDim2.fromOffset(0, 0), UDim2.new(0, 206, 1, 0), C.panel)
label(legend, "CPU Usage", UDim2.fromOffset(12, 6), UDim2.fromOffset(165, 22), 15)
local legendHint =
	label(legend, "Normalized named zones", UDim2.fromOffset(12, 28), UDim2.fromOffset(184, 16), 10, C.dim)

local chartArea = frame(graphPanel, UDim2.fromOffset(207, 0), UDim2.new(1, -207, 1, 0), C.strip)
local graphHeader =
	label(chartArea, "Frame history  -  96 samples", UDim2.fromOffset(10, 2), UDim2.new(1, -20, 0, 21), 11, C.dim)
local chart = frame(chartArea, UDim2.fromOffset(8, 26), UDim2.new(1, -16, 1, -52), C.panel)
local graphFooter = label(
	chartArea,
	"16.67ms (60 FPS)     33.33ms (30 FPS)",
	UDim2.fromOffset(10, 0),
	UDim2.new(1, -20, 1, 0),
	10,
	C.dim
)
graphFooter.Position = UDim2.new(0, 10, 1, -24)
graphFooter.Size = UDim2.new(1, -20, 0, 20)

local graphBars = {}
local samples = {}
local selectedFrame = nil
local selectedOffset = 1
local paused = false
local activeTab = "Timeline"
local dirtyGraph, dirtyDetail = true, true
local drawGraph
local drawDetail
local setPaused
local selectOffset

local function graphSlot(index)
	local hit = button(
		chart,
		"",
		UDim2.new((index - 1) / GRAPH_POINTS, 0, 0, 0),
		UDim2.new(1 / GRAPH_POINTS, -1, 1, 0),
		function()
			if not paused then
				-- Live samples are spaced in time, not indexed by native frame ID.
				-- Freeze first, then choose an exact historical frame on the next click.
				setPaused(true)
				return
			end
			local n = math.min(#samples, GRAPH_POINTS)
			local firstSlot = GRAPH_POINTS - n + 1
			local row = index >= firstSlot and samples[#samples - n + index - firstSlot + 1] or nil
			if row and row.offset then
				selectOffset(row.offset)
			end
		end
	)
	hit.BackgroundTransparency = 1
	local columns = {}
	for _, cat in ipairs(categories) do
		columns[cat.key] = frame(hit, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 0), cat.color)
		columns[cat.key].Visible = false
	end
	local marker = frame(hit, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 2), C.selection)
	marker.Visible = false
	return { button = hit, pieces = columns, marker = marker }
end

for i = 1, GRAPH_POINTS do
	graphBars[i] = graphSlot(i)
end

for _, limit in ipairs({ 16.667, 33.333 }) do
	local marker = frame(chart, UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0, 1), C.outline)
	marker.Name = "Reference" .. tostring(limit)
	marker.BackgroundTransparency = 0.3
	marker.ZIndex = 1
end

local chartReference = {}
for _, child in ipairs(chart:GetChildren()) do
	if child.Name == "Reference16.667" or child.Name == "Reference33.333" then
		table.insert(chartReference, child)
	end
end

for i = 1, #categories do
	local cat = categories[#categories - i + 1]
	local row = button(legend, "", UDim2.fromOffset(0, 48 + (i - 1) * 18), UDim2.new(1, 0, 0, 18), function()
		categoryEnabled[cat.key] = not categoryEnabled[cat.key]
		dirtyGraph = true
		dirtyDetail = true
	end)
	row.BackgroundTransparency = 1
	local chip = frame(row, UDim2.fromOffset(11, 5), UDim2.fromOffset(9, 9), cat.color)
	local caption = label(row, cat.label, UDim2.fromOffset(26, 0), UDim2.new(1, -29, 1, 0), 11, C.text)
	row.MouseButton1Click:Connect(function()
		chip.BackgroundTransparency = categoryEnabled[cat.key] and 0 or 0.72
		caption.TextColor3 = categoryEnabled[cat.key] and C.text or C.dim
	end)
end

local divider = frame(content, UDim2.fromOffset(0, 261), UDim2.new(1, 0, 0, 1), C.outline)
local detailHead = frame(content, UDim2.fromOffset(0, 262), UDim2.new(1, 0, 0, 37), C.panel)
local tabs = {}
for i, tabName in ipairs({ "Timeline", "Threads", "Scripts" }) do
	tabs[tabName] = button(
		detailHead,
		tabName,
		UDim2.fromOffset(10 + (i - 1) * 100, 5),
		UDim2.fromOffset(94, 26),
		function()
			activeTab = tabName
			dirtyDetail = true
		end
	)
end
local zoom = 1
local zoomCaption =
	label(detailHead, "1x", UDim2.new(1, -196, 0, 5), UDim2.fromOffset(36, 26), 12, C.dim, Enum.TextXAlignment.Center)
button(detailHead, "-", UDim2.new(1, -232, 0, 5), UDim2.fromOffset(30, 26), function()
	zoom = math.max(1, zoom / 2)
	zoomCaption.Text = tostring(zoom) .. "x"
	dirtyDetail = true
end)
button(detailHead, "+", UDim2.new(1, -156, 0, 5), UDim2.fromOffset(30, 26), function()
	zoom = math.min(8, zoom * 2)
	zoomCaption.Text = tostring(zoom) .. "x"
	dirtyDetail = true
end)
local detailCaption =
	label(detailHead, "", UDim2.new(1, -118, 0, 5), UDim2.fromOffset(112, 26), 10, C.dim, Enum.TextXAlignment.Right)

local detailBody = frame(content, UDim2.fromOffset(0, 300), UDim2.new(1, 0, 1, -324), C.background)
local laneNames = scroller(detailBody, UDim2.fromOffset(0, 0), UDim2.new(0, 206, 1, 0), C.panel)
local laneCanvas = scroller(detailBody, UDim2.fromOffset(207, 0), UDim2.new(1, -207, 1, 0), C.background)
local statusBar = frame(content, UDim2.new(0, 0, 1, -23), UDim2.new(1, 0, 0, 23), C.panel)
local statusLabel = label(statusBar, "Profiler ready", UDim2.fromOffset(10, 0), UDim2.new(1, -20, 1, 0), 10, C.dim)

local laneObjects = {}
local nameObjects = {}
local function recycleDetails()
	for _, element in ipairs(laneObjects) do
		element:Destroy()
	end
	for _, element in ipairs(nameObjects) do
		element:Destroy()
	end
	table.clear(laneObjects)
	table.clear(nameObjects)
	laneCanvas.CanvasPosition = Vector2.new(0, 0)
	laneNames.CanvasPosition = Vector2.new(0, 0)
end

local function tracked(parent, props, cache)
	local element = make("Frame", parent, props)
	table.insert(cache, element)
	return element
end
local function textRow(parent, value, pos, size, fontSize, color, cache, align)
	local element = label(parent, value, pos, size, fontSize, color, align)
	table.insert(cache, element)
	return element
end

local syncingScroll = false
laneNames:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
	if syncingScroll then
		return
	end
	syncingScroll = true
	laneCanvas.CanvasPosition = Vector2.new(laneCanvas.CanvasPosition.X, laneNames.CanvasPosition.Y)
	syncingScroll = false
end)
laneCanvas:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
	if syncingScroll then
		return
	end
	syncingScroll = true
	laneNames.CanvasPosition = Vector2.new(0, laneCanvas.CanvasPosition.Y)
	syncingScroll = false
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
	value = not not value
	safeCall(value and "Pause" or "Resume")
	-- Void-returning methods yield nil even on success; use the property as truth.
	paused = ProfilerService.Paused == true
	if value ~= paused then
		statusLabel.Text = "Pause/Resume unavailable; check ProfilerService method exposure"
		return
	end
	pauseButton.Text = paused and "Resume" or "Pause"
	liveLabel.Text = paused and "PAUSED" or "LIVE"
	liveLabel.TextColor3 = paused and categories[2].color or C.accent
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

pauseButton = button(toolbar, "Pause", UDim2.new(1, -82, 0, 7), UDim2.fromOffset(74, 27), function()
	setPaused(not paused)
end)
backButton = button(toolbar, "<", UDim2.new(1, -202, 0, 7), UDim2.fromOffset(33, 27), function()
	selectOffset(selectedOffset + 1)
end)
nextButton = button(toolbar, ">", UDim2.new(1, -166, 0, 7), UDim2.fromOffset(33, 27), function()
	selectOffset(selectedOffset - 1)
end)

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
		local stack = 0
		local selected = rec and paused and selectedFrame and rec.offset == selectedOffset
		slot.marker.Visible = not not selected
		slot.marker.Size = UDim2.new(1, 0, 0, 2)
		slot.marker.Position = UDim2.fromOffset(0, 0)
		for _, cat in ipairs(categories) do
			local segment = slot.pieces[cat.key]
			local value = rec and (rec.bucket[cat.key] or 0) or 0
			if value > 0 and categoryEnabled[cat.key] then
				local h = math.max(1, math.floor(graphHeight * (value / maximum)))
				segment.Position = UDim2.new(0, 0, 1, -(stack + h))
				segment.Size = UDim2.new(1, 0, 0, h)
				segment.Visible = true
				stack += h
			else
				segment.Visible = false
			end
		end
		slot.button.BackgroundColor3 = C.hover
		slot.button.BackgroundTransparency = selected and 0.5 or 1
	end
	for _, ref in ipairs(chartReference) do
		local ms = ref.Name == "Reference16.667" and 16.667 or 33.333
		ref.Position = UDim2.new(0, 0, 1, -math.floor(graphHeight * ms / maximum))
	end
	graphFooter.Text = string.format("Guide: 16.67ms / 60 FPS   |   33.33ms / 30 FPS   |   scale %.1fms", maximum)
	graphHeader.Text = paused and ("Exact capture: latest " .. #samples .. " frames")
		or ("Live graph: sampling every " .. math.floor(SAMPLE_INTERVAL * 1000) .. "ms")
end

drawGraph = drawGraphNow

local function titlePair(name, value, y)
	textRow(laneNames, name, UDim2.fromOffset(10, y), UDim2.new(1, -18, 0, ROW_H), 11, C.dim, nameObjects)
	textRow(laneCanvas, value, UDim2.fromOffset(8, y), UDim2.new(1, -16, 0, ROW_H), 11, C.text, laneObjects)
end

local function timeRuler(ms, width, canvasWidth)
	local step = ms <= 16 and 2 or ms <= 50 and 5 or ms <= 120 and 10 or 20
	local maxTick = math.ceil(ms / step)
	for i = 0, maxTick do
		local x = math.floor((i * step / ms) * canvasWidth)
		tracked(laneCanvas, {
			Position = UDim2.fromOffset(x, 0),
			Size = UDim2.new(0, 1, 1, 0),
			BorderSizePixel = 0,
			BackgroundColor3 = C.outline,
			BackgroundTransparency = 0.65,
		}, laneObjects)
		textRow(
			laneCanvas,
			tostring(i * step) .. "ms",
			UDim2.fromOffset(x + 4, 0),
			UDim2.fromOffset(60, 23),
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
		if a.startMs == b.startMs then
			return a.ms > b.ms
		end
		return a.startMs < b.startMs
	end)

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
	local rulerHeight = 27

	timeRuler(maxEnd, width, canvasWidth)
	local drawn = 0
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
		local bar = make("TextButton", laneCanvas, {
			Name = "Zone" .. tostring(i),
			Position = UDim2.fromOffset(x, y + 2),
			Size = UDim2.fromOffset(w, ROW_H - 4),
			BackgroundColor3 = zoneColor(zone),
			BorderSizePixel = 0,
			Text = w >= 55 and tostring(zone.name) or "",
			TextColor3 = C.text,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		table.insert(laneObjects, bar)
		drawn += 1
		bar.MouseButton1Click:Connect(function()
			statusLabel.Text = string.format(
				"%s  |  %.3f ms  |  starts at %.3f ms  |  %s",
				tostring(zone.name),
				duration,
				startTime,
				categorize(zone.name)
			)
		end)
	end
	for i = 1, laneCount do
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
		"Recorded zones are relative to the first zone start. Overlapping intervals may be concurrent; no native thread IDs are attached. Showing %d/%d zones.",
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
	local contentWidth = math.floor(width * zoom)
	local shown = math.min(#rows, 100)
	titlePair("Luau thread", "Per-frame CPU total   |   1 bar = the thread's total recorded CPU time", 0)
	for i = 1, shown do
		local thread = rows[i]
		local y = i * ROW_H
		local name = names[thread.id] or ("Thread #" .. tostring(thread.id))
		textRow(laneNames, name, UDim2.fromOffset(10, y), UDim2.new(1, -18, 0, ROW_H), 11, C.text, nameObjects)
		tracked(laneCanvas, {
			Position = UDim2.fromOffset(0, y + 3),
			Size = UDim2.fromOffset(
				math.floor((tonumber(thread.totalCpuMs) or 0) / maxValue * (contentWidth - 155)),
				ROW_H - 6
			),
			BackgroundColor3 = C.accent,
			BorderSizePixel = 0,
		}, laneObjects)
		textRow(
			laneCanvas,
			string.format(
				"%.3f ms  |  %d resumes  |  %s alloc",
				tonumber(thread.totalCpuMs) or 0,
				tonumber(thread.resumes) or 0,
				memoryText(thread.allocatedBytes)
			),
			UDim2.new(0, contentWidth - 150, 0, y),
			UDim2.fromOffset(150, ROW_H),
			10,
			C.text,
			laneObjects
		)
	end
	laneNames.CanvasSize = UDim2.fromOffset(0, (shown + 2) * ROW_H)
	laneCanvas.CanvasSize = UDim2.fromOffset(contentWidth, (shown + 2) * ROW_H)
	detailCaption.Text = tostring(#rows) .. " active rows"
	statusLabel.Text = string.format(
		"Threads: %d live, %d retired   |   Luau heap %s   |   allocated %.2f MB/s. CPU bars have no scheduling timestamps.",
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
	local contentWidth = math.floor(width * zoom)
	local shown = math.min(#scripts, 100)
	local maxValue = 0.001
	for _, scriptStat in ipairs(scripts) do
		maxValue = math.max(maxValue, tonumber(scriptStat.CpuMs) or 0)
	end
	titlePair("Script", "Cumulative CPU (exclusive)     |     total / resumes / allocations", 0)
	for i = 1, shown do
		local item = scripts[i]
		local y = i * ROW_H
		textRow(
			laneNames,
			item.Name or "Unknown",
			UDim2.fromOffset(10, y),
			UDim2.new(1, -18, 0, ROW_H),
			11,
			C.text,
			nameObjects
		)
		tracked(laneCanvas, {
			Position = UDim2.fromOffset(0, y + 3),
			Size = UDim2.fromOffset(
				math.floor((tonumber(item.CpuMs) or 0) / maxValue * (math.max(40, contentWidth - 220))),
				ROW_H - 6
			),
			BackgroundColor3 = categories[categoryByKey.Scripts].color,
			BorderSizePixel = 0,
		}, laneObjects)
		textRow(
			laneCanvas,
			string.format(
				"%.2f / %.2f ms   |   %d resumes   |   %s",
				tonumber(item.CpuMs) or 0,
				tonumber(item.TotalCpuMs) or 0,
				tonumber(item.Resumes) or 0,
				memoryText(item.AllocatedBytes)
			),
			UDim2.new(0, contentWidth - 216, 0, y),
			UDim2.fromOffset(216, ROW_H),
			10,
			C.text,
			laneObjects
		)
	end
	laneNames.CanvasSize = UDim2.fromOffset(0, (shown + 2) * ROW_H)
	laneCanvas.CanvasSize = UDim2.fromOffset(contentWidth, (shown + 2) * ROW_H)
	detailCaption.Text = tostring(#scripts) .. " scripts"
	statusLabel.Text =
		"Script totals are cumulative for the current Luau VM; they are not per-frame historical script snapshots."
end

drawDetail = function()
	dirtyDetail = false
	for name, control in pairs(tabs) do
		control.BackgroundColor3 = activeTab == name and C.hover or C.strip
		control.TextColor3 = activeTab == name and C.selection or C.dim
	end
	if activeTab == "Timeline" then
		drawTimeline()
	elseif activeTab == "Threads" then
		drawThreads()
	else
		drawScripts()
	end
end

local lastSample = 0
local lastPaint = 0
local lastScriptRefresh = 0
local lastDetailRefresh = 0
local wasVisible = false

local function update()
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
		pauseButton.Text = paused and "Resume" or "Pause"
		liveLabel.Text = paused and "PAUSED" or "LIVE"
		-- FrameCount enables native history collection without enabling the
		-- engine's separate, fullscreen F2 overlay.
		getFrameCount()
		if paused then
			refreshHistorical()
			readSelection()
		end
		dirtyGraph, dirtyDetail = true, true
	end

	if not paused and now - lastSample >= SAMPLE_INTERVAL then
		lastSample = now
		local data = getFrame(1)
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

RunService.RenderStepped:Connect(update)
chart:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	dirtyGraph = true
end)
laneCanvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	dirtyDetail = true
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
		UI.refreshWindow("Profiler")
		dirtyGraph, dirtyDetail = true, true
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

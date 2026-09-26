if not IsPlaytest then
	return
end

local UI = require("@internal/editor_ui")
local StudioThemeService = game:GetService("StudioThemeService")
local theme = StudioThemeService.SelectedTheme
local LogService = game:GetService("LogService")
local RunService = game:GetService("RunService")
local profiler = game:GetService("ProfilerService")
local colors = UI.colors
local tokens = UI.tokens

local ROW_H = 18
local MAX_ROWS = 16
local GRAPH_POINTS = 60

local PANEL_BG = Color3.new(0.055, 0.07, 0.10)
local GRAPH_BG = Color3.new(0.09, 0.11, 0.14)
local ROW_BG = Color3.new(0.13, 0.145, 0.18)
local TEXT = Color3.new(0.82, 0.86, 0.92)
local DIM = Color3.new(0.45, 0.50, 0.58)
local ACCENT = Color3.new(0.337, 0.714, 0.761)

local function colorFromRGB(c)
	return Color3.new(math.floor(c / 65536) / 255, math.floor((c % 65536) / 256) / 255, (c % 256) / 255)
end

local function makeLabel(parent, text, size, color)
	local l = Instance.new("TextLabel")
	l.Parent = parent
	l.Text = text or ""
	l.TextSize = size or 12
	l.TextColor3 = color or TEXT
	l.BackgroundTransparency = 1
	return l
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ProfilerOverlay"
screenGui.RenderOnTop = true
screenGui.IgnoreGuiInset = true
screenGui.Enabled = true

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Parent = screenGui
panel.Position = UDim2.new(0, 0, 0, 0)
panel.Size = UDim2.new(1, 0, 1, 0)
panel.BackgroundColor3 = PANEL_BG
panel.BackgroundTransparency = 0.06
panel.ZIndex = 1

local headerBg = Instance.new("Frame")
headerBg.Parent = panel
headerBg.Position = UDim2.new(0, 0, 0, 0)
headerBg.Size = UDim2.new(1, 0, 0, 34)
headerBg.BackgroundColor3 = Color3.new(0.02, 0.025, 0.04)
headerBg.ZIndex = 2

local title = makeLabel(headerBg, "PROFILER", 15, ACCENT)
title.Position = UDim2.new(0, 12, 0, 7)
title.Size = UDim2.new(0, 120, 0, 20)
title.ZIndex = 3

local header = makeLabel(headerBg, "FPS --", 13, TEXT)
header.Position = UDim2.new(0, 140, 0, 8)
header.Size = UDim2.new(0, 260, 0, 20)
header.ZIndex = 3

local pauseBtn = Instance.new("TextButton")
pauseBtn.Name = "PauseButton"
pauseBtn.Parent = headerBg
pauseBtn.Position = UDim2.new(1, -110, 0, 5)
pauseBtn.Size = UDim2.new(0, 100, 0, 24)
pauseBtn.BackgroundColor3 = ACCENT
pauseBtn.BackgroundTransparency = 0.15
pauseBtn.Text = "Pause"
pauseBtn.TextSize = 13
pauseBtn.TextColor3 = Color3.new(1, 1, 1)
pauseBtn.ZIndex = 3

local nav = Instance.new("Frame")
nav.Parent = headerBg
nav.Position = UDim2.new(1, -360, 0, 5)
nav.Size = UDim2.new(0, 240, 0, 24)
nav.BackgroundTransparency = 1
nav.ZIndex = 3
nav.Visible = profiler.Paused

local frameLabel = makeLabel(nav, "frame --/--", 13, TEXT)
frameLabel.Position = UDim2.new(0, 0, 0, 2)
frameLabel.Size = UDim2.new(0, 160, 0, 20)
frameLabel.ZIndex = 4

local prevBtn = Instance.new("TextButton")
prevBtn.Parent = nav
prevBtn.Position = UDim2.new(0, 165, 0, 0)
prevBtn.Size = UDim2.new(0, 34, 0, 22)
prevBtn.BackgroundColor3 = Color3.new(0.2, 0.25, 0.32)
prevBtn.Text = "<"
prevBtn.TextSize = 14
prevBtn.TextColor3 = TEXT
prevBtn.ZIndex = 4

local nextBtn = Instance.new("TextButton")
nextBtn.Parent = nav
nextBtn.Position = UDim2.new(0, 204, 0, 0)
nextBtn.Size = UDim2.new(0, 34, 0, 22)
nextBtn.BackgroundColor3 = Color3.new(0.2, 0.25, 0.32)
nextBtn.Text = ">"
nextBtn.TextSize = 14
nextBtn.TextColor3 = TEXT
nextBtn.ZIndex = 4

local BODY_Y = 44
local GRAPH_H = 92

local graph = Instance.new("Frame")
graph.Name = "FrameGraph"
graph.Parent = panel
graph.Position = UDim2.new(0, 12, 0, BODY_Y)
graph.Size = UDim2.new(1, -24, 0, GRAPH_H)
graph.BackgroundColor3 = GRAPH_BG
graph.BackgroundTransparency = 0.25
graph.ZIndex = 2

local graphTitle = makeLabel(graph, "frame time (ms)", 11, DIM)
graphTitle.Position = UDim2.new(0, 8, 0, 4)
graphTitle.Size = UDim2.new(0, 180, 0, 16)
graphTitle.ZIndex = 3

local graphBars = {}
local barWidth = math.max(math.floor((1280 - 24) / GRAPH_POINTS), 1)
for i = 1, GRAPH_POINTS do
	local bar = Instance.new("Frame")
	bar.Parent = graph
	bar.Name = "Bar"
	bar.Size = UDim2.new(0, barWidth - 1, 0, 0)
	bar.ZIndex = 3
	graphBars[i] = bar
end

local rowArea = Instance.new("Frame")
rowArea.Parent = panel
rowArea.Position = UDim2.new(0, 12, 0, BODY_Y + GRAPH_H + 8)
rowArea.Size = UDim2.new(1, -340, 1, -(BODY_Y + GRAPH_H + 20))
rowArea.BackgroundColor3 = GRAPH_BG
rowArea.BackgroundTransparency = 0.25
rowArea.ZIndex = 2

local rowTitle = makeLabel(rowArea, "zones", 11, DIM)
rowTitle.Position = UDim2.new(0, 8, 0, 4)
rowTitle.Size = UDim2.new(0, 120, 0, 16)
rowTitle.ZIndex = 3

local statsPanel = Instance.new("Frame")
statsPanel.Name = "StatsPanel"
statsPanel.Parent = panel
statsPanel.Position = UDim2.new(1, -316, 0, BODY_Y + GRAPH_H + 8)
statsPanel.Size = UDim2.new(0, 296, 1, -(BODY_Y + GRAPH_H + 20))
statsPanel.BackgroundColor3 = GRAPH_BG
statsPanel.BackgroundTransparency = 0.25
statsPanel.ZIndex = 2

local statLabels = {}
local function addStat(name)
	local cap = makeLabel(statsPanel, name, 11, DIM)
	cap.Position = UDim2.new(0, 10, 0, 8 + #statLabels * 22)
	cap.Size = UDim2.new(0, 140, 0, 16)
	cap.ZIndex = 3
	local val = makeLabel(statsPanel, "--", 12, TEXT)
	val.Position = UDim2.new(0, 150, 0, 8 + #statLabels * 22)
	val.Size = UDim2.new(0, 136, 0, 16)
	val.ZIndex = 3
	statLabels[#statLabels + 1] = { cap = cap, val = val }
	return val
end

local statFrame = addStat("frame")
local statNumZones = addStat("zones")
local statLast = addStat("last")
local statMin = addStat("min")
local statMax = addStat("max")
local statAvg = addStat("avg")

local rowObjs = {}
for i = 1, MAX_ROWS do
	local row = Instance.new("Frame")
	row.Parent = rowArea
	row.Position = UDim2.new(0, 8, 0, 26 + (i - 1) * ROW_H)
	row.Size = UDim2.new(1, -16, 0, ROW_H - 2)
	row.BackgroundColor3 = ROW_BG
	row.BackgroundTransparency = 0.2
	row.ZIndex = 3

	local bar = Instance.new("Frame")
	bar.Parent = row
	bar.Size = UDim2.new(0, 0, 1, 0)
	bar.BackgroundColor3 = Color3.new(0.3, 0.6, 0.3)
	bar.BackgroundTransparency = 0.1
	bar.ZIndex = 4

	local name = makeLabel(row, "", 12, TEXT)
	name.Position = UDim2.new(0, 6, 0, 0)
	name.Size = UDim2.new(1, -110, 1, 0)
	name.TextXAlignment = "Left"
	name.ZIndex = 4

	local time = makeLabel(row, "", 12, DIM)
	time.Position = UDim2.new(1, -76, 0, 0)
	time.Size = UDim2.new(0, 70, 1, 0)
	time.TextXAlignment = "Right"
	time.ZIndex = 4

	rowObjs[i] = { bar = bar, name = name, time = time }
end

local selected = 1

local function pauseSet(on)
	if on then
		profiler:Pause()
	else
		profiler:Resume()
	end
	nav.Visible = on
	pauseBtn.Text = on and "Resume" or "Pause"
end

pauseBtn.MouseButton1Click:Connect(function()
	pauseSet(not profiler.Paused)
end)

prevBtn.MouseButton1Click:Connect(function()
	if selected < profiler.FrameCount then
		selected = selected + 1
	end
end)

nextBtn.MouseButton1Click:Connect(function()
	if selected > 1 then
		selected = selected - 1
	end
end)

local function update()
	local stats = profiler:GetFrameStats()

	screenGui.Enabled = stats.enabled

	local paused = profiler.Paused
	pauseBtn.Text = paused and "Resume" or "Pause"
	nav.Visible = paused

	local frameMs = stats.frameMs
	local fps = stats.fps
	local zones = stats.zones

	if paused then
		local count = profiler.FrameCount
		if selected < 1 then
			selected = 1
		end
		if selected > math.max(count, 1) then
			selected = math.max(count, 1)
		end

		local rec = profiler:GetFrameRecord(selected)
		if rec then
			frameMs = rec.frameMs
			fps = rec.fps
			zones = rec.zones
		end
		frameLabel.Text = string.format("frame %d/%d", selected, count)
	else
		selected = 1
		frameLabel.Text = "frame --/--"
	end

	-- Header / fps line.
	if frameMs > 0 then
		header.Text = string.format("FPS %.1f   frame %.3f ms", fps, frameMs)
		statFrame.Text = string.format("%d ms / %.1f fps", frameMs, fps)
	else
		header.Text = "FPS --   frame --"
		statFrame.Text = "--"
	end

	local zoneCount = 0
	if zones then
		for _ in ipairs(zones) do
			zoneCount = zoneCount + 1
		end
	end
	statNumZones.Text = tostring(zoneCount)

	-- Graph of frame times.
	local graphMax = 1
	for _, ms in ipairs(stats.history) do
		if ms > graphMax then
			graphMax = ms
		end
	end
	barWidth = math.max(math.floor((graph.AbsoluteSize.X - 16) / GRAPH_POINTS), 1)
	for i = 1, GRAPH_POINTS do
		local ms = stats.history[i]
		local h = 0
		if ms and ms > 0 then
			h = math.floor(math.min(ms / graphMax, 1) * (GRAPH_H - 28))
			if h < 1 then
				h = 1
			end
		end
		graphBars[i].Position = UDim2.new(0, 8 + (i - 1) * barWidth, 0, 24)
		graphBars[i].AnchorPoint = Vector2.new(0, 1)
		graphBars[i].BackgroundColor3 = ACCENT
		graphBars[i].Size = UDim2.new(0, math.max(barWidth - 1, 1), 0, h)
	end

	-- Min/max/avg of the history window.
	if stats.history and #stats.history > 0 then
		local mn, mx, sum, n = math.huge, 0, 0, 0
		for _, ms in ipairs(stats.history) do
			if ms > 0 then
				if ms < mn then
					mn = ms
				end
				if ms > mx then
					mx = ms
				end
				sum = sum + ms
				n = n + 1
			end
		end
		if n > 0 then
			statMin.Text = string.format("%.3f ms", mn)
			statMax.Text = string.format("%.3f ms", mx)
			statAvg.Text = string.format("%.3f ms", sum / n)
			statLast.Text = string.format("%.3f ms", stats.history[1])
		else
			statMin.Text = "--"
			statMax.Text = "--"
			statAvg.Text = "--"
			statLast.Text = "--"
		end
	end

	-- Zones sorted by time, rendered as bars.
	table.sort(zones or {}, function(a, b)
		return a.ms > b.ms
	end)

	for i = 1, MAX_ROWS do
		local row = rowObjs[i]
		local zone = zones and zones[i]
		if zone then
			row.name.Text = zone.name
			row.time.Text = string.format("%.3f ms", zone.ms)
			row.bar.Size = UDim2.new(0, math.floor(math.min(zone.ms / math.max(frameMs, 0.001), 1) * 280), 1, 0)
			row.bar.BackgroundColor3 = colorFromRGB(zone.color)
			row.Visible = true
		else
			row.name.Text = ""
			row.time.Text = ""
			row.bar.Size = UDim2.new(0, 0, 1, 0)
			row.Visible = false
		end
	end
end

while true do
	task.wait()
	update()
end

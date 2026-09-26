if not IsPlaytest then
	return
end

local StudioThemeService = game:GetService("StudioThemeService")
local RunService = game:GetService("RunService")
local theme = StudioThemeService.SelectedTheme

local profiler = game:GetService("ProfilerService")

-- Try to pull colors from the editor theme; fall back to the same palette
-- used by the in-game profiler overlay if the theme API doesn't match.
local function themeColor(styleGuideColor, fallback)
	local ok, col = pcall(function()
		return theme:GetColor(styleGuideColor)
	end)
	if ok and typeof(col) == "Color3" then
		return col
	end
	return fallback
end

local BG = themeColor(Enum.StudioStyleGuideColor.MainBackground, Color3.new(0.055, 0.07, 0.10))
local BG_ALT = themeColor(Enum.StudioStyleGuideColor.Tab, Color3.new(0.09, 0.11, 0.14))
local ROW_BG = themeColor(Enum.StudioStyleGuideColor.Item, Color3.new(0.13, 0.145, 0.18))
local TEXT = themeColor(Enum.StudioStyleGuideColor.MainText, Color3.new(0.82, 0.86, 0.92))
local DIM = themeColor(Enum.StudioStyleGuideColor.SubText, Color3.new(0.45, 0.50, 0.58))

local ACCENT = Color3.new(0.337, 0.714, 0.761)
local GOOD = Color3.new(0.35, 0.75, 0.45)
local WARN = Color3.new(0.85, 0.70, 0.25)
local BAD = Color3.new(0.85, 0.35, 0.35)

local GRAPH_POINTS = 40
local MAX_ROWS = 8
local ROW_H = 15
local TOPBAR_W = 300
local TOPBAR_H = 26
local EXPANDED_H = 230

local function colorFromRGB(c)
	return Color3.new(math.floor(c / 65536) / 255, math.floor((c % 65536) / 256) / 255, (c % 256) / 255)
end

local function fpsColor(fps)
	if fps >= 50 then
		return GOOD
	elseif fps >= 30 then
		return WARN
	end
	return BAD
end

local function makeLabel(parent, text, size, color, bold)
	local l = Instance.new("TextLabel")
	l.Parent = parent
	l.Text = text or ""
	l.TextSize = size or 12
	l.TextColor3 = color or TEXT
	l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
	l.BackgroundTransparency = 1
	l.TextXAlignment = Enum.TextXAlignment.Left
	return l
end

-- Root GUI ------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "ProfilerTopbar"
gui.IgnoreGuiInset = true
gui.Enabled = true
gui.Parent = game:GetService("StarterGui")

local root = Instance.new("Frame")
root.Name = "Root"
root.AnchorPoint = Vector2.new(0.5, 0)
root.Position = UDim2.new(0.5, 0, 0, 4)
root.Size = UDim2.new(0, TOPBAR_W, 0, TOPBAR_H)
root.BackgroundTransparency = 1
root.ClipsDescendants = false
root.Parent = gui

-- Topbar (always visible) ----------------------------------------------

local topbar = Instance.new("Frame")
topbar.Name = "Topbar"
topbar.Size = UDim2.new(1, 0, 0, TOPBAR_H)
topbar.BackgroundColor3 = BG
topbar.BackgroundTransparency = 0.08
topbar.Parent = root

local statusDot = Instance.new("Frame")
statusDot.Name = "StatusDot"
statusDot.AnchorPoint = Vector2.new(0, 0.5)
statusDot.Position = UDim2.new(0, 8, 0.5, 0)
statusDot.Size = UDim2.new(0, 8, 0, 8)
statusDot.BackgroundColor3 = GOOD
statusDot.Parent = topbar

local fpsLabel = makeLabel(topbar, "FPS --", 13, TEXT, true)
fpsLabel.Position = UDim2.new(0, 22, 0, 0)
fpsLabel.Size = UDim2.new(0, 64, 1, 0)
fpsLabel.Parent = topbar

local msLabel = makeLabel(topbar, "-- ms", 12, DIM)
msLabel.Position = UDim2.new(0, 88, 0, 0)
msLabel.Size = UDim2.new(0, 90, 1, 0)
msLabel.Parent = topbar

local pauseBtn = Instance.new("TextButton")
pauseBtn.Name = "PauseButton"
pauseBtn.AnchorPoint = Vector2.new(1, 0.5)
pauseBtn.Position = UDim2.new(1, -30, 0.5, 0)
pauseBtn.Size = UDim2.new(0, 44, 0, 18)
pauseBtn.BackgroundColor3 = ACCENT
pauseBtn.BackgroundTransparency = 0.2
pauseBtn.Text = "Pause"
pauseBtn.TextSize = 11
pauseBtn.TextColor3 = Color3.new(1, 1, 1)
pauseBtn.Parent = topbar

local expandBtn = Instance.new("TextButton")
expandBtn.Name = "ExpandButton"
expandBtn.AnchorPoint = Vector2.new(1, 0.5)
expandBtn.Position = UDim2.new(1, -4, 0.5, 0)
expandBtn.Size = UDim2.new(0, 20, 0, 18)
expandBtn.BackgroundTransparency = 1
expandBtn.Text = "v"
expandBtn.TextSize = 13
expandBtn.TextColor3 = TEXT
expandBtn.Parent = topbar

-- Expanded panel (hidden until maximized) ------------------------------

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Position = UDim2.new(0, 0, 0, TOPBAR_H + 2)
panel.Size = UDim2.new(1, 0, 0, EXPANDED_H)
panel.BackgroundColor3 = BG
panel.BackgroundTransparency = 0.08
panel.Visible = false
panel.Parent = root

local graph = Instance.new("Frame")
graph.Name = "Graph"
graph.Position = UDim2.new(0, 6, 0, 6)
graph.Size = UDim2.new(1, -12, 0, 54)
graph.BackgroundColor3 = BG_ALT
graph.BackgroundTransparency = 0.2
graph.Parent = panel

local graphBars = {}
for i = 1, GRAPH_POINTS do
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0, 1)
	bar.BackgroundColor3 = ACCENT
	bar.BorderSizePixel = 0
	bar.Parent = graph
	graphBars[i] = bar
end

local statsRow = Instance.new("Frame")
statsRow.Name = "Stats"
statsRow.Position = UDim2.new(0, 6, 0, 64)
statsRow.Size = UDim2.new(1, -12, 0, 16)
statsRow.BackgroundTransparency = 1
statsRow.Parent = panel

local minLabel = makeLabel(statsRow, "min --", 11, DIM)
minLabel.Position = UDim2.new(0, 0, 0, 0)
minLabel.Size = UDim2.new(0.25, 0, 1, 0)

local maxLabel = makeLabel(statsRow, "max --", 11, DIM)
maxLabel.Position = UDim2.new(0.25, 0, 0, 0)
maxLabel.Size = UDim2.new(0.25, 0, 1, 0)

local avgLabel = makeLabel(statsRow, "avg --", 11, DIM)
avgLabel.Position = UDim2.new(0.5, 0, 0, 0)
avgLabel.Size = UDim2.new(0.25, 0, 1, 0)

local frameNavLabel = makeLabel(statsRow, "", 11, DIM)
frameNavLabel.Position = UDim2.new(0.75, 0, 0, 0)
frameNavLabel.Size = UDim2.new(0.25, 0, 1, 0)
frameNavLabel.TextXAlignment = Enum.TextXAlignment.Right

local navRow = Instance.new("Frame")
navRow.Name = "NavRow"
navRow.Position = UDim2.new(0, 6, 0, 82)
navRow.Size = UDim2.new(1, -12, 0, 18)
navRow.BackgroundTransparency = 1
navRow.Visible = false
navRow.Parent = panel

local prevBtn = Instance.new("TextButton")
prevBtn.Size = UDim2.new(0, 26, 1, 0)
prevBtn.BackgroundColor3 = ROW_BG
prevBtn.Text = "<"
prevBtn.TextColor3 = TEXT
prevBtn.Parent = navRow

local nextBtn = Instance.new("TextButton")
nextBtn.Position = UDim2.new(0, 30, 0, 0)
nextBtn.Size = UDim2.new(0, 26, 1, 0)
nextBtn.BackgroundColor3 = ROW_BG
nextBtn.Text = ">"
nextBtn.TextColor3 = TEXT
nextBtn.Parent = navRow

local zoneHeader = makeLabel(panel, "zones", 11, DIM)
zoneHeader.Position = UDim2.new(0, 6, 0, 104)
zoneHeader.Size = UDim2.new(0, 100, 0, 14)

local rowObjs = {}
for i = 1, MAX_ROWS do
	local row = Instance.new("Frame")
	row.Position = UDim2.new(0, 6, 0, 120 + (i - 1) * ROW_H)
	row.Size = UDim2.new(1, -12, 0, ROW_H - 1)
	row.BackgroundColor3 = ROW_BG
	row.BackgroundTransparency = 0.25
	row.Visible = false
	row.Parent = panel

	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(0, 0, 1, 0)
	bar.BackgroundTransparency = 0.1
	bar.Parent = row

	local name = makeLabel(row, "", 11, TEXT)
	name.Position = UDim2.new(0, 4, 0, 0)
	name.Size = UDim2.new(1, -80, 1, 0)

	local time = makeLabel(row, "", 11, DIM)
	time.Position = UDim2.new(1, -60, 0, 0)
	time.Size = UDim2.new(0, 56, 1, 0)
	time.TextXAlignment = Enum.TextXAlignment.Right

	rowObjs[i] = { root = row, bar = bar, name = name, time = time }
end

-- State / interaction ---------------------------------------------------

local expanded = false
local selectedFrame = 1

local function setExpanded(on)
	expanded = on
	panel.Visible = on
	root.Size = UDim2.new(0, TOPBAR_W, 0, TOPBAR_H + (on and (EXPANDED_H + 2) or 0))
	expandBtn.Text = on and "^" or "v"
	navRow.Visible = on and profiler.Paused
end

local function setPaused(on)
	if on then
		profiler:Pause()
	else
		profiler:Resume()
	end
	pauseBtn.Text = on and "Resume" or "Pause"
	navRow.Visible = on and expanded
end

expandBtn.MouseButton1Click:Connect(function()
	setExpanded(not expanded)
end)

topbar.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		setExpanded(not expanded)
	end
end)

pauseBtn.MouseButton1Click:Connect(function()
	setPaused(not profiler.Paused)
end)

prevBtn.MouseButton1Click:Connect(function()
	-- Previous = older frame = larger index (1 = newest).
	if selectedFrame < profiler.FrameCount then
		selectedFrame = selectedFrame + 1
	end
end)

nextBtn.MouseButton1Click:Connect(function()
	if selectedFrame > 1 then
		selectedFrame = selectedFrame - 1
	end
end)

-- Update loop -------------------------------------------------------------

local function update()
	gui.Enabled = profiler.Enabled
	if not gui.Enabled then
		return
	end

	local paused = profiler.Paused
	pauseBtn.Text = paused and "Resume" or "Pause"
	navRow.Visible = paused and expanded

	local stats = profiler:GetFrameStats()
	local frameMs, fps, zones, history = stats.frameMs, stats.fps, stats.zones, stats.history

	if paused then
		local count = profiler.FrameCount
		selectedFrame = math.clamp(selectedFrame, 1, math.max(count, 1))
		local rec = profiler:GetFrameRecord(selectedFrame)
		if rec then
			frameMs, fps, zones = rec.frameMs, rec.fps, rec.zones
		end
		frameNavLabel.Text = string.format("#%d/%d", selectedFrame, count)
	else
		selectedFrame = 1
		frameNavLabel.Text = ""
	end

	if frameMs and frameMs > 0 then
		fpsLabel.Text = string.format("FPS %d", math.floor(fps + 0.5))
		fpsLabel.TextColor3 = fpsColor(fps)
		msLabel.Text = string.format("%.2f ms", frameMs)
		statusDot.BackgroundColor3 = fpsColor(fps)
	else
		fpsLabel.Text = "FPS --"
		msLabel.Text = "-- ms"
	end

	if not expanded then
		return
	end

	-- Frame time graph.
	local graphMax = 1
	if history then
		for _, ms in ipairs(history) do
			if ms > graphMax then
				graphMax = ms
			end
		end
	end
	local graphW = math.max(graph.AbsoluteSize.X - 4, GRAPH_POINTS)
	local barW = math.max(math.floor(graphW / GRAPH_POINTS), 1)
	for i = 1, GRAPH_POINTS do
		local ms = history and history[i]
		local h = 0
		if ms and ms > 0 then
			h = math.max(math.floor(math.min(ms / graphMax, 1) * 46), 1)
		end
		local bar = graphBars[i]
		bar.Position = UDim2.new(0, 2 + (i - 1) * barW, 1, -2)
		bar.Size = UDim2.new(0, math.max(barW - 1, 1), 0, h)
	end

	-- Min / max / avg over the visible history window.
	if history and #history > 0 then
		local mn, mx, sum, n = math.huge, 0, 0, 0
		for _, ms in ipairs(history) do
			if ms > 0 then
				mn = math.min(mn, ms)
				mx = math.max(mx, ms)
				sum += ms
				n += 1
			end
		end
		if n > 0 then
			minLabel.Text = string.format("min %.2f", mn)
			maxLabel.Text = string.format("max %.2f", mx)
			avgLabel.Text = string.format("avg %.2f", sum / n)
		end
	end

	-- Zones, sorted by time descending.
	if zones then
		table.sort(zones, function(a, b)
			return a.ms > b.ms
		end)
	end

	for i = 1, MAX_ROWS do
		local row = rowObjs[i]
		local zone = zones and zones[i]
		if zone then
			row.name.Text = zone.name
			row.time.Text = string.format("%.2f ms", zone.ms)
			row.bar.Size =
				UDim2.new(0, math.floor(math.min(zone.ms / math.max(frameMs, 0.001), 1) * (TOPBAR_W - 20)), 1, 0)
			row.bar.BackgroundColor3 = colorFromRGB(zone.color)
			row.root.Visible = true
		else
			row.root.Visible = false
		end
	end
end

RunService.Heartbeat:Connect(update)

local RunService = game:GetService("RunService")
local ProfilerService = game:GetService("ProfilerService")
local UI = require("@internal/editor_ui")

local colors = UI.tokens.color

local ROW = 20
local TICK = 0.1 -- refresh interval (seconds)
local GRAPH_FRAMES = 240 -- frames shown in the graphs
local FLAME_ROW = 18
local MAX_BOXES = 600
local ZONE_W = 380

------------------------------------------------------------------ formatting

local function fmtMs(v)
	return string.format("%.3f ms", v or 0)
end

local function fmtNum(v)
	return string.format("%.3f", v or 0)
end

local function fmtInt(v)
	return string.format("%d", math.floor((v or 0) + 0.5))
end

local function fmtBytes(b)
	b = b or 0
	local sign = b < 0 and "-" or ""
	b = math.abs(b)

	if b < 1024 then
		return sign .. string.format("%d B", b)
	elseif b < 1024 * 1024 then
		return sign .. string.format("%.1f KB", b / 1024)
	end

	return sign .. string.format("%.2f MB", b / (1024 * 1024))
end

local function colorFromRGB(c)
	if not c or c == 0 then
		return colors.accent
	end

	return Color3.new(math.floor(c / 65536) / 255, math.floor((c % 65536) / 256) / 255, (c % 256) / 255)
end

------------------------------------------------------------------ pooled list

-- Scrollable list with fixed columns. Rows are created once and reused.
-- columns: { header, x, w, align }  (x / w are fractions of the list width)
local function createList(parent, position, size, title, columns, onSelect, topExtra)
	topExtra = topExtra or 0

	local container = UI.card(parent, position, size, { color = colors.panel })

	local titleLabel =
		UI.label(container, title, UDim2.fromOffset(10, 4), UDim2.new(1, -20, 0, 18), UI.tokens.type.body, colors.text)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left

	local headerY = 24 + topExtra

	for _, col in ipairs(columns) do
		local h = UI.label(
			container,
			col.header,
			UDim2.new(col.x, 12, 0, headerY),
			UDim2.new(col.w, -12, 0, 16),
			UI.tokens.type.caption,
			colors.muted
		)
		h.TextXAlignment = col.align or Enum.TextXAlignment.Left
	end

	local scroll = UI.create("ScrollingFrame", {
		Position = UDim2.fromOffset(6, headerY + 18),
		Size = UDim2.new(1, -12, 1, -(headerY + 18 + 6)),
		BackgroundColor3 = colors.input,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(1, 0, 0, 0),
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = colors.subtext,
		ScrollBarImageTransparency = 0.4,
		ScrollBarAutoHide = true,
		ClipsDescendants = true,
	}, container)

	local list = { frame = container, scroll = scroll, rows = {} }

	local function newRow(index)
		local row = { id = nil, labels = {} }

		local button, _, record = UI.button(
			scroll,
			"",
			UDim2.fromOffset(0, (index - 1) * ROW),
			UDim2.new(1, 0, 0, ROW),
			function()
				if onSelect and row.id ~= nil then
					onSelect(row.id)
				end
			end,
			{
				color = colors.rowEven,
				hoverColor = colors.hover,
				pressedColor = colors.pressed,
				radius = 0,
				border = false,
			}
		)

		button.ClipsDescendants = true
		row.button = button
		row.record = record

		for c, col in ipairs(columns) do
			local label = UI.label(
				button,
				"",
				UDim2.new(col.x, 6, 0, 0),
				UDim2.new(col.w, -12, 1, 0),
				UI.tokens.type.small,
				colors.text
			)
			label.TextXAlignment = col.align or Enum.TextXAlignment.Left
			label.TextYAlignment = Enum.TextYAlignment.Center
			row.labels[c] = label
		end

		list.rows[index] = row
		return row
	end

	-- data: array of { id = any, cells = { string... }, selected = bool }
	function list.set(data)
		for i, item in ipairs(data) do
			local row = list.rows[i] or newRow(i)

			row.id = item.id
			row.button.Visible = true

			for c, text in ipairs(item.cells) do
				row.labels[c].Text = text
			end

			local base = item.selected and colors.selection or (i % 2 == 0 and colors.rowEven or colors.rowOdd)

			row.record.color = base
			row.record.defaultColor = base
			row.button.BackgroundColor3 = base
		end

		for i = #data + 1, #list.rows do
			list.rows[i].button.Visible = false
			list.rows[i].id = nil
		end

		scroll.CanvasSize = UDim2.new(1, 0, 0, math.max(#data * ROW, 1))
	end

	return list
end

------------------------------------------------------------------ zone analysis

-- zones: array of { name, color, ms, startMs } (start relative to the frame's first zone).
-- Returns:
--   items  : every zone instance, sorted by start, with depth / childMs filled in
--   rows   : one aggregate row per zone name { name, color, total, self, calls, max }
--   maxEnd : end of the last zone (ms) = span of the timeline
local function analyzeZones(zones)
	local items = {}

	for i, z in ipairs(zones) do
		items[i] = {
			name = z.name,
			color = z.color,
			start = z.startMs or 0,
			ms = z.ms,
			idx = i,
			childMs = 0,
			depth = 0,
		}
	end

	-- Zones are recorded when they END, so children come before parents. Sort by
	-- start asc / duration desc / record index desc so parents precede children.
	table.sort(items, function(a, b)
		if a.start ~= b.start then
			return a.start < b.start
		end

		if a.ms ~= b.ms then
			return a.ms > b.ms
		end

		return a.idx > b.idx
	end)

	local stack = {}
	local maxEnd = 0

	for _, it in ipairs(items) do
		while #stack > 0 do
			local top = stack[#stack]

			if top.start + top.ms <= it.start + 1e-9 then
				stack[#stack] = nil
			else
				break
			end
		end

		it.depth = #stack

		local parent = stack[#stack]

		if parent then
			parent.childMs += it.ms
		end

		stack[#stack + 1] = it
		maxEnd = math.max(maxEnd, it.start + it.ms)
	end

	local byName = {}
	local rows = {}

	for _, it in ipairs(items) do
		local row = byName[it.name]

		if not row then
			row = { name = it.name, color = it.color, total = 0, self = 0, calls = 0, max = 0 }
			byName[it.name] = row
			rows[#rows + 1] = row
		end

		row.total += it.ms
		row.self += math.max(it.ms - it.childMs, 0)
		row.calls += 1
		row.max = math.max(row.max, it.ms)
	end

	return items, rows, maxEnd
end

------------------------------------------------------------------ main

return function(content)
	local view = "scripts"
	local accumulator = TICK

	local selectedScript = nil
	local scriptSort = "CpuMs"

	local selectedZone = nil
	local zoneSort = "self"
	local selectedFrame = 1 -- 1 = newest (matches GetFrameRecord)
	local lastCount = 0
	local viewLo, viewHi = 0, 1
	local current = { items = {}, maxEnd = 0 }

	local setView

	-- Top bar -----------------------------------------------------------------
	local top =
		UI.frame(content, UDim2.fromOffset(8, 6), UDim2.new(1, -16, 0, 30), colors.panelRaised, UI.tokens.radius.sm)

	local viewRecords = {}

	local _, _, scriptsTab = UI.button(top, "Scripts", UDim2.fromOffset(4, 3), UDim2.fromOffset(70, 24), function()
		setView("scripts")
	end, { color = colors.input })
	viewRecords.scripts = scriptsTab

	local _, _, engineTab = UI.button(top, "Engine", UDim2.fromOffset(78, 3), UDim2.fromOffset(70, 24), function()
		setView("engine")
	end, { color = colors.input })
	viewRecords.engine = engineTab

	local _, pauseLabel = UI.button(top, "Pause", UDim2.fromOffset(156, 3), UDim2.fromOffset(84, 24), function()
		if ProfilerService.Paused then
			ProfilerService:Resume()
		else
			ProfilerService:Pause()
		end
	end, { color = colors.input })

	local _, trackLabel, trackRecord = UI.button(
		top,
		"Tracking",
		UDim2.fromOffset(246, 3),
		UDim2.fromOffset(120, 24),
		function()
			ProfilerService:SetTrackingEnabled(not ProfilerService.TrackingEnabled)
		end,
		{ color = colors.input }
	)

	local statsLabel =
		UI.label(top, "", UDim2.fromOffset(378, 5), UDim2.new(1, -386, 0, 20), UI.tokens.type.small, colors.subtext)
	statsLabel.TextXAlignment = Enum.TextXAlignment.Left

	local BODY_Y = 44

	local function newView()
		local frame = UI.frame(content, UDim2.fromOffset(0, BODY_Y), UDim2.new(1, 0, 1, -BODY_Y), colors.panel)
		frame.BackgroundTransparency = 1
		return frame
	end

	local scriptsView = newView()
	local engineView = newView()
	engineView.Visible = false

	------------------------------------------------------------------ SCRIPTS VIEW

	local LEFT_W = 340

	local scriptList = createList(scriptsView, UDim2.fromOffset(8, 0), UDim2.new(0, LEFT_W, 1, -8), "Scripts", {
		{ header = "Name", x = 0, w = 0.46 },
		{ header = "CPU", x = 0.46, w = 0.2, align = Enum.TextXAlignment.Right },
		{ header = "Live", x = 0.66, w = 0.2, align = Enum.TextXAlignment.Right },
		{ header = "Thr", x = 0.86, w = 0.14, align = Enum.TextXAlignment.Right },
	}, function(name)
		selectedScript = (selectedScript == name) and nil or name
		accumulator = TICK
	end, 26)

	local scriptSortRecords = {}

	for i, option in ipairs({
		{ "CPU", "CpuMs" },
		{ "Total", "TotalCpuMs" },
		{ "Alloc", "AllocatedBytes" },
		{ "Live", "LiveBytes" },
		{ "Calls", "Resumes" },
	}) do
		local _, _, record = UI.button(
			scriptList.frame,
			option[1],
			UDim2.fromOffset(6 + (i - 1) * 66, 24),
			UDim2.fromOffset(62, 22),
			function()
				scriptSort = option[2]
				accumulator = TICK
			end,
			{ color = colors.input, paddingX = 2 }
		)
		scriptSortRecords[option[2]] = record
	end

	local sRight =
		UI.frame(scriptsView, UDim2.fromOffset(LEFT_W + 16, 0), UDim2.new(1, -(LEFT_W + 24), 1, -8), colors.panel)
	sRight.BackgroundTransparency = 1

	local _, scriptGraph = UI.graph(sRight, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 180), {
		title = "Frame time",
		yLabel = "ms",
		legend = false,
		color = colors.panel,
	})
	scriptGraph:SetSeries({ { name = "Frame", values = {}, color = colors.accent } })

	local details = UI.card(sRight, UDim2.fromOffset(0, 188), UDim2.new(1, 0, 0, 100), { color = colors.panel })

	local detailsTitle = UI.label(
		details,
		"Select a script",
		UDim2.fromOffset(10, 4),
		UDim2.new(1, -20, 0, 18),
		UI.tokens.type.body,
		colors.text
	)
	detailsTitle.TextXAlignment = Enum.TextXAlignment.Left

	local statDefs = {
		{ "Frame CPU", "CpuMs", fmtMs },
		{ "Total CPU", "TotalCpuMs", fmtMs },
		{ "Resumes", "Resumes", fmtInt },
		{ "Threads", "Threads", fmtInt },
		{ "Allocated", "AllocatedBytes", fmtBytes },
		{ "Freed", "FreedBytes", fmtBytes },
		{ "Live", "LiveBytes", fmtBytes },
		{ "Alive threads", "AliveThreads", fmtInt },
	}
	local statValues = {}

	for i, def in ipairs(statDefs) do
		local col = (i - 1) % 4
		local row = math.floor((i - 1) / 4)
		local y = 28 + row * 34

		local cap = UI.label(
			details,
			def[1],
			UDim2.new(col * 0.25, 12, 0, y),
			UDim2.new(0.25, -12, 0, 14),
			UI.tokens.type.caption,
			colors.muted
		)
		cap.TextXAlignment = Enum.TextXAlignment.Left

		local val = UI.label(
			details,
			"--",
			UDim2.new(col * 0.25, 12, 0, y + 14),
			UDim2.new(0.25, -12, 0, 16),
			UI.tokens.type.body,
			colors.text
		)
		val.TextXAlignment = Enum.TextXAlignment.Left
		statValues[i] = val
	end

	local threadList = createList(sRight, UDim2.fromOffset(0, 296), UDim2.new(1, 0, 1, -296), "Threads", {
		{ header = "Id", x = 0, w = 0.06 },
		{ header = "Name", x = 0.06, w = 0.44 },
		{ header = "Status", x = 0.5, w = 0.14 },
		{ header = "CPU", x = 0.64, w = 0.12, align = Enum.TextXAlignment.Right },
		{ header = "Resumes", x = 0.76, w = 0.12, align = Enum.TextXAlignment.Right },
		{ header = "Live", x = 0.88, w = 0.12, align = Enum.TextXAlignment.Right },
	})

	------------------------------------------------------------------ ENGINE VIEW

	local eLeft = UI.frame(engineView, UDim2.fromOffset(8, 0), UDim2.new(1, -(ZONE_W + 24), 1, -8), colors.panel)
	eLeft.BackgroundTransparency = 1

	-- frame navigation (slider only while paused)
	local navLabel =
		UI.label(eLeft, "", UDim2.fromOffset(0, 4), UDim2.fromOffset(230, 18), UI.tokens.type.small, colors.text)
	navLabel.TextXAlignment = Enum.TextXAlignment.Left

	local navFrame = UI.frame(eLeft, UDim2.fromOffset(236, 0), UDim2.new(1, -236, 0, 26), colors.panel)
	navFrame.BackgroundTransparency = 1

	UI.button(navFrame, "<", UDim2.fromOffset(0, 1), UDim2.fromOffset(28, 24), function()
		selectedFrame = math.min(selectedFrame + 1, math.max(lastCount, 1)) -- older
		accumulator = TICK
	end, { color = colors.input })

	local _, frameSlider = UI.slider(navFrame, UDim2.fromOffset(34, 1), UDim2.new(1, -72, 0, 24), 1, 2, 2, function(v)
		selectedFrame = math.clamp(lastCount - math.floor(v + 0.5) + 1, 1, math.max(lastCount, 1))
		accumulator = TICK
	end, { step = 1 })

	UI.button(navFrame, ">", UDim2.new(1, -30, 0, 1), UDim2.fromOffset(28, 24), function()
		selectedFrame = math.max(selectedFrame - 1, 1) -- newer
		accumulator = TICK
	end, { color = colors.input })

	-- frame time + selected zone history
	local _, engineGraph = UI.graph(eLeft, UDim2.fromOffset(0, 30), UDim2.new(1, 0, 0, 130), {
		title = "Frame time (ms)",
		yLabel = "ms",
		legend = "top-right",
		color = colors.panel,
	})
	engineGraph:SetSeries({
		{ name = "Frame", values = {}, color = colors.accent },
		{ name = "Zone", values = {}, color = colors.warning, fill = false },
	})

	-- zoom for the flame chart
	local zoomLabel = UI.label(
		eLeft,
		"Zoom",
		UDim2.fromOffset(0, 165),
		UDim2.fromOffset(40, 18),
		UI.tokens.type.small,
		colors.subtext
	)
	zoomLabel.TextXAlignment = Enum.TextXAlignment.Left

	local flameRelayout

	local _, zoomSlider = UI.rangeSlider(
		eLeft,
		UDim2.fromOffset(44, 162),
		UDim2.new(1, -130, 0, 24),
		0,
		1,
		0,
		1,
		function(lo, hi)
			viewLo, viewHi = lo, hi
			flameRelayout()
		end
	)

	UI.button(eLeft, "Fit", UDim2.new(1, -76, 0, 164), UDim2.fromOffset(70, 20), function()
		zoomSlider:SetValues(0, 1)
	end, { color = colors.input })

	-- flame chart
	local flame =
		UI.frame(eLeft, UDim2.fromOffset(0, 192), UDim2.new(1, 0, 1, -(192 + 26)), colors.input, UI.tokens.radius.xs)
	flame.ClipsDescendants = true
	UI.stroke(flame, colors.border, 1, 0)

	local hoverLabel =
		UI.label(eLeft, "", UDim2.new(0, 0, 1, -22), UDim2.new(1, 0, 0, 20), UI.tokens.type.small, colors.subtext)
	hoverLabel.TextXAlignment = Enum.TextXAlignment.Left

	local function setHover(it)
		if it then
			hoverLabel.Text = string.format(
				"%s   total %s ms   self %s ms   start +%s ms   depth %d",
				it.name,
				fmtNum(it.ms),
				fmtNum(math.max(it.ms - it.childMs, 0)),
				fmtNum(it.start),
				it.depth
			)
		elseif selectedZone then
			hoverLabel.Text = "Selected: " .. selectedZone .. "  (click again to clear)"
		else
			hoverLabel.Text = "Click a zone to graph it over time"
		end
	end

	setHover(nil)

	local boxes = {}

	local function newBox(index)
		local box = {}

		local button = UI.create("TextButton", {
			Text = "",
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Active = true,
			InputSink = true,
			ClipsDescendants = true,
		}, flame)

		local label = UI.label(button, "", UDim2.fromOffset(3, 0), UDim2.new(1, -3, 1, 0), 11, Color3.new(1, 1, 1))
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Center

		box.button = button
		box.label = label

		button.MouseButton1Click:Connect(function()
			if box.zone then
				selectedZone = (selectedZone == box.zone.name) and nil or box.zone.name
				accumulator = TICK
			end
		end)

		button.MouseEnter:Connect(function()
			if box.zone then
				setHover(box.zone)
			end
		end)

		button.MouseLeave:Connect(function()
			setHover(nil)
		end)

		boxes[index] = box
		return box
	end

	flameRelayout = function()
		local size = flame.AbsoluteSize
		local width, height = size.X, size.Y

		if width <= 0 or height <= 0 then
			return
		end

		local span = math.max(current.maxEnd, 1e-6)
		local lo, hi = viewLo, viewHi

		if hi - lo < 0.002 then
			hi = lo + 0.002
		end

		lo, hi = lo * span, hi * span

		local scale = width / (hi - lo)
		local maxRows = math.max(math.floor((height - 4) / FLAME_ROW), 1)
		local used = 0

		for _, it in ipairs(current.items) do
			if it.depth < maxRows and used < MAX_BOXES then
				local x0 = (it.start - lo) * scale
				local x1 = x0 + it.ms * scale

				if x1 >= 0 and x0 <= width and x1 - x0 >= 1 then
					used += 1

					local box = boxes[used] or newBox(used)
					local px = math.max(x0, 0)
					local pw = math.min(x1, width) - px

					box.zone = it
					box.button.Position = UDim2.fromOffset(px, 2 + it.depth * FLAME_ROW)
					box.button.Size = UDim2.fromOffset(math.max(pw, 1), FLAME_ROW - 2)
					box.button.BackgroundColor3 = colorFromRGB(it.color)
					box.button.BackgroundTransparency = (selectedZone and it.name ~= selectedZone) and 0.65 or 0
					box.label.Text = pw > 36 and it.name or ""
					box.button.Visible = true
				end
			end
		end

		for i = used + 1, #boxes do
			boxes[i].button.Visible = false
			boxes[i].zone = nil
		end
	end

	-- zone table (aggregated by name)
	local zoneList = createList(
		engineView,
		UDim2.new(1, -(ZONE_W + 8), 0, 0),
		UDim2.new(0, ZONE_W, 1, -8),
		"Zones (selected frame)",
		{
			{ header = "Name", x = 0, w = 0.34 },
			{ header = "Self ms", x = 0.34, w = 0.17, align = Enum.TextXAlignment.Right },
			{ header = "Total ms", x = 0.51, w = 0.17, align = Enum.TextXAlignment.Right },
			{ header = "Calls", x = 0.68, w = 0.12, align = Enum.TextXAlignment.Right },
			{ header = "Max ms", x = 0.8, w = 0.2, align = Enum.TextXAlignment.Right },
		},
		function(name)
			selectedZone = (selectedZone == name) and nil or name
			accumulator = TICK
		end,
		26
	)

	local zoneSortRecords = {}

	for i, option in ipairs({ { "Self", "self" }, { "Total", "total" }, { "Calls", "calls" }, { "Max", "max" } }) do
		local _, _, record = UI.button(
			zoneList.frame,
			option[1],
			UDim2.fromOffset(6 + (i - 1) * 66, 24),
			UDim2.fromOffset(62, 22),
			function()
				zoneSort = option[2]
				accumulator = TICK
			end,
			{ color = colors.input, paddingX = 2 }
		)
		zoneSortRecords[option[2]] = record
	end

	------------------------------------------------------------------ refresh

	local function refreshTop()
		local threadStats = ProfilerService:GetThreadStats()
		local paused = ProfilerService.Paused

		pauseLabel.Text = paused and "Resume" or "Pause"
		trackLabel.Text = threadStats.trackingEnabled and "Tracking: On" or "Tracking: Off"
		UI.setButtonState(trackRecord, threadStats.trackingEnabled and "selected" or "default")

		if ProfilerService.Enabled then
			statsLabel.Text = string.format(
				"FPS %.1f   frame %.2f ms   heap %s   alloc %s/s   threads %d (+%d dead)%s",
				ProfilerService.FPS,
				ProfilerService.FrameTime,
				fmtBytes(threadStats.heapBytes),
				fmtBytes(threadStats.allocationRateBytesPerSecond),
				threadStats.threads,
				threadStats.deadThreads,
				paused and "   [paused]" or ""
			)
		else
			statsLabel.Text = "Profiler disabled"
		end
	end

	local function refreshScripts()
		for key, record in pairs(scriptSortRecords) do
			UI.setButtonState(record, key == scriptSort and "selected" or "default")
		end

		scriptGraph:SetValues("Frame", ProfilerService:GetFrameTimes(GRAPH_FRAMES))

		local scripts = ProfilerService:GetScripts()

		table.sort(scripts, function(a, b)
			if a[scriptSort] ~= b[scriptSort] then
				return a[scriptSort] > b[scriptSort]
			end

			return a.Name < b.Name
		end)

		local scriptData = {}
		local selectedStat = nil

		for i, s in ipairs(scripts) do
			if s.Name == selectedScript then
				selectedStat = s
			end

			scriptData[i] = {
				id = s.Name,
				selected = s.Name == selectedScript,
				cells = {
					s.Name,
					fmtMs(s.CpuMs),
					fmtBytes(s.LiveBytes),
					string.format("%d/%d", s.AliveThreads, s.Threads),
				},
			}
		end

		scriptList.set(scriptData)

		detailsTitle.Text = selectedScript and selectedScript or "Select a script (showing all threads)"

		for i, def in ipairs(statDefs) do
			statValues[i].Text = selectedStat and def[3](selectedStat[def[2]]) or "--"
		end

		local threads = ProfilerService:GetThreads()

		table.sort(threads, function(a, b)
			return a.CpuMs > b.CpuMs
		end)

		local threadData = {}

		for _, t in ipairs(threads) do
			if not selectedScript or string.find(t.Name, selectedScript, 1, true) then
				table.insert(threadData, {
					id = t.Id,
					cells = {
						fmtInt(t.Id),
						t.Name,
						t.Status,
						fmtMs(t.CpuMs),
						fmtInt(t.Resumes),
						fmtBytes(t.LiveBytes),
					},
				})
			end
		end

		threadList.set(threadData)
	end

	local lastGraphKey = nil
	local lastTitle = nil
	local zoneSeriesShown = false

	local function refreshEngine()
		local count = ProfilerService.FrameCount
		local paused = ProfilerService.Paused

		lastCount = count

		if paused then
			selectedFrame = math.clamp(selectedFrame, 1, math.max(count, 1))
		else
			selectedFrame = 1
		end

		-- the frame being inspected
		local record = nil

		if count > 0 then
			record = ProfilerService:GetFrameRecord(selectedFrame)
		end

		local zones = record and record.zones or {}
		local frameMs = record and record.frameMs or 0

		local items, rows, maxEnd = analyzeZones(zones)

		current = { items = items, maxEnd = maxEnd }

		-- navigation
		navFrame.Visible = paused

		if paused then
			navLabel.Text = string.format("Frame %d / %d   (%.2f ms)", selectedFrame, count, frameMs)
			frameSlider:SetRange(1, math.max(count, 2))
			frameSlider:SetValue(count - selectedFrame + 1, true)
		else
			navLabel.Text = string.format("Live   %.2f ms   (pause to inspect)", frameMs)
		end

		-- graph (skip the redraw when paused and nothing changed)
		local key = tostring(paused) .. ":" .. count .. ":" .. (selectedZone or "")

		if not paused or key ~= lastGraphKey then
			lastGraphKey = key

			engineGraph:SetValues("Frame", ProfilerService:GetFrameTimes(GRAPH_FRAMES))

			if selectedZone then
				engineGraph:SetValues("Zone", ProfilerService:GetZoneHistory(selectedZone, GRAPH_FRAMES))
				zoneSeriesShown = true
			elseif zoneSeriesShown then
				engineGraph:SetValues("Zone", {})
				zoneSeriesShown = false
			end

			local title = selectedZone and ("Frame time vs " .. selectedZone .. " (ms)") or "Frame time (ms)"

			if title ~= lastTitle then
				lastTitle = title
				engineGraph:SetTitle(title)
			end
		end

		-- flame chart
		flameRelayout()

		-- table
		for k, rec in pairs(zoneSortRecords) do
			UI.setButtonState(rec, k == zoneSort and "selected" or "default")
		end

		table.sort(rows, function(a, b)
			if a[zoneSort] ~= b[zoneSort] then
				return a[zoneSort] > b[zoneSort]
			end

			return a.name < b.name
		end)

		local data = {}

		for i, r in ipairs(rows) do
			data[i] = {
				id = r.name,
				selected = r.name == selectedZone,
				cells = { r.name, fmtNum(r.self), fmtNum(r.total), fmtInt(r.calls), fmtNum(r.max) },
			}
		end

		zoneList.set(data)
	end

	setView = function(name)
		view = name
		scriptsView.Visible = name == "scripts"
		engineView.Visible = name == "engine"

		for key, record in pairs(viewRecords) do
			UI.setButtonState(record, key == name and "selected" or "default")
		end

		lastGraphKey = nil
		accumulator = TICK
	end

	setView("scripts")

	local connection = RunService.Heartbeat:Connect(function(dt)
		accumulator += dt

		if accumulator < TICK then
			return
		end

		accumulator = 0

		refreshTop()

		if view == "scripts" then
			refreshScripts()
		else
			refreshEngine()
		end
	end)

	content.Destroying:Connect(function()
		connection:Disconnect()
		scriptGraph:Destroy()
		engineGraph:Destroy()
	end)
end

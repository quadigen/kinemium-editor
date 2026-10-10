local RunService = game:GetService("RunService")
local ProfilerService = game:GetService("ProfilerService")
local UI = require("@internal/editor_ui")

local colors = UI.tokens.color

local ROW = 20
local TICK = 0.1 -- refresh interval (seconds)
local GRAPH_FRAMES = 240 -- frames shown in the frame-time graph
local ZONE_W = 380
local BODY_Y = 44

local HINT = "Wheel: zoom   Drag / right-drag: pan   Double-click: fit   Click a zone to graph it"

------------------------------------------------------------------ formatting

local function fmtNum(v)
	return string.format("%.3f", v or 0)
end

local function fmtInt(v)
	return string.format("%d", math.floor((v or 0) + 0.5))
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

			-- keep the record in sync so hover/leave restores the right colour
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

------------------------------------------------------------------ main

return function(content)
	local accumulator = TICK

	local selectedZone = nil
	local zoneSort = "self"
	local selectedFrame = 1 -- 1 = newest (matches GetFrameRecord)
	local lastCount = 0

	-- Top bar -----------------------------------------------------------------
	local top =
		UI.frame(content, UDim2.fromOffset(8, 6), UDim2.new(1, -16, 0, 30), colors.panelRaised, UI.tokens.radius.sm)

	local _, pauseLabel = UI.button(top, "Pause", UDim2.fromOffset(4, 3), UDim2.fromOffset(84, 24), function()
		if ProfilerService.Paused then
			ProfilerService:Resume()
		else
			ProfilerService:Pause()
		end

		accumulator = TICK
	end, { color = colors.input })

	local statsLabel =
		UI.label(top, "", UDim2.fromOffset(100, 5), UDim2.new(1, -108, 0, 20), UI.tokens.type.small, colors.subtext)
	statsLabel.TextXAlignment = Enum.TextXAlignment.Left

	-- Left column: navigation, graph, flamegraph --------------------------------
	local left =
		UI.frame(content, UDim2.fromOffset(8, BODY_Y), UDim2.new(1, -(ZONE_W + 24), 1, -(BODY_Y + 8)), colors.panel)
	left.BackgroundTransparency = 1

	local navLabel =
		UI.label(left, "", UDim2.fromOffset(0, 4), UDim2.fromOffset(230, 18), UI.tokens.type.small, colors.text)
	navLabel.TextXAlignment = Enum.TextXAlignment.Left

	local jumpToSlowest

	UI.button(left, "Slowest", UDim2.fromOffset(236, 2), UDim2.fromOffset(80, 22), function()
		jumpToSlowest()
	end, { color = colors.input })

	-- frame scrubber (visible while paused)
	local navFrame = UI.frame(left, UDim2.fromOffset(324, 0), UDim2.new(1, -324, 0, 26), colors.panel)
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
	local _, graph = UI.graph(left, UDim2.fromOffset(0, 30), UDim2.new(1, 0, 0, 130), {
		title = "Frame time (ms)",
		yLabel = "ms",
		legend = "top-right",
		color = colors.panel,
	})

	graph:SetSeries({
		{ name = "Frame", values = {}, color = colors.accent },
		{ name = "Zone", values = {}, color = colors.warning, fill = false },
	})

	local hoverLabel =
		UI.label(left, HINT, UDim2.new(0, 0, 1, -22), UDim2.new(1, 0, 0, 20), UI.tokens.type.small, colors.subtext)
	hoverLabel.TextXAlignment = Enum.TextXAlignment.Left

	local accumulatorReset = function()
		accumulator = TICK
	end

	local flame

	local function describeIdle()
		if selectedZone then
			hoverLabel.Text = "Selected: " .. selectedZone .. "   (click again to clear)"
		else
			hoverLabel.Text = HINT
		end
	end

	local _, flameController = UI.flamegraph(left, UDim2.fromOffset(0, 164), UDim2.new(1, 0, 1, -(164 + 26)), {
		onSelect = function(name)
			selectedZone = name
			accumulatorReset()
		end,
		onHover = function(item)
			if item then
				hoverLabel.Text = string.format(
					"%s   total %s ms   self %s ms   start +%s ms   depth %d",
					item.name,
					fmtNum(item.ms),
					fmtNum(item.self),
					fmtNum(item.start),
					item.depth
				)
			else
				describeIdle()
			end
		end,
	})

	flame = flameController

	-- Right column: zone table --------------------------------------------------
	local zoneList = createList(
		content,
		UDim2.new(1, -(ZONE_W + 8), 0, BODY_Y),
		UDim2.new(0, ZONE_W, 1, -(BODY_Y + 8)),
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
			flame:SetSelected(selectedZone, true)
			describeIdle()
			accumulator = TICK
		end,
		26
	)

	local sortRecords = {}

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
		sortRecords[option[2]] = record
	end

	-- Slowest frame -------------------------------------------------------------
	jumpToSlowest = function()
		-- pause first so the history stops moving, then look for the worst frame
		if not ProfilerService.Paused then
			ProfilerService:Pause()
		end

		local times = ProfilerService:GetFrameTimes(GRAPH_FRAMES)
		local n = #times

		if n == 0 then
			return
		end

		local best, bestMs = 1, -1

		for i, ms in ipairs(times) do
			if ms > bestMs then
				best, bestMs = i, ms
			end
		end

		-- times are oldest -> newest; selectedFrame counts from the newest
		selectedFrame = n - best + 1
		accumulator = TICK
	end

	-- Refresh -------------------------------------------------------------------
	local lastGraphKey = nil
	local lastTitle = nil
	local zoneSeriesShown = false

	local function refresh()
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

		local rows = flame:SetData(zones)

		-- top bar
		pauseLabel.Text = paused and "Resume" or "Pause"

		if ProfilerService.Enabled then
			statsLabel.Text = string.format(
				"FPS %.1f   frame %.2f ms   %d frames captured%s",
				ProfilerService.FPS,
				ProfilerService.FrameTime,
				count,
				paused and "   [paused]" or ""
			)
		else
			statsLabel.Text = "Profiler disabled"
		end

		-- navigation
		navFrame.Visible = paused

		if paused then
			navLabel.Text = string.format("Frame %d / %d   (%.2f ms)", selectedFrame, count, frameMs)
			frameSlider:SetRange(1, math.max(count, 2))
			frameSlider:SetValue(count - selectedFrame + 1, true)
		else
			navLabel.Text = string.format("Live   %.2f ms", frameMs)
		end

		-- graph (skip the redraw when paused and nothing changed)
		local key = tostring(paused) .. ":" .. count .. ":" .. (selectedZone or "")

		if not paused or key ~= lastGraphKey then
			lastGraphKey = key

			graph:SetValues("Frame", ProfilerService:GetFrameTimes(GRAPH_FRAMES))

			if selectedZone then
				graph:SetValues("Zone", ProfilerService:GetZoneHistory(selectedZone, GRAPH_FRAMES))
				zoneSeriesShown = true
			elseif zoneSeriesShown then
				graph:SetValues("Zone", {})
				zoneSeriesShown = false
			end

			local title = selectedZone and ("Frame time vs " .. selectedZone .. " (ms)") or "Frame time (ms)"

			if title ~= lastTitle then
				lastTitle = title
				graph:SetTitle(title)
			end
		end

		-- table
		for k, rec in pairs(sortRecords) do
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

	local connection = RunService.Heartbeat:Connect(function(dt)
		accumulator += dt

		if accumulator < TICK then
			return
		end

		accumulator = 0

		refresh()
	end)

	content.Destroying:Connect(function()
		connection:Disconnect()
		graph:Destroy()
		flame:Destroy()
	end)
end

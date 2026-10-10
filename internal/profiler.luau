local RunService = game:GetService("RunService")
local ProfilerService = game:GetService("ProfilerService")
local UI = require("@internal/editor_ui")

local colors = UI.tokens.color
local ROW = 20
local TICK = 0.1 -- text/list refresh interval (seconds)
local GRAPH_POINTS = 300

------------------------------------------------------------------ formatting

local function fmtMs(v)
	return string.format("%.3f ms", v or 0)
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

------------------------------------------------------------------ pooled list

-- Scrollable list with a fixed set of columns. Rows are created once and reused,
-- so refreshing never creates/destroys instances (and never eats clicks).
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
	local selected = nil -- selected script name
	local sortKey = "CpuMs"

	-- Top bar ---------------------------------------------------------------
	local top =
		UI.frame(content, UDim2.fromOffset(8, 6), UDim2.new(1, -16, 0, 30), colors.panelRaised, UI.tokens.radius.sm)

	local _, pauseLabel = UI.button(top, "Pause", UDim2.fromOffset(4, 3), UDim2.fromOffset(84, 24), function()
		if ProfilerService.Paused then
			ProfilerService:Resume()
		else
			ProfilerService:Pause()
		end
	end, { color = colors.input })

	local _, trackLabel, trackRecord = UI.button(
		top,
		"Tracking",
		UDim2.fromOffset(94, 3),
		UDim2.fromOffset(120, 24),
		function()
			ProfilerService:SetTrackingEnabled(not ProfilerService.TrackingEnabled)
		end,
		{ color = colors.input }
	)

	local statsLabel =
		UI.label(top, "", UDim2.fromOffset(226, 5), UDim2.new(1, -234, 0, 20), UI.tokens.type.small, colors.subtext)
	statsLabel.TextXAlignment = Enum.TextXAlignment.Left

	local BODY_Y = 44
	local LEFT_W = 150

	local scriptList = createList(
		content,
		UDim2.fromOffset(8, BODY_Y),
		UDim2.new(0, LEFT_W, 1, -(BODY_Y + 8)),
		"Scripts",
		{
			{ header = "Name", x = 0, w = 0.46 },
			{ header = "CPU", x = 0.46, w = 0.2, align = Enum.TextXAlignment.Right },
			{ header = "Live", x = 0.66, w = 0.2, align = Enum.TextXAlignment.Right },
			{ header = "Thr", x = 0.86, w = 0.14, align = Enum.TextXAlignment.Right },
		},
		function(name)
			selected = (selected == name) and nil or name
		end,
		26
	)

	local sortOptions = {
		{ "CPU", "CpuMs" },
		{ "Total", "TotalCpuMs" },
		{ "Alloc", "AllocatedBytes" },
		{ "Live", "LiveBytes" },
		{ "Calls", "Resumes" },
	}
	local sortRecords = {}

	for i, option in ipairs(sortOptions) do
		local _, _, record = UI.button(
			scriptList.frame,
			option[1],
			UDim2.fromOffset(6 + (i - 1) * 66, 24),
			UDim2.fromOffset(62, 22),
			function()
				sortKey = option[2]
			end,
			{ color = colors.input, paddingX = 2 }
		)
		sortRecords[option[2]] = record
	end

	-- Right column ----------------------------------------------------------
	local right = UI.frame(
		content,
		UDim2.fromOffset(LEFT_W + 16, BODY_Y),
		UDim2.new(1, -(LEFT_W + 24), 1, -(BODY_Y + 8)),
		colors.panel
	)
	right.BackgroundTransparency = 1

	-- frame time graph
	local _, graph = UI.graph(right, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 180), {
		title = "Frame time",
		yLabel = "ms",
		legend = false,
		color = colors.panel,
	})
	graph:SetSeries({ { name = "Frame time", values = {}, color = colors.accent } })

	-- selected script details
	local details = UI.card(right, UDim2.fromOffset(0, 188), UDim2.new(1, 0, 0, 100), { color = colors.panel })

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

	local threadList = createList(right, UDim2.fromOffset(0, 296), UDim2.new(0.6, -4, 1, -296), "Threads", {
		{ header = "Id", x = 0, w = 0.08 },
		{ header = "Name", x = 0.08, w = 0.34 },
		{ header = "Status", x = 0.42, w = 0.2 },
		{ header = "CPU", x = 0.62, w = 0.18, align = Enum.TextXAlignment.Right },
		{ header = "Live", x = 0.8, w = 0.2, align = Enum.TextXAlignment.Right },
	})

	local zoneList = createList(right, UDim2.new(0.6, 4, 0, 296), UDim2.new(0.4, -4, 1, -296), "Zones (last frame)", {
		{ header = "Name", x = 0, w = 0.55 },
		{ header = "Time", x = 0.55, w = 0.25, align = Enum.TextXAlignment.Right },
		{ header = "%", x = 0.8, w = 0.2, align = Enum.TextXAlignment.Right },
	})

	local function refresh()
		local frameStats = ProfilerService:GetFrameStats()
		local threadStats = ProfilerService:GetThreadStats()

		-- top bar
		pauseLabel.Text = ProfilerService.Paused and "Resume" or "Pause"
		trackLabel.Text = threadStats.trackingEnabled and "Tracking: On" or "Tracking: Off"
		UI.setButtonState(trackRecord, threadStats.trackingEnabled and "selected" or "default")

		if frameStats.enabled then
			statsLabel.Text = string.format(
				"FPS %.1f   frame %.2f ms   heap %s   alloc %s/s   threads %d (+%d dead)%s",
				frameStats.fps,
				frameStats.frameMs,
				fmtBytes(threadStats.heapBytes),
				fmtBytes(threadStats.allocationRateBytesPerSecond),
				threadStats.threads,
				threadStats.deadThreads,
				ProfilerService.Paused and "   [paused]" or ""
			)
		else
			statsLabel.Text = "Profiler disabled"
		end

		for key, record in pairs(sortRecords) do
			UI.setButtonState(record, key == sortKey and "selected" or "default")
		end

		-- scripts
		local scripts = ProfilerService:GetScripts()

		table.sort(scripts, function(a, b)
			if a[sortKey] ~= b[sortKey] then
				return a[sortKey] > b[sortKey]
			end

			return a.Name < b.Name
		end)

		local scriptData = {}
		local selectedScript = nil

		for i, s in ipairs(scripts) do
			if s.Name == selected then
				selectedScript = s
			end

			scriptData[i] = {
				id = s.Name,
				selected = s.Name == selected,
				cells = {
					s.Name,
					fmtMs(s.CpuMs),
					fmtBytes(s.LiveBytes),
					string.format("%d/%d", s.AliveThreads, s.Threads),
				},
			}
		end

		scriptList.set(scriptData)

		-- details
		detailsTitle.Text = selected and selected or "Select a script (showing all threads)"

		for i, def in ipairs(statDefs) do
			statValues[i].Text = selectedScript and def[3](selectedScript[def[2]]) or "--"
		end

		-- threads (filtered to the selected script when there is one)
		local threads = ProfilerService:GetThreads()

		table.sort(threads, function(a, b)
			return a.CpuMs > b.CpuMs
		end)

		local threadData = {}

		for _, t in ipairs(threads) do
			if not selected or string.find(t.Name, selected, 1, true) then
				table.insert(threadData, {
					id = t.Id,
					cells = { fmtInt(t.Id), t.Name, t.Status, fmtMs(t.CpuMs), fmtBytes(t.LiveBytes) },
				})
			end
		end

		threadList.set(threadData)

		-- zones
		local zones = frameStats.zones or {}

		table.sort(zones, function(a, b)
			return a.ms > b.ms
		end)

		local zoneData = {}
		local total = math.max(frameStats.frameMs, 0.001)

		for i, z in ipairs(zones) do
			zoneData[i] = {
				id = z.name,
				cells = { z.name, fmtMs(z.ms), string.format("%.1f%%", z.ms / total * 100) },
			}
		end

		zoneList.set(zoneData)
	end

	local pending = {}
	local accumulator = TICK

	local connection = RunService.Heartbeat:Connect(function(dt)
		if not ProfilerService.Paused then
			local ms = ProfilerService.FrameTime

			if ms > 0 then
				pending[#pending + 1] = ms
			end
		end

		accumulator += dt

		if accumulator < TICK then
			return
		end

		accumulator = 0

		for _, ms in ipairs(pending) do
			graph:Push("Frame time", ms, GRAPH_POINTS)
		end

		pending = {}

		refresh()
	end)

	content.Destroying:Connect(function()
		connection:Disconnect()
		graph:Destroy()
	end)
end

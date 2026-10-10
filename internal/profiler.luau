local UI = require("@internal/editor_ui")

local RunService = game:GetService("RunService")
local ProfilerService = game:GetService("ProfilerService")

local colors = UI.tokens.color
local REFRESH_INTERVAL = 0.5
local MAX_ROWS = 100
local GRAPH_POINTS = 60

return function(gui)
	local alive = true
	local elapsed = 0
	local sampleCount = 0
	local sortBy = "CpuMs"
	local ascending = false
	local rows = {}

	local content = Instance.new("ScrollingFrame")
	content.Size = UDim2.new(1, 0, 1, 0)
	content.BackgroundTransparency = 1
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.Parent = gui

	local root = UI.frame(content, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 1, 0), colors.canvas)

	local header = UI.label(root, "SCRIPT PROFILER", UDim2.fromOffset(12, 8), UDim2.new(1, -24, 0, 24), 16, colors.text)

	header.Font = Enum.Font.GothamBold
	header.TextXAlignment = Enum.TextXAlignment.Left

	local summary = UI.label(
		root,
		"Waiting for profiler data...",
		UDim2.fromOffset(12, 34),
		UDim2.new(1, -24, 0, 20),
		12,
		colors.subtext
	)

	summary.TextXAlignment = Enum.TextXAlignment.Left

	local refreshButton, _, refreshRecord = UI.button(
		root,
		"Refresh",
		UDim2.fromOffset(12, 60),
		UDim2.fromOffset(84, 26),
		function()
			elapsed = REFRESH_INTERVAL
		end
	)

	local trackingButton, _, trackingRecord = UI.button(
		root,
		"Enable Tracking",
		UDim2.fromOffset(104, 60),
		UDim2.fromOffset(132, 26),
		function()
			ProfilerService:SetTrackingEnabled(not ProfilerService.TrackingEnabled)
			elapsed = REFRESH_INTERVAL
		end
	)

	local graphFrame, graph = UI.graph(root, UDim2.fromOffset(12, 96), UDim2.new(1, -24, 0, 190), {
		title = "Top Script CPU Time",
		xLabel = "Samples",
		yLabel = "CPU ms",
		legend = "top-left",
		includeZero = true,
	})

	local tablePanel = UI.frame(root, UDim2.fromOffset(12, 294), UDim2.new(1, -24, 1, -306), colors.panel)

	UI.stroke(tablePanel, colors.border, 1, 0)

	local columns = {
		{ key = "Name", label = "Script", width = 0.34 },
		{ key = "CpuMs", label = "CPU ms", width = 0.16 },
		{ key = "TotalCpuMs", label = "Total ms", width = 0.18 },
		{ key = "AllocatedBytes", label = "Allocated", width = 0.16 },
		{ key = "AliveThreads", label = "Threads", width = 0.16 },
	}

	local columnHeader = UI.frame(tablePanel, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 28), colors.panelRaised)

	local headerButtons = {}

	local function updateHeader()
		for _, item in ipairs(columns) do
			local arrow = ""
			if sortBy == item.key then
				arrow = ascending and " ↑" or " ↓"
			end

			local label = item.label .. arrow
			headerButtons[item.key].Text = label
		end
	end

	local list = UI.create("ScrollingFrame", {
		Name = "ScriptRows",
		Position = UDim2.fromOffset(0, 29),
		Size = UDim2.new(1, 0, 1, -29),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = colors.subtext,
		CanvasSize = UDim2.fromOffset(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, tablePanel)

	local layout = UI.create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 1),
	}, list)

	local function makeCell(parent, text, position, size, color)
		local label = UI.label(parent, text, position, size, 12, color or colors.text)

		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTruncate = Enum.TextTruncate.AtEnd

		return label
	end

	for _, item in ipairs(columns) do
		local button = UI.create("TextButton", {
			Name = item.key,
			Position = UDim2.new(
				(function()
					local total = 0
					for _, column in ipairs(columns) do
						if column.key == item.key then
							break
						end
						total += column.width
					end
					return total
				end)(),
				6,
				0,
				0
			),
			Size = UDim2.new(item.width, -8, 1, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = item.label,
			TextColor3 = colors.text,
			TextSize = 12,
			Font = Enum.Font.GothamMedium,
			TextXAlignment = Enum.TextXAlignment.Left,
			AutoButtonColor = true,
		}, columnHeader)

		button.Activated:Connect(function()
			if sortBy == item.key then
				ascending = not ascending
			else
				sortBy = item.key
				ascending = item.key == "Name"
			end

			updateHeader()
			elapsed = REFRESH_INTERVAL
		end)

		headerButtons[item.key] = button
	end

	updateHeader()

	local function formatValue(key, value)
		if key == "Name" then
			return tostring(value or "Unknown")
		elseif key == "AllocatedBytes" then
			return string.format("%.1f KB", (value or 0) / 1024)
		elseif key == "AliveThreads" then
			return tostring(value or 0)
		end

		return string.format("%.3f", value or 0)
	end

	local function renderRows(scripts)
		for _, row in ipairs(rows) do
			row:Destroy()
		end
		table.clear(rows)

		for index, stats in ipairs(scripts) do
			if index > MAX_ROWS then
				break
			end

			local row = UI.frame(
				list,
				UDim2.fromOffset(0, 0),
				UDim2.new(1, 0, 0, 26),
				index % 2 == 0 and colors.rowEven or colors.rowOdd
			)

			row.LayoutOrder = index

			local x = 0

			for _, item in ipairs(columns) do
				makeCell(
					row,
					formatValue(item.key, stats[item.key]),
					UDim2.new(x, 6, 0, 0),
					UDim2.new(item.width, -8, 1, 0)
				)

				x += item.width
			end

			table.insert(rows, row)
		end
	end

	local function refresh()
		if not alive then
			return
		end

		local ok, scripts = pcall(function()
			return ProfilerService:GetScripts()
		end)

		if not ok or type(scripts) ~= "table" then
			summary.Text = "Unable to retrieve script statistics"
			return
		end

		local totalCpu = 0

		for _, stats in ipairs(scripts) do
			totalCpu += stats.CpuMs or 0
		end

		table.sort(scripts, function(a, b)
			local av = a[sortBy] or 0
			local bv = b[sortBy] or 0

			if sortBy == "Name" then
				av = tostring(av)
				bv = tostring(bv)
			end

			if av == bv then
				return tostring(a.Name) < tostring(b.Name)
			end

			if ascending then
				return av < bv
			end

			return av > bv
		end)

		summary.Text = string.format(
			"%d scripts    |    %.3f ms aggregate CPU    |    Tracking %s",
			#scripts,
			totalCpu,
			ProfilerService.TrackingEnabled and "ON" or "OFF"
		)

		UI.setButtonState(trackingRecord, ProfilerService.TrackingEnabled and "accent" or "normal")

		local top = {}
		local limit = math.min(5, #scripts)

		for i = 1, limit do
			top[i] = scripts[i]
		end

		if sampleCount == 0 then
			for _, stats in ipairs(top) do
				graph:Push(stats.Name or "Script", stats.CpuMs or 0, GRAPH_POINTS)
			end
		else
			for _, stats in ipairs(top) do
				graph:Push(stats.Name or "Script", stats.CpuMs or 0, GRAPH_POINTS)
			end
		end

		sampleCount += 1
		graph:AutoFit()

		renderRows(scripts)
	end

	local connection = RunService.Heartbeat:Connect(function(dt)
		if not alive then
			return
		end

		elapsed += dt

		if elapsed >= REFRESH_INTERVAL then
			elapsed = 0
			refresh()
		end
	end)

	refresh()

	return {
		Destroy = function()
			alive = false
			connection:Disconnect()
			root:Destroy()
		end,
	}
end

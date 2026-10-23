local UserInputService = game:GetService("UserInputService")

return function(ctx)
	local UI = ctx.UI
	local colors = UI.tokens.color
	local MIN_SPAN = 0.0005
	local MAX_TICKS = 16

	local function niceStep(range, count)
		if range <= 0 then
			return 1
		end

		local rough = range / math.max(count - 1, 1)
		local exponent = math.floor(math.log10(rough))
		local fraction = rough / 10 ^ exponent

		local nice

		if fraction <= 1 then
			nice = 1
		elseif fraction <= 2 then
			nice = 2
		elseif fraction <= 5 then
			nice = 5
		else
			nice = 10
		end

		return nice * 10 ^ exponent
	end

	local function formatTick(value, step)
		if step >= 1 then
			return string.format("%d ms", math.floor(value + 0.5))
		end

		local decimals = math.clamp(-math.floor(math.log10(step)), 0, 6)

		return string.format("%." .. decimals .. "f ms", value)
	end

	local function colorFromRGB(c)
		if not c or c == 0 then
			return colors.accent
		end

		return Color3.new(math.floor(c / 65536) / 255, math.floor((c % 65536) / 256) / 255, (c % 256) / 255)
	end

	local function textColorFor(background)
		local luminance = 0.299 * background.R + 0.587 * background.G + 0.114 * background.B

		return luminance > 0.62 and Color3.new(0.06, 0.07, 0.09) or Color3.new(1, 1, 1)
	end

	local function analyze(zones)
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
			it.self = math.max(it.ms - it.childMs, 0)

			local row = byName[it.name]

			if not row then
				row = { name = it.name, color = it.color, total = 0, self = 0, calls = 0, max = 0 }
				byName[it.name] = row
				rows[#rows + 1] = row
			end

			row.total += it.ms
			row.self += it.self
			row.calls += 1
			row.max = math.max(row.max, it.ms)
		end

		return items, rows, maxEnd
	end

	function UI.flamegraph(parent, position, size, options)
		options = options or {}

		local rowHeight = options.rowHeight or 18
		local rulerHeight = options.ruler == false and 0 or 18
		local maxBoxes = options.maxBoxes or 800
		local labelMinWidth = options.labelMinWidth or 36
		local zoomEnabled = options.zoom ~= false

		local container = UI.frame(
			parent,
			position or UDim2.fromOffset(0, 0),
			size or UDim2.fromOffset(600, 240),
			options.color or colors.input,
			UI.tokens.radius.xs
		)

		container.Name = options.name or "Flamegraph"
		container.ClipsDescendants = true
		UI.stroke(container, colors.border, 1, 0)

		local data = { items = {}, rows = {}, maxEnd = 0 }
		local viewLo, viewHi = 0, 1
		local selectedName = nil
		local panning = nil
		local lastMouse = nil
		local lastClick = 0
		local destroyed = false
		local connections = {}
		local boxes = {}
		local ticks = {}

		local controller = { frame = container, rows = data.rows }

		local gridLayer = UI.create("Frame", {
			Name = "Grid",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, container)

		local hit = UI.create("TextButton", {
			Name = "Hit",
			Text = "",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Active = true,
			InputSink = false,
		}, container)

		local ruler = nil

		if rulerHeight > 0 then
			ruler = UI.frame(container, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, rulerHeight), colors.panelRaised)
			ruler.Name = "Ruler"
			UI.separator(ruler, UDim2.new(0, 0, 1, -1), UDim2.new(1, 0, 0, 1), colors.border)
		end

		local emptyLabel = UI.label(
			container,
			options.emptyText or "No zones captured",
			UDim2.new(0, 0, 0.5, -10),
			UDim2.new(1, 0, 0, 20),
			UI.tokens.type.small,
			colors.muted
		)
		emptyLabel.TextXAlignment = Enum.TextXAlignment.Center

		local relayout

		local function setView(lo, hi)
			local span = math.clamp(hi - lo, MIN_SPAN, 1)

			lo = math.clamp(lo, 0, 1 - span)

			viewLo, viewHi = lo, lo + span

			relayout()

			if options.onViewChanged then
				options.onViewChanged(viewLo, viewHi)
			end
		end

		local function beginPan()
			panning = {
				loc = UserInputService:GetMouseLocation(),
				lo = viewLo,
				hi = viewHi,
			}
		end

		local function setHover(item)
			if options.onHover then
				options.onHover(item)
			end
		end

		local function newBox(index)
			local box = {}

			local button = UI.create("TextButton", {
				Text = "",
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Active = true,
				InputSink = true,
				ClipsDescendants = true,
			}, container)

			local label = UI.label(button, "", UDim2.fromOffset(3, 0), UDim2.new(1, -3, 1, 0), 11, Color3.new(1, 1, 1))
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextYAlignment = Enum.TextYAlignment.Center

			box.button = button
			box.label = label

			button.MouseButton1Click:Connect(function()
				if box.zone then
					controller:SetSelected(selectedName ~= box.zone.name and box.zone.name or nil)
				end
			end)

			button.MouseButton2Down:Connect(function(x, y)
				lastMouse = Vector2.new(x, y)
				beginPan()
			end)

			button.MouseEnter:Connect(function(x, y)
				lastMouse = Vector2.new(x, y)

				if box.zone then
					setHover(box.zone)
				end
			end)

			button.MouseMoved:Connect(function(x, y)
				lastMouse = Vector2.new(x, y)
			end)

			button.MouseLeave:Connect(function()
				lastMouse = nil
				setHover(nil)
			end)

			boxes[index] = box
			return box
		end

		local function newTick(index)
			local grid = UI.frame(gridLayer, UDim2.fromOffset(0, 0), UDim2.new(0, 1, 1, 0), colors.border)
			grid.BackgroundTransparency = 0.7

			local label = nil

			if ruler then
				label = UI.label(
					ruler,
					"",
					UDim2.fromOffset(0, 1),
					UDim2.fromOffset(70, rulerHeight - 3),
					10,
					colors.subtext
				)
				label.TextXAlignment = Enum.TextXAlignment.Left
				label.TextYAlignment = Enum.TextYAlignment.Center
			end

			ticks[index] = { grid = grid, label = label }
			return ticks[index]
		end

		relayout = function()
			if destroyed then
				return
			end

			local sizeNow = container.AbsoluteSize
			local width, height = sizeNow.X, sizeNow.Y

			if width <= 0 or height <= 0 then
				return
			end

			local span = math.max(data.maxEnd, 1e-6)
			local lo, hi = viewLo * span, viewHi * span
			local scale = width / (hi - lo)

			local tickCount = math.clamp(math.floor(width / 90) + 1, 3, MAX_TICKS - 2)
			local step = niceStep(hi - lo, tickCount)
			local value = math.ceil(lo / step - 1e-9) * step
			local used = 0

			while value <= hi + step * 1e-6 and used < MAX_TICKS do
				used += 1

				local tick = ticks[used] or newTick(used)
				local px = math.floor((value - lo) * scale)

				tick.grid.Position = UDim2.fromOffset(px, 0)
				tick.grid.Visible = true

				if tick.label then
					tick.label.Position = UDim2.fromOffset(px + 3, 1)
					tick.label.Text = formatTick(value, step)
					tick.label.Visible = true
				end

				value += step
			end

			for i = used + 1, #ticks do
				ticks[i].grid.Visible = false

				if ticks[i].label then
					ticks[i].label.Visible = false
				end
			end

			local maxRows = math.max(math.floor((height - rulerHeight - 4) / rowHeight), 1)
			local boxesUsed = 0

			for _, it in ipairs(data.items) do
				if it.depth < maxRows and boxesUsed < maxBoxes then
					local x0 = (it.start - lo) * scale
					local x1 = x0 + it.ms * scale

					if x1 >= 0 and x0 <= width and x1 - x0 >= 1 then
						boxesUsed += 1

						local box = boxes[boxesUsed] or newBox(boxesUsed)
						local px = math.max(x0, 0)
						local pw = math.min(x1, width) - px
						local fill = colorFromRGB(it.color)

						box.zone = it
						box.button.Position = UDim2.fromOffset(px, rulerHeight + 2 + it.depth * rowHeight)
						box.button.Size = UDim2.fromOffset(math.max(pw, 1), rowHeight - 2)
						box.button.BackgroundColor3 = fill
						box.button.BackgroundTransparency = (selectedName and it.name ~= selectedName) and 0.65 or 0
						box.label.TextColor3 = textColorFor(fill)

						if pw > 150 then
							box.label.Text = string.format("%s  %.3f ms", it.name, it.ms)
						elseif pw > labelMinWidth then
							box.label.Text = it.name
						else
							box.label.Text = ""
						end

						box.button.Visible = true
					end
				end
			end

			for i = boxesUsed + 1, #boxes do
				boxes[i].button.Visible = false
				boxes[i].zone = nil
			end
		end

		hit.MouseButton1Down:Connect(function(x, y)
			lastMouse = Vector2.new(x, y)

			local now = os.clock()

			if now - lastClick < 0.3 then
				lastClick = 0
				panning = nil
				setView(0, 1)
				return
			end

			lastClick = now
			beginPan()
		end)

		hit.MouseButton2Down:Connect(function(x, y)
			lastMouse = Vector2.new(x, y)
			beginPan()
		end)

		hit.MouseEnter:Connect(function(x, y)
			lastMouse = Vector2.new(x, y)
		end)

		hit.MouseMoved:Connect(function(x, y)
			lastMouse = Vector2.new(x, y)
		end)

		hit.MouseLeave:Connect(function()
			lastMouse = nil
		end)

		table.insert(
			connections,
			UserInputService.InputChanged:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseWheel then
					if not zoomEnabled or panning or not lastMouse or not UI.pointInside(container, lastMouse) then
						return
					end

					local steps = input.Position.Z

					if steps == 0 then
						return
					end

					local width = math.max(container.AbsoluteSize.X, 1)
					local fx = math.clamp((lastMouse.X - container.AbsolutePosition.X) / width, 0, 1)

					local span = viewHi - viewLo
					local anchor = viewLo + fx * span
					local newSpan = math.clamp(span * (options.zoomSpeed or 0.8) ^ steps, MIN_SPAN, 1)
					local newLo = anchor - fx * newSpan

					setView(newLo, newLo + newSpan)
				elseif input.UserInputType == Enum.UserInputType.MouseMovement then
					if not panning then
						return
					end

					local loc = UserInputService:GetMouseLocation()
					local dx = loc.X - panning.loc.X
					local width = math.max(container.AbsoluteSize.X, 1)
					local shift = dx / width * (panning.hi - panning.lo)

					setView(panning.lo - shift, panning.hi - shift)
				end
			end)
		)

		table.insert(
			connections,
			UserInputService.InputEnded:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.MouseButton2
				then
					panning = nil
				end
			end)
		)

		pcall(function()
			container:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
				relayout()
			end)
		end)

		function controller:SetData(zones)
			local items, rows, maxEnd = analyze(zones or {})

			data = { items = items, rows = rows, maxEnd = maxEnd }
			self.rows = rows

			emptyLabel.Visible = #items == 0

			relayout()

			return rows, maxEnd
		end

		function controller:GetRows()
			return data.rows
		end

		function controller:GetItems()
			return data.items
		end

		function controller:SetSelected(name, silent)
			if selectedName == name then
				return
			end

			selectedName = name

			relayout()

			if not silent and options.onSelect then
				options.onSelect(name)
			end
		end

		function controller:GetSelected()
			return selectedName
		end

		function controller:SetView(lo, hi)
			setView(lo, hi)
		end

		function controller:GetView()
			return viewLo, viewHi
		end

		function controller:Fit()
			setView(0, 1)
		end

		function controller:Relayout()
			relayout()
		end

		function controller:Destroy()
			if destroyed then
				return
			end

			destroyed = true

			for _, connection in ipairs(connections) do
				connection:Disconnect()
			end

			container:Destroy()
		end

		emptyLabel.Visible = true

		return container, controller
	end
end

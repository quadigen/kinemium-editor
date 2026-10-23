local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

return function(ctx)
	local UI = ctx.UI
	local colors = UI.tokens.color
	local tooltipSmoothTowards = ctx.tooltipSmoothTowards

	function UI.graph(parent, position, size, options)
		options = options or {}

		local colors = UI.tokens.color
		local UserInputService = game:GetService("UserInputService")

		local palette = {
			Color3.fromRGB(76, 114, 176),
			Color3.fromRGB(221, 132, 82),
			Color3.fromRGB(85, 168, 104),
			Color3.fromRGB(196, 78, 82),
			Color3.fromRGB(129, 114, 179),
			Color3.fromRGB(147, 120, 96),
			Color3.fromRGB(218, 139, 195),
			Color3.fromRGB(140, 140, 140),
		}

		local interactive = options.interactive ~= false
		local tickTextSize = options.tickTextSize or UI.tokens.type.caption
		local legendMode = options.legend
		if legendMode == nil then
			legendMode = "top-left"
		end

		local marginLeft = options.leftMargin or (options.yLabel and 58 or 42)
		local marginRight = options.rightMargin or 14
		local marginTop = options.topMargin or (options.title and 30 or 12)
		local marginBottom = options.bottomMargin or (options.xLabel and 42 or 26)

		local state = {
			series = {},
			title = options.title,
			xLabel = options.xLabel,
			yLabel = options.yLabel,
			fixed = { xMin = options.xMin, xMax = options.xMax, yMin = options.yMin, yMax = options.yMax },
			auto = { xMin = 0, xMax = 1, yMin = 0, yMax = 1 },
			xMin = 0,
			xMax = 1,
			yMin = 0,
			yMax = 1,
			target = nil,
			clearAfter = false,
			dirty = false,
			cache = nil,
			destroyed = false,
		}

		local function getX(s, i)
			if s.xs then
				return s.xs[i]
			end
			return s.x0 + i - 1
		end

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
				return string.format("%d", math.floor(value + 0.5))
			end

			local decimals = math.clamp(-math.floor(math.log10(step)), 0, 8)
			return string.format("%." .. decimals .. "f", value)
		end

		local function formatValue(value)
			return string.format("%.4g", value)
		end

		local function clearChildren(frame)
			for _, child in ipairs(frame:GetChildren()) do
				if not (child:IsA("UICorner") or child:IsA("UIStroke") or child:IsA("UIGradient")) then
					child:Destroy()
				end
			end
		end

		local function makeLabel(layer, text, pos, sz, textSize, color, alignX)
			local label = UI.label(layer, text, pos, sz, textSize, color)
			label.TextXAlignment = alignX or Enum.TextXAlignment.Center
			label.TextYAlignment = Enum.TextYAlignment.Center
			return label
		end

		local function line(layer, x1, y1, x2, y2, thickness, color)
			local dx, dy = x2 - x1, y2 - y1
			local length = math.sqrt(dx * dx + dy * dy)

			if length < 0.01 then
				return
			end

			UI.create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2),
				Size = UDim2.fromOffset(length + thickness * 0.5, thickness),
				Rotation = math.deg(math.atan2(dy, dx)),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
			}, layer)
		end

		local function clipSegment(x1, y1, x2, y2, w, h)
			local dx, dy = x2 - x1, y2 - y1
			local t0, t1 = 0, 1

			local p = { -dx, dx, -dy, dy }
			local q = { x1 + 2, w + 2 - x1, y1 + 2, h + 2 - y1 }

			for i = 1, 4 do
				if p[i] == 0 then
					if q[i] < 0 then
						return nil
					end
				else
					local r = q[i] / p[i]

					if p[i] < 0 then
						if r > t1 then
							return nil
						end
						if r > t0 then
							t0 = r
						end
					else
						if r < t0 then
							return nil
						end
						if r < t1 then
							t1 = r
						end
					end
				end
			end

			return x1 + t0 * dx, y1 + t0 * dy, x1 + t1 * dx, y1 + t1 * dy
		end

		local container = UI.frame(
			parent,
			position or UDim2.fromOffset(0, 0),
			size or UDim2.fromOffset(500, 300),
			options.color or colors.panel
		)

		container.Name = options.name or "Graph"
		container.BackgroundTransparency = options.color and 0 or 1

		local tickLayer = UI.create("Frame", {
			Name = "Ticks",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, container)

		local plot = UI.frame(
			container,
			UDim2.fromOffset(marginLeft, marginTop),
			UDim2.new(1, -(marginLeft + marginRight), 1, -(marginTop + marginBottom)),
			options.plotColor or colors.input,
			UI.tokens.radius.xs
		)

		plot.Name = "Plot"
		plot.ClipsDescendants = true
		UI.stroke(plot, colors.border, 1, 0)

		local function newLayer(name)
			return UI.create("Frame", {
				Name = name,
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
			}, plot)
		end

		local gridLayer = newLayer("Grid")
		local seriesLayer = newLayer("Series")
		local overlayLayer = newLayer("Overlay")

		local crossLine = UI.frame(overlayLayer, UDim2.fromOffset(0, 0), UDim2.new(0, 1, 1, 0), colors.subtext)
		crossLine.BackgroundTransparency = 0.5
		crossLine.Visible = false

		local dots = {}

		local selFrame = UI.frame(overlayLayer, UDim2.fromOffset(0, 0), UDim2.fromOffset(0, 0), colors.accent)
		selFrame.Name = "Selection"
		selFrame.BackgroundTransparency = 0.8
		selFrame.Visible = false
		UI.stroke(selFrame, colors.accent, 1, 0.1)

		local selLabel = UI.label(overlayLayer, "", UDim2.fromOffset(0, 0), UDim2.fromOffset(120, 16), 11, colors.text)
		selLabel.Name = "SelectionLabel"
		selLabel.Visible = false
		selLabel.TextXAlignment = Enum.TextXAlignment.Center
		selLabel.BackgroundTransparency = 0.15
		selLabel.BackgroundColor3 = colors.panelRaised

		local hit = UI.create("TextButton", {
			Name = "Hit",
			Text = "",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Active = true,
			InputSink = false,
		}, plot)

		local legendFrame = nil

		local function plotSize()
			local s = plot.AbsoluteSize
			return math.max(s.X, 1), math.max(s.Y, 1)
		end

		local function invalidate()
			state.cache = nil
		end

		local function scanExtent(x0, x1)
			local function run(onlyVisible)
				local xMin, xMax, yMin, yMax = math.huge, -math.huge, math.huge, -math.huge

				for _, s in ipairs(state.series) do
					if not onlyVisible or s.visible then
						for i, v in ipairs(s.values) do
							local x = getX(s, i)

							if not x0 or (x >= x0 and x <= x1) then
								xMin = math.min(xMin, x)
								xMax = math.max(xMax, x)
								yMin = math.min(yMin, v)
								yMax = math.max(yMax, v)
							end
						end
					end
				end

				if xMin == math.huge then
					return nil
				end

				return { xMin = xMin, xMax = xMax, yMin = yMin, yMax = yMax }
			end

			return run(true) or run(false)
		end

		local function niceY(yMin, yMax)
			if options.includeZero ~= false then
				yMin = math.min(yMin, 0)
				yMax = math.max(yMax, 0)
			end

			if yMax - yMin < 1e-9 then
				yMin -= 1
				yMax += 1
			end

			local _, ph = plotSize()
			local count = math.clamp(math.floor(ph / 40) + 1, 3, 11)
			local step = niceStep(yMax - yMin, count)

			return math.floor(yMin / step) * step, math.ceil(yMax / step) * step
		end

		local function computeBounds()
			local full = state.cache

			if not full then
				full = scanExtent() or { xMin = 0, xMax = 1, yMin = 0, yMax = 1 }
				state.cache = full
			end

			local axMin, axMax = full.xMin, full.xMax

			if axMax - axMin < 1e-9 then
				axMin -= 1
				axMax += 1
			end

			local ayMin, ayMax = niceY(full.yMin, full.yMax)

			state.auto = { xMin = axMin, xMax = axMax, yMin = ayMin, yMax = ayMax }

			local fixed = state.fixed

			state.xMin = fixed.xMin or axMin
			state.xMax = fixed.xMax or axMax

			if state.xMax - state.xMin < 1e-12 then
				state.xMax = state.xMin + 1e-12
			end

			if fixed.yMin and fixed.yMax then
				state.yMin, state.yMax = fixed.yMin, fixed.yMax
			else
				local yMin, yMax = ayMin, ayMax

				if options.autoFitY and (fixed.xMin or fixed.xMax) then
					local visible = scanExtent(state.xMin, state.xMax)

					if visible then
						yMin, yMax = niceY(visible.yMin, visible.yMax)
					end
				end

				state.yMin = fixed.yMin or yMin
				state.yMax = fixed.yMax or yMax
			end

			if state.yMax - state.yMin < 1e-12 then
				state.yMax = state.yMin + 1e-12
			end
		end

		local redraw

		local function buildLegend()
			if legendFrame then
				UI.forgetButtons(legendFrame)
				legendFrame:Destroy()
				legendFrame = nil
			end

			if not legendMode or #state.series == 0 then
				return
			end

			local rowHeight = 20
			local widest = 0

			for _, s in ipairs(state.series) do
				widest = math.max(widest, #s.name)
			end

			local width = widest * 7 + 38
			local height = #state.series * rowHeight + 6

			local anchor = Vector2.new(0, 0)
			local pos = UDim2.fromOffset(marginLeft + 8, marginTop + 8)

			if legendMode == "top-right" then
				anchor = Vector2.new(1, 0)
				pos = UDim2.new(1, -(marginRight + 8), 0, marginTop + 8)
			end

			legendFrame = UI.frame(container, pos, UDim2.fromOffset(width, height), colors.panel, UI.tokens.radius.xs)
			legendFrame.Name = "Legend"
			legendFrame.AnchorPoint = anchor
			legendFrame.BackgroundTransparency = 0.1
			UI.stroke(legendFrame, colors.border, 1, 0)

			for index, s in ipairs(state.series) do
				local row, label = UI.button(
					legendFrame,
					s.name,
					UDim2.fromOffset(3, 3 + (index - 1) * rowHeight),
					UDim2.new(1, -6, 0, rowHeight),
					function()
						s.visible = not s.visible
						invalidate()
						buildLegend()
						redraw()
					end,
					{
						color = colors.panel,
						hoverColor = colors.hover,
						pressedColor = colors.pressed,
						textColor = s.visible and colors.text or colors.muted,
						textSize = UI.tokens.type.small,
						radius = UI.tokens.radius.xs,
						border = false,
						bgTransparency = 1,
					}
				)

				row.Name = s.name

				label.Position = UDim2.fromOffset(24, 0)
				label.Size = UDim2.new(1, -28, 1, 0)
				label.TextXAlignment = Enum.TextXAlignment.Left

				local swatch = UI.frame(row, UDim2.fromOffset(6, 5), UDim2.fromOffset(11, 11), s.color, 2)
				swatch.BackgroundTransparency = s.visible and 0 or 0.7
			end
		end

		local function lowerBound(s, x)
			local lo, hi = 1, #s.values + 1

			while lo < hi do
				local mid = math.floor((lo + hi) / 2)

				if getX(s, mid) < x then
					lo = mid + 1
				else
					hi = mid
				end
			end

			return lo
		end

		local lastNotified = nil

		redraw = function()
			if state.destroyed then
				return
			end

			clearChildren(tickLayer)
			clearChildren(gridLayer)
			clearChildren(seriesLayer)

			computeBounds()

			local pw, ph = plotSize()
			local xMin, xMax, yMin, yMax = state.xMin, state.xMax, state.yMin, state.yMax

			local function toX(x)
				return (x - xMin) / (xMax - xMin) * pw
			end

			local function toY(y)
				return ph - (y - yMin) / (yMax - yMin) * ph
			end

			local yTicks = math.clamp(math.floor(ph / 40) + 1, 3, 11)
			local yStep = niceStep(yMax - yMin, yTicks)
			local yStart = math.ceil(yMin / yStep - 1e-9) * yStep

			local labelX = options.yLabel and 18 or 0

			local value = yStart
			local guard = 0
			while value <= yMax + yStep * 1e-6 and guard < 64 do
				guard += 1
				local py = toY(value)

				if options.grid ~= false then
					local g =
						UI.frame(gridLayer, UDim2.fromOffset(0, math.floor(py)), UDim2.new(1, 0, 0, 1), colors.border)
					g.BackgroundTransparency = 0.45
				end

				makeLabel(
					tickLayer,
					formatTick(value, yStep),
					UDim2.fromOffset(labelX, marginTop + py - 8),
					UDim2.fromOffset(marginLeft - 6 - labelX, 16),
					tickTextSize,
					colors.subtext,
					Enum.TextXAlignment.Right
				)

				value += yStep
			end

			local xTicks = math.clamp(math.floor(pw / 70) + 1, 3, 11)
			local xStep = niceStep(xMax - xMin, xTicks)
			local xStart = math.ceil(xMin / xStep - 1e-9) * xStep

			value = xStart
			guard = 0
			while value <= xMax + xStep * 1e-6 and guard < 64 do
				guard += 1
				local px = toX(value)

				if options.grid ~= false then
					local g =
						UI.frame(gridLayer, UDim2.fromOffset(math.floor(px), 0), UDim2.new(0, 1, 1, 0), colors.border)
					g.BackgroundTransparency = 0.45
				end

				makeLabel(
					tickLayer,
					formatTick(value, xStep),
					UDim2.fromOffset(marginLeft + px - 25, marginTop + ph + 4),
					UDim2.fromOffset(50, 14),
					tickTextSize,
					colors.subtext
				)

				value += xStep
			end

			if state.title then
				makeLabel(
					tickLayer,
					state.title,
					UDim2.fromOffset(marginLeft, 4),
					UDim2.fromOffset(pw, 20),
					UI.tokens.type.body,
					colors.text
				)
			end

			if state.xLabel then
				makeLabel(
					tickLayer,
					state.xLabel,
					UDim2.fromOffset(marginLeft, marginTop + ph + 20),
					UDim2.fromOffset(pw, 16),
					UI.tokens.type.small,
					colors.text
				)
			end

			if state.yLabel then
				local yl = makeLabel(
					tickLayer,
					state.yLabel,
					UDim2.fromOffset(9, marginTop + ph / 2),
					UDim2.fromOffset(ph, 16),
					UI.tokens.type.small,
					colors.text
				)
				yl.AnchorPoint = Vector2.new(0.5, 0.5)
				yl.Rotation = -90
			end

			for _, s in ipairs(state.series) do
				local n = #s.values

				if s.visible and n > 0 then
					local first = math.max(1, lowerBound(s, xMin) - 1)
					local last = math.min(n, lowerBound(s, xMax))

					if last >= first then
						local count = last - first + 1
						local stride = math.max(1, math.floor(count / (pw * 1.5)))
						local px, py = {}, {}

						local function addPoint(i)
							table.insert(px, toX(getX(s, i)))
							table.insert(py, toY(s.values[i]))
						end

						local i = first
						local lastAdded = first

						while i <= last do
							addPoint(i)
							lastAdded = i
							i += stride
						end

						if lastAdded ~= last then
							addPoint(last)
						end

						if s.fill and #px >= 2 then
							local colW = 2
							local j = 1

							local c0 = math.max(math.floor(px[1]), 0)
							local c1 = math.min(math.ceil(px[#px]), pw) - 1

							for col = c0, c1, colW do
								local cx = col + colW / 2

								while j < #px - 1 and px[j + 1] < cx do
									j += 1
								end

								local span = px[j + 1] - px[j]
								local t = span > 0 and math.clamp((cx - px[j]) / span, 0, 1) or 0
								local y = py[j] + (py[j + 1] - py[j]) * t

								if y < ph then
									y = math.max(y, -1)

									local c = UI.frame(
										seriesLayer,
										UDim2.fromOffset(col, y),
										UDim2.fromOffset(colW, ph - y),
										s.color
									)
									c.BackgroundTransparency = s.fillTransparency
								end
							end
						end

						for k = 1, #px - 1 do
							local ax, ay, bx, by = clipSegment(px[k], py[k], px[k + 1], py[k + 1], pw, ph)

							if ax then
								line(seriesLayer, ax, ay, bx, by, s.thickness, s.color)
							end
						end

						if #px == 1 then
							local dot = UI.frame(
								seriesLayer,
								UDim2.fromOffset(px[1] - 2, py[1] - 2),
								UDim2.fromOffset(4, 4),
								s.color,
								2
							)
							dot.Name = "Point"
						end
					end
				end
			end

			if options.onViewChanged then
				local v = lastNotified

				if not v or v[1] ~= state.xMin or v[2] ~= state.xMax or v[3] ~= state.yMin or v[4] ~= state.yMax then
					lastNotified = { state.xMin, state.xMax, state.yMin, state.yMax }
					options.onViewChanged(state.xMin, state.xMax, state.yMin, state.yMax)
				end
			end
		end

		local function clampAxis(lo, hi, aLo, aHi)
			local aSpan = math.max(aHi - aLo, 1e-9)
			local minSpan = aSpan * 1e-7
			local maxSpan = aSpan * (options.maxZoomOut or 4)

			local span = hi - lo
			local clamped = math.clamp(span, minSpan, maxSpan)

			if clamped ~= span then
				local center = (lo + hi) / 2
				lo = center - clamped / 2
				hi = center + clamped / 2
				span = clamped
			end

			local keep = span * 0.1

			if hi < aLo + keep then
				local shift = aLo + keep - hi
				lo += shift
				hi += shift
			elseif lo > aHi - keep then
				local shift = lo - (aHi - keep)
				lo -= shift
				hi -= shift
			end

			return lo, hi
		end

		local function setTarget(partial, clearAfter)
			if options.smooth == false then
				for key, value in pairs(partial) do
					state.fixed[key] = value
				end

				state.target = nil

				if clearAfter then
					state.fixed = {}
				end

				state.dirty = true
				return
			end

			state.target = state.target or {}

			for key, value in pairs(partial) do
				state.target[key] = value
			end

			state.clearAfter = clearAfter == true
		end

		local function zoomAxis(axis, fraction, factor)
			local target = state.target
			local lo = (target and target[axis .. "Min"]) or state[axis .. "Min"]
			local hi = (target and target[axis .. "Max"]) or state[axis .. "Max"]

			local anchor = lo + fraction * (hi - lo)
			local span = (hi - lo) * factor

			lo, hi = anchor - fraction * span, anchor + (1 - fraction) * span
			lo, hi = clampAxis(lo, hi, state.auto[axis .. "Min"], state.auto[axis .. "Max"])

			return { [axis .. "Min"] = lo, [axis .. "Max"] = hi }
		end

		local function nearestIndex(s, x)
			local n = #s.values

			if n == 0 then
				return nil
			end

			local hi = math.min(lowerBound(s, x), n)
			local lo = math.max(hi - 1, 1)

			if math.abs(getX(s, lo) - x) <= math.abs(getX(s, hi) - x) then
				return lo
			end

			return hi
		end

		local function hideHover()
			crossLine.Visible = false

			for _, dot in ipairs(dots) do
				dot.Visible = false
			end
		end

		local tip = nil
		local hovering = false
		local lastMouse = Vector2.new(0, 0)
		local panning = nil
		local selecting = nil
		local lastClick = 0
		local connections = {}
		local controller_AutoFit

		local function isShift()
			return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		end

		local function isCtrl()
			return UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
		end

		if options.crosshair ~= false then
			tip = UI.tooltip(hit, "", { followCursor = true, hoverDelay = 0, placement = "cursor" })
		end

		local function updateHover(mx)
			local pw, ph = plotSize()
			local lx = mx - plot.AbsolutePosition.X

			local dataX = state.xMin + math.clamp(lx / pw, 0, 1) * (state.xMax - state.xMin)

			local lines = {}
			local snapped = nil
			local dotIndex = 0

			for _, s in ipairs(state.series) do
				if s.visible then
					local i = nearestIndex(s, dataX)

					if i then
						local x, y = getX(s, i), s.values[i]

						snapped = snapped or x

						if #lines == 0 then
							table.insert(lines, (state.xLabel or "x") .. ": " .. formatValue(x))
						end

						table.insert(lines, s.name .. ": " .. formatValue(y))

						dotIndex += 1

						local dot = dots[dotIndex]

						if not dot then
							dot = UI.frame(overlayLayer, UDim2.fromOffset(0, 0), UDim2.fromOffset(7, 7), s.color, 4)
							dots[dotIndex] = dot
						end

						dot.BackgroundColor3 = s.color
						dot.Visible = true
						dot.Position = UDim2.fromOffset(
							(x - state.xMin) / (state.xMax - state.xMin) * pw - 3,
							ph - (y - state.yMin) / (state.yMax - state.yMin) * ph - 3
						)
					end
				end
			end

			for k = dotIndex + 1, #dots do
				dots[k].Visible = false
			end

			if snapped then
				crossLine.Visible = true
				crossLine.Position =
					UDim2.fromOffset(math.floor((snapped - state.xMin) / (state.xMax - state.xMin) * pw), 0)

				if tip then
					tip:SetText(table.concat(lines, "\n"))
				end
			else
				hideHover()
			end
		end

		hit.MouseEnter:Connect(function(x, y)
			hovering = true
			lastMouse = Vector2.new(x, y)
		end)

		hit.MouseLeave:Connect(function()
			hovering = false
			hideHover()
		end)

		hit.MouseMoved:Connect(function(x, y)
			lastMouse = Vector2.new(x, y)

			if panning or selecting then
				hideHover()
				return
			end

			if options.crosshair ~= false then
				updateHover(x)
			end
		end)

		local function updateSelection()
			if not selecting then
				selFrame.Visible = false
				selLabel.Visible = false
				return
			end

			local pw, ph = plotSize()
			local origin = plot.AbsolutePosition

			local x0 = math.clamp(selecting.start.X - origin.X, 0, pw)
			local x1 = math.clamp(selecting.current.X - origin.X, 0, pw)
			local y0 = math.clamp(selecting.start.Y - origin.Y, 0, ph)
			local y1 = math.clamp(selecting.current.Y - origin.Y, 0, ph)

			local left, right = math.min(x0, x1), math.max(x0, x1)
			local top, bottom = math.min(y0, y1), math.max(y0, y1)

			selecting.box = isShift()

			if not selecting.box then
				top, bottom = 0, ph
			end

			selecting.rect = { left = left, right = right, top = top, bottom = bottom }

			selFrame.Visible = true
			selFrame.Position = UDim2.fromOffset(left, top)
			selFrame.Size = UDim2.fromOffset(right - left, bottom - top)

			local width = (right - left) / pw * (state.xMax - state.xMin)

			selLabel.Visible = true
			selLabel.Text = " " .. formatValue(width)
			selLabel.Position = UDim2.fromOffset(
				math.clamp((left + right) / 2 - 60, 0, math.max(pw - 120, 0)),
				math.clamp(top + 4, 0, math.max(ph - 20, 0))
			)
		end

		if interactive then
			hit.MouseButton1Down:Connect(function(x, y)
				lastMouse = Vector2.new(x, y)

				local now = os.clock()

				if now - lastClick < 0.3 then
					lastClick = 0
					panning = nil
					controller_AutoFit()
					return
				end

				lastClick = now

				state.target = nil

				panning = {
					loc = UserInputService:GetMouseLocation(),
					view = { xMin = state.xMin, xMax = state.xMax, yMin = state.yMin, yMax = state.yMax },
					movedY = false,
				}

				if tip then
					tip:Hide()
				end

				hideHover()
			end)

			hit.MouseButton2Down:Connect(function(x, y)
				lastMouse = Vector2.new(x, y)

				state.target = nil

				selecting = {
					start = Vector2.new(x, y),
					current = Vector2.new(x, y),
					loc = UserInputService:GetMouseLocation(),
				}

				if tip then
					tip:Hide()
				end

				hideHover()
				updateSelection()
			end)

			table.insert(
				connections,
				UserInputService.InputChanged:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseWheel then
						if not hovering or panning or selecting then
							return
						end

						local steps = input.Position.Z

						if steps == 0 then
							return
						end

						local factor = (options.zoomSpeed or 0.8) ^ steps

						local pw, ph = plotSize()
						local origin = plot.AbsolutePosition

						local fx = math.clamp((lastMouse.X - origin.X) / pw, 0, 1)
						local fy = 1 - math.clamp((lastMouse.Y - origin.Y) / ph, 0, 1)

						local shift, ctrl = isShift(), isCtrl()

						local partial = {}

						if (not shift or ctrl) and options.zoomX ~= false then
							for k, v in pairs(zoomAxis("x", fx, factor)) do
								partial[k] = v
							end
						end

						if (shift or ctrl) and options.zoomY ~= false then
							for k, v in pairs(zoomAxis("y", fy, factor)) do
								partial[k] = v
							end
						end

						if next(partial) then
							setTarget(partial, false)
							hideHover()
						end
					elseif input.UserInputType == Enum.UserInputType.MouseMovement then
						if panning then
							local loc = UserInputService:GetMouseLocation()
							local dx, dy = loc.X - panning.loc.X, loc.Y - panning.loc.Y

							local pw, ph = plotSize()
							local v = panning.view
							local a = state.auto

							local shiftX = dx / pw * (v.xMax - v.xMin)
							local nx0, nx1 = clampAxis(v.xMin - shiftX, v.xMax - shiftX, a.xMin, a.xMax)

							state.fixed.xMin, state.fixed.xMax = nx0, nx1

							if options.panY ~= false and (panning.movedY or math.abs(dy) > 4) then
								panning.movedY = true

								local shiftY = dy / ph * (v.yMax - v.yMin)
								local ny0, ny1 = clampAxis(v.yMin + shiftY, v.yMax + shiftY, a.yMin, a.yMax)

								state.fixed.yMin, state.fixed.yMax = ny0, ny1
							end

							state.dirty = true
						elseif selecting then
							local loc = UserInputService:GetMouseLocation()

							selecting.current = selecting.start + (loc - selecting.loc)

							updateSelection()
						end
					end
				end)
			)

			table.insert(
				connections,
				UserInputService.InputEnded:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 then
						if panning then
							panning = nil

							if tip and hovering then
								tip:Show()
							end
						end
					elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
						if selecting then
							local sel = selecting
							selecting = nil

							updateSelection()

							local rect = sel.rect

							if rect and rect.right - rect.left >= 4 then
								local pw, ph = plotSize()
								local a = state.auto

								local dx = state.xMax - state.xMin
								local x0 = state.xMin + rect.left / pw * dx
								local x1 = state.xMin + rect.right / pw * dx

								x0, x1 = clampAxis(x0, x1, a.xMin, a.xMax)

								local partial = { xMin = x0, xMax = x1 }

								if sel.box and rect.bottom - rect.top >= 4 then
									local dy = state.yMax - state.yMin
									local y1 = state.yMax - rect.top / ph * dy
									local y0 = state.yMax - rect.bottom / ph * dy

									y0, y1 = clampAxis(y0, y1, a.yMin, a.yMax)

									partial.yMin, partial.yMax = y0, y1
								end

								setTarget(partial, false)
							end

							if tip and hovering then
								tip:Show()
							end
						end
					end
				end)
			)
		end

		table.insert(
			connections,
			RunService.Heartbeat:Connect(function(dt)
				if state.destroyed then
					return
				end

				local target = state.target

				if target then
					local speed = options.smoothSpeed or 16
					local done = true

					for key, goal in pairs(target) do
						local axis = string.sub(key, 1, 1)
						local span = math.max(state[axis .. "Max"] - state[axis .. "Min"], 1e-12)

						local current = state.fixed[key]

						if current == nil then
							current = state[key]
						end

						local nextValue = tooltipSmoothTowards(current, goal, speed, dt)

						if math.abs(nextValue - goal) < span * 1e-4 then
							nextValue = goal
						else
							done = false
						end

						state.fixed[key] = nextValue
					end

					if done then
						state.target = nil

						if state.clearAfter then
							state.fixed = {}
							state.clearAfter = false
						end
					end

					state.dirty = true
				end

				if state.dirty then
					state.dirty = false
					redraw()
				end
			end)
		)

		pcall(function()
			plot:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
				state.dirty = true
			end)
		end)

		local function normalize(config, index)
			return {
				name = tostring(config.name or ("Series " .. index)),
				values = config.values or {},
				xs = config.xs,
				x0 = config.xStart or 0,
				color = config.color or palette[((index - 1) % #palette) + 1],
				fill = config.fill ~= nil and config.fill or options.fill ~= false,
				fillTransparency = config.fillTransparency or options.fillTransparency or 0.8,
				thickness = config.thickness or options.thickness or 1.5,
				visible = config.visible ~= false,
			}
		end

		local function find(name)
			for _, s in ipairs(state.series) do
				if s.name == name then
					return s
				end
			end

			return nil
		end

		local controller = { frame = container, plot = plot }

		function controller:SetSeries(list)
			state.series = {}

			for index, config in ipairs(list or {}) do
				table.insert(state.series, normalize(config, index))
			end

			invalidate()
			buildLegend()
			redraw()
		end

		function controller:AddSeries(config)
			table.insert(state.series, normalize(config, #state.series + 1))

			invalidate()
			buildLegend()
			redraw()
		end

		function controller:SetValues(name, values, xs)
			local s = find(name)

			if not s then
				return false
			end

			s.values = values or {}
			s.xs = xs

			invalidate()
			redraw()

			return true
		end

		function controller:Push(name, value, maxPoints)
			local s = find(name)

			if not s then
				return false
			end

			table.insert(s.values, value)

			if s.xs then
				table.insert(s.xs, (s.xs[#s.xs] or -1) + 1)
			end

			if maxPoints then
				while #s.values > maxPoints do
					table.remove(s.values, 1)

					if s.xs then
						table.remove(s.xs, 1)
					else
						s.x0 += 1
					end
				end
			end

			invalidate()
			state.dirty = true

			return true
		end

		function controller:SetRange(xMin, xMax, yMin, yMax)
			state.fixed = { xMin = xMin, xMax = xMax, yMin = yMin, yMax = yMax }
			state.target = nil

			redraw()
		end

		function controller:SetView(xMin, xMax, yMin, yMax, animate)
			local partial = { xMin = xMin, xMax = xMax, yMin = yMin, yMax = yMax }

			if animate == false then
				for key, value in pairs(partial) do
					state.fixed[key] = value
				end

				state.target = nil
				redraw()
			else
				setTarget(partial, false)
			end
		end

		function controller:ZoomTo(x0, x1, animate)
			self:SetView(x0, x1, nil, nil, animate)
		end

		function controller:GetView()
			return state.xMin, state.xMax, state.yMin, state.yMax
		end

		function controller:AutoFit(animate)
			if animate == false then
				state.fixed = {}
				state.target = nil
				redraw()
				return
			end

			local a = state.auto

			setTarget({ xMin = a.xMin, xMax = a.xMax, yMin = a.yMin, yMax = a.yMax }, true)
		end

		controller_AutoFit = function()
			controller:AutoFit()
		end

		function controller:SetTitle(text)
			state.title = text
			redraw()
		end

		function controller:SetLabels(xLabel, yLabel)
			state.xLabel = xLabel
			state.yLabel = yLabel
			redraw()
		end

		function controller:SetSeriesVisible(name, visible)
			local s = find(name)

			if not s then
				return false
			end

			s.visible = visible == true

			invalidate()
			buildLegend()
			redraw()

			return true
		end

		function controller:GetSeries(name)
			return find(name)
		end

		function controller:Redraw()
			redraw()
		end

		function controller:Destroy()
			if state.destroyed then
				return
			end

			state.destroyed = true

			for _, connection in ipairs(connections) do
				connection:Disconnect()
			end

			if tip then
				tip:Destroy()
			end

			UI.forgetButtons(container)
			container:Destroy()
		end

		for index, config in ipairs(options.series or {}) do
			table.insert(state.series, normalize(config, index))
		end

		buildLegend()
		redraw()

		return container, controller
	end
end

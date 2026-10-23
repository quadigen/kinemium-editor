local RunService = game:GetService("RunService")

return function(ctx)
	local UI = ctx.UI
	local colors = UI.tokens.color
	local tooltipSmoothTowards = ctx.tooltipSmoothTowards

	function UI.rangeSlider(parent, position, size, minimum, maximum, low, high, callback, options)
		options = options or {}

		local colors = UI.tokens.color

		minimum = minimum or 0
		maximum = maximum or 1

		low = math.clamp(low or minimum, minimum, maximum)
		high = math.clamp(high or maximum, minimum, maximum)

		if low > high then
			low, high = high, low
		end

		local step = options.step or 0
		local dragging = nil

		local animate = options.animate ~= false
		local animationSpeed = options.animationSpeed or 18

		local displayLow, displayHigh = low, high
		local heartbeat = nil

		local container = UI.create("TextButton", {
			Text = "",
			Position = position or UDim2.fromOffset(0, 0),
			Size = size or UDim2.fromOffset(160, UI.metrics.inputHeight),

			BackgroundTransparency = 1,
			BorderSizePixel = 0,

			Active = true,
			InputSink = true,
			AutoButtonColor = false,
		}, parent)

		local trackHeight = options.trackHeight or 4

		local track = UI.frame(
			container,
			UDim2.new(0, 0, 0.5, -math.floor(trackHeight / 2)),
			UDim2.new(1, 0, 0, trackHeight),
			options.trackColor or colors.input,
			math.floor(trackHeight / 2)
		)

		local fill = UI.frame(
			track,
			UDim2.fromOffset(0, 0),
			UDim2.fromOffset(0, trackHeight),
			options.fillColor or colors.accent,
			math.floor(trackHeight / 2)
		)

		local knobSize = options.knobSize or 12

		local lowKnob = UI.frame(
			container,
			UDim2.fromOffset(0, 0),
			UDim2.fromOffset(knobSize, knobSize),
			options.knobColor or colors.text,
			math.floor(knobSize / 2)
		)

		local highKnob = UI.frame(
			container,
			UDim2.fromOffset(0, 0),
			UDim2.fromOffset(knobSize, knobSize),
			options.knobColor or colors.text,
			math.floor(knobSize / 2)
		)

		UI.stroke(lowKnob, options.knobBorderColor or colors.borderStrong, 1, 0)
		UI.stroke(highKnob, options.knobBorderColor or colors.borderStrong, 1, 0)

		local function alpha(value)
			if maximum == minimum then
				return 0
			end

			return math.clamp((value - minimum) / (maximum - minimum), 0, 1)
		end

		local function redraw()
			local lowAlpha = alpha(displayLow)
			local highAlpha = alpha(displayHigh)

			fill.Position = UDim2.new(lowAlpha, 0, 0, 0)
			fill.Size = UDim2.new(math.max(highAlpha - lowAlpha, 0), 0, 1, 0)

			lowKnob.Position = UDim2.new(lowAlpha, -math.floor(knobSize / 2), 0.5, -math.floor(knobSize / 2))

			highKnob.Position = UDim2.new(highAlpha, -math.floor(knobSize / 2), 0.5, -math.floor(knobSize / 2))
		end

		local function stopAnimation()
			if heartbeat then
				heartbeat:Disconnect()
				heartbeat = nil
			end
		end

		local function snapVisual()
			stopAnimation()

			displayLow, displayHigh = low, high

			redraw()
		end

		local function wake()
			if not animate or dragging then
				snapVisual()

				return
			end

			if heartbeat then
				return
			end

			heartbeat = RunService.Heartbeat:Connect(function(dt)
				displayLow = tooltipSmoothTowards(displayLow, low, animationSpeed, dt)
				displayHigh = tooltipSmoothTowards(displayHigh, high, animationSpeed, dt)

				local finished = math.abs(displayLow - low) < 0.0005 and math.abs(displayHigh - high) < 0.0005

				if finished then
					displayLow, displayHigh = low, high
				end

				redraw()

				if finished then
					stopAnimation()
				end
			end)
		end

		container.Destroying:Connect(stopAnimation)

		local function valueFromPoint(x)
			local position = track.AbsolutePosition
			local absoluteSize = track.AbsoluteSize

			if not position or not absoluteSize or absoluteSize.X <= 0 then
				return nil
			end

			local a = math.clamp((x - position.X) / absoluteSize.X, 0, 1)
			local value = minimum + (maximum - minimum) * a

			if step > 0 then
				value = math.floor((value - minimum) / step + 0.5) * step + minimum
			end

			return math.clamp(value, minimum, maximum)
		end

		local function chooseKnob(x)
			local value = valueFromPoint(x)

			if value == nil then
				return
			end

			if math.abs(value - low) <= math.abs(value - high) then
				dragging = "low"
			else
				dragging = "high"
			end
		end

		local function updateFromPoint(x, silent)
			local value = valueFromPoint(x)

			if value == nil then
				return
			end

			if dragging == "low" then
				low = math.min(value, high)
			elseif dragging == "high" then
				high = math.max(value, low)
			else
				return
			end

			displayLow, displayHigh = low, high

			redraw()

			if not silent and callback then
				callback(low, high)
			end
		end

		container.MouseButton1Down:Connect(function(x)
			stopAnimation()

			chooseKnob(x)

			if options.onBegin then
				options.onBegin()
			end

			updateFromPoint(x)
		end)

		container.MouseMoved:Connect(function(x)
			if dragging then
				updateFromPoint(x)
			end
		end)

		container.MouseButton1Up:Connect(function(x)
			if dragging then
				updateFromPoint(x)
			end

			dragging = nil

			if options.onEnd then
				options.onEnd()
			end
		end)

		local controller = {
			frame = container,
			track = track,
			fill = fill,
			lowKnob = lowKnob,
			highKnob = highKnob,
		}

		function controller:GetValues()
			return low, high
		end

		function controller:SetValues(newLow, newHigh, silent, instant)
			low = math.clamp(newLow, minimum, maximum)
			high = math.clamp(newHigh, minimum, maximum)

			if low > high then
				low, high = high, low
			end

			if instant then
				snapVisual()
			else
				wake()
			end

			if not silent and callback then
				callback(low, high)
			end
		end

		function controller:SetRange(newMinimum, newMaximum)
			minimum = newMinimum
			maximum = newMaximum

			low = math.clamp(low, minimum, maximum)
			high = math.clamp(high, minimum, maximum)

			snapVisual()
		end

		redraw()

		return container, controller
	end
end

local RunService = game:GetService("RunService")

return function(ctx)
	local UI = ctx.UI
	local colors = UI.tokens.color
	local tooltipSmoothTowards = ctx.tooltipSmoothTowards

	function UI.slider(parent, position, size, minimum, maximum, value, callback, options)
		options = options or {}

		local colors = UI.tokens.color

		minimum = minimum or 0

		maximum = maximum or 1

		value = math.clamp(value or minimum, minimum, maximum)

		local step = options.step or 0

		local dragging = false

		local animate = options.animate ~= false
		local animationSpeed = options.animationSpeed or 20

		local displayValue = value
		local heartbeat = nil

		local container = UI.create("TextButton", {

			Text = "",

			Position = position or UDim2.fromOffset(0, 0),

			Size = size or UDim2.fromOffset(160, UI.metrics.inputHeight),

			BackgroundColor3 = colors.panel,

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
			UDim2.new(0, 0, 1, 0),
			options.fillColor or colors.accent,
			math.floor(trackHeight / 2)
		)

		local knobSize = options.knobSize or 12

		local knob = UI.frame(
			container,
			UDim2.fromOffset(0, 0),
			UDim2.fromOffset(knobSize, knobSize),
			options.knobColor or colors.text,
			math.floor(knobSize / 2)
		)

		UI.stroke(knob, options.knobBorderColor or colors.borderStrong, 1, options.knobBorderTransparency or 0)

		local function alphaFromValue(input)
			if maximum == minimum then
				return 0
			end

			return math.clamp((input - minimum) / (maximum - minimum), 0, 1)
		end

		local function redraw()
			local alpha = alphaFromValue(displayValue)

			fill.Size = UDim2.new(alpha, 0, 1, 0)

			knob.Position = UDim2.new(alpha, -math.floor(knobSize / 2), 0.5, -math.floor(knobSize / 2))
		end

		local function stopAnimation()
			if heartbeat then
				heartbeat:Disconnect()
				heartbeat = nil
			end
		end

		local function snapVisual()
			stopAnimation()

			displayValue = value

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
				displayValue = tooltipSmoothTowards(displayValue, value, animationSpeed, dt)

				local finished = math.abs(displayValue - value) < 0.0005

				if finished then
					displayValue = value
				end

				redraw()

				if finished then
					stopAnimation()
				end
			end)
		end

		container.Destroying:Connect(stopAnimation)

		local function setFromPoint(pointX, silent)
			local absolutePosition = track.AbsolutePosition

			local absoluteSize = track.AbsoluteSize

			if not absolutePosition or not absoluteSize or absoluteSize.X <= 0 then
				return
			end

			local alpha = math.clamp((pointX - absolutePosition.X) / absoluteSize.X, 0, 1)

			local newValue = minimum + (maximum - minimum) * alpha

			if step > 0 then
				newValue = math.floor((newValue - minimum) / step + 0.5) * step + minimum
			end

			newValue = math.clamp(newValue, minimum, maximum)

			if newValue == value then
				return
			end

			value = newValue
			displayValue = newValue

			redraw()

			if not silent and callback then
				callback(value)
			end
		end

		container.MouseButton1Down:Connect(function(x)
			stopAnimation()

			dragging = true

			setFromPoint(x)
		end)

		container.MouseMoved:Connect(function(x)
			if not dragging then
				return
			end

			setFromPoint(x)
		end)

		container.MouseButton1Up:Connect(function(x)
			if dragging then
				setFromPoint(x)
			end

			dragging = false
		end)

		local controller = {}

		function controller:GetValue()
			return value
		end

		function controller:SetValue(newValue, silent, instant)
			value = math.clamp(newValue, minimum, maximum)

			if step > 0 then
				value = math.floor((value - minimum) / step + 0.5) * step + minimum
			end

			if instant then
				snapVisual()
			else
				wake()
			end

			if not silent and callback then
				callback(value)
			end
		end

		function controller:SetRange(newMinimum, newMaximum)
			minimum = newMinimum

			maximum = newMaximum

			value = math.clamp(value, minimum, maximum)

			snapVisual()
		end

		controller.frame = container

		controller.track = track

		controller.fill = fill

		controller.knob = knob

		redraw()

		return container, controller
	end
end

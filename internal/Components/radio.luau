return function(ctx)
	local UI = ctx.UI
	local colors = UI.tokens.color

	function UI.radio(parent, text, position, selected, callback, options)
		options = options or {}

		local colors = UI.tokens.color

		local value = selected == true
		local enabled = options.enabled ~= false

		local circleSize = options.circleSize or 18
		local dotSize = options.dotSize or 8

		local container = UI.frame(
			parent,
			position or UDim2.fromOffset(0, 0),
			options.size or UDim2.fromOffset(180, UI.metrics.propertyRow),
			colors.panel
		)

		container.BackgroundTransparency = 1

		local circle, record, dot, stroke, textLabel

		local function redraw()
			dot.Visible = value

			local base = options.color or colors.input

			record.color = base
			record.defaultColor = base

			circle.BackgroundColor3 = base

			if stroke then
				stroke.Color = value and (options.selectedBorderColor or colors.accent)
					or (options.borderColor or colors.border)
			end

			textLabel.TextColor3 = enabled and (options.textColor or colors.text) or colors.muted
		end

		local function select()
			if not enabled or value then
				return
			end

			value = true

			redraw()

			if callback then
				callback(true)
			end
		end

		circle, _, record = UI.button(
			container,
			"",
			UDim2.fromOffset(0, math.floor((UI.metrics.propertyRow - circleSize) / 2)),
			UDim2.fromOffset(circleSize, circleSize),
			select,
			{
				color = options.color or colors.input,
				hoverColor = colors.hover,
				pressedColor = colors.pressed,
				radius = math.floor(circleSize / 2),
				borderColor = colors.border,
				paddingX = 0,
				enabled = enabled,
			}
		)

		stroke = circle:FindFirstChildOfClass("UIStroke")

		dot = UI.frame(
			circle,
			UDim2.new(0.5, -math.floor(dotSize / 2), 0.5, -math.floor(dotSize / 2)),
			UDim2.fromOffset(dotSize, dotSize),
			options.dotColor or colors.accent,
			math.floor(dotSize / 2)
		)

		textLabel = UI.label(
			container,
			text,
			UDim2.fromOffset(circleSize + 7, 1),
			UDim2.new(1, -(circleSize + 7), 1, -1),
			options.textSize or UI.tokens.type.small,
			options.textColor or colors.text
		)

		textLabel.TextXAlignment = Enum.TextXAlignment.Left

		local textButton = UI.create("TextButton", {
			Text = "",
			Position = UDim2.fromOffset(circleSize + 4, 0),
			Size = UDim2.new(1, -(circleSize + 4), 1, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Active = true,
			InputSink = true,
		}, container)

		textButton.MouseButton1Click:Connect(select)

		local controller = {}

		function controller:GetValue()
			return value
		end

		function controller:SetValue(newValue, silent)
			newValue = newValue == true

			if value == newValue then
				return
			end

			value = newValue

			redraw()

			if not silent and callback then
				callback(value)
			end
		end

		function controller:SetText(newText)
			textLabel.Text = tostring(newText or "")
		end

		function controller:SetEnabled(newEnabled)
			enabled = newEnabled == true

			record.enabled = enabled
			circle.Active = enabled
			textButton.Active = enabled

			redraw()
		end

		controller.frame = container
		controller.circle = circle
		controller.dot = dot
		controller.label = textLabel
		controller.record = record

		redraw()

		return container, controller
	end
end

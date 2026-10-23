local RunService = game:GetService("RunService")

return function(ctx)
	local UI = ctx.UI
	local tooltipSmoothTowards = ctx.tooltipSmoothTowards

	function UI.input(parent, placeholder, position, size, options)
		options = options or {}

		local field = UI.create("TextBox", {

			Position = position or UDim2.fromOffset(0, 0),

			Size = size or UDim2.fromOffset(100, UI.metrics.inputHeight),

			BackgroundColor3 = options.color or UI.tokens.color.input,

			BorderSizePixel = 0,

			Text = options.text or "",

			PlaceholderText = tostring(placeholder or ""),

			TextSize = options.textSize or UI.tokens.type.small,

			TextColor3 = options.textColor or UI.tokens.color.text,

			PlaceholderColor3 = options.placeholderColor or UI.tokens.color.muted,

			TextTransparency = options.textTransparency or 0,

			TextEditable = options.textEditable ~= false,

			ClearTextOnFocus = options.clearTextOnFocus == true,

			SelectAllOnFocus = options.selectAllOnFocus == true,

			MaxLength = options.maxLength or -1,

			CaretColor3 = options.caretColor or UI.tokens.color.accent,

			SelectionColor3 = options.selectionColor or UI.tokens.color.selection,

			SelectionTransparency = options.selectionTransparency or 0.65,

			FocusColor3 = options.focusColor or UI.tokens.color.focus,

			Active = true,

			InputSink = true,
		}, parent)

		local squircle = Instance.new("UISquircle")
		squircle.Parent = field

		local stroke = UI.stroke(
			field,
			options.borderColor or UI.tokens.color.border,
			options.strokeThickness or 1,
			options.strokeTransparency or 0
		)

		local animate = options.animate ~= false
		local focusSpeed = options.focusSpeed or 16
		local focusTarget = 0
		local focusAlpha = 0
		local focusHeartbeat = nil
		local baseColor = stroke.Color
		local baseTransparency = stroke.Transparency

		local function focusColor()
			return options.focusColor or UI.tokens.color.focus
		end

		local function applyFocus()
			stroke.Color = baseColor:Lerp(focusColor(), focusAlpha)

			local targetTransparency = options.focusTransparency or 0

			stroke.Transparency = baseTransparency + (targetTransparency - baseTransparency) * focusAlpha
		end

		local function stopFocusAnimation()
			if focusHeartbeat then
				focusHeartbeat:Disconnect()
				focusHeartbeat = nil
			end
		end

		local function setFocus(target, snap)
			focusTarget = target

			if snap or not animate then
				stopFocusAnimation()

				focusAlpha = target

				applyFocus()

				return
			end

			if focusHeartbeat then
				return
			end

			focusHeartbeat = RunService.Heartbeat:Connect(function(dt)
				focusAlpha = tooltipSmoothTowards(focusAlpha, focusTarget, focusSpeed, dt)

				local finished = math.abs(focusAlpha - focusTarget) < 0.005

				if finished then
					focusAlpha = focusTarget
				end

				applyFocus()

				if finished then
					stopFocusAnimation()
				end
			end)
		end

		field.FocusLost:Connect(function()
			setFocus(0, false)
		end)

		field.Destroying:Connect(stopFocusAnimation)

		return field, field, stroke
	end
end

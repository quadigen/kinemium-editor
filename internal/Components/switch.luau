local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

return function(ctx)
	local UI = ctx.UI
	local colors = UI.tokens.color
	local tooltipSmoothTowards = ctx.tooltipSmoothTowards

	function UI.switch(parent, position, value, callback, options)
		options = options or {}

		local colors = UI.tokens.color

		local enabled = value == true

		local width = options.width or 34
		local height = options.height or 18
		local knobSize = height - 6
		local pad = 3

		local animate = options.animate ~= false
		local speed = options.animationSpeed or 22
		local pressStretch = options.pressStretch or 3

		local track
		local knob
		local record

		local state = {
			alpha = enabled and 1 or 0, -- 0 = off, 1 = on
			hover = 0,
			press = 0,
			hovered = false,
			pressed = false,
			destroyed = false,
		}

		local function render()
			local enabledColor = options.enabledColor or colors.accent
			local disabledColor = options.disabledColor or colors.input

			-- track colour: off -> on, with subtle hover lighten / press darken
			local color = disabledColor:Lerp(enabledColor, state.alpha)
			color = color:Lerp(Color3.new(1, 1, 1), 0.08 * state.hover)
			color = color:Lerp(Color3.new(0, 0, 0), 0.1 * state.press)

			track.BackgroundColor3 = color

			-- knob stretches slightly while pressed (iOS style), staying inside the track
			local knobWidth = knobSize + pressStretch * state.press
			local left = pad + (width - pad * 2 - knobWidth) * state.alpha

			knob.Size = UDim2.fromOffset(knobWidth, knobSize)
			knob.Position = UDim2.new(0, left, 0.5, -math.floor(knobSize / 2))
		end

		track, _, record = UI.button(parent, "", position, UDim2.fromOffset(width, height), function()
			enabled = not enabled

			if not animate then
				state.alpha = enabled and 1 or 0
				render()
			end

			if callback then
				callback(enabled)
			end
		end, {
			color = colors.input,
			hoverColor = colors.hover,
			pressedColor = colors.pressed,
			radius = math.floor(height / 2),
			borderColor = colors.border,
			paddingX = 0,
			hoveringEnabled = false, -- we drive hover/press colours ourselves
		})

		knob = UI.frame(
			track,
			UDim2.fromOffset(pad, pad),
			UDim2.fromOffset(knobSize, knobSize),
			options.knobColor or colors.text,
			math.floor(knobSize / 2)
		)

		track.MouseEnter:Connect(function()
			state.hovered = true
		end)

		track.MouseLeave:Connect(function()
			state.hovered = false
		end)

		track.MouseButton1Down:Connect(function()
			state.pressed = true
		end)

		-- MouseButton1Up only fires over the button, so release is tracked globally
		local inputEnded = UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				state.pressed = false
			end
		end)

		local heartbeat

		local function cleanup()
			if state.destroyed then
				return
			end

			state.destroyed = true

			if heartbeat then
				heartbeat:Disconnect()
				heartbeat = nil
			end

			inputEnded:Disconnect()
		end

		heartbeat = RunService.Heartbeat:Connect(function(dt)
			if state.destroyed then
				return
			end

			if not UI.isAlive(track) then
				cleanup()
				return
			end

			local alphaTarget = enabled and 1 or 0
			local hoverTarget = (state.hovered and not state.pressed) and 1 or 0
			local pressTarget = state.pressed and 1 or 0

			if animate then
				state.alpha = tooltipSmoothTowards(state.alpha, alphaTarget, speed, dt)
				state.hover = tooltipSmoothTowards(state.hover, hoverTarget, speed, dt)
				state.press = tooltipSmoothTowards(state.press, pressTarget, speed * 1.6, dt)

				if math.abs(state.alpha - alphaTarget) < 0.005 then
					state.alpha = alphaTarget
				end

				if math.abs(state.hover - hoverTarget) < 0.005 then
					state.hover = hoverTarget
				end

				if math.abs(state.press - pressTarget) < 0.005 then
					state.press = pressTarget
				end
			else
				state.alpha, state.hover, state.press = alphaTarget, hoverTarget, pressTarget
			end

			render()
		end)

		track.Destroying:Connect(cleanup)

		local controller = {}

		function controller:GetValue()
			return enabled
		end

		function controller:SetValue(newValue, silent, instant)
			enabled = newValue == true

			if instant or not animate then
				state.alpha = enabled and 1 or 0
				render()
			end

			if not silent and callback then
				callback(enabled)
			end
		end

		function controller:Destroy()
			cleanup()
			UI.forgetButtons(track)
			track:Destroy()
		end

		controller.track = track
		controller.knob = knob
		controller.record = record

		render()

		return track, controller
	end
end

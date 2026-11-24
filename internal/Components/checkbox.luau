local UserInputService = game:GetService("UserInputService")

return function(ctx)
	local UI = ctx.UI
	local colors = UI.tokens.color
	local tooltipSmoothTowards = ctx.tooltipSmoothTowards

	function UI.checkbox(parent, text, position, checked, callback, options)
		options = options or {}

		local colors = UI.tokens.color

		local value = checked == true

		local boxSize = options.boxSize or 18
		local markSize = options.markSize or 12
		local markIcon = options.markIcon or "builtin://global-icons/check.svg"

		local animate = options.animate ~= false
		local speed = options.animationSpeed or 22
		local pressShrink = options.pressShrink or 0.15 -- fraction the mark shrinks while pressed

		local container = UI.frame(
			parent,
			position or UDim2.fromOffset(0, 0),
			options.size or UDim2.fromOffset(180, UI.metrics.propertyRow),
			colors.panel
		)

		container.BackgroundTransparency = 1

		local box
		local mark
		local record
		local stroke

		local state = {
			alpha = value and 1 or 0, -- 0 = unchecked, 1 = checked
			hover = 0,
			press = 0,
			hovered = false,
			pressed = false,
			destroyed = false,
		}

		-- overshoot curve so the checkmark "pops" in
		local function easeOutBack(t)
			local c1 = 1.70158
			local c3 = c1 + 1
			return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
		end

		local wake
		local function render()
			local uncheckedColor = options.color or colors.input
			local checkedColor = options.checkedColor or colors.accent

			-- box colour: unchecked -> checked
			local color = uncheckedColor:Lerp(checkedColor, state.alpha)

			-- hover: unchecked boxes move toward the hover colour, checked boxes lighten slightly
			color = color:Lerp(colors.hover, state.hover * (1 - state.alpha))
			color = color:Lerp(Color3.new(1, 1, 1), 0.08 * state.hover * state.alpha)

			-- press: darken
			color = color:Lerp(Color3.new(0, 0, 0), 0.1 * state.press)

			box.BackgroundColor3 = color

			-- border blends toward the accent as the box gets checked
			if stroke then
				stroke.Color = (options.borderColor or colors.border):Lerp(checkedColor, state.alpha)
			end

			-- checkmark: fade + scale in with overshoot, shrinks a little while pressed
			local a = math.clamp(state.alpha, 0, 1)
			local scale = value and easeOutBack(a) or a
			scale *= 1 - pressShrink * state.press

			local size = math.max(math.floor(markSize * scale + 0.5), 0)

			mark.Visible = a > 0.001
			mark.Size = UDim2.fromOffset(size, size)
			mark.ImageTransparency = 1 - math.clamp(a * 1.6, 0, 1)
		end

		box, _, record = UI.button(
			container,
			"",
			UDim2.fromOffset(0, math.floor((UI.metrics.propertyRow - boxSize) / 2)),
			UDim2.fromOffset(boxSize, boxSize),
			function()
				value = not value

				wake()

				if callback then
					callback(value)
				end
			end,
			{
				color = colors.input,

				hoverColor = colors.hover,

				pressedColor = colors.pressed,

				radius = options.radius or UI.tokens.radius.xs,

				borderColor = colors.border,

				paddingX = 0,

				hoveringEnabled = false, -- hover/press colours are driven by the animation
			}
		)

		stroke = box:FindFirstChildOfClass("UIStroke")

		mark = UI.image(box, markIcon, UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(markSize, markSize))

		mark.Name = "Mark"
		mark.AnchorPoint = Vector2.new(0.5, 0.5)

		local textLabel = UI.label(
			container,
			text,
			UDim2.fromOffset(boxSize + 7, 1),
			UDim2.new(1, -(boxSize + 7), 1, -1),
			options.textSize or UI.tokens.type.small,
			options.textColor or colors.text
		)

		textLabel.TextYAlignment = Enum.TextYAlignment.Center
		textLabel.TextXAlignment = Enum.TextXAlignment.Left

		local animation
		local inputEnded
		local themeListener

		local function release()
			if inputEnded then
				inputEnded:Disconnect()
				inputEnded = nil
			end
			if state.pressed then
				state.pressed = false
				wake()
			end
		end

		local function cleanup()
			if state.destroyed then return end
			state.destroyed = true
			animation:Destroy()
			if inputEnded then
				inputEnded:Disconnect()
				inputEnded = nil
			end
			if themeListener then
				themeListener.Disconnect()
			end
		end

		local function targets()
			return value and 1 or 0, (state.hovered and not state.pressed) and 1 or 0, state.pressed and 1 or 0
		end

		local function step(dt)
			if state.destroyed then return false end
			if not UI.isAlive(box) then
				cleanup()
				return false
			end
			local alphaTarget, hoverTarget, pressTarget = targets()
			if not ctx.isVisible(box) then
				state.hovered = false
				state.pressed = false
				if inputEnded then
					inputEnded:Disconnect()
					inputEnded = nil
				end
				hoverTarget, pressTarget = 0, 0
				state.alpha, state.hover, state.press = alphaTarget, hoverTarget, pressTarget
			elseif animate then
				state.alpha = tooltipSmoothTowards(state.alpha, alphaTarget, speed, dt)
				state.hover = tooltipSmoothTowards(state.hover, hoverTarget, speed, dt)
				state.press = tooltipSmoothTowards(state.press, pressTarget, speed * 1.6, dt)
				if math.abs(state.alpha - alphaTarget) < 0.005 then state.alpha = alphaTarget end
				if math.abs(state.hover - hoverTarget) < 0.005 then state.hover = hoverTarget end
				if math.abs(state.press - pressTarget) < 0.005 then state.press = pressTarget end
			else
				state.alpha, state.hover, state.press = alphaTarget, hoverTarget, pressTarget
			end
			render()
			return state.alpha ~= alphaTarget or state.hover ~= hoverTarget or state.press ~= pressTarget
		end

		animation = ctx.animations.newTask(step)
		wake = function()
			if state.destroyed then return end
			if not animate or not ctx.isVisible(box) then
				animation:Stop()
				step(0)
			else
				animation:Wake()
			end
		end

		box.MouseEnter:Connect(function()
			state.hovered = true
			wake()
		end)
		box.MouseLeave:Connect(function()
			state.hovered = false
			wake()
		end)
		box.MouseButton1Down:Connect(function()
			if state.destroyed then return end
			state.pressed = true
			if not inputEnded then
				inputEnded = UserInputService.InputEnded:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 then release() end
				end)
			end
			wake()
		end)
		themeListener = UI.onThemeChanged(wake)

		box.MouseButton1Up:Connect(function()
			if not state.destroyed then wake() end
		end)

		box.Destroying:Connect(cleanup)

		local controller = {}

		function controller:GetValue()
			return value
		end

		function controller:SetValue(newValue, silent, instant)
			if state.destroyed then return end
			local changed = value ~= (newValue == true)
			value = newValue == true

			if instant then
				state.alpha = value and 1 or 0
				render()
				local _, hoverTarget, pressTarget = targets()
				if state.hover == hoverTarget and state.press == pressTarget then
					animation:Stop()
				else
					wake()
				end
			elseif changed then
				wake()
			end

			if not silent and callback then
				callback(value)
			end
		end

		function controller:Destroy()
			cleanup()
			UI.forgetButtons(container)
			container:Destroy()
		end

		controller.frame = container

		controller.box = box

		controller.mark = mark

		controller.label = textLabel

		controller.record = record

		render()

		return container, controller
	end
end

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

return function(ctx)
	local UI = ctx.UI
	local tooltipSmoothTowards = ctx.tooltipSmoothTowards

	function UI.TopbarButton(parent, definition, options)
		options = options or {}

		local tokens = UI.tokens

		local radius = options.radius or tokens.radius.sm
		local size = options.size or UDim2.fromOffset(52, 58)
		local position = options.position or UDim2.fromOffset(0, 0)
		local onClick = options.onClick

		local iconSize = options.iconSize or 22
		local iconTop = 7

		local animate = options.animate ~= false
		local speed = options.animationSpeed or 22
		local hoverLift = options.hoverLift or 2 -- px the icon rises on hover
		local hoverScale = options.hoverScale or 0.08 -- icon grows by this fraction on hover
		local pressScale = options.pressScale or 0.12 -- icon shrinks by this fraction on press
		local hoverEnabled = options.hoveringEnabled ~= false

		local function pick(key, fallback)
			local override = options.colors and options.colors[key]
			return override or fallback
		end

		local function palette()
			local c = UI.tokens.color

			return {
				surface = pick("surface", c.surface),
				raised = pick("raised", c.panelRaised),
				input = pick("input", c.input),
				subtext = pick("subtext", c.subtext),
				text = pick("text", c.text),
				accent = pick("accent", c.accent),
			}
		end

		local initial = palette()

		local item, _, record = UI.button(parent, "", position, size, function() end, {
			color = initial.surface,
			hoverColor = initial.raised,
			pressedColor = initial.input,
			radius = radius,
			hoveringEnabled = false, -- hover/press colours are driven by the animation
			border = false,
		})

		item.Name = definition.name .. "Tool"

		local icon = nil

		if definition.icon then
			icon = UI.image(
				item,
				"builtin://icons/" .. definition.icon,
				UDim2.new(0.5, 0, 0, iconTop + math.floor(iconSize / 2)),
				UDim2.fromOffset(iconSize, iconSize)
			)

			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Name = "Icon"
		end

		local label = UI.label(
			item,
			definition.name,
			UDim2.fromOffset(4, 35),
			UDim2.new(1, -8, 0, 16),
			tokens.type.caption,
			initial.subtext
		)

		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextYAlignment = Enum.TextYAlignment.Top

		-- accent indicator that grows in when the button is selected
		local indicator = UI.frame(item, UDim2.new(0.5, 0, 1, -3), UDim2.new(0, 0, 0, 2), initial.accent, 1)

		indicator.AnchorPoint = Vector2.new(0.5, 1)
		indicator.Name = "Indicator"
		indicator.Visible = false

		local state = {
			hover = 0,
			press = 0,
			select = 0,
			hovered = false,
			pressed = false,
			selected = options.selected == true,
			running = true,
			destroyed = false,
		}

		state.select = state.selected and 1 or 0

		local function render()
			local p = palette()

			-- background: surface -> raised on hover/selected, -> input on press
			local color = p.surface:Lerp(p.raised, math.max(state.hover, state.select * 0.6))
			color = color:Lerp(p.input, state.press)

			item.BackgroundColor3 = color

			-- label brightens with hover / selection
			label.TextColor3 = p.subtext:Lerp(p.text, math.max(state.hover, state.select))

			if icon then
				local scale = 1 + hoverScale * state.hover - pressScale * state.press
				local px = math.max(math.floor(iconSize * scale + 0.5), 1)
				local lift = hoverLift * state.hover * (1 - state.press)

				icon.Size = UDim2.fromOffset(px, px)
				icon.Position = UDim2.new(0.5, 0, 0, iconTop + math.floor(iconSize / 2) - lift)
			end

			indicator.BackgroundColor3 = p.accent
			indicator.Visible = state.select > 0.001
			indicator.Size = UDim2.new(0.6 * state.select, 0, 0, 2)
		end

		local function wake()
			state.running = true
		end

		item.MouseEnter:Connect(function()
			state.hovered = true
			wake()
		end)

		item.MouseLeave:Connect(function()
			state.hovered = false
			wake()
		end)

		item.MouseButton1Down:Connect(function()
			state.pressed = true
			wake()
		end)

		-- MouseButton1Up only fires over the button, so release is tracked globally
		local inputEnded = UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				state.pressed = false
				wake()
			end
		end)

		if onClick then
			item.MouseButton1Click:Connect(function()
				onClick(item, definition)
			end)
		end

		local heartbeat
		local themeListener

		local function cleanup()
			if state.destroyed then
				return
			end

			state.destroyed = true

			if heartbeat then
				heartbeat:Disconnect()
				heartbeat = nil
			end

			if themeListener then
				themeListener.Disconnect()
				themeListener = nil
			end

			inputEnded:Disconnect()
		end

		-- repaint once when the theme changes, even if the button is idle
		themeListener = UI.onThemeChanged(function()
			if not state.destroyed then
				wake()
			end
		end)

		heartbeat = RunService.Heartbeat:Connect(function(dt)
			if state.destroyed then
				return
			end

			if not UI.isAlive(item) then
				cleanup()
				return
			end

			-- idle: nothing to animate
			if not state.running then
				return
			end

			local hoverTarget = (hoverEnabled and state.hovered and not state.pressed) and 1 or 0
			local pressTarget = (hoverEnabled and state.pressed) and 1 or 0
			local selectTarget = state.selected and 1 or 0

			local moving = false

			if animate then
				state.hover = tooltipSmoothTowards(state.hover, hoverTarget, speed, dt)
				state.press = tooltipSmoothTowards(state.press, pressTarget, speed * 1.6, dt)
				state.select = tooltipSmoothTowards(state.select, selectTarget, speed, dt)

				if math.abs(state.hover - hoverTarget) < 0.005 then
					state.hover = hoverTarget
				else
					moving = true
				end

				if math.abs(state.press - pressTarget) < 0.005 then
					state.press = pressTarget
				else
					moving = true
				end

				if math.abs(state.select - selectTarget) < 0.005 then
					state.select = selectTarget
				else
					moving = true
				end
			else
				state.hover, state.press, state.select = hoverTarget, pressTarget, selectTarget
			end

			render()

			state.running = moving
		end)

		item.Destroying:Connect(cleanup)

		local controller = {}

		function controller:SetSelected(selected, instant)
			state.selected = selected == true

			if instant or not animate then
				state.select = state.selected and 1 or 0
				render()
			end

			wake()
		end

		function controller:IsSelected()
			return state.selected
		end

		function controller:SetText(text)
			label.Text = tostring(text or "")
		end

		function controller:Destroy()
			cleanup()
			UI.forgetButtons(item)
			item:Destroy()
		end

		controller.button = item
		controller.label = label
		controller.icon = icon
		controller.indicator = indicator
		controller.record = record

		render()

		return item, label, controller
	end
end

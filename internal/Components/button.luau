return function(ctx)
	local UI = ctx.UI
	local shared = ctx.shared
	local colors = UI.tokens.color
	local pointInside = UI.pointInside

	local closeActiveDropdown = function(instant)
		if UI.closeDropdown then
			UI.closeDropdown(instant)
		end
	end

	local function wireNativeButton(button, record, enableHovering)
		button.MouseEnter:Connect(function()
			if record.enabled and enableHovering then
				button.BackgroundColor3 = record.hoverColor
			end
		end)

		button.MouseLeave:Connect(function()
			if enableHovering then
				button.BackgroundColor3 = record.color
			end
		end)

		button.MouseButton1Down:Connect(function()
			if not record.enabled then
				return
			end

			button.BackgroundColor3 = record.pressedColor
		end)

		button.MouseButton1Up:Connect(function(x, y)
			if not record.enabled then
				button.BackgroundColor3 = record.color
				return
			end

			local point = Vector2.new(x, y)

			if enableHovering and pointInside(button, point) then
				button.BackgroundColor3 = record.hoverColor
			else
				button.BackgroundColor3 = record.color
			end
		end)

		button.MouseButton1Click:Connect(function()
			if not record.enabled then
				return
			end

			local active = shared.activeDropdown

			if active and closeActiveDropdown and active.closeOnOutsideClick ~= false then
				local insideButton = button == active.button or button:IsDescendantOf(active.button)

				local insideMenu = active.menu and (button == active.menu or button:IsDescendantOf(active.menu))

				if not insideButton and not insideMenu then
					closeActiveDropdown()
				end
			end

			record.callback()
		end)
	end

	function UI.setButtonState(record, state)
		if not record or record.destroyed or not UI.isAlive(record.gui) then
			return
		end

		local colors = UI.tokens.color

		if state == "selected" then
			record.state = "selected"
			record.color, record.hoverColor = colors.selection, colors.selectionHover
		elseif state == "accent" then
			record.state = "accent"
			record.color, record.hoverColor = colors.accentSoft, colors.accent
		else
			record.state = nil
			record.color, record.hoverColor = record.defaultColor, record.defaultHoverColor
		end

		record.gui.BackgroundColor3 = record.color
	end

	function UI.button(parent, text, position, size, callback, options)
		options = options or {}

		local colors, padding = UI.tokens.color, options.paddingX or UI.tokens.space.md

		local color = options.color or colors.panelRaised

		local button = UI.create("TextButton", {
			Text = "",
			Position = position or UDim2.fromOffset(0, 0),
			Size = size or UDim2.fromOffset(100, UI.metrics.buttonHeight),
			BackgroundColor3 = color,
			BackgroundTransparency = options.bgTransparency,
			BorderSizePixel = 0,
			Active = options.enabled ~= false,
			InputSink = true,
			AutoButtonColor = false,
		}, parent)

		local radius = options.radius or UI.tokens.radius.sm

		if radius and radius > 0 then
			UI.corner(button, radius)
		end

		local label = UI.label(
			button,
			text,
			UDim2.fromOffset(padding, options.textY or 3),
			UDim2.new(1, -padding * 2, 1, -(options.textY or 3)),
			options.textSize or UI.tokens.type.small,
			options.textColor or colors.subtext
		)

		if options.icon then
			local iconSize = options.iconSize or 16

			UI.image(
				button,
				options.icon,
				UDim2.fromOffset(6, math.floor((((size and size.Y.Offset) or UI.metrics.buttonHeight) - iconSize) / 2)),
				UDim2.fromOffset(iconSize, iconSize)
			)

			label.Position = UDim2.fromOffset(iconSize + 12, options.textY or 3)
		end

		if options.border ~= false then
			UI.stroke(button, options.borderColor or colors.border, 1, options.borderTransparency or 0)
		end

		local record = {

			gui = button,

			callback = callback or function() end,

			color = color,

			defaultColor = color,

			hoverColor = options.hoverColor or colors.hover,

			defaultHoverColor = options.hoverColor or colors.hover,

			pressedColor = options.pressedColor or colors.pressed,

			enabled = options.enabled ~= false,
		}

		table.insert(shared.buttons, record)

		wireNativeButton(button, record, options.hoveringEnabled ~= false)

		if options.selected then
			UI.setButtonState(record, "selected")
		end

		return button, label, record
	end
end

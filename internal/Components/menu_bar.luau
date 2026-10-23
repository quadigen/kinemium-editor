local UserInputService = game:GetService("UserInputService")

return function(ctx)
	local UI = ctx.UI
	local colors = UI.tokens.color

	function UI.menuBar(parent, position, size, menus, options)
		options = options or {}

		local tokens = UI.tokens
		local colors = tokens.color

		local height = (size and size.Y.Offset) or options.height or 28
		local inset = options.inset or 3
		local gap = options.gap or 1
		local paddingX = options.paddingX or 10
		local textSize = options.textSize or tokens.type.small
		local charWidth = options.charWidth or (textSize * 0.6)
		local radius = options.radius or tokens.radius.md
		local triggerRadius = options.triggerRadius or tokens.radius.sm
		local menuGap = options.menuGap or 4

		local palette = {
			bar = options.color or colors.panel,
			border = options.borderColor or colors.border,
			hover = options.hoverColor or colors.hover,
			text = options.textColor or colors.text,
			subtext = options.subtextColor or colors.subtext,
		}

		local entries = {}
		local connections = {}
		local state = { open = nil, destroyed = false }

		-- width of the whole bar
		local totalWidth = inset * 2
		local widths = {}

		for index, definition in ipairs(menus or {}) do
			local width = definition.width or (math.ceil(#tostring(definition.name) * charWidth) + paddingX * 2)

			widths[index] = width
			totalWidth += width + (index > 1 and gap or 0)
		end

		local container = UI.frame(
			parent,
			position or UDim2.fromOffset(0, 0),
			UDim2.fromOffset(size and size.X.Offset > 0 and size.X.Offset or totalWidth, height),
			palette.bar,
			radius
		)

		container.Name = options.name or "MenuBar"
		container.BackgroundTransparency = options.transparent and 1 or 0

		local stroke = UI.stroke(container, palette.border, 1, options.borderTransparency or 0.45)

		local function paint(entry)
			local active = state.open == entry.index

			entry.button.BackgroundColor3 = palette.hover

			if active then
				entry.button.BackgroundTransparency = 0
			elseif entry.hovered then
				entry.button.BackgroundTransparency = 0.4
			else
				entry.button.BackgroundTransparency = 1
			end

			entry.label.TextColor3 = (active or entry.hovered) and palette.text or palette.subtext
		end

		local function repaintAll()
			for _, entry in ipairs(entries) do
				paint(entry)
			end
		end

		local function closeOpen(reason)
			local entry = state.open and entries[state.open]

			state.open = nil

			if entry then
				entry.menu:Close(reason or "menubar")
			end

			repaintAll()
		end

		local function openMenu(index)
			local entry = entries[index]

			if not entry or state.open == index then
				return
			end

			local previous = state.open and entries[state.open]

			state.open = index

			if previous then
				previous.menu:Close("switch")
			end

			entry.menu:Open()

			repaintAll()
		end

		local x = inset

		for index, definition in ipairs(menus or {}) do
			local width = widths[index]

			local button = UI.create("TextButton", {
				Name = tostring(definition.name) .. "Trigger",
				Text = "",
				Position = UDim2.fromOffset(x, inset),
				Size = UDim2.fromOffset(width, height - inset * 2),
				BackgroundColor3 = palette.hover,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Active = true,
				InputSink = true,
			}, container)

			UI.corner(button, triggerRadius)

			local label = UI.label(
				button,
				definition.name,
				UDim2.fromOffset(0, 0),
				UDim2.fromScale(1, 1),
				textSize,
				palette.subtext
			)

			label.TextXAlignment = Enum.TextXAlignment.Center
			label.TextYAlignment = Enum.TextYAlignment.Center

			local menuOptions = {
				items = definition.items,
				menuWidth = definition.menuWidth or options.menuWidth or 200,
				itemHeight = options.itemHeight or 28,
				maxVisibleItems = options.maxVisibleItems or 12,

				menuPosition = function()
					local buttonPosition = button.AbsolutePosition
					local barPosition = container.AbsolutePosition

					return Vector2.new(buttonPosition.X, barPosition.Y + container.AbsoluteSize.Y + menuGap)
				end,

				onClose = function()
					if state.open == index then
						state.open = nil
						repaintAll()
					end
				end,
			}

			for key, value in pairs(options.menuOptions or {}) do
				menuOptions[key] = value
			end

			local entry = {
				index = index,
				name = definition.name,
				button = button,
				label = label,
				hovered = false,
				menu = UI.contextMenu(menuOptions),
			}

			entries[index] = entry

			button.MouseButton1Click:Connect(function()
				if state.open == index then
					closeOpen("toggle")
				else
					openMenu(index)
				end
			end)

			button.MouseEnter:Connect(function()
				entry.hovered = true

				-- once any menu is open, hovering another trigger switches to it
				if state.open ~= nil and state.open ~= index then
					openMenu(index)
				else
					paint(entry)
				end
			end)

			button.MouseLeave:Connect(function()
				entry.hovered = false
				paint(entry)
			end)

			x += width + gap
		end

		table.insert(
			connections,
			UserInputService.InputBegan:Connect(function(input)
				if state.open == nil or state.destroyed then
					return
				end

				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					local mouse = UserInputService:GetMouseLocation()
					local entry = entries[state.open]

					if entry and entry.menu:ContainsPoint(mouse.X, mouse.Y) then
						return
					end

					if UI.pointInside(container, mouse) then
						return -- the trigger's own click handler deals with this
					end

					closeOpen("outside")
				elseif input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.Right then
					local step = input.KeyCode == Enum.KeyCode.Right and 1 or -1
					local count = #entries

					if count > 1 then
						openMenu(((state.open - 1 + step) % count) + 1)
					end
				end
			end)
		)

		local controller = { frame = container, entries = entries }

		function controller:GetWidth()
			return container.Size.X.Offset
		end

		function controller:IsOpen()
			return state.open ~= nil
		end

		function controller:Open(nameOrIndex)
			if type(nameOrIndex) == "number" then
				openMenu(nameOrIndex)

				return
			end

			for index, entry in ipairs(entries) do
				if entry.name == nameOrIndex then
					openMenu(index)

					return
				end
			end
		end

		function controller:Close()
			closeOpen("api")
		end

		function controller:SetColors(new)
			for key, value in pairs(new or {}) do
				if palette[key] ~= nil then
					palette[key] = value
				end
			end

			container.BackgroundColor3 = palette.bar
			stroke.Color = palette.border

			repaintAll()
		end

		function controller:Destroy()
			if state.destroyed then
				return
			end

			state.destroyed = true

			for _, connection in ipairs(connections) do
				connection:Disconnect()
			end

			for _, entry in ipairs(entries) do
				entry.menu:Destroy()
			end

			UI.forgetButtons(container)
			container:Destroy()
		end

		repaintAll()

		return container, controller
	end
end

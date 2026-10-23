return function(ctx)
	local UI = ctx.UI
	local colors = UI.tokens.color

	function UI.buttonList(parent, position, size, buttons, options)
		options = options or {}

		local colors = UI.tokens.color
		local horizontal = options.direction == "horizontal"
		local iconPrefix = options.iconPrefix or "builtin://global-icons/"

		local BASE =
			{ rowHeight = 22, gap = 0, iconSize = 14, textSize = 12, paddingX = 6, iconGap = 6, separatorSpace = 7 }

		local scale = options.scale or 1
		local rowHeight, gap, iconSize, textSize, paddingX, iconGap, separatorSpace, charWidth

		local function applyScale(newScale)
			scale = math.max(newScale or 1, 0.1)

			local function s(value)
				return math.max(1, math.floor(value * scale + 0.5))
			end

			rowHeight = options.rowHeight or s(BASE.rowHeight)
			gap = options.gap or math.floor(BASE.gap * scale + 0.5)
			iconSize = options.iconSize or s(BASE.iconSize)
			textSize = options.textSize or math.clamp(s(BASE.textSize), 6, 100)
			paddingX = options.paddingX or s(BASE.paddingX)
			iconGap = options.iconGap or s(BASE.iconGap)
			separatorSpace = options.separatorSpace or s(BASE.separatorSpace)
			charWidth = options.charWidth or (textSize * 0.58)
		end

		applyScale(scale)
		local hoverColor = options.hoverColor or colors.hover
		local selectedColor = options.selectedColor or colors.selection
		local textColor = options.textColor or colors.text

		local function iconPath(icon)
			if not icon or icon == "" then
				return nil
			end
			if string.find(icon, "://", 1, true) then
				return icon
			end
			return iconPrefix .. icon
		end

		local function rowWidth(config)
			if config.width then
				return config.width
			end
			local text = tostring(config.text or config.label or config.name or "")
			local width = math.ceil(#text * charWidth) + paddingX * 2
			if config.icon then
				width += iconSize + iconGap
			end
			return width
		end

		local function computeAutoWidth(list)
			local widest = 0
			for _, config in ipairs(list or {}) do
				if (config.type or "button") == "button" then
					widest = math.max(widest, rowWidth(config))
				end
			end
			return options.width or widest
		end

		local autoWidth = computeAutoWidth(buttons)

		local autoSize = size == nil

		local container = UI.frame(
			parent,
			position or UDim2.fromOffset(0, 0),
			size or (horizontal and UDim2.fromOffset(0, rowHeight) or UDim2.fromOffset(autoWidth, 0)),
			options.color or colors.panel
		)
		container.Name = options.name or "ButtonList"
		container.BackgroundTransparency = options.color and 0 or 1

		if autoSize then
			container.AutomaticSize = horizontal and Enum.AutomaticSize.X or Enum.AutomaticSize.Y
		end

		local layout = UI.create("UIListLayout", {
			FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, gap),
			VerticalAlignment = Enum.VerticalAlignment.Top,
		}, container)

		local controller = { frame = container, layout = layout, items = {}, selected = options.selected }

		local function paint(item, hovered)
			if not item.enabled then
				item.button.BackgroundTransparency = 1
				item.label.TextColor3 = colors.muted
				return
			end

			local isSelected = options.selectable and controller.selected == item.id

			item.label.TextColor3 = textColor

			if isSelected then
				item.button.BackgroundColor3 = hovered and colors.selectionHover or selectedColor
				item.button.BackgroundTransparency = 0
			elseif hovered then
				item.button.BackgroundColor3 = hoverColor
				item.button.BackgroundTransparency = 0
			else
				item.button.BackgroundTransparency = 1
			end
		end

		local function repaintAll()
			for _, item in pairs(controller.items) do
				if item.button then
					paint(item, item.hovered)
				end
			end
		end

		local function build()
			UI.clear(container, { [layout] = true })
			controller.items = {}

			for index, config in ipairs(controller.buttonConfigs) do
				local kind = config.type or "button"

				if kind == "separator" then
					local holder = UI.create("Frame", {
						Name = "Separator",
						Size = horizontal and UDim2.new(0, separatorSpace, 1, 0) or UDim2.new(1, 0, 0, separatorSpace),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						LayoutOrder = index,
					}, container)

					UI.separator(
						holder,
						horizontal and UDim2.new(0.5, 0, 0, 3) or UDim2.new(0, 4, 0.5, 0),
						horizontal and UDim2.new(0, 1, 1, -6) or UDim2.new(1, -8, 0, 1),
						colors.border
					)
				elseif kind == "custom" then
					local holder = UI.create("Frame", {
						Name = tostring(config.name or ("Custom" .. index)),
						Size = horizontal and UDim2.new(0, config.width or 100, 1, 0)
							or UDim2.new(1, 0, 0, config.height or rowHeight),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						LayoutOrder = index,
					}, container)

					if config.create then
						config.create(holder, colors, UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1))
					end
				else
					local id = config.name or config.id or tostring(index)
					local text = tostring(config.text or config.label or config.name or "")
					local icon = iconPath(config.icon)
					local enabled = config.enabled ~= false

					local button, label, record
					button, label, record = UI.button(
						container,
						text,
						UDim2.fromOffset(0, 0),
						horizontal and UDim2.fromOffset(rowWidth(config), rowHeight) or UDim2.new(1, 0, 0, rowHeight),
						function()
							if options.selectable then
								controller.selected = id
								repaintAll()
								if options.onSelected then
									options.onSelected(id, config)
								end
							end
							if config.callback then
								config.callback(controller, config)
							end
						end,
						{
							color = colors.panel,
							hoverColor = hoverColor,
							pressedColor = colors.pressed,
							textColor = textColor,
							textSize = textSize,
							radius = options.radius or UI.tokens.radius.xs,
							border = false,
							paddingX = paddingX,
							textY = 0,
							enabled = enabled,
						}
					)

					button.Name = tostring(id)
					button.LayoutOrder = index
					button.BackgroundTransparency = 1

					local labelX = paddingX
					if icon then
						UI.image(
							button,
							icon,
							UDim2.new(0, paddingX, 0.5, -math.floor(iconSize / 2)),
							UDim2.fromOffset(iconSize, iconSize)
						)
						labelX = paddingX + iconSize + iconGap
					end

					label.Position = UDim2.fromOffset(labelX, 0)
					label.Size = UDim2.new(1, -(labelX + paddingX), 1, 0)
					label.TextXAlignment = Enum.TextXAlignment.Left
					label.TextYAlignment = Enum.TextYAlignment.Center

					local item = {
						id = id,
						button = button,
						label = label,
						record = record,
						config = config,
						enabled = enabled,
						hovered = false,
					}
					controller.items[id] = item

					button.MouseEnter:Connect(function()
						item.hovered = true
						paint(item, true)
					end)
					button.MouseLeave:Connect(function()
						item.hovered = false
						paint(item, false)
					end)
					button.MouseButton1Down:Connect(function()
						if item.enabled then
							button.BackgroundColor3 = colors.pressed
							button.BackgroundTransparency = 0
						end
					end)
					button.MouseButton1Up:Connect(function()
						paint(item, item.hovered)
					end)

					if config.tooltip then
						UI.tooltip(button, config.tooltip, config.tooltipOptions)
					end

					paint(item, false)
				end
			end
		end

		function controller:GetButton(name)
			local item = self.items[name]
			return item and item.button or nil
		end

		function controller:GetSelected()
			return self.selected
		end

		function controller:SetSelected(name, silent)
			self.selected = name
			repaintAll()
			if not silent and name ~= nil and options.onSelected and self.items[name] then
				options.onSelected(name, self.items[name].config)
			end
		end

		function controller:SetEnabled(name, enabled)
			local item = self.items[name]
			if not item then
				return false
			end
			item.enabled = enabled == true
			item.record.enabled = item.enabled
			item.button.Active = item.enabled
			paint(item, false)
			return true
		end

		function controller:SetScale(newScale)
			applyScale(newScale)

			layout.Padding = UDim.new(0, gap)

			if autoSize then
				if horizontal then
					container.Size = UDim2.fromOffset(0, rowHeight)
				else
					container.Size = UDim2.fromOffset(computeAutoWidth(self.buttonConfigs), 0)
				end
			end

			build()
		end

		function controller:GetScale()
			return scale
		end

		function controller:SetText(name, text)
			local item = self.items[name]
			if item then
				item.label.Text = tostring(text or "")
			end
		end

		function controller:SetButtons(newButtons)
			self.buttonConfigs = newButtons or {}

			if autoSize and not horizontal then
				container.Size = UDim2.fromOffset(computeAutoWidth(self.buttonConfigs), 0)
			end

			build()
		end

		function controller:Destroy()
			UI.forgetButtons(container)
			container:Destroy()
		end

		controller.buttonConfigs = buttons or {}
		build()

		return container, controller
	end
end

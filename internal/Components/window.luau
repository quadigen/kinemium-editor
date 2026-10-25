local UserInputService = game:GetService("UserInputService")

return function(ctx)
	local UI = ctx.UI
	local shared = ctx.shared

	function UI.window(name, position, size, title, options)
		options = options or {}

		local colors = UI.tokens.color
		local radius = options.radius or UI.tokens.radius.md
		local draggable = options.draggable ~= false
		local gripSize = 10
		local gripOffset = 6
		local titleX = draggable and (gripOffset + gripSize + 4) or 10

		local tabs = options.tabs or {}
		local hasTabs = #tabs > 0

		local headerHeight = options.headerHeight or 30
		local tabTop = options.tabTop or 4
		local tabPaddingX = options.tabPaddingX or 12
		local tabRadius = options.tabRadius or UI.tokens.radius.sm

		local headerColor = options.headerColor or colors.panelRaised
		local contentColor = options.contentColor or colors.panel

		local filletRadius = options.tabFilletRadius or 8

		local panel = UI.frame(UI.root(), position, size, colors.panel, radius)

		panel.Name = name
		panel.ClipsDescendants = true

		shared.windows[string.lower(name)] = panel

		if options.backdrop == true then
			UI.create("UIBackdrop", {
				Enabled = true,
				BlurRadius = options.backdropBlur or 16,
				TintColor3 = options.backdropColor or colors.panel,
				TintTransparency = options.backdropTransparency or 0.78,
			}, panel)

			panel.BackgroundTransparency = options.panelTransparency or 0.08
		end

		local border = UI.stroke(
			panel,
			options.borderColor or colors.borderStrong,
			options.borderThickness or 1,
			options.borderTransparency or 0.35
		)

		local header = UI.frame(panel, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, headerHeight), headerColor, 0)

		header.Name = "Header"
		header.ClipsDescendants = true

		UI.frame(header, UDim2.new(0, 0, 1, -radius), UDim2.new(1, 0, 0, radius), headerColor)
		UI.frame(header, UDim2.new(0, 8, 1, -1), UDim2.new(1, -16, 0, 1), colors.border)

		local tabHeight = headerHeight - tabTop
		local titleTab = nil
		local titleText = tostring(title or name)
		local titleLabel

		if not hasTabs then
			local function titleWidth(text)
				return options.titleTabWidth or (#text * 7 + tabPaddingX * 2)
			end

			titleTab = UI.tabShape(
				header,
				UDim2.fromOffset(titleX, tabTop),
				UDim2.fromOffset(titleWidth(titleText), tabHeight),
				options.activeTabColor or contentColor,
				{
					radius = tabRadius,
					filletRadius = filletRadius,
					barColor = headerColor,
					accentColor = options.tabAccentColor,
				}
			)

			titleTab.Name = "TitleTab"

			titleLabel = UI.label(
				titleTab,
				titleText,
				UDim2.fromOffset(0, 0),
				UDim2.fromScale(1, 1),
				options.titleSize or UI.tokens.type.small,
				options.titleColor or colors.text
			)

			titleLabel.TextXAlignment = Enum.TextXAlignment.Center
			titleLabel.TextYAlignment = Enum.TextYAlignment.Center

			titleLabel:GetPropertyChangedSignal("Text"):Connect(function()
				titleTab.Size = UDim2.fromOffset(titleWidth(titleLabel.Text), tabHeight)
			end)
		else
			titleLabel =
				UI.label(header, titleText, UDim2.fromOffset(titleX, 0), UDim2.fromOffset(0, 0), 12, colors.text)
			titleLabel.Visible = false
		end

		titleLabel.Name = "Title"

		local closeButton = nil

		if options.closable then
			closeButton = UI.iconButton(
				header,
				options.closeIcon or "builtin://global-icons/x.svg",
				UDim2.new(1, -27, 0.5, -math.floor(19 / 2)),
				UDim2.fromOffset(22, 19),
				function()
					if options.onClose then
						options.onClose(panel)
					else
						panel.Visible = false
					end
				end,
				{
					color = headerColor,
					hoverColor = options.closeHoverColor or colors.hover,
					pressedColor = colors.pressed,
					iconSize = 11,
					radius = UI.tokens.radius.sm,
					border = false,
				}
			)
		end

		local dragHandle = nil

		if draggable then
			dragHandle = UI.iconButton(
				header,
				options.gripIcon or "builtin://global-icons/grip.svg",
				UDim2.new(0, gripOffset, 0.5, -math.floor(19 / 2)),
				UDim2.fromOffset(gripSize, 19),
				function() end,
				{
					color = headerColor,
					hoverColor = colors.hover,
					pressedColor = colors.pressed,
					iconSize = 11,
					radius = UI.tokens.radius.sm,
					border = false,
				}
			)

			dragHandle.Name = "DragHandle"

			local dragging = false
			local dragStartX, dragStartY = 0, 0
			local startPos = nil

			local function isPointer(input)
				return input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
			end

			local connections = {}

			table.insert(
				connections,
				dragHandle.InputBegan:Connect(function(input)
					if not isPointer(input) then
						return
					end

					local mouse = UserInputService:GetMouseLocation()

					dragging = true
					dragStartX, dragStartY = mouse.X, mouse.Y
					startPos = panel.Position

					panel:SetAttribute("Dragging", true)
				end)
			)

			table.insert(
				connections,
				UserInputService.InputChanged:Connect(function(input)
					if not dragging or not startPos then
						return
					end

					if input.UserInputType ~= Enum.UserInputType.MouseMovement then
						return
					end

					local mouse = UserInputService:GetMouseLocation()

					local newX = startPos.X.Offset + (mouse.X - dragStartX)
					local newY = startPos.Y.Offset + (mouse.Y - dragStartY)

					local root = UI.root()
					local rootSize = root and root.AbsoluteSize
					local panelSize = panel.AbsoluteSize

					if rootSize and panelSize then
						newX = math.clamp(newX, 0, math.max(0, rootSize.X - panelSize.X))
						newY = math.clamp(newY, 0, math.max(0, rootSize.Y - headerHeight))
					end

					panel.Position = UDim2.new(startPos.X.Scale, newX, startPos.Y.Scale, newY)
				end)
			)

			table.insert(
				connections,
				UserInputService.InputEnded:Connect(function(input)
					if isPointer(input) then
						dragging = false
						startPos = nil

						panel:SetAttribute("Dragging", false)
					end
				end)
			)

			panel.Destroying:Connect(function()
				for _, c in ipairs(connections) do
					c:Disconnect()
				end
			end)
		end

		local content =
			UI.frame(panel, UDim2.fromOffset(0, headerHeight), UDim2.new(1, 0, 1, -headerHeight), contentColor)

		content.Name = "Content"
		content.ClipsDescendants = true

		local tabsController = nil

		if hasTabs then
			local _, controller = UI.tabs(nil, nil, nil, {
				tabs = tabs,
				selectedTab = options.selectedTab,
				barFrame = header,
				contentFrame = content,
				startX = titleX,
				barHeight = headerHeight,
				barColor = headerColor,
				contentColor = contentColor,

				tabGap = options.tabGap,
				tabTop = tabTop,
				tabPaddingX = tabPaddingX,
				tabRadius = tabRadius,
				tabSpeed = options.tabSpeed,
				tabWidth = options.tabWidth,
				tabTextSize = options.tabTextSize,
				tabFilletRadius = filletRadius,
				tabAccentColor = options.tabAccentColor,

				activeTabColor = options.activeTabColor,
				inactiveTabColor = options.inactiveTabColor,
				tabHoverColor = options.tabHoverColor,
				tabPressedColor = options.tabPressedColor,
				activeTabTextColor = options.activeTabTextColor,
				inactiveTabTextColor = options.inactiveTabTextColor,

				onTabChanged = function(tabName, previousTab, page)
					if options.onTabChanged then
						options.onTabChanged(tabName, previousTab, page, panel)
					end
				end,
			})

			tabsController = controller
		end

		local clip = UI.frame(panel, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 1, 0), colors.panel, radius)

		clip.Name = "WindowClip"
		clip.BackgroundTransparency = 1
		clip.InputSink = false
		clip.Selectable = false

		return panel,
			content,
			header,
			{
				title = titleLabel,
				titleTab = titleTab,
				indicator = tabsController and tabsController.indicator or nil,
				closeButton = closeButton,
				dragHandle = dragHandle,
				border = border,
				clip = clip,

				tabBar = nil,
				tabs = tabsController and tabsController.tabs or {},
				pages = tabsController and tabsController.pages or {},

				selectTab = tabsController and tabsController.selectTab or function() end,
				getSelectedTab = tabsController and tabsController.getSelectedTab or function()
					return nil
				end,
				getPage = tabsController and tabsController.getPage or function()
					return nil
				end,
			}
	end

	function UI.toggleWindow(name)
		local window = shared.windows[string.lower(name)]

		if window then
			window.Visible = not window.Visible
		end
	end

	function UI.getWindow(name)
		return shared.windows[string.lower(name)]
	end
end

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

		local windowKey = string.lower(name)
		local controls = {}

		if options.backdrop == true then
			UI.create("UIBackdrop", {
				Enabled = true,
				BlurRadius = options.backdropBlur or 16,
				TintColor3 = options.backdropColor or colors.panel,
				TintTransparency = options.backdropTransparency or 0.78,
			}, panel)

			panel.BackgroundTransparency = options.panelTransparency or 0.08
		end

		local backgroundImageLabel = nil
		local backgroundImageCorner = nil

		local function resolveScaleType(value)
			local scaleType = value or Enum.ScaleType.Crop

			if type(scaleType) == "string" then
				scaleType = Enum.ScaleType[scaleType] or Enum.ScaleType.Crop
			end

			return scaleType
		end

		local function createBackgroundImage(source, transparency, color, scaleType)
			local label = UI.create("ImageLabel", {
				Name = "BackgroundImage",
				Position = UDim2.fromScale(0, 0),
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Image = source or "",
				ImageTransparency = transparency or 0,
				ImageColor3 = color or Color3.new(1, 1, 1),
				ScaleType = resolveScaleType(scaleType),
				ZIndex = panel.ZIndex,
				Active = false,
				Selectable = false,
			}, panel)

			backgroundImageCorner = UI.create("UICorner", {
				CornerRadius = UDim.new(0, radius),
			}, label)

			return label
		end

		backgroundImageLabel = createBackgroundImage(
			options.backgroundImage,
			options.backgroundImageTransparency,
			options.backgroundImageColor,
			options.backgroundImageScaleType
		)

		local hasBackgroundImage = type(options.backgroundImage) == "string" and options.backgroundImage ~= ""

		backgroundImageLabel.Visible = hasBackgroundImage

		local border = UI.stroke(
			panel,
			options.borderColor or colors.borderStrong,
			options.borderThickness or 1,
			options.borderTransparency or 0.35
		)

		local header = UI.frame(panel, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, headerHeight), headerColor, 0)

		header.Name = "Header"
		header.ClipsDescendants = true

		local headerBottomFill = UI.frame(header, UDim2.new(0, 0, 1, -radius), UDim2.new(1, 0, 0, radius), headerColor)
		UI.frame(header, UDim2.new(0, 8, 1, -1), UDim2.new(1, -16, 0, 1), colors.border)

		if options.headerTransparency ~= nil then
			header.BackgroundTransparency = options.headerTransparency
			headerBottomFill.BackgroundTransparency = options.headerTransparency
		end

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
				for _, connection in ipairs(connections) do
					connection:Disconnect()
				end
			end)
		end

		local content =
			UI.frame(panel, UDim2.fromOffset(0, headerHeight), UDim2.new(1, 0, 1, -headerHeight), contentColor)

		content.Name = "Content"
		content.ClipsDescendants = true

		if options.contentTransparency ~= nil then
			content.BackgroundTransparency = options.contentTransparency
		elseif hasBackgroundImage then
			content.BackgroundTransparency = 1
		end

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

		local function styleValue(props, key)
			local value = props[key]

			if value ~= nil then
				return value
			end

			return options[key]
		end

		local function updateCorner(instance, cornerRadius)
			if not instance then
				return
			end

			local corner = instance:FindFirstChildOfClass("UICorner")

			if corner then
				corner.CornerRadius = UDim.new(0, cornerRadius)
			end
		end

		local function applyOverrides(props)
			local target = props.name or props.window or props.Name

			if type(target) == "string" and string.lower(target) ~= windowKey then
				return
			end

			local tokens = UI.tokens.color
			local nextRadius = styleValue(props, "radius") or UI.tokens.radius.md
			local nextHeaderColor = styleValue(props, "headerColor") or options.headerColor or tokens.panelRaised
			local nextContentColor = styleValue(props, "contentColor") or options.contentColor or tokens.panel
			local image = styleValue(props, "backgroundImage")
			local imageVisible = type(image) == "string" and image ~= ""

			if imageVisible then
				backgroundImageLabel.Image = image
				backgroundImageLabel.ImageTransparency = styleValue(props, "backgroundImageTransparency") or 0
				backgroundImageLabel.ImageColor3 = styleValue(props, "backgroundImageColor") or Color3.new(1, 1, 1)
				backgroundImageLabel.ScaleType = resolveScaleType(styleValue(props, "backgroundImageScaleType"))
			end

			backgroundImageLabel.Visible = imageVisible

			controls.backgroundImage = backgroundImageLabel

			panel.BackgroundColor3 = styleValue(props, "panelColor") or tokens.panel

			local panelTransparency = styleValue(props, "panelTransparency")

			if options.backdrop == true or panelTransparency ~= nil then
				if panelTransparency == nil then
					panelTransparency = options.backdrop and 0.08 or 0
				end

				panel.BackgroundTransparency = panelTransparency
			end

			local headerTransparency = styleValue(props, "headerTransparency") or 0

			header.BackgroundColor3 = nextHeaderColor
			headerBottomFill.BackgroundColor3 = nextHeaderColor
			header.BackgroundTransparency = headerTransparency
			headerBottomFill.BackgroundTransparency = headerTransparency

			content.BackgroundColor3 = nextContentColor

			local contentTransparency = styleValue(props, "contentTransparency")

			if contentTransparency == nil then
				contentTransparency = backgroundImageLabel.Visible and 1 or 0
			end

			content.BackgroundTransparency = contentTransparency

			border.Color = styleValue(props, "borderColor") or tokens.borderStrong
			border.Thickness = styleValue(props, "borderThickness") or 1
			border.Transparency = styleValue(props, "borderTransparency") or 0.35

			if titleLabel then
				titleLabel.TextColor3 = styleValue(props, "titleColor") or tokens.text

				local nextTitle = styleValue(props, "title")

				if type(nextTitle) == "string" and nextTitle ~= "" then
					titleLabel.Text = nextTitle
				end
			end

			if titleTab then
				local activeColor = styleValue(props, "activeTabColor") or nextContentColor
				local fill = titleTab:FindFirstChild("BottomFill")

				titleTab.BackgroundColor3 = activeColor

				if fill then
					fill.BackgroundColor3 = activeColor
				end
			end

			updateCorner(panel, nextRadius)
			updateCorner(clip, nextRadius)

			if backgroundImageCorner then
				backgroundImageCorner.CornerRadius = UDim.new(0, nextRadius)
			end
		end

		controls.title = titleLabel
		controls.titleTab = titleTab
		controls.indicator = tabsController and tabsController.indicator or nil
		controls.closeButton = closeButton
		controls.dragHandle = dragHandle
		controls.border = border
		controls.clip = clip
		controls.backgroundImage = backgroundImageLabel

		controls.tabBar = nil
		controls.tabs = tabsController and tabsController.tabs or {}
		controls.pages = tabsController and tabsController.pages or {}

		controls.selectTab = tabsController and tabsController.selectTab or function() end
		controls.getSelectedTab = tabsController and tabsController.getSelectedTab or function()
			return nil
		end
		controls.getPage = tabsController and tabsController.getPage or function()
			return nil
		end

		local componentKey = "window:" .. windowKey

		local function applyWindowComponent(componentProps)
			local props = {}
			local global = shared.componentOverrides.window
			local globalName = global and (global.name or global.window or global.Name)
			local globalMatches = type(globalName) ~= "string" or string.lower(globalName) == windowKey

			if globalMatches then
				for key, value in pairs(global or {}) do
					props[key] = value
				end
			end

			for key, value in pairs(componentProps or {}) do
				props[key] = value
			end

			applyOverrides(props)
		end

		shared.windowBindings[windowKey] = applyWindowComponent

		controls.refreshBindings = {
			UI.onComponentRefresh("window", applyOverrides),
			UI.onComponentRefresh(componentKey, applyWindowComponent),
		}

		panel.Destroying:Connect(function()
			shared.windowBindings[windowKey] = nil

			for _, binding in ipairs(controls.refreshBindings) do
				binding:Disconnect()
			end

			controls.refreshBindings = {}
		end)

		return panel, content, header, controls
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

	function UI.refreshWindow(name)
		local windowKey = string.lower(name)

		if not shared.windowBindings[windowKey] then
			return false
		end

		UI.refreshComponent("window:" .. windowKey)

		return true
	end

	function UI.refreshAllWindows(props)
		return UI.refreshComponent("window", props)
	end

	function UI.setWindowProps(name, props)
		return UI.setComponentProps("window:" .. string.lower(name), props)
	end

	function UI.clearWindowProps(name)
		return UI.clearComponentProps("window:" .. string.lower(name))
	end
end

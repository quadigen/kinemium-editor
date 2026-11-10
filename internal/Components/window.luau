local UserInputService = game:GetService("UserInputService")

return function(ctx)
	local UI = ctx.UI
	local shared = ctx.shared

	function UI.window(name, position, size, title, options)
		options = options or {}

		local colors = UI.tokens.color
		local windowKey = string.lower(name)
		local radius = options.radius or 12
		local headerHeight = options.headerHeight or 42
		local tabBarHeight = options.tabBarHeight or 32
		local tabTop = options.tabTop or 3
		local tabPaddingX = options.tabPaddingX or 12
		local tabRadius = options.tabRadius or UI.tokens.radius.sm
		local filletRadius = options.tabFilletRadius or 8
		local draggable = options.draggable ~= false
		local tabs = options.tabs or {}
		local hasTabs = #tabs > 0
		local headerColor = options.headerColor or colors.panelRaised
		local contentColor = options.contentColor or colors.panel
		local activeTabColor = options.activeTabColor or contentColor
		local titleText = tostring(title or name)
		local connections = {}
		local controls = {}
		local minimized = false
		local maximized = false
		local savedSize = nil
		local savedPosition = nil
		local minimizedSize = nil
		local dragging = false
		local dragInput = nil
		local dragStart = nil
		local dragPosition = nil
		local dragAbsolute = nil
		local lastHeaderClick = 0

		local panel = UI.frame(UI.root(), position, size, colors.panel, radius)
		panel.Name = name
		panel.ClipsDescendants = true
		panel.Active = true
		shared.windows[windowKey] = panel

		if options.backdrop == true then
			UI.create("UIBackdrop", {
				Enabled = true,
				BlurRadius = options.backdropBlur or 16,
				TintColor3 = options.backdropColor or colors.panel,
				TintTransparency = options.backdropTransparency or 0.78,
			}, panel)
			panel.BackgroundTransparency = options.panelTransparency or 0.08
		elseif options.panelTransparency ~= nil then
			panel.BackgroundTransparency = options.panelTransparency
		end

		local backgroundImageLabel = UI.create("ImageLabel", {
			Name = "BackgroundImage",
			Position = UDim2.fromScale(0, 0),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = options.backgroundImage or "",
			ImageTransparency = options.backgroundImageTransparency or 0,
			ImageColor3 = options.backgroundImageColor or Color3.new(1, 1, 1),
			ScaleType = Enum.ScaleType.Crop,
			ZIndex = panel.ZIndex,
			Active = false,
			Selectable = false,
		}, panel)

		local backgroundImageCorner = UI.create("UICorner", {
			CornerRadius = UDim.new(0, radius),
		}, backgroundImageLabel)

		local function resolveScaleType(value)
			if type(value) == "string" then
				return Enum.ScaleType[value] or Enum.ScaleType.Crop
			end
			return value or Enum.ScaleType.Crop
		end

		backgroundImageLabel.ScaleType = resolveScaleType(options.backgroundImageScaleType)
		backgroundImageLabel.Visible = type(options.backgroundImage) == "string" and options.backgroundImage ~= ""

		local border = UI.stroke(
			panel,
			options.borderColor or colors.borderStrong,
			options.borderThickness or 1,
			options.borderTransparency or 0.32
		)

		local header = UI.frame(panel, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, headerHeight), headerColor, 0)
		header.Name = "Header"
		header.ClipsDescendants = true
		header.Active = true
		header.BackgroundTransparency = options.headerTransparency or 0

		local headerGradient = UI.create("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(231, 233, 237)),
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.93),
				NumberSequenceKeypoint.new(1, 0.98),
			}),
		}, header)

		local titleTab = nil
		local titleParent = header

		if not hasTabs then
			titleTab = UI.frame(header, UDim2.fromOffset(94, 0), UDim2.new(1, -188, 1, 0), headerColor, 0)
			titleTab.Name = "TitleTab"
			titleTab.BackgroundTransparency = 1
			titleParent = titleTab
		end

		local titleLabel = UI.label(
			titleParent,
			titleText,
			hasTabs and UDim2.fromOffset(94, 0) or UDim2.fromOffset(0, 0),
			hasTabs and UDim2.new(1, -188, 1, 0) or UDim2.fromScale(1, 1),
			options.titleSize or 13,
			options.titleColor or colors.text
		)
		titleLabel.Name = "Title"
		titleLabel.Font = Enum.Font.GothamMedium
		titleLabel.TextXAlignment = Enum.TextXAlignment.Center
		titleLabel.TextYAlignment = Enum.TextYAlignment.Center
		titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
		titleLabel.BackgroundTransparency = 1

		local headerDivider = UI.frame(header, UDim2.new(0, 0, 1, -1), UDim2.new(1, 0, 0, 1), colors.border, 0)
		headerDivider.Name = "HeaderDivider"
		headerDivider.BackgroundTransparency = 0.4

		local tabBar = nil
		local totalTop = headerHeight

		if hasTabs then
			tabBar =
				UI.frame(panel, UDim2.fromOffset(0, headerHeight), UDim2.new(1, 0, 0, tabBarHeight), headerColor, 0)
			tabBar.Name = "TabBar"
			totalTop += tabBarHeight
		end

		local content = UI.frame(panel, UDim2.fromOffset(0, totalTop), UDim2.new(1, 0, 1, -totalTop), contentColor, 0)
		content.Name = "Content"
		content.ClipsDescendants = true
		content.BackgroundTransparency = options.contentTransparency ~= nil and options.contentTransparency
			or (backgroundImageLabel.Visible and 1 or 0)

		local tabDivider = nil
		if hasTabs then
			tabDivider = UI.frame(tabBar, UDim2.new(0, 0, 1, -1), UDim2.new(1, 0, 0, 1), colors.border, 0)
			tabDivider.Name = "TabDivider"
			tabDivider.BackgroundTransparency = 0.4
		end

		local tabsController = nil

		if hasTabs then
			local _, controller = UI.tabs(nil, nil, nil, {
				tabs = tabs,
				selectedTab = options.selectedTab,
				barFrame = tabBar,
				contentFrame = content,
				startX = 12,
				barHeight = tabBarHeight,
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
				activeTabColor = activeTabColor,
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

		local clip = UI.frame(panel, UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), colors.panel, radius)
		clip.Name = "WindowClip"
		clip.BackgroundTransparency = 1
		clip.Active = false
		clip.Selectable = false

		local function restoreMinimized()
			if not minimized then
				return
			end
			minimized = false
			panel.Size = minimizedSize or size
			content.Visible = true
			if tabBar then
				tabBar.Visible = true
			end
		end

		local function restoreMaximized()
			if not maximized then
				return
			end
			maximized = false
			if savedPosition then
				panel.Position = savedPosition
			end
			if savedSize then
				panel.Size = savedSize
			end
			savedPosition = nil
			savedSize = nil
		end

		local function toggleMinimize()
			if options.minimizable == false then
				return
			end
			if minimized then
				restoreMinimized()
			else
				if maximized then
					restoreMaximized()
				end
				minimizedSize = panel.Size
				minimized = true
				content.Visible = false
				if tabBar then
					tabBar.Visible = false
				end
				panel.Size = UDim2.new(panel.Size.X.Scale, panel.Size.X.Offset, 0, headerHeight)
			end
		end

		local function toggleMaximize()
			if options.maximizable == false then
				return
			end
			restoreMinimized()
			if maximized then
				restoreMaximized()
			else
				savedPosition = panel.Position
				savedSize = panel.Size
				maximized = true
				panel.Position = UDim2.fromOffset(8, 8)
				panel.Size = UDim2.new(1, -16, 1, -16)
			end
		end

		local function closeWindow()
			if options.closable == false then
				return
			end
			if options.onClose then
				options.onClose(panel)
			else
				panel.Visible = false
			end
		end

		local function makeTrafficButton(buttonName, x, fill, rim, symbol, onClick, enabled)
			local button = UI.create("TextButton", {
				Name = buttonName,
				Position = UDim2.new(0, x, 0.5, -7),
				Size = UDim2.fromOffset(14, 14),
				BackgroundColor3 = enabled and fill or colors.border,
				BackgroundTransparency = enabled and 0 or 0.35,
				BorderSizePixel = 0,
				Text = "",
				TextColor3 = rim,
				TextSize = 11,
				Font = Enum.Font.GothamBold,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
				AutoButtonColor = false,
				Active = enabled,
			}, header)
			UI.create("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}, button)
			UI.create("UIStroke", {
				Color = rim,
				Thickness = 1,
				Transparency = enabled and 0.48 or 0.85,
			}, button)
			button.MouseEnter:Connect(function()
				if enabled then
					button.Text = symbol
				end
			end)
			button.MouseLeave:Connect(function()
				button.Text = ""
			end)
			button.MouseButton1Click:Connect(function()
				if enabled then
					onClick()
				end
			end)
			return button
		end

		local closeButton = makeTrafficButton(
			"CloseButton",
			15,
			Color3.fromRGB(255, 95, 86),
			Color3.fromRGB(145, 32, 30),
			"×",
			closeWindow,
			options.closable ~= false
		)

		local minimizeButton = makeTrafficButton(
			"MinimizeButton",
			37,
			Color3.fromRGB(255, 189, 46),
			Color3.fromRGB(150, 99, 23),
			"−",
			toggleMinimize,
			options.minimizable ~= false
		)

		local maximizeButton = makeTrafficButton(
			"MaximizeButton",
			59,
			Color3.fromRGB(39, 201, 63),
			Color3.fromRGB(30, 119, 36),
			"+",
			toggleMaximize,
			options.maximizable ~= false
		)

		local function isPointer(input)
			return input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
		end

		if draggable then
			table.insert(
				connections,
				header.InputBegan:Connect(function(input)
					if not isPointer(input) then
						return
					end

					local mouse = UserInputService:GetMouseLocation()
					if mouse.X - header.AbsolutePosition.X < 88 then
						return
					end

					local now = os.clock()
					if now - lastHeaderClick < 0.3 then
						lastHeaderClick = 0
						if not maximized or options.maximizable ~= false then
							toggleMaximize()
						end
						return
					end
					lastHeaderClick = now

					if maximized then
						return
					end
					dragging = true
					dragInput = input
					dragStart = mouse
					dragPosition = panel.Position
					dragAbsolute = panel.AbsolutePosition
					panel:SetAttribute("Dragging", true)
				end)
			)

			table.insert(
				connections,
				UserInputService.InputChanged:Connect(function(input)
					if not dragging or not dragStart or not dragPosition or not dragAbsolute then
						return
					end
					if input.UserInputType ~= Enum.UserInputType.MouseMovement and input ~= dragInput then
						return
					end

					local mouse = UserInputService:GetMouseLocation()
					local dx = mouse.X - dragStart.X
					local dy = mouse.Y - dragStart.Y
					local root = UI.root()
					local rootSize = root and root.AbsoluteSize
					local panelSize = panel.AbsoluteSize

					if rootSize then
						local nextX = math.clamp(dragAbsolute.X + dx, 0, math.max(0, rootSize.X - panelSize.X))
						local nextY = math.clamp(dragAbsolute.Y + dy, 0, math.max(0, rootSize.Y - headerHeight))
						dx = nextX - dragAbsolute.X
						dy = nextY - dragAbsolute.Y
					end

					panel.Position = UDim2.new(
						dragPosition.X.Scale,
						dragPosition.X.Offset + dx,
						dragPosition.Y.Scale,
						dragPosition.Y.Offset + dy
					)
				end)
			)

			table.insert(
				connections,
				UserInputService.InputEnded:Connect(function(input)
					if
						isPointer(input)
						and (input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1)
					then
						dragging = false
						dragInput = nil
						dragStart = nil
						dragPosition = nil
						dragAbsolute = nil
						panel:SetAttribute("Dragging", false)
					end
				end)
			)
		end

		local function styleValue(props, key)
			if props[key] ~= nil then
				return props[key]
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
			props = props or {}
			local target = props.name or props.window or props.Name
			if type(target) == "string" and string.lower(target) ~= windowKey then
				return
			end

			local nextRadius = styleValue(props, "radius") or 12
			local nextHeaderColor = styleValue(props, "headerColor") or colors.panelRaised
			local nextContentColor = styleValue(props, "contentColor") or colors.panel
			local image = styleValue(props, "backgroundImage")
			local imageVisible = type(image) == "string" and image ~= ""

			if imageVisible then
				backgroundImageLabel.Image = image
				backgroundImageLabel.ImageTransparency = styleValue(props, "backgroundImageTransparency") or 0
				backgroundImageLabel.ImageColor3 = styleValue(props, "backgroundImageColor") or Color3.new(1, 1, 1)
				backgroundImageLabel.ScaleType = resolveScaleType(styleValue(props, "backgroundImageScaleType"))
			end
			backgroundImageLabel.Visible = imageVisible

			panel.BackgroundColor3 = styleValue(props, "panelColor") or colors.panel
			local transparency = styleValue(props, "panelTransparency")
			if options.backdrop or transparency ~= nil then
				panel.BackgroundTransparency = transparency ~= nil and transparency or (options.backdrop and 0.08 or 0)
			end

			header.BackgroundColor3 = nextHeaderColor
			header.BackgroundTransparency = styleValue(props, "headerTransparency") or 0
			if tabBar then
				tabBar.BackgroundColor3 = nextHeaderColor
			end
			content.BackgroundColor3 = nextContentColor
			local contentTransparency = styleValue(props, "contentTransparency")
			if contentTransparency == nil then
				contentTransparency = imageVisible and 1 or 0
			end
			content.BackgroundTransparency = contentTransparency
			border.Color = styleValue(props, "borderColor") or colors.borderStrong
			border.Thickness = styleValue(props, "borderThickness") or 1
			border.Transparency = styleValue(props, "borderTransparency") or 0.32
			titleLabel.TextColor3 = styleValue(props, "titleColor") or colors.text

			local nextTitle = styleValue(props, "title")
			if type(nextTitle) == "string" and nextTitle ~= "" then
				titleLabel.Text = nextTitle
			end

			if titleTab then
				titleTab.BackgroundColor3 = nextHeaderColor
			end

			updateCorner(panel, nextRadius)
			updateCorner(clip, nextRadius)
			backgroundImageCorner.CornerRadius = UDim.new(0, nextRadius)
		end

		controls.title = titleLabel
		controls.titleTab = titleTab
		controls.indicator = tabsController and tabsController.indicator or nil
		controls.closeButton = closeButton
		controls.minimizeButton = minimizeButton
		controls.maximizeButton = maximizeButton
		controls.dragHandle = header
		controls.border = border
		controls.clip = clip
		controls.backgroundImage = backgroundImageLabel
		controls.tabBar = tabBar
		controls.tabs = tabsController and tabsController.tabs or {}
		controls.pages = tabsController and tabsController.pages or {}
		controls.selectTab = tabsController and tabsController.selectTab or function() end
		controls.setTabDetached = tabsController and tabsController.setTabDetached
		controls.getSelectedTab = tabsController and tabsController.getSelectedTab or function()
			return nil
		end
		controls.getPage = tabsController and tabsController.getPage or function()
			return nil
		end
		controls.toggleMinimize = toggleMinimize
		controls.toggleMaximize = toggleMaximize
		controls.close = closeWindow

		local componentKey = "window:" .. windowKey

		local function applyWindowComponent(componentProps)
			local props = {}
			local allOverrides = shared.componentOverrides or {}
			local global = allOverrides.window
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
			if shared.windows[windowKey] == panel then
				shared.windows[windowKey] = nil
			end
			shared.windowBindings[windowKey] = nil
			for _, connection in ipairs(connections) do
				connection:Disconnect()
			end
			for _, binding in ipairs(controls.refreshBindings) do
				binding:Disconnect()
			end
			table.clear(controls.refreshBindings)
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

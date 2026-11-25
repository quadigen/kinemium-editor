local UserInputService = game:GetService("UserInputService")
local Studio = game:GetService("Studio")
local ThemeService = game:GetService("StudioThemeService")
local HttpService = game:GetService("HttpService")

return function(ctx)
	local UI = ctx.UI
	local shared = ctx.shared
	local layouts = setmetatable({}, { __mode = "k" })
	local dockResizeState = {}

	function UI.restoreDockResizeState(enabled)
		table.clear(dockResizeState)
		if not enabled then return end

		local encoded = Studio:GetSetting("dockResizeState", "")
		local ok, saved = pcall(function()
			return HttpService:JSONDecode(encoded)
		end)
		if ok and type(saved) == "table" then
			dockResizeState = saved
			ThemeService:SetDockResizeState(saved)
		end
	end

	function UI.restoreDockWindowWeight(name)
		local key = "window." .. name
		local value = dockResizeState[key]
		if value ~= nil then
			ThemeService:SetDockResizeState({ [key] = value })
		end
	end

	local function saveDockResizeState()
		for key, value in pairs(ThemeService:GetDockResizeState()) do
			dockResizeState[key] = value
		end
		Studio:SetSetting("dockResizeState", HttpService:JSONEncode(dockResizeState))
	end

	local function dockName(panel)
		return panel.Name == "Console" and "Output" or panel.Name
	end

	local function dockCoordinates(panel)
		local theme = ThemeService.SelectedTheme
		local name = dockName(panel)
		return theme[name .. "Coordinates"] or (theme.DockedWindows and theme.DockedWindows[name])
	end

	local function encode(position, size)
		return string.format("%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g,%.9g",
			position.X.Scale, position.X.Offset, position.Y.Scale, position.Y.Offset,
			size.X.Scale, size.X.Offset, size.Y.Scale, size.Y.Offset)
	end

	local function decode(value)
		if type(value) ~= "string" then return nil end
		local numbers = {}
		for field in string.gmatch(value, "[^,]+") do
			local number = tonumber(field)
			if not number or number ~= number or math.abs(number) > 1000000 then return nil end
			table.insert(numbers, number)
		end
		if #numbers ~= 8 then return nil end
		return {
			position = UDim2.new(numbers[1], numbers[2], numbers[3], numbers[4]),
			size = UDim2.new(numbers[5], numbers[6], numbers[7], numbers[8]),
		}
	end

	local function settingKey(state, mode)
		return "windowLayout." .. state.key .. "." .. mode
	end

	local function savedLayout(state, mode)
		if state.saved[mode] == nil then
			local saved = Studio:GetSetting("restoreLayout", true) and decode(Studio:GetSetting(settingKey(state, mode), "")) or nil
			state.saved[mode] = saved or false
		end
		return state.saved[mode]
	end

	function UI.applyWindowLayout(panel, position, size, mode)
		local state = layouts[panel]
		if state then
			mode = mode or "docked"
			state.mode = mode
			state.basePosition = position
			state.baseSize = size
			if panel:GetAttribute("Dragging") == true then return end
		end
		if panel.Position ~= position then panel.Position = position end
		if panel.Size ~= size then panel.Size = size end
	end

	function UI.restoreFloatingWindow(panel, fallbackSize)
		local state = layouts[panel]
		if state then
			state.mode = "floating"
			state.basePosition = nil
			state.baseSize = nil
			local saved = savedLayout(state, "floating")
			if saved then
				panel.Size = saved.size
				return
			end
		end
		if fallbackSize then panel.Size = fallbackSize end
	end

	function UI.applyWindowBackground(label, source, transparency, scaleType, color)
		local theme = UI.tokens.window
		source = source or theme.backgroundImage
		transparency = transparency or theme.backgroundImageTransparency
		scaleType = scaleType or theme.backgroundImageScaleType
		if type(scaleType) == "string" then
			scaleType = Enum.ScaleType[scaleType]
		end

		local visible = type(source) == "string" and source ~= "" and transparency < 1
		label.Image = visible and source or ""
		label.ImageTransparency = transparency
		label.ImageColor3 = color or Color3.new(1, 1, 1)
		label.ScaleType = scaleType or Enum.ScaleType.Crop
		label.Visible = visible
		return visible
	end

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

		local panel = UI.frame(UI.root(), position, size, colors.panel, radius, options.radius == nil and "md" or nil)

		panel.Name = name
		panel:SetAttribute("Dockable", draggable and options.dockable ~= false)
		panel.ClipsDescendants = true

		shared.windows[string.lower(name)] = panel

		local windowKey = string.lower(name)
		local controls = {}

		if options.resizable ~= false then
			local state = {
				key = windowKey,
				mode = "floating",
				saved = {},
				resizing = false,
			}
			layouts[panel] = state

			if not options.managedLayout then
				UI.restoreFloatingWindow(panel)
			end

			local detector = UI.create("UIScaleDetector", {
				EdgeThickness = options.resizeEdgeThickness or 6,
				MinSize = options.minSize or Vector2.new(160, headerHeight + 64),
				MaxSize = options.maxSize or Vector2.new(0, 0),
			}, panel)
			controls.resizeDetector = detector

			detector.ScaleStart:Connect(function(pointer)
				state.resizing = true
				state.startPosition = panel.Position
				state.startSize = panel.Size
				state.dockChanged = false

				local position, size = panel.AbsolutePosition, panel.AbsoluteSize
				local x, y = pointer.X - position.X, pointer.Y - position.Y
				local edge = detector.EdgeThickness
				state.edges = (x <= edge and 1 or 0) + (size.X - x <= edge and 2 or 0)
					+ (y <= edge and 4 or 0) + (size.Y - y <= edge and 8 or 0)
			end)

			detector.ScaleContinue:Connect(function()
				if not state.resizing or state.mode == "floating" then return end

				local position, size = panel.Position, panel.Size
				local changed = ThemeService:ResizeDockWindow(
					dockName(panel), position.X.Offset, position.Y.Offset, size.X.Offset, size.Y.Offset, state.edges
				)
				state.dockChanged = state.dockChanged or changed
				local coordinates = dockCoordinates(panel)
				if coordinates then
					UI.applyWindowLayout(panel, coordinates.Position, coordinates.Size)
				end
			end)

			detector.ScaleEnd:Connect(function()
				state.resizing = false
				if state.mode ~= "floating" then
					if state.dockChanged then saveDockResizeState() end
					return
				end
				if panel.Size == state.startSize and panel.Position == state.startPosition then return end

				local position = UDim2.new()
				local size = panel.Size
				state.saved.floating = { position = position, size = size }
				Studio:SetSetting(settingKey(state, "floating"), encode(position, size))
			end)

			panel:GetPropertyChangedSignal("Visible"):Connect(function()
				if not panel.Visible then state.resizing = false end
			end)
		end

		if options.backdrop == true then
			UI.create("UIBackdrop", {
				Enabled = true,
				BlurRadius = options.backdropBlur or 16,
				TintColor3 = options.backdropColor or colors.panel,
				TintTransparency = options.backdropTransparency or 0.78,
			}, panel)

			panel.BackgroundTransparency = options.panelTransparency or 0.08
		end

		local backgroundImageLabel = UI.image(panel, "", UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1))
		backgroundImageLabel.Name = "BackgroundImage"
		backgroundImageLabel.ZIndex = panel.ZIndex
		backgroundImageLabel.Active = false
		backgroundImageLabel.Selectable = false
		backgroundImageLabel.Visible = false
		local backgroundImageCorner = UI.corner(backgroundImageLabel, radius)

		local border = UI.stroke(
			panel,
			options.borderColor or colors.borderStrong,
			options.borderThickness or 1,
			options.borderTransparency or 0.35
		)

		local header = UI.frame(panel, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, headerHeight), headerColor, 0)

		header.Name = "Header"
		header.ClipsDescendants = true

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
			UI.tooltip(dragHandle, "Drag to move or dock this window")

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
					local absolute = panel.AbsolutePosition
					local parent = panel.Parent
					local offset = parent and parent:IsA("GuiObject") and parent.AbsolutePosition or Vector2.new(0, 0)
					panel.AnchorPoint = Vector2.new(0, 0)
					panel.Position = UDim2.fromOffset(absolute.X - offset.X, absolute.Y - offset.Y)
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

		local clip = UI.frame(panel, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 1, 0), colors.panel, radius, options.radius == nil and "md" or nil)

		clip.Name = "WindowClip"
		clip.BackgroundTransparency = 1
		clip.InputSink = false
		clip.Selectable = false

		local function styleValue(props, key)
			local value = props[key]

			if value ~= nil then
				return value
			end

			if options[key] ~= nil then
				return options[key]
			end

			return UI.tokens.window[key]
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
			local nextActiveTabColor = styleValue(props, "activeTabColor") or nextContentColor
			local imageVisible = UI.applyWindowBackground(
				backgroundImageLabel,
				styleValue(props, "backgroundImage"),
				styleValue(props, "backgroundImageTransparency"),
				styleValue(props, "backgroundImageScaleType"),
				styleValue(props, "backgroundImageColor")
			)
			local themeTint = UI.tokens.window.contentTransparency
			local contentTransparency = props.contentTransparency or options.contentTransparency
				or (imageVisible and themeTint or options.contentTransparencyWithoutImage or 0)
			local headerTransparency = styleValue(props, "headerTransparency") or (imageVisible and themeTint or 0)

			panel.BackgroundColor3 = styleValue(props, "panelColor") or tokens.panel

			local panelTransparency = styleValue(props, "panelTransparency")

			if options.backdrop == true or panelTransparency ~= nil then
				if panelTransparency == nil then
					panelTransparency = options.backdrop and 0.08 or 0
				end

				panel.BackgroundTransparency = panelTransparency
			end

			header.BackgroundColor3 = nextHeaderColor
			header.BackgroundTransparency = headerTransparency

			content.BackgroundColor3 = nextContentColor
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
				local fill = titleTab:FindFirstChild("BottomFill")

				titleTab.BackgroundColor3 = nextActiveTabColor

				if fill then
					fill.BackgroundColor3 = nextActiveTabColor
				end
			elseif tabsController then
				tabsController.setColors({
					bar = nextHeaderColor,
					content = nextContentColor,
					activeTab = nextActiveTabColor,
					inactiveTab = styleValue(props, "inactiveTabColor") or nextHeaderColor,
					hover = styleValue(props, "tabHoverColor") or tokens.hover,
					pressed = styleValue(props, "tabPressedColor") or tokens.pressed,
					activeText = styleValue(props, "activeTabTextColor") or tokens.text,
					inactiveText = styleValue(props, "inactiveTabTextColor") or tokens.muted,
				})
			end

			updateCorner(panel, nextRadius)
			updateCorner(clip, nextRadius)

			backgroundImageCorner.CornerRadius = UDim.new(0, nextRadius)
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
		controls.setTabDetached = tabsController and tabsController.setTabDetached
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

		local function refreshStyle()
			applyWindowComponent(UI.getComponentProps(componentKey))
		end

		controls.refreshBindings = {
			UI.onComponentRefresh("window", refreshStyle),
			UI.onComponentRefresh(componentKey, applyWindowComponent),
			UI.onThemeChanged(refreshStyle),
		}

		-- Restores component styling for windows created after a theme switch.
		refreshStyle()

		panel.Destroying:Connect(function()
			shared.windowBindings[windowKey] = nil
			if shared.windows[windowKey] == panel then
				shared.windows[windowKey] = nil
			end

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

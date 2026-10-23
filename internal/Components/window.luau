local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

return function(ctx)
	local UI = ctx.UI
	local shared = ctx.shared
	local colors = UI.tokens.color
	local tooltipSmoothTowards = ctx.tooltipSmoothTowards

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
		local tabGap = options.tabGap or 2
		local tabTop = options.tabTop or 4
		local tabPaddingX = options.tabPaddingX or 12
		local tabRadius = options.tabRadius or UI.tokens.radius.sm
		local tabSpeed = options.tabSpeed or 18

		local headerColor = options.headerColor or colors.panelRaised
		local contentColor = options.contentColor or colors.panel

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
		local activeTabColor = options.activeTabColor or contentColor
		local inactiveTabColor = options.inactiveTabColor or headerColor
		local tabHoverColor = options.tabHoverColor or colors.hover

		local activeText = options.activeTabTextColor or colors.text
		local inactiveText = options.inactiveTabTextColor or colors.muted

		local titleTab = nil
		local titleText = tostring(title or name)

		local titleLabel

		local indicator = nil

		local function makeTabShape(parent, pos, sz, color)
			local shape = UI.frame(parent, pos, sz, color, tabRadius)

			local fill = UI.frame(shape, UDim2.new(0, 0, 1, -tabRadius), UDim2.new(1, 0, 0, tabRadius), color, 0)
			fill.Name = "BottomFill"

			if options.tabAccentColor then
				local accent = UI.frame(
					shape,
					UDim2.fromOffset(tabRadius + 2, 0),
					UDim2.new(1, -(tabRadius + 2) * 2, 0, 2),
					options.tabAccentColor,
					1
				)
				accent.Name = "ActiveAccent"
			end

			return shape
		end

		if not hasTabs then
			local function titleWidth(text)
				return options.titleTabWidth or (#text * 7 + tabPaddingX * 2)
			end

			titleTab = makeTabShape(
				header,
				UDim2.fromOffset(titleX, tabTop),
				UDim2.fromOffset(titleWidth(titleText), tabHeight),
				activeTabColor
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

			indicator =
				makeTabShape(header, UDim2.fromOffset(titleX, tabTop), UDim2.fromOffset(0, tabHeight), activeTabColor)

			indicator.Name = "TabIndicator"
			indicator.Visible = false
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

			local UserInputService = game:GetService("UserInputService")

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
					if
						input.UserInputType == Enum.UserInputType.MouseButton1
						or input.UserInputType == Enum.UserInputType.Touch
					then
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

		local tabButtons = {}
		local pages = {}
		local selectedTab = nil

		local contentY = headerHeight

		local content = UI.frame(panel, UDim2.fromOffset(0, contentY), UDim2.new(1, 0, 1, -contentY), contentColor)

		content.Name = "Content"
		content.ClipsDescendants = true

		local controller = {}

		local function getTabName(tab)
			if type(tab) == "table" then
				return tab.name or tab.id or tab.text or "Tab"
			end

			return tostring(tab)
		end

		local function getTabText(tab)
			if type(tab) == "table" then
				return tab.text or tab.title or tab.name or tab.id or "Tab"
			end

			return tostring(tab)
		end

		local anim = {
			x = titleX,
			w = 0,
			running = false,
			snap = false,
		}

		local function wake()
			anim.running = true
		end

		local function step(dt)
			if not anim.running then
				return
			end

			local moving = false

			for tabName, data in pairs(tabButtons) do
				local active = tabName == selectedTab

				local activeTarget = active and 1 or 0
				local hoverTarget = (data.hovered and not active) and 1 or 0

				if anim.snap then
					data.activeAlpha = activeTarget
					data.hoverAlpha = hoverTarget
				else
					data.activeAlpha = tooltipSmoothTowards(data.activeAlpha, activeTarget, tabSpeed, dt)
					data.hoverAlpha = tooltipSmoothTowards(data.hoverAlpha, hoverTarget, tabSpeed, dt)
				end

				if math.abs(data.activeAlpha - activeTarget) < 0.005 then
					data.activeAlpha = activeTarget
				else
					moving = true
				end

				if math.abs(data.hoverAlpha - hoverTarget) < 0.005 then
					data.hoverAlpha = hoverTarget
				else
					moving = true
				end

				data.label.TextColor3 = inactiveText:Lerp(activeText, data.activeAlpha)
				data.button.BackgroundTransparency = 1 - data.hoverAlpha
			end

			local current = selectedTab and tabButtons[selectedTab]

			if current and indicator then
				indicator.Visible = true

				if anim.snap then
					anim.x, anim.w = current.x, current.width
				else
					anim.x = tooltipSmoothTowards(anim.x, current.x, tabSpeed, dt)
					anim.w = tooltipSmoothTowards(anim.w, current.width, tabSpeed, dt)
				end

				if math.abs(anim.x - current.x) < 0.25 and math.abs(anim.w - current.width) < 0.25 then
					anim.x, anim.w = current.x, current.width
				else
					moving = true
				end

				indicator.Position = UDim2.fromOffset(anim.x, tabTop)
				indicator.Size = UDim2.fromOffset(anim.w, tabHeight)
			end

			anim.snap = false
			anim.running = moving
		end

		local heartbeat = nil

		if hasTabs then
			heartbeat = RunService.Heartbeat:Connect(step)

			panel.Destroying:Connect(function()
				if heartbeat then
					heartbeat:Disconnect()
					heartbeat = nil
				end
			end)
		end

		function controller.selectTab(tabName)
			if not pages[tabName] then
				return
			end

			if selectedTab == tabName then
				return
			end

			local previousTab = selectedTab

			selectedTab = tabName

			for pageName, page in pairs(pages) do
				page.Visible = pageName == selectedTab
			end

			if previousTab == nil then
				anim.snap = true
			end

			wake()

			if options.onTabChanged then
				options.onTabChanged(tabName, previousTab, pages[tabName], panel)
			end
		end

		function controller.getSelectedTab()
			return selectedTab
		end

		function controller.getPage(tabName)
			return pages[tabName]
		end

		if hasTabs then
			local x = titleX

			for index, tab in ipairs(tabs) do
				local tabName = getTabName(tab)
				local tabText = getTabText(tab)

				local tabWidth = options.tabWidth
				if type(tab) == "table" and tab.width then
					tabWidth = tab.width
				end
				tabWidth = tabWidth or (#tabText * 7 + tabPaddingX * 2)

				local page = UI.frame(content, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 1, 0), contentColor)

				page.Name = tabName
				page.Visible = false
				page.ClipsDescendants = true

				pages[tabName] = page

				local button, label, record

				button, label, record = UI.button(
					header,
					tabText,
					UDim2.fromOffset(x, tabTop),
					UDim2.fromOffset(tabWidth, tabHeight),
					function()
						controller.selectTab(tabName)
					end,
					{
						color = inactiveTabColor,
						hoverColor = tabHoverColor,
						pressedColor = options.tabPressedColor or colors.pressed,
						textColor = inactiveText,
						textSize = options.tabTextSize or UI.tokens.type.small,
						textY = 0,
						radius = tabRadius,
						border = false,
						paddingX = tabPaddingX,
					}
				)

				button.Name = tabName .. "Tab"
				button.BackgroundTransparency = 1

				label.TextXAlignment = Enum.TextXAlignment.Center
				label.TextYAlignment = Enum.TextYAlignment.Center

				local data = {
					button = button,
					label = label,
					record = record,
					index = index,
					x = x,
					width = tabWidth,
					activeAlpha = 0,
					hoverAlpha = 0,
					hovered = false,
				}

				button.MouseEnter:Connect(function()
					data.hovered = true
					wake()
				end)

				button.MouseLeave:Connect(function()
					data.hovered = false
					wake()
				end)

				tabButtons[tabName] = data

				x += tabWidth + tabGap
			end

			local initialTab = options.selectedTab

			if not initialTab then
				initialTab = getTabName(tabs[1])
			end

			controller.selectTab(initialTab)

			step(0)
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
				indicator = indicator,
				closeButton = closeButton,
				dragHandle = dragHandle,
				border = border,
				clip = clip,

				tabBar = nil,
				tabs = tabButtons,
				pages = pages,

				selectTab = controller.selectTab,
				getSelectedTab = controller.getSelectedTab,
				getPage = controller.getPage,
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

local RunService = game:GetService("RunService")

return function(ctx)
	local UI = ctx.UI
	local tooltipSmoothTowards = ctx.tooltipSmoothTowards

	function UI.tabShape(parent, position, size, color, options)
		options = options or {}

		local colors = UI.tokens.color
		local tabRadius = options.radius or UI.tokens.radius.sm
		local filletRadius = options.filletRadius or 8
		local barColor = options.barColor or colors.panelRaised

		local function makeFillet(shape, side)
			local isLeft = side == "left"

			local square = UI.frame(
				shape,
				isLeft and UDim2.new(0, -filletRadius, 1, -filletRadius) or UDim2.new(1, 0, 1, -filletRadius),
				UDim2.fromOffset(filletRadius, filletRadius),
				color,
				0
			)

			square.Name = isLeft and "FilletLeft" or "FilletRight"
			square.ClipsDescendants = true

			local circle = UI.frame(
				square,
				isLeft and UDim2.fromOffset(-filletRadius, -filletRadius) or UDim2.fromOffset(0, -filletRadius),
				UDim2.fromOffset(filletRadius * 2, filletRadius * 2),
				barColor,
				filletRadius
			)

			circle.Name = "Cutout"
		end

		local shape = UI.frame(parent, position, size, color, tabRadius)
		shape.ClipsDescendants = false

		local fill = UI.frame(shape, UDim2.new(0, 0, 1, -tabRadius), UDim2.new(1, 0, 0, tabRadius), color, 0)
		fill.Name = "BottomFill"

		if options.accentColor then
			local accent = UI.frame(
				shape,
				UDim2.fromOffset(tabRadius + 2, 0),
				UDim2.new(1, -(tabRadius + 2) * 2, 0, 2),
				options.accentColor,
				1
			)
			accent.Name = "ActiveAccent"
		end

		if filletRadius > 0 then
			makeFillet(shape, "left")
			makeFillet(shape, "right")
		end

		return shape
	end

	function UI.tabs(parent, position, size, options)
		options = options or {}

		local colors = UI.tokens.color

		local tabs = options.tabs or {}
		local barHeight = options.barHeight or 30
		local startX = options.startX or 10
		local tabGap = options.tabGap or 2
		local tabTop = options.tabTop or 4
		local tabPaddingX = options.tabPaddingX or 12
		local tabRadius = options.tabRadius or UI.tokens.radius.sm
		local tabSpeed = options.tabSpeed or 18
		local filletRadius = options.tabFilletRadius or 8

		local barColor = options.barColor or colors.panelRaised
		local contentColor = options.contentColor or colors.panel

		local activeTabColor = options.activeTabColor or contentColor
		local inactiveTabColor = options.inactiveTabColor or barColor
		local tabHoverColor = options.tabHoverColor or colors.hover
		local tabPressedColor = options.tabPressedColor or colors.pressed

		local activeText = options.activeTabTextColor or colors.text
		local inactiveText = options.inactiveTabTextColor or colors.muted

		local tabHeight = barHeight - tabTop

		local container = nil
		local bar = options.barFrame
		local content = options.contentFrame

		if not bar or not content then
			container = UI.frame(parent, position, size, contentColor, 0)
			container.Name = "Tabs"
			container.ClipsDescendants = true
		end

		if not bar then
			bar = UI.frame(container, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, barHeight), barColor, 0)
			bar.Name = "TabBar"
			bar.ClipsDescendants = true
		end

		if not content then
			content =
				UI.frame(container, UDim2.fromOffset(0, barHeight), UDim2.new(1, 0, 1, -barHeight), contentColor, 0)
			content.Name = "Content"
			content.ClipsDescendants = true
		end

		local controller = {}
		local tabButtons = {}
		local pages = {}
		local selectedTab = nil

		local anim = {
			x = startX,
			w = 0,
			running = false,
			snap = false,
		}

		local indicator =
			UI.tabShape(bar, UDim2.fromOffset(startX, tabTop), UDim2.fromOffset(0, tabHeight), activeTabColor, {
				radius = tabRadius,
				filletRadius = filletRadius,
				barColor = barColor,
				accentColor = options.tabAccentColor,
			})

		indicator.Name = "TabIndicator"
		indicator.Visible = false

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

			if current then
				indicator.Visible = options.EnableIndicator or false

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

		local heartbeat = RunService.Heartbeat:Connect(step)

		function controller.destroy()
			if heartbeat then
				heartbeat:Disconnect()
				heartbeat = nil
			end
		end

		bar.Destroying:Connect(controller.destroy)

		function controller.selectTab(tabName)
			if not pages[tabName] or selectedTab == tabName then
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
				options.onTabChanged(tabName, previousTab, pages[tabName], container or bar.Parent)
			end
		end

		function controller.getSelectedTab()
			return selectedTab
		end

		function controller.getPage(tabName)
			return pages[tabName]
		end

		function controller.setColors(c)
			c = c or {}

			barColor = c.bar or barColor
			contentColor = c.content or contentColor
			activeTabColor = c.activeTab or activeTabColor
			inactiveTabColor = c.inactiveTab or inactiveTabColor
			tabHoverColor = c.hover or tabHoverColor
			tabPressedColor = c.pressed or tabPressedColor
			activeText = c.activeText or activeText
			inactiveText = c.inactiveText or inactiveText

			indicator.BackgroundColor3 = activeTabColor

			for _, d in ipairs(indicator:GetDescendants()) do
				if d.Name == "BottomFill" or d.Name == "FilletLeft" or d.Name == "FilletRight" then
					d.BackgroundColor3 = activeTabColor
				elseif d.Name == "Cutout" then
					d.BackgroundColor3 = barColor
				elseif d.Name == "ActiveAccent" and c.accent then
					d.BackgroundColor3 = c.accent
				end
			end

			for _, page in pairs(pages) do
				page.BackgroundColor3 = contentColor
			end

			for _, data in pairs(tabButtons) do
				local record = data.record

				if record then
					record.color = inactiveTabColor
					record.defaultColor = inactiveTabColor
					record.hoverColor = tabHoverColor
					record.defaultHoverColor = tabHoverColor
					record.pressedColor = tabPressedColor

					if UI.isAlive(record.gui) then
						record.gui.BackgroundColor3 = inactiveTabColor
					end
				end
			end

			wake()
		end

		local x = startX

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
				bar,
				tabText,
				UDim2.fromOffset(x, tabTop),
				UDim2.fromOffset(tabWidth, tabHeight),
				function()
					local wasSelected = selectedTab == tabName

					controller.selectTab(tabName)

					if options.onTabClicked then
						options.onTabClicked(tabName, wasSelected)
					end
				end,
				{
					color = inactiveTabColor,
					hoverColor = tabHoverColor,
					pressedColor = tabPressedColor,
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

		if #tabs > 0 then
			controller.selectTab(options.selectedTab or getTabName(tabs[1]))
			step(0)
		end

		controller.bar = bar
		controller.content = content
		controller.indicator = indicator
		controller.tabs = tabButtons
		controller.pages = pages

		return container, controller
	end
end

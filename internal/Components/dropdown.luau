local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

return function(ctx)
	local UI = ctx.UI
	local shared = ctx.shared
	local colors = UI.tokens.color
	local tooltipSmoothTowards = ctx.tooltipSmoothTowards
	local closeActiveDropdown

	local function removeButtonRecords(gui)
		UI.forgetButtons(gui)
	end

	closeActiveDropdown = function(instant)
		local active = shared.activeDropdown

		if not active then
			return
		end

		shared.activeDropdown = nil

		if active.dismiss then
			active.dismiss(instant == true)
		elseif active.menu then
			removeButtonRecords(active.menu)

			active.menu:Destroy()
		end

		if active.wake then
			active.wake()
		end
	end

	function UI.closeDropdown(instant)
		closeActiveDropdown(instant == true)
	end

	local function resolveDropdownItem(item)
		if type(item) == "table" then
			local itemValue = item.value

			if itemValue == nil then
				itemValue = item[1]
			end

			return itemValue,
				tostring(item.label or item.text or item.name or itemValue or ""),
				item.icon,
				item.shortcut
		end

		return item, tostring(item), nil, nil
	end

	local function createDropdownMenuAnimator(menu, config)
		local animate = config.animate ~= false
		local fadeSpeed = config.fadeSpeed or 22
		local sizeSpeed = config.sizeSpeed or 24
		local rowSpeed = config.rowSpeed or 22
		local rowHoverSpeed = config.rowHoverSpeed or 26
		local rowStagger = config.rowStagger or 0.025
		local maxStagger = config.maxStagger or 0.2
		local rowSlide = config.rowSlide or 8
		local slideDistance = config.slideDistance or 6
		local startScale = config.startScale or 0.6

		local anchorBottom = config.anchorBottom == true
		local dynamicRoot = config.dynamicRoot -- container whose children get rebuilt (search results)
		local x, y, width, height = config.x, config.y, config.width, config.height

		local state = {
			alpha = animate and 0 or 1,
			cur = animate and height * startScale or height,
			closing = false,
			started = false,
			destroyed = false,
			lastAlpha = nil,
		}

		local staticFades = {}
		local dynamicFades = {}
		local rows = {}
		local connection = nil
		local animator = {}

		menu.AnchorPoint = Vector2.new(0, anchorBottom and 1 or 0)

		local function addFades(list, obj)
			if obj:IsA("GuiObject") then
				table.insert(list, { obj = obj, prop = "BackgroundTransparency", base = obj.BackgroundTransparency })
			end

			if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
				table.insert(list, { obj = obj, prop = "TextTransparency", base = obj.TextTransparency })
			end

			if obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
				table.insert(list, { obj = obj, prop = "ImageTransparency", base = obj.ImageTransparency })
			end

			if obj:IsA("ScrollingFrame") then
				table.insert(
					list,
					{ obj = obj, prop = "ScrollBarImageTransparency", base = obj.ScrollBarImageTransparency }
				)
			end

			if obj:IsA("UIStroke") then
				table.insert(list, { obj = obj, prop = "Transparency", base = obj.Transparency })
			end

			if obj:IsA("UIBackdrop") then
				local okBlur, blur = pcall(function()
					return obj.BlurRadius
				end)

				local okTint, tint = pcall(function()
					return obj.TintTransparency
				end)

				if okBlur and type(blur) == "number" then
					table.insert(list, { obj = obj, prop = "BlurRadius", base = blur, blur = true })
				end

				if okTint and type(tint) == "number" then
					table.insert(list, { obj = obj, prop = "TintTransparency", base = tint })
				end
			end
		end

		local function applyList(list, a)
			for _, fade in ipairs(list) do
				if fade.blur then
					fade.obj[fade.prop] = fade.base * a
				else
					fade.obj[fade.prop] = 1 - (1 - fade.base) * a
				end
			end
		end

		local function applyFades(a)
			if a == state.lastAlpha then
				return
			end

			state.lastAlpha = a

			applyList(staticFades, a)
			applyList(dynamicFades, a)
		end

		local function place()
			local offsetY = (anchorBottom and 1 or -1) * slideDistance * (1 - state.alpha)

			menu.Position = UDim2.fromOffset(x, math.floor(y + offsetY + 0.5))
			menu.Size = UDim2.fromOffset(width, math.floor(state.cur + 0.5))
		end

		local function destroy()
			if state.destroyed then
				return
			end

			state.destroyed = true

			if connection then
				connection:Disconnect()
				connection = nil
			end

			UI.forgetButtons(menu)

			menu:Destroy()
		end

		local function updateRows(dt)
			for _, row in ipairs(rows) do
				local active = row.hovered or row.hover > 0 or row.appear < 1

				if row.appear < 1 then
					row.age += dt

					if row.age >= row.delay then
						row.appear = tooltipSmoothTowards(row.appear, 1, rowSpeed, dt)

						if row.appear > 0.995 then
							row.appear = 1
						end
					end
				end

				local hoverTarget = (row.hovered and row.record.enabled and not state.closing) and 1 or 0

				row.hover = tooltipSmoothTowards(row.hover, hoverTarget, rowHoverSpeed, dt)

				if math.abs(row.hover - hoverTarget) < 0.005 then
					row.hover = hoverTarget
				end

				if active then
					row.button.BackgroundColor3 = row.record.color:Lerp(row.record.hoverColor, row.hover)
					row.button.Position = UDim2.fromOffset(row.baseX - rowSlide * (1 - row.appear), row.baseY)
				end
			end
		end

		local function step(dt)
			if state.destroyed then
				return
			end

			if not UI.isAlive(menu) then
				destroy()

				return
			end

			local target = state.closing and 0 or 1

			if animate then
				state.alpha = tooltipSmoothTowards(state.alpha, target, fadeSpeed, dt)

				if math.abs(state.alpha - target) < 0.01 then
					state.alpha = target
				end

				state.cur = tooltipSmoothTowards(state.cur, height, sizeSpeed, dt)

				if math.abs(state.cur - height) < 0.5 then
					state.cur = height
				end
			else
				state.alpha, state.cur = target, height
			end

			updateRows(dt)
			applyFades(state.alpha)
			place()

			if state.closing and state.alpha <= 0.01 then
				destroy()
			end
		end

		-- Rows added before start() get the staggered slide-in; rows added later (search) appear instantly.
		function animator.addRow(rowButton, record, index)
			local row = {
				button = rowButton,
				record = record,
				baseX = rowButton.Position.X.Offset,
				baseY = rowButton.Position.Y.Offset,
				hover = 0,
				hovered = false,
				appear = (animate and not state.started) and 0 or 1,
				age = 0,
				delay = math.min((index or (#rows + 1)) * rowStagger, maxStagger),
			}

			table.insert(rows, row)

			rowButton.MouseEnter:Connect(function()
				row.hovered = true
			end)

			rowButton.MouseLeave:Connect(function()
				row.hovered = false
			end)
		end

		function animator.clearRows()
			rows = {}
		end

		-- call after rebuilding the contents of dynamicRoot
		function animator.refresh()
			if not state.started or not dynamicRoot then
				return
			end

			dynamicFades = {}

			for _, descendant in ipairs(dynamicRoot:GetDescendants()) do
				addFades(dynamicFades, descendant)
			end

			state.lastAlpha = nil
		end

		function animator.start()
			if state.started then
				return
			end

			state.started = true

			addFades(staticFades, menu)

			for _, descendant in ipairs(menu:GetDescendants()) do
				if dynamicRoot and descendant ~= dynamicRoot and descendant:IsDescendantOf(dynamicRoot) then
					addFades(dynamicFades, descendant)
				else
					addFades(staticFades, descendant)
				end
			end

			-- apply the starting state immediately so the menu never flashes at full opacity
			applyFades(state.alpha)
			place()

			connection = RunService.Heartbeat:Connect(step)
		end

		function animator.dismiss(instant)
			if state.destroyed or state.closing then
				return
			end

			if instant or not animate or not state.started then
				destroy()

				return
			end

			state.closing = true

			-- stop the fading menu from receiving clicks
			for _, descendant in ipairs(menu:GetDescendants()) do
				if descendant:IsA("TextButton") or descendant:IsA("ImageButton") or descendant:IsA("TextBox") then
					descendant.Active = false
				end
			end
		end

		return animator
	end

	function UI.dropdown(parent, value, position, size, chevronIcon, options)
		options = options or {}

		local colors = UI.tokens.color

		local currentValue = value

		local items = options.items or {}

		local animate = options.animate ~= false
		local speed = options.animationSpeed or 22
		local hoverEnabled = options.hoveringEnabled ~= false

		local button
		local label
		local record
		local chevron

		local controller = {}

		local function menuOverlay()
			local overlay = options.menuParent or UI.contextMenuOverlay()

			if overlay and overlay:IsA("ScreenGui") then
				pcall(function()
					overlay.Enabled = true
				end)
			end

			return overlay or UI.root()
		end

		local anim = {
			hover = 0,
			press = 0,
			open = 0,
			hovered = false,
			pressed = false,
			running = true,
			destroyed = false,
		}

		local function isOpen()
			local active = shared.activeDropdown

			return active ~= nil and active.controller == controller
		end

		local function wake()
			anim.running = true
		end

		local function choose(itemValue, itemText, item)
			currentValue = itemValue

			if not options.keepLabel then
				label.Text = itemText
			end

			closeActiveDropdown()

			if options.onChanged then
				options.onChanged(itemValue, item)
			end
		end

		local function newMenuAnimator(menu, extra)
			local config = {
				animate = animate,
				fadeSpeed = options.menuFadeSpeed,
				sizeSpeed = options.menuSizeSpeed,
				slideDistance = options.menuSlide,
				rowSlide = options.rowSlide,
				rowStagger = options.rowStagger,
			}

			for key, configValue in pairs(extra) do
				config[key] = configValue
			end

			return createDropdownMenuAnimator(menu, config)
		end

		local function buildRow(list, y, item, rowHeight, index, animator, highlight, suffix)
			local itemValue, itemText, icon = resolveDropdownItem(item)

			local selected = highlight and itemValue == currentValue

			local row, _, rowRecord = UI.button(
				list,
				itemText .. (suffix or ""),
				UDim2.fromOffset(0, y),
				UDim2.new(1, 0, 0, rowHeight),
				function()
					choose(itemValue, itemText, item)
				end,
				{
					color = selected and colors.selection or options.menuColor or colors.panelRaised,
					hoverColor = selected and colors.selectionHover or colors.hover,
					pressedColor = colors.pressed,
					textColor = selected and colors.text or colors.subtext,
					textSize = options.textSize or UI.tokens.type.small,
					radius = 0,
					border = false,
					paddingX = UI.tokens.space.md,
					icon = icon,
					iconSize = options.iconSize or 14,
					selected = selected,
					hoveringEnabled = false, -- the animator drives row hover
				}
			)

			row.BackgroundTransparency = options.itemBgTransparency or options.BackgroundTransparency or 0

			animator.addRow(row, rowRecord, index)

			return row
		end

		local function openMenu()
			local rowHeight = options.itemHeight or UI.metrics.inputHeight
			local maxVisibleItems = options.maxVisibleItems or 8
			local gap = options.menuGap or 2
			local margin = options.menuMargin or 4

			local desiredRows = math.max(1, math.min(#items, maxVisibleItems))
			local menuWidth = options.menuWidth or 140

			local menuPositionOption = options.menuPosition
			local fixedMenuPosition

			if type(menuPositionOption) == "function" then
				fixedMenuPosition = menuPositionOption()
			elseif typeof(menuPositionOption) == "UDim2" then
				fixedMenuPosition = menuPositionOption
			end

			---------------------------------------------------------------------
			-- Fixed position menu (with optional search / categories)
			---------------------------------------------------------------------
			if fixedMenuPosition then
				local overlay = menuOverlay()
				local screen = workspace:GetWindowDimensions()
				local edge = margin

				local showSearch = options.showSearch ~= false
				local searchHeight = showSearch and 34 or 0

				local totalHeight = desiredRows * rowHeight + searchHeight

				totalHeight = math.min(totalHeight, math.max(screen.Y - edge * 2, 1))

				local clampedWidth = math.min(menuWidth, math.max(screen.X - edge * 2, 1))

				local px = fixedMenuPosition.X.Scale * screen.X + fixedMenuPosition.X.Offset
				local py = fixedMenuPosition.Y.Scale * screen.Y + fixedMenuPosition.Y.Offset

				local flipped = false

				if px + clampedWidth > screen.X - edge then
					px = px - clampedWidth
				end

				if py + totalHeight > screen.Y - edge then
					py = py - totalHeight
					flipped = true
				end

				px = math.clamp(px, edge, math.max(edge, screen.X - clampedWidth - edge))
				py = math.clamp(py, edge, math.max(edge, screen.Y - totalHeight - edge))

				local menu = UI.frame(
					overlay,
					UDim2.fromOffset(px, py),
					UDim2.fromOffset(clampedWidth, totalHeight),
					options.menuColor or colors.panelRaised,
					options.radius or UI.tokens.radius.sm
				)

				if options.backdrop then
					UI.create("UIBackdrop", {
						Enabled = true,
						BlurRadius = options.backdropBlur or 18,
						TintColor3 = options.backdropColor or colors.panelRaised,
						TintTransparency = options.backdropTransparency or options.BackgroundTransparency or 0.85,
					}, menu)
				end

				menu.BackgroundTransparency = options.BackgroundTransparency or 0
				menu.Name = "DropdownMenu"
				menu.ZIndex = options.menuZIndex or 100000
				menu.ClipsDescendants = true

				UI.stroke(menu, options.borderColor or colors.borderStrong, 1, options.borderTransparency or 0)

				local search

				if showSearch then
					search = UI.input(
						menu,
						options.searchPlaceholder or "Search...",
						UDim2.fromOffset(5, 5),
						UDim2.new(1, -10, 0, 24),
						{ textSize = options.textSize or UI.tokens.type.small }
					)

					search.ZIndex = (options.menuZIndex or 100000) + 1
					controller.SearchBox = search
				end

				local list = UI.create("ScrollingFrame", {
					Position = UDim2.fromOffset(0, searchHeight),
					Size = UDim2.new(1, 0, 1, -searchHeight),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					CanvasPosition = Vector2.new(0, 0),
					CanvasSize = UDim2.new(1, 0, 0, 0),
					ScrollingEnabled = true,
					ScrollBarThickness = 5,
					ScrollBarImageColor3 = colors.subtext,
					ScrollBarImageTransparency = 0.4,
					ScrollBarAutoHide = true,
					ClipsDescendants = true,
				}, menu)

				list.ZIndex = (options.menuZIndex or 100000) + 1

				local animator = newMenuAnimator(menu, {
					x = px,
					y = flipped and (py + totalHeight) or py,
					width = clampedWidth,
					height = totalHeight,
					anchorBottom = flipped,
					dynamicRoot = list,
				})

				local function itemMatches(item, query)
					if query == "" then
						return true
					end

					local _, itemText = resolveDropdownItem(item)

					return string.find(string.lower(itemText), query, 1, true) ~= nil
				end

				local function renderItems()
					UI.clear(list)
					animator.clearRows()

					local query = search and string.lower(search.Text or "") or ""
					local y = 0
					local visible = 0

					local categories = options.categories

					if categories then
						for _, category in ipairs(categories) do
							local categoryItems = {}

							for _, item in ipairs(category.items or {}) do
								if itemMatches(item, query) then
									table.insert(categoryItems, item)
								end
							end

							if #categoryItems > 0 then
								UI.label(
									list,
									category.name,
									UDim2.fromOffset(10, y + 3),
									UDim2.new(1, -20, 0, rowHeight - 4),
									options.categoryTextSize or 10,
									colors.muted
								)

								y += rowHeight

								for _, item in ipairs(categoryItems) do
									local _, _, _, shortcut = resolveDropdownItem(item)

									visible += 1

									buildRow(
										list,
										y,
										item,
										rowHeight,
										visible,
										animator,
										false,
										shortcut and ("    " .. shortcut) or ""
									)

									y += rowHeight
								end
							end
						end
					else
						for _, item in ipairs(items) do
							if itemMatches(item, query) then
								visible += 1

								buildRow(list, y, item, rowHeight, visible, animator, false)

								y += rowHeight
							end
						end
					end

					list.CanvasSize = UDim2.new(1, 0, 0, math.max(y, rowHeight))

					animator.refresh()
				end

				if search then
					search.TextChanged:Connect(renderItems)
					search.FocusLost:Connect(renderItems)
				end

				renderItems()

				animator.start()

				shared.activeDropdown = {
					button = button,
					menu = menu,
					controller = controller,
					closeOnOutsideClick = options.closeOnOutsideClick ~= false,
					dismiss = animator.dismiss,
					wake = wake,
				}

				wake()

				return
			end

			---------------------------------------------------------------------
			-- Menu anchored to the button
			---------------------------------------------------------------------
			local absolutePosition = button.AbsolutePosition
			local absoluteSize = button.AbsoluteSize

			if not absolutePosition or not absoluteSize then
				return
			end

			local boundsSize = workspace:GetWindowDimensions()

			local boundsLeft = margin
			local boundsTop = margin
			local boundsRight = boundsSize.X - margin
			local boundsBottom = boundsSize.Y - margin

			menuWidth = math.min(menuWidth, math.max(1, boundsRight - boundsLeft))

			local menuX = absolutePosition.X

			if options.menuSide == "left" then
				menuX = absolutePosition.X - menuWidth - gap
			end

			if options.menuSide ~= "left" and menuX + menuWidth > boundsRight then
				menuX = boundsRight - menuWidth
			end

			if options.menuSide ~= "left" and menuX < boundsLeft then
				menuX = boundsLeft
			end

			local buttonTop = absolutePosition.Y
			local buttonBottom = absolutePosition.Y + absoluteSize.Y

			local spaceBelow = boundsBottom - buttonBottom - gap
			local spaceAbove = buttonTop - boundsTop - gap

			local desiredHeight = desiredRows * rowHeight

			local openAbove = desiredHeight > spaceBelow and spaceAbove > spaceBelow

			local availableSpace = openAbove and spaceAbove or spaceBelow

			local visibleRows = math.clamp(math.floor(availableSpace / rowHeight), 1, desiredRows)

			local menuHeight = visibleRows * rowHeight

			local menuY

			if openAbove then
				menuY = buttonTop - menuHeight - gap
			else
				menuY = buttonBottom + gap
			end

			menuY = math.clamp(menuY, boundsTop, math.max(boundsTop, boundsBottom - menuHeight))

			local menu = UI.create("ScrollingFrame", {
				Position = UDim2.fromOffset(menuX, menuY),
				Size = UDim2.fromOffset(menuWidth, menuHeight),
				BackgroundColor3 = options.menuColor or colors.panelRaised,
				BackgroundTransparency = options.BackgroundTransparency or 0,
				BorderSizePixel = 0,
				CanvasPosition = Vector2.new(0, 0),
				CanvasSize = UDim2.new(1, 0, 0, #items * rowHeight),
				ScrollingEnabled = #items > visibleRows,
				ScrollBarThickness = 5,
				ScrollBarImageColor3 = colors.subtext,
				ScrollBarImageTransparency = 0.4,
				ScrollBarAutoHide = true,
				ScrollBarFadeDelay = 0.45,
				ScrollBarFadeSpeed = 12,
				ClipsDescendants = true,
			}, menuOverlay())

			UI.corner(menu, options.radius or UI.tokens.radius.sm)

			if options.backdrop then
				UI.create("UIBackdrop", {
					Enabled = true,
					BlurRadius = options.backdropBlur or 18,
					TintColor3 = options.backdropColor or colors.panelRaised,
					TintTransparency = options.backdropTransparency or 0.85,
				}, menu)
			end

			menu.Name = "DropdownMenu"
			menu.ZIndex = options.menuZIndex or 100000
			menu.ClipsDescendants = true

			UI.stroke(menu, options.borderColor or colors.borderStrong, 1, options.borderTransparency or 0)

			local animator = newMenuAnimator(menu, {
				x = menuX,
				y = openAbove and (menuY + menuHeight) or menuY,
				width = menuWidth,
				height = menuHeight,
				anchorBottom = openAbove,
			})

			for index, item in ipairs(items) do
				buildRow(menu, (index - 1) * rowHeight, item, rowHeight, index, animator, true)
			end

			animator.start()

			shared.activeDropdown = {
				button = button,
				menu = menu,
				controller = controller,
				closeOnOutsideClick = options.closeOnOutsideClick ~= false,
				dismiss = animator.dismiss,
				wake = wake,
			}

			wake()
		end

		button, label, record = UI.button(
			parent,
			tostring(options.format and options.format(value) or value or ""),
			position,
			size or UDim2.fromOffset(140, UI.metrics.inputHeight),
			function()
				if isOpen() then
					closeActiveDropdown()

					return
				end

				closeActiveDropdown()

				openMenu()
			end,
			{
				color = options.color or colors.input,

				hoverColor = options.hoverColor or colors.hover,

				pressedColor = options.pressedColor or colors.pressed,

				textColor = options.textColor or colors.subtext,

				textSize = options.textSize or UI.tokens.type.small,

				radius = options.radius or UI.tokens.radius.sm,

				border = options.border ~= false,

				borderColor = options.borderColor or colors.border,

				paddingX = options.paddingX or UI.tokens.space.md,

				textY = options.textY,

				icon = options.icon,

				iconSize = options.iconSize or 14,

				hoveringEnabled = false, -- hover / press colours are driven by the animation below
			}
		)

		if chevronIcon then
			local iconSize = options.chevronSize or 12

			chevron = UI.image(
				button,
				chevronIcon,
				UDim2.new(1, -(iconSize + 6), 0.5, -math.floor(iconSize / 2)),
				UDim2.fromOffset(iconSize, iconSize)
			)

			chevron.Name = "Chevron"

			label.Size = UDim2.new(1, -(iconSize + 18), 1, 0)
		end

		---------------------------------------------------------------------
		-- Trigger button animation
		---------------------------------------------------------------------
		local stroke = button:FindFirstChildOfClass("UIStroke")

		local function renderButton()
			local focus = math.max(anim.hover, anim.open * 0.7)

			local color = record.color:Lerp(record.hoverColor, focus)

			color = color:Lerp(record.pressedColor, anim.press)

			button.BackgroundColor3 = color

			if stroke then
				stroke.Color = (options.borderColor or colors.border):Lerp(colors.borderStrong, anim.open)
			end

			if chevron then
				chevron.Rotation = 180 * anim.open
			end
		end

		button.MouseEnter:Connect(function()
			anim.hovered = true
			wake()
		end)

		button.MouseLeave:Connect(function()
			anim.hovered = false
			wake()
		end)

		button.MouseButton1Down:Connect(function()
			anim.pressed = true
			wake()
		end)

		-- MouseButton1Up only fires over the button, so release is tracked globally
		local inputEnded = UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				anim.pressed = false
				wake()
			end
		end)

		local heartbeat
		local themeListener

		local function cleanup()
			if anim.destroyed then
				return
			end

			anim.destroyed = true

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

		-- repaint once after a theme change, even if the button is idle
		themeListener = UI.onThemeChanged(function()
			if not anim.destroyed then
				wake()
			end
		end)

		heartbeat = RunService.Heartbeat:Connect(function(dt)
			if anim.destroyed then
				return
			end

			if not UI.isAlive(button) then
				cleanup()

				return
			end

			if not anim.running then
				return
			end

			local hoverTarget = (hoverEnabled and anim.hovered and not anim.pressed) and 1 or 0
			local pressTarget = (hoverEnabled and anim.pressed) and 1 or 0
			local openTarget = isOpen() and 1 or 0

			local moving = false

			if animate then
				anim.hover = tooltipSmoothTowards(anim.hover, hoverTarget, speed, dt)
				anim.press = tooltipSmoothTowards(anim.press, pressTarget, speed * 1.6, dt)
				anim.open = tooltipSmoothTowards(anim.open, openTarget, speed * 0.8, dt)

				if math.abs(anim.hover - hoverTarget) < 0.005 then
					anim.hover = hoverTarget
				else
					moving = true
				end

				if math.abs(anim.press - pressTarget) < 0.005 then
					anim.press = pressTarget
				else
					moving = true
				end

				if math.abs(anim.open - openTarget) < 0.005 then
					anim.open = openTarget
				else
					moving = true
				end
			else
				anim.hover, anim.press, anim.open = hoverTarget, pressTarget, openTarget
			end

			renderButton()

			anim.running = moving
		end)

		button.Destroying:Connect(cleanup)

		---------------------------------------------------------------------
		-- Controller
		---------------------------------------------------------------------
		function controller:GetValue()
			return currentValue
		end

		function controller:SetValue(newValue, silent)
			currentValue = newValue

			if not options.keepLabel then
				label.Text = tostring(options.format and options.format(newValue) or newValue or "")
			end

			if not silent and options.onChanged then
				options.onChanged(newValue)
			end
		end

		function controller:SetItems(newItems)
			items = newItems or {}

			if isOpen() then
				closeActiveDropdown()
			end
		end

		function controller:IsOpen()
			return isOpen()
		end

		function controller:Open()
			if isOpen() or record == nil or record.destroyed or not UI.isAlive(record.gui) then
				return
			end

			record.callback()
		end

		function controller:Close(instant)
			if isOpen() then
				closeActiveDropdown(instant)
			end
		end

		function controller:Destroy()
			if isOpen() then
				closeActiveDropdown(true)
			end

			cleanup()

			UI.forgetButtons(button)

			button:Destroy()
		end

		controller.button = button

		controller.label = label

		controller.chevron = chevron

		controller.record = record

		button.BackgroundTransparency = options.BackgroundTransparency or 0

		renderButton()

		return button, label, controller
	end
end

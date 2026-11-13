local Preferences = require("@internal/preferences")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

return function(ctx)
	local UI = ctx.UI

	local function tween(instance, props, duration, style, direction)
		local info =
			TweenInfo.new(duration or 0.15, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
		local t = TweenService:Create(instance, info, props)
		t:Play()
		return t
	end

	local function toKeyList(key)
		if key == nil then
			return {}
		elseif typeof(key) == "EnumItem" then
			return { key }
		end
		return key
	end

	function UI.iconButtonGroup(parent, position, items, options)
		options = options or {}

		local tokens = UI.tokens
		local palette = UI.colors or {}

		local vertical = options.orientation == "vertical"
		local mode = options.mode or "momentary"
		local defaultSize = options.buttonSize or Vector2.new(28, 21)
		local gap = options.gap or 4
		local pad = options.padding or 1
		local iconSize = options.iconSize or 14
		local animate = options.animate ~= false
		local animateIn = animate and options.animateIn ~= false

		local groupColor = options.color or tokens.color.surfaceAlt
		local activeColor = options.activeColor or palette.accent or Color3.fromRGB(0, 120, 215)
		local hoverColor = options.hoverColor or palette.hover or Color3.fromRGB(70, 70, 70)
		local pressedColor = palette.pressed or hoverColor

		local main, cross = pad * 2, pad * 2
		local count = 0
		for _, item in ipairs(items) do
			local s = item.size or defaultSize
			local extent = item.separator and 1 or (vertical and s.Y or s.X)
			local crossExtent = item.separator and 0 or (vertical and s.X or s.Y)
			main += extent
			cross = math.max(cross, crossExtent + pad * 2)
			count += 1
		end
		main += gap * math.max(0, count - 1)

		local initialSize = vertical and UDim2.fromOffset(cross, main) or UDim2.fromOffset(main, cross)

		local group = UI.group(parent, position, initialSize, {
			color = groupColor,
			radius = options.radius or tokens.radius.sm,
		})
		group.Name = options.name or "IconButtonGroup"
		if options.anchorPoint then
			group.AnchorPoint = options.anchorPoint
		end

		local track = UI.create("Frame", {
			Name = "Track",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = group.ZIndex,
		}, group)

		local itemsFrame = UI.create("Frame", {
			Name = "Items",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = group.ZIndex + 1,
		}, group)

		UI.create("UIPadding", {
			PaddingLeft = UDim.new(0, pad),
			PaddingRight = UDim.new(0, pad),
			PaddingTop = UDim.new(0, pad),
			PaddingBottom = UDim.new(0, pad),
		}, itemsFrame)

		local layout = UI.create("UIListLayout", {
			FillDirection = vertical and Enum.FillDirection.Vertical or Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, gap),
		}, itemsFrame)

		local indicator = nil
		if mode == "radio" then
			indicator = UI.frame(
				track,
				UDim2.fromOffset(0, 0),
				UDim2.fromOffset(defaultSize.X, defaultSize.Y),
				activeColor,
				options.buttonRadius or tokens.radius.xs
			)
			indicator.Name = "Indicator"
			indicator.BackgroundTransparency = 0.1
			indicator.Visible = false
		end

		local records = {}
		local order = {}
		local connections = {}
		local changed = Instance.new("BindableEvent")
		local selected = nil
		local destroyed = false

		local function connect(signal, fn)
			local c = signal:Connect(fn)
			table.insert(connections, c)
			return c
		end

		local function findIcon(button)
			return button:FindFirstChildOfClass("ImageLabel")
		end

		local function isActive(record)
			if mode == "radio" and not record.toggle then
				return selected == record.name
			end
			return record.active == true
		end

		local function iconRestTransparency(record)
			return record.disabled and 0.65 or 0
		end

		local function applyVisual(record, animated)
			local button = record.button
			local dur = (animate and animated) and 0.12 or 0

			local bgColor, bgTransparency = hoverColor, 1

			if record.disabled then
				bgTransparency = 1
			elseif record.pressed then
				bgColor, bgTransparency = pressedColor, 0.4
			elseif (mode ~= "radio" or record.toggle) and isActive(record) then
				bgColor, bgTransparency = activeColor, record.hovered and 0.0 or 0.1
			elseif record.hovered then
				bgColor, bgTransparency = hoverColor, 0.6
			end

			tween(button, { BackgroundColor3 = bgColor, BackgroundTransparency = bgTransparency }, dur)

			if record.icon and not record.fading then
				tween(record.icon, { ImageTransparency = iconRestTransparency(record) }, dur)
			end
		end

		local function refreshIndicator(animated)
			if not indicator then
				return
			end

			local record = selected and records[selected]
			if not record or not record.visible then
				indicator.Visible = false
				return
			end

			local button = record.button
			local offset = button.AbsolutePosition - track.AbsolutePosition
			local goalPos = UDim2.fromOffset(offset.X, offset.Y)
			local goalSize = UDim2.fromOffset(button.AbsoluteSize.X, button.AbsoluteSize.Y)

			if not indicator.Visible or not animate or not animated then
				indicator.Position = goalPos
				indicator.Size = goalSize
				indicator.Visible = true
			else
				tween(indicator, { Position = goalPos, Size = goalSize }, 0.22, Enum.EasingStyle.Back)
			end
		end

		-- Fade a record's icon in (from invisible) after an optional delay
		local function fadeIn(record, delay)
			if not record.icon then
				return
			end
			record.fading = true
			record.icon.ImageTransparency = 1
			task.delay(delay or 0, function()
				if destroyed then
					return
				end
				record.fading = false
				tween(record.icon, { ImageTransparency = iconRestTransparency(record) }, 0.25)
			end)
		end

		local function fadeOut(record, onDone)
			if not record.icon then
				if onDone then
					onDone()
				end
				return
			end
			record.fading = true
			local t = tween(record.icon, { ImageTransparency = 1 }, 0.15)
			if onDone then
				t.Completed:Once(onDone)
			end
		end

		local function setActive(record, value, silent)
			if mode == "radio" and not record.toggle then
				if not value or selected == record.name then
					return
				end
				local previous = selected and records[selected]
				selected = record.name
				if previous then
					applyVisual(previous, true)
				end
				applyVisual(record, true)
				refreshIndicator(true)
			else
				if record.active == value then
					return
				end
				record.active = value
				applyVisual(record, true)
			end

			if not silent then
				changed:Fire(record.name, value)
			end
		end

		local function activate(record)
			if record.disabled or not record.visible then
				return
			end

			local value = true
			if mode == "radio" and not record.toggle then
				setActive(record, true)
				value = true
			elseif record.toggle or mode == "toggle" then
				value = not record.active
				setActive(record, value)
			else
				changed:Fire(record.name, true)
			end

			if record.onClick then
				record.onClick(value)
			end
		end

		for index, item in ipairs(items) do
			if item.separator then
				local sepFrame = UI.separator(
					itemsFrame,
					UDim2.fromOffset(0, 0),
					vertical and UDim2.fromOffset(defaultSize.X - 6, 1) or UDim2.fromOffset(1, defaultSize.Y - 4)
				)
				sepFrame.LayoutOrder = index
				table.insert(order, { separator = sepFrame })
			else
				local size = item.size or defaultSize
				local record = {
					name = item.name,
					toggle = item.toggle,
					active = item.active == true,
					disabled = item.disabled == true,
					visible = item.visible ~= false,
					onClick = item.onClick,
					keys = toKeyList(item.key),
					tooltipText = item.tooltip,
					hovered = false,
					pressed = false,
					fading = false,
				}

				local button = UI.iconButton(
					itemsFrame,
					item.icon,
					UDim2.fromOffset(0, 0),
					UDim2.fromOffset(size.X, size.Y),
					function()
						activate(record)
					end,
					{
						color = groupColor,
						hoverColor = hoverColor,
						pressedColor = pressedColor,
						radius = options.buttonRadius or tokens.radius.xs,
						border = false,
						iconSize = iconSize,
					}
				)

				button.Name = item.name
				button.LayoutOrder = index
				button.BackgroundTransparency = 1
				button.Visible = record.visible

				record.button = button
				record.icon = findIcon(button)

				if item.tooltip then
					local text = item.tooltip
					if record.keys[1] then
						text ..= " (" .. record.keys[1].Name .. ")"
					end
					UI.tooltip(button, text, { placement = "cursor", hoverDelay = 0.35 })
				end

				connect(button.MouseEnter, function()
					record.hovered = true
					applyVisual(record, true)
				end)

				connect(button.MouseLeave, function()
					record.hovered = false
					record.pressed = false
					applyVisual(record, true)
				end)

				if button:IsA("GuiButton") then
					connect(button.MouseButton1Down, function()
						record.pressed = true
						applyVisual(record, true)
					end)
					connect(button.MouseButton1Up, function()
						record.pressed = false
						applyVisual(record, true)
					end)
				end

				records[item.name] = record
				table.insert(order, record)

				if mode == "radio" and options.selected == item.name then
					selected = item.name
				end

				applyVisual(record, false)
			end
		end

		connect(layout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
			local content = layout.AbsoluteContentSize
			local goal = vertical and UDim2.fromOffset(cross, content.Y + pad * 2)
				or UDim2.fromOffset(content.X + pad * 2, cross)
			if animate and group.Visible then
				tween(group, { Size = goal }, 0.2)
			else
				group.Size = goal
			end
			task.defer(refreshIndicator, true)
		end)

		-- Staggered fade-in of the icons
		local function playIn()
			local n = 0
			for _, record in ipairs(order) do
				if record.button then
					fadeIn(record, n * 0.05)
					n += 1
				end
			end
		end

		if animateIn then
			playIn()
		end

		task.defer(function()
			refreshIndicator(false)
		end)

		connect(UserInputService.InputBegan, function(input)
			if not Preferences.get("enableKeyboardShortcuts") or input.UserInputType ~= Enum.UserInputType.Keyboard then
				return
			end
			if UserInputService:GetFocusedTextBox() then
				return
			end
			for _, record in pairs(records) do
				if table.find(record.keys, input.KeyCode) then
					activate(record)
					break
				end
			end
		end)

		local controller = {}
		controller.Changed = changed.Event

		local function get(name)
			return records[name]
		end

		function controller:GetButton(name)
			local record = get(name)
			return record and record.button
		end

		function controller:GetActive(name)
			local record = get(name)
			if mode == "radio" and not (record and record.toggle) then
				return selected
			end
			return record and record.active or false
		end

		function controller:SetActive(name, value, silent)
			local record = get(name)
			if record then
				setActive(record, value ~= false, silent)
			end
		end

		function controller:Click(name)
			local record = get(name)
			if record then
				activate(record)
			end
		end

		function controller:SetEnabled(name, enabled)
			local record = get(name)
			if record then
				record.disabled = not enabled
				record.button.Active = enabled
				applyVisual(record, true)
			end
		end

		function controller:SetVisible(name, visible)
			local record = get(name)
			if not record or record.visible == visible then
				return
			end
			record.visible = visible

			if visible then
				record.button.Visible = true
				if animate then
					fadeIn(record, 0)
				else
					record.fading = false
					applyVisual(record, false)
				end
			elseif animate then
				fadeOut(record, function()
					if not record.visible then
						record.button.Visible = false
					end
				end)
			else
				record.button.Visible = false
			end
		end

		function controller:SetIcon(name, image)
			local record = get(name)
			if not record or not record.icon then
				return
			end
			if not animate then
				record.icon.Image = image
				return
			end
			local out = tween(record.icon, { ImageTransparency = 1 }, 0.08)
			out.Completed:Once(function()
				record.icon.Image = image
				tween(record.icon, { ImageTransparency = iconRestTransparency(record) }, 0.12)
			end)
		end

		function controller:SetBadge(name, text)
			local record = get(name)
			if not record then
				return
			end

			if text == nil or text == "" then
				if record.badge then
					local badge = record.badge
					record.badge = nil
					local t = tween(badge, { Size = UDim2.fromOffset(0, 0) }, 0.15)
					t.Completed:Once(function()
						badge:Destroy()
					end)
				end
				return
			end

			if not record.badge then
				local badge = UI.create("Frame", {
					Name = "Badge",
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, 2, 0, -2),
					Size = animate and UDim2.fromOffset(0, 0) or UDim2.fromOffset(12, 12),
					BackgroundColor3 = Color3.fromRGB(235, 70, 70),
					ZIndex = record.button.ZIndex + 5,
					Active = false,
				}, record.button)
				UI.create("UICorner", { CornerRadius = UDim.new(1, 0) }, badge)
				local label = UI.label(
					badge,
					tostring(text),
					UDim2.fromOffset(0, 0),
					UDim2.fromScale(1, 1),
					9,
					Color3.new(1, 1, 1)
				)
				label.TextXAlignment = Enum.TextXAlignment.Center
				label.TextYAlignment = Enum.TextYAlignment.Center
				label.Name = "BadgeText"
				record.badge = badge
				if animate then
					tween(badge, { Size = UDim2.fromOffset(12, 12) }, 0.25, Enum.EasingStyle.Back)
				end
			else
				local label = record.badge:FindFirstChild("BadgeText")
				if label then
					label.Text = tostring(text)
				end
				if animate then
					record.badge.Size = UDim2.fromOffset(8, 8)
					tween(record.badge, { Size = UDim2.fromOffset(12, 12) }, 0.25, Enum.EasingStyle.Back)
				end
			end
		end

		-- Attention flash: briefly lights the button with the accent color, then settles
		function controller:Pulse(name)
			local record = get(name)
			if not record or not animate then
				return
			end
			record.button.BackgroundColor3 = activeColor
			record.button.BackgroundTransparency = 0.2
			task.delay(0.12, function()
				if not destroyed then
					applyVisual(record, true)
				end
			end)
		end

		function controller:Show()
			group.Visible = true
			if animate then
				playIn()
			end
		end

		function controller:Hide()
			if not animate then
				group.Visible = false
				return
			end
			for _, record in ipairs(order) do
				if record.button then
					fadeOut(record)
				end
			end
			task.delay(0.16, function()
				if not destroyed then
					group.Visible = false
				end
			end)
		end

		function controller:Destroy()
			destroyed = true
			for _, c in ipairs(connections) do
				c:Disconnect()
			end
			connections = {}
			changed:Destroy()
			group:Destroy()
		end

		group.Destroying:Connect(function()
			destroyed = true
			for _, c in ipairs(connections) do
				c:Disconnect()
			end
		end)

		controller.Instance = group
		controller.Records = records

		return group, controller
	end
end

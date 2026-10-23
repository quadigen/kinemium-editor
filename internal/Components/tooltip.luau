local RunService = game:GetService("RunService")

return function(ctx)
	local UI = ctx.UI
	local shared = ctx.shared
	local colors = UI.tokens.color
	local tooltipSmoothTowards = ctx.tooltipSmoothTowards

	function UI.tooltip(target, text, options)
		options = options or {}

		local colors = UI.tokens.color

		shared.tooltips = shared.tooltips or {}

		local existing = shared.tooltips[target]
		if existing then
			existing:SetText(text)
			return existing
		end

		if not shared.tooltipJanitor then
			shared.tooltipJanitor = RunService.Heartbeat:Connect(function()
				local registry = shared.tooltips
				if registry == nil then
					return
				end

				for tooltipTarget, tooltipController in pairs(registry) do
					if not UI.isAlive(tooltipTarget) then
						tooltipController:Destroy()
						registry[tooltipTarget] = nil
					end
				end
			end)
		end

		local hoverDelay = options.hoverDelay or 0.4

		local fadeSpeed = options.fadeSpeed or 14

		local riseDistance = options.riseDistance or 6

		local padding = options.padding or 6

		local gap = options.gap or 8

		local screenMargin = options.screenMargin or 4

		local placement = options.placement or "cursor"

		local offset = options.offset or Vector2.new(12, 20)

		local textSize = options.textSize or 12

		local maxWidth = options.maxWidth

		local backgroundTransparency = options.backgroundTransparency or 0

		local borderTransparency = options.borderTransparency or 0

		local textTransparency = options.textTransparency or 0

		local root = UI.RootOverlay()

		local tooltip = UI.create("Frame", {

			Name = "Tooltip",

			Position = UDim2.fromOffset(0, 0),

			Size = UDim2.fromOffset(1, 1),

			BackgroundColor3 = options.backgroundColor or colors.surface,

			BackgroundTransparency = 1,

			BorderSizePixel = 0,

			Active = false,

			InputSink = false,

			Selectable = false,

			Visible = false,

			ZIndex = options.zIndex or 100000,
		}, root)

		UI.corner(tooltip, options.cornerRadius or UI.tokens.radius.sm)

		local stroke = UI.stroke(tooltip, options.borderColor or colors.borderStrong, options.borderThickness or 1, 1)

		local label = UI.create("TextLabel", {

			Name = "Text",

			Text = tostring(text or ""),

			Position = UDim2.fromOffset(padding, padding),

			Size = UDim2.fromOffset(1, 1),

			BackgroundTransparency = 1,

			BorderSizePixel = 0,

			TextSize = textSize,

			TextColor3 = options.textColor or colors.text,

			TextTransparency = 1,

			TextWrapped = maxWidth ~= nil,

			ZIndex = (options.zIndex or 100000) + 1,
		}, tooltip)

		local state = {

			hovered = false,

			hoverTime = 0,

			alpha = 0,

			anchorMouse = Vector2.new(0, 0),

			mouse = Vector2.new(0, 0),

			destroyed = false,
		}

		local controller = {}

		local function updateSize()
			local bounds = label.TextBounds

			if not bounds then
				return tooltip.AbsoluteSize.X, tooltip.AbsoluteSize.Y
			end

			local contentWidth = math.max(bounds.X, 1)

			local contentHeight = math.max(bounds.Y, textSize)

			if maxWidth then
				contentWidth = math.min(contentWidth, maxWidth)

				label.Size = UDim2.fromOffset(maxWidth, math.max(contentHeight, textSize))

				contentWidth = maxWidth
			else
				label.Size = UDim2.fromOffset(contentWidth, contentHeight)
			end

			local width = contentWidth + padding * 2

			local height = contentHeight + padding * 2

			tooltip.Size = UDim2.fromOffset(width, height)

			return width, height
		end

		local function calculatePosition(width, height)
			local targetPosition = target.AbsolutePosition

			local targetSize = target.AbsoluteSize

			local x
			local y

			if placement == "cursor" then
				local anchor = options.followCursor and state.mouse or state.anchorMouse

				x = anchor.X + offset.X

				y = anchor.Y + offset.Y
			elseif placement == "above" then
				x = targetPosition.X + (targetSize.X - width) / 2

				y = targetPosition.Y - height - gap
			elseif placement == "below" then
				x = targetPosition.X + (targetSize.X - width) / 2

				y = targetPosition.Y + targetSize.Y + gap
			elseif placement == "left" then
				x = targetPosition.X - width - gap

				y = targetPosition.Y + (targetSize.Y - height) / 2
			else
				x = targetPosition.X + targetSize.X + gap

				y = targetPosition.Y + (targetSize.Y - height) / 2
			end

			local rise = (1 - state.alpha) * riseDistance

			if placement == "left" then
				x -= rise
			elseif placement == "right" then
				x += rise
			else
				y -= rise
			end

			local screenSize = root.AbsoluteSize

			if screenSize then
				x = math.clamp(x, screenMargin, math.max(screenMargin, screenSize.X - width - screenMargin))

				y = math.clamp(y, screenMargin, math.max(screenMargin, screenSize.Y - height - screenMargin))
			end

			return x, y
		end

		local function updateTransparency()
			tooltip.BackgroundTransparency = 1 - state.alpha * (1 - backgroundTransparency)

			stroke.Transparency = 1 - state.alpha * (1 - borderTransparency)

			label.TextTransparency = 1 - state.alpha * (1 - textTransparency)
		end

		local enterConnection = target.MouseEnter:Connect(function(x, y)
			state.hovered = true

			state.hoverTime = 0

			state.anchorMouse = Vector2.new(x, y)

			state.mouse = state.anchorMouse
		end)

		local leaveConnection = target.MouseLeave:Connect(function()
			state.hovered = false

			state.hoverTime = 0
		end)

		local moveConnection = target.MouseMoved:Connect(function(x, y)
			state.mouse = Vector2.new(x, y)
		end)

		local heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
			if state.destroyed then
				return
			end

			if state.hovered then
				state.hoverTime += dt
			else
				state.hoverTime = 0
			end

			local targetAlpha = state.hovered and state.hoverTime >= hoverDelay and 1 or 0

			state.alpha = tooltipSmoothTowards(state.alpha, targetAlpha, fadeSpeed, dt)

			if math.abs(state.alpha - targetAlpha) < 0.01 then
				state.alpha = targetAlpha
			end

			if state.alpha <= 0.001 then
				tooltip.Visible = false

				return
			end

			tooltip.Visible = true

			local width, height = updateSize()

			local x, y = calculatePosition(width, height)

			tooltip.Position = UDim2.fromOffset(x, y)

			updateTransparency()
		end)

		function controller:SetText(newText)
			label.Text = tostring(newText or "")
		end

		function controller:SetPlacement(newPlacement)
			placement = newPlacement or "cursor"
		end

		function controller:Show()
			state.hovered = true

			state.hoverTime = hoverDelay
		end

		function controller:Hide()
			state.hovered = false

			state.hoverTime = 0
		end

		function controller:Destroy()
			if state.destroyed then
				return
			end

			state.destroyed = true

			if shared.tooltips and shared.tooltips[target] == controller then
				shared.tooltips[target] = nil
			end

			enterConnection:Disconnect()

			leaveConnection:Disconnect()

			moveConnection:Disconnect()

			heartbeatConnection:Disconnect()

			tooltip:Destroy()
		end

		controller.frame = tooltip
		controller.label = label
		controller.target = target

		shared.tooltips[target] = controller

		return controller
	end
end

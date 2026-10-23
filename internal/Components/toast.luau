local RunService = game:GetService("RunService")

return function(ctx)
	local UI = ctx.UI
	local shared = ctx.shared
	local colors = UI.tokens.color
	local tooltipSmoothTowards = ctx.tooltipSmoothTowards

	function UI.toast(text, options)
		options = options or {}

		local colors = UI.tokens.color

		shared.toasts = shared.toasts or {}
		shared.toastSerial = (shared.toastSerial or 0) + 1

		shared.toastMargin = shared.toastMargin or (options.margin or 20)
		shared.toastGap = shared.toastGap or (options.gap or 10)

		local margin = shared.toastMargin
		local gap = shared.toastGap

		if not shared.toastRoot then
			shared.toastRoot = UI.create("ScreenGui", {
				Name = "ToastOverlay",

				DisplayOrder = options.displayOrder or 3000,

				IgnoreGuiInset = true,
				RenderOnTop = true,
			}, options.parent or game.CoreGui)
		end

		local root = shared.toastRoot

		local kind = options.type or "info"

		local typeConfigs = {
			info = {
				color = colors.accent,
				icon = "builtin://global-icons/info.svg",
			},

			success = {
				color = colors.success,
				icon = "builtin://global-icons/check.svg",
			},

			warning = {
				color = colors.warning,
				icon = "builtin://global-icons/warning.svg",
			},

			error = {
				color = colors.error,
				icon = "builtin://global-icons/error",
			},
		}

		local typeConfig = typeConfigs[kind] or typeConfigs.info

		local accentColor = options.accentColor or typeConfig.color
		local iconCharacter = options.icon or typeConfig.icon
		local blur
		local controller = {}

		local title = options.title or tostring(text or "Notification")
		local messagePrefix = options.message or ""

		local details = tostring(options.details or "")

		local hasDetails = details ~= "" or options.buildDetails ~= nil

		local width = options.width or 520

		local headerHeight = options.headerHeight or 52
		local summaryHeight = options.summaryHeight or 40
		local progressHeight = options.progressHeight or 4

		local collapsedHeight = options.height or (headerHeight + summaryHeight + progressHeight)

		local expandedHeight = options.expandedHeight or (collapsedHeight + 120)

		expandedHeight = math.max(expandedHeight, collapsedHeight + 50)

		local duration = options.duration

		if duration == nil then
			duration = 9
		end

		local fadeSpeed = options.fadeSpeed or 14
		local moveSpeed = options.moveSpeed or 16
		local slideDistance = options.slideDistance or 18

		local backgroundTransparency = options.backgroundTransparency or 0
		local borderTransparency = options.borderTransparency or 0.25

		local zIndex = options.zIndex or (150000 + shared.toastSerial * 10)

		local frame = UI.create("Frame", {
			Name = "Toast" .. tostring(shared.toastSerial),
			ClipsDescendants = true,

			AnchorPoint = Vector2.new(0.5, 0),

			Position = UDim2.new(0.5, 0, 0, margin - slideDistance),

			Size = UDim2.fromOffset(width, collapsedHeight),

			BackgroundColor3 = options.backgroundColor or colors.panelRaised,
			BackgroundTransparency = 1,

			BorderSizePixel = 0,

			Active = false,
			InputSink = false,

			ZIndex = zIndex,
		}, root)

		UI.corner(frame, options.radius or UI.tokens.radius.md)

		local border = UI.stroke(frame, options.borderColor or colors.borderStrong, options.borderThickness or 1, 1)

		local shadow = nil

		if options.shadow ~= false then
			shadow = UI.create("UIShadow", {
				BlurRadius = UDim.new(0, options.shadowBlur or 18),

				Offset = UDim2.fromOffset(0, options.shadowOffset or 6),

				Spread = UDim2.fromOffset(0, 0),

				Color3 = options.shadowColor or Color3.new(0, 0, 0),

				Transparency = 1,

				Enabled = true,
			}, frame)
		end

		if options.blur ~= false then
			blur = UI.create("UIBackdrop", {
				TintColor3 = options.shadowColor or Color3.new(0, 0, 0),
			}, frame)
		end

		local titleLabel = UI.label(
			frame,
			title,
			UDim2.fromOffset(20, 15),
			UDim2.new(1, -155, 0, headerHeight),
			options.titleSize or 15,
			options.titleColor or colors.text
		)

		titleLabel.Name = "Title"

		titleLabel.TextXAlignment = Enum.TextXAlignment.Left
		titleLabel.TextTransparency = 1

		titleLabel.ZIndex = zIndex + 2

		local summaryButton = UI.create("TextButton", {
			Name = "Summary",

			Text = "",

			Position = UDim2.fromOffset(0, headerHeight + 1),

			Size = UDim2.new(1, 0, 0, summaryHeight - 1),

			BackgroundTransparency = 1,

			BorderSizePixel = 0,

			Active = true,
			InputSink = true,
			AutoButtonColor = false,

			ZIndex = zIndex + 2,
		}, frame)

		local summaryLabel = UI.create("TextLabel", {
			Name = "Message",

			Text = "",

			Position = UDim2.fromOffset(20, 0),

			Size = UDim2.new(1, -40, 1, 0),

			BackgroundTransparency = 1,

			BorderSizePixel = 0,

			TextSize = options.textSize or UI.tokens.type.body,

			TextColor3 = options.textColor or colors.subtext,

			TextTransparency = 1,

			TextWrapped = true,

			TextXAlignment = Enum.TextXAlignment.Left,

			ZIndex = zIndex + 3,
		}, summaryButton)

		local detailsFrame = UI.create("Frame", {
			Name = "Details",

			Position = UDim2.fromOffset(0, headerHeight + summaryHeight),

			Size = UDim2.new(1, 0, 0, expandedHeight - collapsedHeight),

			BackgroundTransparency = 1,

			BorderSizePixel = 0,

			Visible = false,

			ZIndex = zIndex + 2,
		}, frame)

		local detailsTitle = nil

		if options.detailsTitle then
			detailsTitle = UI.label(
				detailsFrame,
				options.detailsTitle,
				UDim2.fromOffset(20, 12),
				UDim2.new(1, -40, 0, 20),
				options.detailsTitleSize or UI.tokens.type.small,
				options.detailsTitleColor or colors.text
			)

			detailsTitle.TextXAlignment = Enum.TextXAlignment.Left

			detailsTitle.TextTransparency = 1

			detailsTitle.ZIndex = zIndex + 3
		end

		local detailsY = options.detailsTitle and 38 or 12

		local detailsLabel = UI.create("TextLabel", {
			Name = "DetailsText",

			Text = details,

			Position = UDim2.fromOffset(20, detailsY),

			Size = UDim2.new(1, -40, 1, -(detailsY + 12)),

			BackgroundTransparency = 1,

			BorderSizePixel = 0,

			TextSize = options.detailsTextSize or UI.tokens.type.small,

			TextColor3 = options.detailsTextColor or colors.subtext,

			TextTransparency = 1,

			TextWrapped = true,

			TextXAlignment = Enum.TextXAlignment.Left,

			ZIndex = zIndex + 3,
		}, detailsFrame)

		local expandIconImage = options.expandIcon or "builtin://global-icons/chevron-down.svg"
		local collapseIconImage = options.collapseIcon or "builtin://global-icons/chevron-up.svg"

		local expandButton, _, expandIcon = UI.iconButton(
			frame,
			expandIconImage,
			UDim2.new(1, -70, 0, 10),
			UDim2.fromOffset(32, 32),
			function() end,
			{
				color = colors.panelRaised,
				bgTransparency = 1,
				hoverColor = colors.hover,
				pressedColor = colors.pressed,
				iconSize = options.closeIconSize or 16,
				border = false,
			}
		)

		local closeButton, _, closeIcon = UI.iconButton(
			frame,
			options.closeIcon or "builtin://global-icons/x.svg",
			UDim2.new(1, -46, 0, 10),
			UDim2.fromOffset(32, 32),
			function() end,
			{
				color = colors.panelRaised,
				bgTransparency = 1,
				hoverColor = colors.hover,
				pressedColor = colors.pressed,
				iconSize = options.closeIconSize or 16,
				border = false,
			}
		)

		local progressBackground = UI.frame(
			frame,
			UDim2.new(0, 0, 1, -progressHeight),
			UDim2.new(1, 0, 0, progressHeight),
			options.progressBackgroundColor or colors.input
		)

		progressBackground.ZIndex = zIndex + 4
		progressBackground.BackgroundTransparency = 1

		local progress = UI.frame(progressBackground, UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), accentColor)

		progress.ZIndex = zIndex + 5
		progress.BackgroundTransparency = 1

		local state = {
			alpha = 0,

			y = margin - slideDistance,
			targetY = margin,

			elapsed = 0,

			timerStopped = false,

			expanded = false,

			closing = false,
			destroyed = false,

			reason = nil,
		}

		local record = {
			frame = frame,
			state = state,
			controller = controller,
		}

		table.insert(shared.toasts, 1, record)

		local function reflowToasts()
			local y = margin

			for _, toast in ipairs(shared.toasts) do
				if not toast.state.destroyed then
					toast.state.targetY = y

					y += toast.frame.Size.Y.Offset + gap
				end
			end
		end

		local function removeToast()
			for index, toast in ipairs(shared.toasts) do
				if toast == record then
					table.remove(shared.toasts, index)

					break
				end
			end

			reflowToasts()
		end

		local function updateSummary()
			if duration <= 0 then
				if messagePrefix ~= "" then
					summaryLabel.Text = messagePrefix
				else
					summaryLabel.Text = "Click  to close."
				end

				return
			end

			if state.timerStopped then
				if messagePrefix ~= "" then
					summaryLabel.Text = messagePrefix .. " Automatic closing stopped."
				else
					summaryLabel.Text = "Automatic closing stopped."
				end

				return
			end

			local remaining = math.max(duration - state.elapsed, 0)

			local seconds = math.ceil(remaining)

			local timerText = string.format(
				"This message will close in %d second%s. Click to stop.",
				seconds,
				seconds == 1 and "" or "s"
			)

			if messagePrefix ~= "" then
				summaryLabel.Text = messagePrefix .. " " .. timerText
			else
				summaryLabel.Text = timerText
			end
		end

		local function setExpanded(expanded)
			if not hasDetails then
				return false
			end

			expanded = expanded == true

			if state.expanded == expanded then
				return true
			end

			state.expanded = expanded

			if expanded then
				frame.Size = UDim2.fromOffset(width, expandedHeight)

				detailsFrame.Visible = true

				expandIcon.Image = collapseIconImage

				if options.stopOnExpand ~= false and duration > 0 then
					state.timerStopped = true
				end
			else
				frame.Size = UDim2.fromOffset(width, collapsedHeight)

				detailsFrame.Visible = false

				expandIcon.Image = expandIconImage
			end

			updateSummary()
			reflowToasts()

			if options.onExpand then
				options.onExpand(expanded, controller)
			end

			return true
		end

		local heartbeatConnection = nil

		controller.frame = frame
		controller.detailsFrame = detailsFrame
		controller.summary = summaryLabel
		controller.details = detailsLabel

		function controller:IsOpen()
			return not state.destroyed and not state.closing
		end

		function controller:IsExpanded()
			return state.expanded
		end

		function controller:Expand()
			return setExpanded(true)
		end

		function controller:Collapse()
			return setExpanded(false)
		end

		function controller:Toggle()
			return setExpanded(not state.expanded)
		end

		function controller:StopTimer()
			if state.timerStopped then
				return
			end

			state.timerStopped = true

			updateSummary()

			if options.onStop then
				options.onStop(controller)
			end
		end

		function controller:SetTitle(newTitle)
			title = tostring(newTitle or "")

			titleLabel.Text = title
		end

		function controller:SetMessage(newMessage)
			messagePrefix = tostring(newMessage or "")

			updateSummary()
		end

		function controller:SetDetails(newDetails)
			details = tostring(newDetails or "")

			detailsLabel.Text = details

			hasDetails = details ~= "" or options.buildDetails ~= nil

			expandButton.Visible = hasDetails
			expandButton.Active = hasDetails
			expandButton.InputSink = hasDetails

			if not hasDetails and state.expanded then
				setExpanded(false)
			end
		end

		function controller:SetDuration(seconds)
			duration = math.max(tonumber(seconds) or 0, 0)

			state.elapsed = 0
			state.timerStopped = false

			updateSummary()
		end

		function controller:SetType(newType)
			local config = typeConfigs[newType]

			if not config then
				return false
			end

			kind = newType
			typeConfig = config

			accentColor = config.color

			progress.BackgroundColor3 = accentColor

			return true
		end

		function controller:Close(reason)
			if state.destroyed or state.closing then
				return false
			end

			state.closing = true

			state.reason = reason or "closed"

			return true
		end

		function controller:Destroy()
			if state.destroyed then
				return
			end

			state.destroyed = true

			if heartbeatConnection then
				heartbeatConnection:Disconnect()
				heartbeatConnection = nil
			end

			removeToast()

			UI.forgetButtons(frame)

			frame:Destroy()
		end

		summaryButton.MouseButton1Click:Connect(function()
			controller:StopTimer()
		end)

		expandButton.MouseButton1Click:Connect(function()
			controller:Toggle()
		end)

		closeButton.MouseButton1Click:Connect(function()
			controller:Close("close")
		end)

		if options.buildDetails then
			options.buildDetails(detailsFrame, controller)
		end

		updateSummary()
		reflowToasts()

		heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
			if state.destroyed then
				if heartbeatConnection then
					heartbeatConnection:Disconnect()
					heartbeatConnection = nil
				end

				return
			end

			if not state.closing and not state.timerStopped and duration > 0 then
				state.elapsed += dt

				if state.elapsed >= duration then
					state.elapsed = duration

					controller:Close("timeout")
				end
			end

			updateSummary()

			local progressAlpha = 0

			if duration > 0 then
				progressAlpha = math.clamp((duration - state.elapsed) / duration, 0, 1)
			end

			progress.Size = UDim2.new(progressAlpha, 0, 1, 0)

			local targetAlpha = state.closing and 0 or 1

			state.alpha = tooltipSmoothTowards(state.alpha, targetAlpha, fadeSpeed, dt)

			state.y = tooltipSmoothTowards(state.y, state.targetY, moveSpeed, dt)

			if math.abs(state.alpha - targetAlpha) < 0.005 then
				state.alpha = targetAlpha
			end

			if math.abs(state.y - state.targetY) < 0.1 then
				state.y = state.targetY
			end

			local slide = (1 - state.alpha) * -slideDistance

			frame.Position = UDim2.new(0.5, 0, 0, state.y + slide)

			frame.BackgroundTransparency = 1 - state.alpha * (1 - backgroundTransparency)

			border.Transparency = 1 - state.alpha * (1 - borderTransparency)

			titleLabel.TextTransparency = 1 - state.alpha

			summaryLabel.TextTransparency = 1 - state.alpha

			progressBackground.BackgroundTransparency = 1 - state.alpha

			progress.BackgroundTransparency = 1 - state.alpha

			if state.expanded then
				detailsLabel.TextTransparency = 1 - state.alpha

				if detailsTitle then
					detailsTitle.TextTransparency = 1 - state.alpha
				end
			end

			if shadow then
				local wantedShadowTransparency = options.shadowTransparency or 0.5

				shadow.Transparency = 1 - state.alpha * (1 - wantedShadowTransparency)
			end

			if state.closing and state.alpha <= 0.001 then
				if heartbeatConnection then
					heartbeatConnection:Disconnect()
					heartbeatConnection = nil
				end

				state.destroyed = true

				removeToast()

				UI.forgetButtons(frame)

				frame:Destroy()

				if options.onClose then
					options.onClose(state.reason, controller)
				end
			end
		end)

		return controller
	end
end

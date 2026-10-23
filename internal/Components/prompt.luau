local RunService = game:GetService("RunService")

return function(ctx)
	local UI = ctx.UI
	local shared = ctx.shared
	local colors = UI.tokens.color
	local tooltipSmoothTowards = ctx.tooltipSmoothTowards

	function UI.prompt(options)
		options = options or {}

		local colors = UI.tokens.color

		local title = options.title or "Prompt"
		local description = options.description

		local modal = options.modal ~= false
		local dim = options.dim ~= false
		local closable = options.closable ~= false
		local draggable = options.draggable ~= false
		local showHeader = options.showHeader ~= false
		local showFooter = options.showFooter ~= false

		local radius = options.radius or UI.tokens.radius.md
		local padding = options.padding or 12

		local headerHeight = showHeader and (options.headerHeight or (description and 54 or 38)) or 0
		local footerHeight = showFooter and (options.footerHeight or 52) or 0

		local size = options.size or UDim2.fromOffset(440, 260)
		local position = options.position or UDim2.fromScale(0.5, 0.5)
		local anchorPoint = options.anchorPoint or Vector2.new(0.5, 0.5)

		shared.promptSerial = (shared.promptSerial or 0) + 1

		local promptId = shared.promptSerial
		local baseZIndex = options.zIndex or (200000 + promptId * 20)

		local screenGui = UI.create("ScreenGui", {
			Name = options.screenGuiName or ("PromptGui" .. tostring(promptId)),
			RenderOnTop = options.renderOnTop ~= false,
			DisplayOrder = 4000,
		}, options.parent or game.CoreGui)

		local host = UI.create("Frame", {
			Name = options.name or ("Prompt" .. tostring(promptId)),

			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.fromScale(1, 1),

			BackgroundTransparency = 1,
			BorderSizePixel = 0,

			Active = false,
			InputSink = false,
			Selectable = false,

			ZIndex = baseZIndex,
		}, screenGui)

		local controller = {
			screenGui = screenGui,

			frame = nil,
			host = host,

			backdrop = nil,

			header = nil,
			contentArea = nil,
			content = nil,
			footer = nil,

			title = nil,
			description = nil,

			buttons = {},
			buttonConfigs = {},

			open = options.startVisible ~= false,
			promptDestroyPending = false,
			busy = false,
			destroyed = false,
		}

		local needsBackdrop = modal or dim or options.closeOnBackdrop == true or options.blur ~= nil

		local backdrop = nil

		if needsBackdrop then
			backdrop = UI.create("Frame", {
				Name = "Backdrop",
				Position = UDim2.fromOffset(0, 0),
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = options.dimColor or Color3.new(0, 0, 0),
				BackgroundTransparency = dim and (options.dimTransparency or 0.45) or 1,
				BorderSizePixel = 0,
				InputSink = modal,
				ZIndex = baseZIndex,
			}, host)

			controller.backdrop = backdrop

			if options.blur then
				UI.create("UIBackdrop", {
					Enabled = true,

					BlurRadius = options.blur,

					TintColor3 = options.blurTintColor or Color3.new(0, 0, 0),

					TintTransparency = options.blurTintTransparency or 1,
				}, backdrop)
			end

			if options.closeOnBackdrop == true then
				backdrop.MouseButton1Click:Connect(function()
					controller:Close("backdrop")
				end)
			end
		end

		local panel = UI.frame(host, position, size, options.color or colors.panel, radius)

		panel.Name = "PromptPanel"

		panel.AnchorPoint = anchorPoint
		panel.ClipsDescendants = options.clip == true
		panel.ZIndex = baseZIndex + 1

		if options.transparency ~= nil then
			panel.BackgroundTransparency = options.transparency
		end

		controller.frame = panel

		if options.border ~= false then
			controller.border = UI.stroke(
				panel,
				options.borderColor or colors.borderStrong,
				options.borderThickness or 1,
				options.borderTransparency or 0.25
			)
		end

		if options.shadow ~= false then
			controller.shadow = UI.create("UIShadow", {
				BlurRadius = UDim.new(0, options.shadowBlur or 18),

				Offset = UDim2.fromOffset(options.shadowOffsetX or 0, options.shadowOffsetY or 6),

				Spread = UDim2.fromOffset(options.shadowSpread or 0, options.shadowSpread or 0),

				Color3 = options.shadowColor or Color3.new(0, 0, 0),

				Transparency = options.shadowTransparency or 0.45,

				Enabled = true,
			}, panel)
		end

		if options.glass == true then
			controller.panelBackdrop = UI.create("UIBackdrop", {
				Enabled = true,

				BlurRadius = options.glassBlur or 20,

				TintColor3 = options.glassColor or colors.panel,

				TintTransparency = options.glassTransparency or 0.82,
			}, panel)

			if options.transparency == nil then
				panel.BackgroundTransparency = 0.12
			end
		end

		local animatePrompt = options.animate ~= false
		local promptSpeed = options.animationSpeed or 18
		local promptCloseSpeed = options.closeSpeed or 28
		local promptProgress = 0
		local promptTarget = 0
		local promptHeartbeat = nil
		local promptBaseSize = nil
		local promptVisualActive = false
		local promptBackdropTransparency = backdrop and backdrop.BackgroundTransparency or 1
		local promptBorderTransparency = controller.border and controller.border.Transparency or nil
		local promptShadowTransparency = controller.shadow and controller.shadow.Transparency or nil

		local function scaleSize(size, factor)
			return UDim2.new(
				size.X.Scale * factor,
				math.floor(size.X.Offset * factor + 0.5),
				size.Y.Scale * factor,
				math.floor(size.Y.Offset * factor + 0.5)
			)
		end

		local function applyPrompt(alpha)
			alpha = math.clamp(alpha, 0, 1)

			local eased = alpha * alpha * (3 - 2 * alpha)

			if animatePrompt and promptVisualActive and promptBaseSize then
				if eased >= 1 then
					panel.Size = promptBaseSize
				else
					panel.Size = scaleSize(promptBaseSize, 0.98 + 0.02 * eased)
				end
			end

			if backdrop then
				backdrop.BackgroundTransparency = 1 - (1 - promptBackdropTransparency) * eased
			end

			if controller.border and promptBorderTransparency then
				controller.border.Transparency = 1 - (1 - promptBorderTransparency) * eased
			end

			if controller.shadow and promptShadowTransparency then
				controller.shadow.Transparency = 1 - (1 - promptShadowTransparency) * eased
			end
		end

		local function stopPromptAnimation()
			if promptHeartbeat then
				promptHeartbeat:Disconnect()
				promptHeartbeat = nil
			end
		end

		local function finishPromptClose()
			if promptBaseSize then
				panel.Size = promptBaseSize
			end

			promptVisualActive = false

			if not controller.promptDestroyPending then
				return
			end

			controller.promptDestroyPending = false

			if not controller.destroyed then
				controller:Destroy()
			end
		end

		local function wakePrompt(target)
			promptTarget = target

			if not animatePrompt then
				stopPromptAnimation()

				promptProgress = target

				applyPrompt(target)

				if target <= 0 then
					screenGui.Enabled = false

					finishPromptClose()
				end

				return
			end

			if promptHeartbeat then
				return
			end

			promptHeartbeat = RunService.Heartbeat:Connect(function(dt)
				local speed = promptTarget <= 0 and promptCloseSpeed or promptSpeed

				promptProgress = tooltipSmoothTowards(promptProgress, promptTarget, speed, dt)

				local finished = math.abs(promptProgress - promptTarget) < 0.002

				if finished then
					promptProgress = promptTarget
				end

				applyPrompt(promptProgress)

				if finished then
					stopPromptAnimation()

					if promptTarget <= 0 then
						screenGui.Enabled = false

						finishPromptClose()
					end
				end
			end)
		end

		panel.Destroying:Connect(stopPromptAnimation)

		local header = nil

		if showHeader then
			header = UI.create("TextButton", {
				Name = "Header",

				Text = "",

				Position = UDim2.fromOffset(0, 0),
				Size = UDim2.new(1, 0, 0, headerHeight),

				BackgroundColor3 = options.headerColor or colors.panelRaised,
				BackgroundTransparency = options.headerTransparency or 0,

				BorderSizePixel = 0,

				Active = draggable,
				InputSink = true,
				AutoButtonColor = false,

				ZIndex = baseZIndex + 2,
			}, panel)

			UI.corner(header, radius)

			UI.frame(
				header,
				UDim2.new(0, 0, 1, -radius),
				UDim2.new(1, 0, 0, radius),
				options.headerColor or colors.panelRaised
			)

			controller.header = header

			local titleX = options.titleX or 12

			if options.icon then
				local iconSize = options.iconSize or 18

				controller.icon = UI.image(
					header,
					options.icon,
					UDim2.fromOffset(titleX, math.floor((headerHeight - iconSize) / 2)),
					UDim2.fromOffset(iconSize, iconSize)
				)

				titleX += iconSize + (options.iconGap or 8)
			end

			local titleHeight = description and 20 or headerHeight

			local titleLabel = UI.label(
				header,
				title,
				description and UDim2.fromOffset(titleX, 7) or UDim2.fromOffset(titleX, 0),
				UDim2.new(1, -(titleX + (closable and 42 or 12)), 0, titleHeight),
				options.titleSize or UI.tokens.type.body,
				options.titleColor or colors.text
			)

			titleLabel.Name = "Title"
			titleLabel.TextXAlignment = Enum.TextXAlignment.Left

			controller.title = titleLabel

			if description then
				local descriptionLabel = UI.label(
					header,
					description,
					UDim2.fromOffset(titleX, 27),
					UDim2.new(1, -(titleX + (closable and 42 or 12)), 0, headerHeight - 30),
					options.descriptionSize or UI.tokens.type.caption,
					options.descriptionColor or colors.muted
				)

				descriptionLabel.Name = "Description"
				descriptionLabel.TextXAlignment = Enum.TextXAlignment.Left

				controller.description = descriptionLabel
			end

			if options.headerSeparator ~= false then
				controller.headerSeparator = UI.separator(
					header,
					UDim2.new(0, 8, 1, -1),
					UDim2.new(1, -16, 0, 1),
					options.separatorColor or colors.border
				)
			end
		end

		if showHeader and closable then
			local closeButton

			if options.closeIcon then
				closeButton = UI.iconButton(
					header,
					options.closeIcon,
					UDim2.new(1, -31, 0.5, -11),
					UDim2.fromOffset(22, 22),
					function()
						controller:Close("close")
					end,
					{
						color = options.closeColor or colors.panelRaised,

						hoverColor = options.closeHoverColor or colors.hover,

						pressedColor = options.closePressedColor or colors.pressed,

						iconSize = options.closeIconSize or 11,

						radius = options.closeRadius or UI.tokens.radius.sm,

						border = false,
					}
				)
			else
				closeButton = UI.button(header, "", UDim2.new(1, -31, 0.5, -11), UDim2.fromOffset(22, 22), function()
					controller:Close("close")
				end, {
					color = options.closeColor or colors.panelRaised,

					hoverColor = options.closeHoverColor or colors.hover,

					pressedColor = options.closePressedColor or colors.pressed,

					textColor = options.closeTextColor or colors.subtext,

					textSize = options.closeTextSize or 16,

					paddingX = 0,

					radius = options.closeRadius or UI.tokens.radius.sm,

					border = false,
				})
			end

			controller.closeButton = closeButton
		end

		local contentArea = UI.frame(
			panel,
			UDim2.fromOffset(0, headerHeight),
			UDim2.new(1, 0, 1, -(headerHeight + footerHeight)),
			options.contentColor or colors.panel
		)

		contentArea.Name = "ContentArea"

		contentArea.BackgroundTransparency = options.contentTransparency or 0
		contentArea.ClipsDescendants = options.clipContent == true

		controller.contentArea = contentArea

		local contentProperties = {
			Name = "Content",

			Position = UDim2.fromOffset(padding, padding),

			Size = UDim2.new(1, -padding * 2, 1, -padding * 2),

			BackgroundTransparency = 1,

			BorderSizePixel = 0,

			ClipsDescendants = options.clipContent == true,

			ZIndex = baseZIndex + 2,
		}

		local content

		if options.scrollable == true then
			contentProperties.CanvasPosition = options.canvasPosition or Vector2.new(0, 0)

			contentProperties.CanvasSize = options.canvasSize or UDim2.new(0, 0, 0, 0)

			contentProperties.ScrollingEnabled = options.scrollingEnabled ~= false

			contentProperties.ScrollBarThickness = options.scrollBarThickness or 5

			contentProperties.ScrollBarImageColor3 = options.scrollBarColor or colors.subtext

			contentProperties.ScrollBarImageTransparency = options.scrollBarTransparency or 0.4

			contentProperties.ScrollBarAutoHide = options.scrollBarAutoHide ~= false

			content = UI.create("ScrollingFrame", contentProperties, contentArea)
		else
			content = UI.create("Frame", contentProperties, contentArea)
		end

		controller.content = content

		local footer = nil
		local buttonGroup = nil

		if showFooter then
			footer = UI.frame(
				panel,
				UDim2.new(0, 0, 1, -footerHeight),
				UDim2.new(1, 0, 0, footerHeight),
				options.footerColor or colors.panelRaised
			)

			footer.Name = "Footer"

			footer.BackgroundTransparency = options.footerTransparency or 0

			controller.footer = footer

			if options.footerSeparator ~= false then
				controller.footerSeparator = UI.separator(
					footer,
					UDim2.fromOffset(8, 0),
					UDim2.new(1, -16, 0, 1),
					options.separatorColor or colors.border
				)
			end

			buttonGroup =
				UI.frame(footer, UDim2.fromOffset(0, 0), UDim2.fromOffset(0, footerHeight), Color3.new(0, 0, 0))

			buttonGroup.Name = "Buttons"
			buttonGroup.BackgroundTransparency = 1

			controller.buttonGroup = buttonGroup
		end

		local function getButtonColors(config)
			local role = config.role or "secondary"

			if role == "primary" then
				return config.color or colors.accent,
					config.hoverColor or colors.selectionHover,
					config.pressedColor or colors.pressed,
					config.textColor or colors.text,
					config.backgroundTransparency or 0
			elseif role == "danger" then
				return config.color or colors.error,
					config.hoverColor or colors.error,
					config.pressedColor or colors.pressed,
					config.textColor or colors.text,
					config.backgroundTransparency or 0
			elseif role == "ghost" then
				return config.color or colors.panelRaised,
					config.hoverColor or colors.hover,
					config.pressedColor or colors.pressed,
					config.textColor or colors.subtext,
					config.backgroundTransparency or 1
			end

			return config.color or colors.panelRaised,
				config.hoverColor or colors.hover,
				config.pressedColor or colors.pressed,
				config.textColor or colors.subtext,
				config.backgroundTransparency or 0
		end

		local function calculateButtonWidth(config)
			if config.width then
				return config.width
			end

			local text = tostring(config.text or config.label or config.id or "Button")

			return math.max(options.buttonWidth or 82, #text * (options.buttonCharacterWidth or 7) + 28)
		end

		local function renderButtons()
			if not buttonGroup then
				return
			end

			UI.clear(buttonGroup)

			controller.buttons = {}

			local configs = controller.buttonConfigs

			local gap = options.buttonGap or 7
			local totalWidth = 0

			for index, config in ipairs(configs) do
				totalWidth += calculateButtonWidth(config)

				if index > 1 then
					totalWidth += gap
				end
			end

			local alignment = options.buttonAlignment or "right"

			if alignment == "left" then
				buttonGroup.AnchorPoint = Vector2.new(0, 0)

				buttonGroup.Position = UDim2.fromOffset(options.footerPadding or 10, 0)
			elseif alignment == "center" then
				buttonGroup.AnchorPoint = Vector2.new(0.5, 0)

				buttonGroup.Position = UDim2.new(0.5, 0, 0, 0)
			else
				buttonGroup.AnchorPoint = Vector2.new(1, 0)

				buttonGroup.Position = UDim2.new(1, -(options.footerPadding or 10), 0, 0)
			end

			buttonGroup.Size = UDim2.fromOffset(totalWidth, footerHeight)

			local x = 0

			for index, config in ipairs(configs) do
				local id = config.id or config.name or tostring(index)

				local text = config.text or config.label or tostring(id)

				local width = calculateButtonWidth(config)

				local height = config.height or options.buttonHeight or UI.metrics.buttonHeight

				local color, hoverColor, pressedColor, textColor, backgroundTransparency = getButtonColors(config)

				local button
				local label
				local record

				button, label, record = UI.button(
					buttonGroup,
					text,
					UDim2.fromOffset(x, math.floor((footerHeight - height) / 2)),
					UDim2.fromOffset(width, height),
					function()
						if record and not record.enabled then
							return
						end

						local callbackResult = nil

						if config.callback then
							callbackResult = config.callback(controller, config, content)
						end

						local resultValue = id

						if config.value ~= nil then
							resultValue = config.value
						end

						if options.onResult then
							options.onResult(id, resultValue, config, controller, callbackResult)
						end

						if callbackResult ~= false and config.close ~= false then
							controller:Close(id, resultValue)
						end
					end,
					{
						color = color,

						hoverColor = hoverColor,

						pressedColor = pressedColor,

						textColor = textColor,

						textSize = config.textSize or options.buttonTextSize or UI.tokens.type.small,

						radius = config.radius or options.buttonRadius or UI.tokens.radius.sm,

						border = config.border ~= false,

						borderColor = config.borderColor or options.buttonBorderColor or colors.border,

						borderTransparency = config.borderTransparency or options.buttonBorderTransparency or 0,

						paddingX = config.paddingX or options.buttonPaddingX or UI.tokens.space.md,

						icon = config.icon,

						iconSize = config.iconSize or options.buttonIconSize or 14,

						enabled = config.enabled ~= false,
					}
				)

				button.Name = tostring(id)

				button.BackgroundTransparency = backgroundTransparency

				controller.buttons[id] = {
					id = id,

					button = button,
					label = label,
					record = record,

					config = config,

					color = color,
					hoverColor = hoverColor,

					textColor = textColor,

					enabled = config.enabled ~= false,
				}

				x += width + gap
			end
		end

		function controller:IsOpen()
			return self.open and not self.destroyed
		end

		function controller:Open()
			if self.destroyed then
				return false
			end

			if self.open then
				return true
			end

			self.open = true
			self.promptDestroyPending = false

			if animatePrompt and not promptVisualActive then
				promptBaseSize = panel.Size
			end

			promptVisualActive = animatePrompt

			self.screenGui.Enabled = true

			wakePrompt(1)

			if options.onOpen then
				options.onOpen(self)
			end

			return true
		end

		function controller:Close(reason, result)
			if self.destroyed or not self.open then
				return false
			end

			if options.beforeClose then
				local allowed = options.beforeClose(reason, result, self)

				if allowed == false then
					return false
				end
			end

			self.open = false
			self.promptDestroyPending = options.destroyOnClose == true

			if animatePrompt and not promptVisualActive then
				promptBaseSize = panel.Size
			end

			promptVisualActive = animatePrompt

			if options.onClose then
				options.onClose(reason, result, self)
			end

			wakePrompt(0)

			return true
		end

		function controller:Destroy()
			if self.destroyed then
				return
			end

			self.destroyed = true
			self.open = false
			self.promptDestroyPending = false

			stopPromptAnimation()

			UI.forgetButtons(self.screenGui)

			self.screenGui:Destroy()
		end

		function controller:SetTitle(text)
			if self.title then
				self.title.Text = tostring(text or "")
			end
		end

		function controller:SetDescription(text)
			if not self.description then
				return
			end

			self.description.Text = tostring(text or "")
		end

		function controller:SetSize(newSize)
			promptBaseSize = newSize

			if promptVisualActive then
				applyPrompt(promptProgress)
			else
				panel.Size = newSize
			end
		end

		function controller:SetPosition(newPosition)
			panel.Position = newPosition
		end

		function controller:SetModal(value)
			modal = value == true

			if backdrop then
				backdrop.Active = modal or options.closeOnBackdrop == true
				backdrop.InputSink = modal
			end
		end

		function controller:GetButton(id)
			return self.buttons[id]
		end

		function controller:SetButtonEnabled(id, enabled)
			local data = self.buttons[id]

			if not data then
				return false
			end

			enabled = enabled == true

			data.enabled = enabled
			data.record.enabled = enabled

			data.button.Active = enabled

			if enabled then
				data.record.color = data.color
				data.record.hoverColor = data.hoverColor

				data.button.BackgroundColor3 = data.color
				data.label.TextColor3 = data.textColor
			else
				data.button.BackgroundColor3 = options.disabledButtonColor or colors.surface

				data.label.TextColor3 = options.disabledTextColor or colors.muted
			end

			return true
		end

		function controller:SetButtons(buttons)
			self.buttonConfigs = buttons or {}

			renderButtons()
		end

		function controller:AddButton(config)
			table.insert(self.buttonConfigs, config)

			renderButtons()

			return self.buttons[config.id or config.name or tostring(#self.buttonConfigs)]
		end

		function controller:SetBusy(value, targetButton, busyText)
			value = value == true

			if self.busy == value then
				return
			end

			self.busy = value

			if value then
				self._busyStates = {}

				for id, data in pairs(self.buttons) do
					self._busyStates[id] = data.enabled

					self:SetButtonEnabled(id, false)
				end

				if targetButton and self.buttons[targetButton] then
					local data = self.buttons[targetButton]

					data._normalText = data.label.Text

					if busyText then
						data.label.Text = busyText
					end
				end
			else
				for id, enabled in pairs(self._busyStates or {}) do
					self:SetButtonEnabled(id, enabled)
				end

				if targetButton and self.buttons[targetButton] then
					local data = self.buttons[targetButton]

					if data._normalText then
						data.label.Text = data._normalText
						data._normalText = nil
					end
				end

				self._busyStates = nil
			end
		end

		if header and draggable then
			local dragging = false

			local startMouseX = 0
			local startMouseY = 0

			local startPosition = nil

			header.MouseButton1Down:Connect(function(x, y)
				dragging = true

				startMouseX = x
				startMouseY = y

				startPosition = panel.Position

				if options.onDragBegin then
					options.onDragBegin(controller)
				end
			end)

			header.MouseMoved:Connect(function(x, y)
				if not dragging or not startPosition then
					return
				end

				local deltaX = x - startMouseX
				local deltaY = y - startMouseY

				panel.Position = UDim2.new(
					startPosition.X.Scale,
					startPosition.X.Offset + deltaX,
					startPosition.Y.Scale,
					startPosition.Y.Offset + deltaY
				)

				if options.onDrag then
					options.onDrag(panel.Position, controller)
				end
			end)

			header.MouseButton1Up:Connect(function()
				if not dragging then
					return
				end

				dragging = false

				if options.onDragEnd then
					options.onDragEnd(panel.Position, controller)
				end
			end)
		end

		local initialButtons = options.buttons

		if initialButtons == nil and showFooter then
			initialButtons = {
				{
					id = "ok",
					text = options.defaultButtonText or "OK",
					role = "primary",
				},
			}
		end

		controller.buttonConfigs = initialButtons or {}

		renderButtons()

		if options.build then
			options.build(content, controller)
		end

		if options.onCreated then
			options.onCreated(controller, content)
		end

		if not promptBaseSize then
			promptBaseSize = panel.Size
		end

		if controller.open then
			promptVisualActive = animatePrompt

			screenGui.Enabled = true

			if animatePrompt then
				applyPrompt(0)
				wakePrompt(1)
			else
				promptProgress = 1

				applyPrompt(1)
			end
		else
			promptVisualActive = false

			screenGui.Enabled = false

			applyPrompt(0)
		end

		if controller.open and options.onOpen then
			options.onOpen(controller)
		end

		return panel, content, controller
	end
end

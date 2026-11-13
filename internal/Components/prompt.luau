local RunService = game:GetService("RunService")

return function(ctx)
    local UI = ctx.UI
    local shared = ctx.shared
    local colors = UI.tokens.color
    local smoothTowards = ctx.tooltipSmoothTowards

    local function option(value, fallback)
        if value == nil then
            return fallback
        end
        return value
    end

    local function textLines(value, charsPerLine)
        local text = tostring(value or "")
        if text == "" then
            return 0
        end

        local lines = 0
        for line in (text .. "\n"):gmatch("(.-)\n") do
            local length = utf8.len(line) or #line
            lines += math.max(1, math.ceil(length / math.max(1, charsPerLine)))
        end
        return lines
    end

    local function scaledSize(size, factor)
        return UDim2.new(
            size.X.Scale * factor,
            math.floor(size.X.Offset * factor + 0.5),
            size.Y.Scale * factor,
            math.floor(size.Y.Offset * factor + 0.5)
        )
    end

    function UI.prompt(options)
        options = options or {}

        local title = tostring(options.title or "Prompt")
        local description = tostring(options.description or "")
        local modal = options.modal ~= false
        local dim = options.dim ~= false
        local closable = options.closable == true
        local draggable = options.draggable ~= false
        local showHeader = options.showHeader ~= false
        local showFooter = options.showFooter ~= false
        local buttonLayout = options.buttonLayout or "stacked"
        local autoSize = options.size == nil and options.autoSize ~= false
        local padding = options.padding or 20
        local width = options.width or 376
        local radius = options.radius or 15
        local position = options.position or UDim2.fromScale(0.5, 0.5)
        local anchorPoint = options.anchorPoint or Vector2.new(0.5, 0.5)
        local iconSize = options.iconSize or 46
        local titleSize = options.titleSize or 16
        local descriptionSize = options.descriptionSize or 13
        local buttonHeight = options.buttonHeight or 32
        local buttonGap = options.buttonGap or 7
        local buttonInset = options.footerPadding or 20
        local footerTop = options.footerTopPadding or 8
        local footerBottom = options.footerBottomPadding or 17
        local contentHeight = options.contentHeight or (options.build and 112 or 0)

        shared.promptSerial = (shared.promptSerial or 0) + 1
        local promptId = shared.promptSerial
        local baseZIndex = options.zIndex or (200000 + promptId * 20)

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

        local screenGui = UI.create("ScreenGui", {
            Name = options.screenGuiName or ("PromptGui" .. tostring(promptId)),
            RenderOnTop = options.renderOnTop ~= false,
            DisplayOrder = options.displayOrder or 4000,
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
            host = host,
            frame = nil,
            backdrop = nil,
            header = nil,
            contentArea = nil,
            content = nil,
            footer = nil,
            title = nil,
            description = nil,
            icon = nil,
            buttons = {},
            buttonConfigs = initialButtons or {},
            open = options.startVisible ~= false,
            promptDestroyPending = false,
            busy = false,
            destroyed = false,
        }

        local needsBackdrop = true or dim or options.closeOnBackdrop == true or options.blur ~= nil
        local backdrop
        if needsBackdrop then
            backdrop = UI.create(options.closeOnBackdrop == true and "TextButton" or "Frame", {
                Name = "Backdrop",
                Text = options.closeOnBackdrop == true and "" or nil,
                AutoButtonColor = options.closeOnBackdrop == true and false or nil,
                Position = UDim2.fromOffset(0, 0),
                Size = UDim2.fromScale(1, 1),
                BackgroundColor3 = options.dimColor or Color3.new(0, 0, 0),
                BackgroundTransparency = dim and option(options.dimTransparency, 0.70) or 1,
                BorderSizePixel = 0,
                Active = modal or options.closeOnBackdrop == true,
                InputSink = modal,
                ZIndex = baseZIndex,
            }, host)
            controller.backdrop = backdrop

            if options.blur then
                UI.create("UIBackdrop", {
                    Enabled = true,
                    BlurRadius = options.blur,
                    TintColor3 = options.blurTintColor or Color3.new(0, 0, 0),
                    TintTransparency = option(options.blurTintTransparency, 1),
                }, backdrop)
            end

            if options.closeOnBackdrop == true then
                backdrop.MouseButton1Click:Connect(function()
                    controller:Close("backdrop")
                end)
            end
        end

        local panelColor = options.color or colors.panel
        local panel = UI.frame(host, position, options.size or UDim2.fromOffset(width, 220), panelColor, radius)
        panel.Name = "PromptPanel"
        panel.AnchorPoint = anchorPoint
        panel.ClipsDescendants = options.clip == true
        panel.ZIndex = baseZIndex + 1
        panel.BackgroundTransparency = option(options.transparency, 0.06)
        controller.frame = panel

        if options.border ~= false then
            controller.border = UI.stroke(
                panel,
                options.borderColor or colors.border,
                options.borderThickness or 1,
                option(options.borderTransparency, 0.66)
            )
        end

        if options.shadow ~= false then
            controller.shadow = UI.create("UIShadow", {
                BlurRadius = UDim.new(0, options.shadowBlur or 32),
                Offset = UDim2.fromOffset(options.shadowOffsetX or 0, options.shadowOffsetY or 12),
                Spread = UDim2.fromOffset(options.shadowSpread or 0, options.shadowSpread or 0),
                Color3 = options.shadowColor or Color3.new(0, 0, 0),
                Transparency = option(options.shadowTransparency, 0.65),
                Enabled = true,
            }, panel)
        end

        if options.glass ~= false then
            controller.panelBackdrop = UI.create("UIBackdrop", {
                Enabled = true,
                BlurRadius = options.glassBlur or 20,
                TintColor3 = options.glassColor or panelColor,
                TintTransparency = option(options.glassTransparency, 0.87),
            }, panel)
        end

        local header
        local titleLabel
        local descriptionLabel
        local closeButton
        local image
        local headerHeight = 0
        local footerHeight = 0
        local titleHeight = 0
        local descriptionHeight = 0
        local titleY = 0
        local descriptionY = 0
        local contentArea
        local content
        local footer
        local buttonGroup

        if showHeader then
            header = UI.create("TextButton", {
                Name = "Header",
                Text = "",
                AutoButtonColor = false,
                Position = UDim2.fromOffset(0, 0),
                Size = UDim2.new(1, 0, 0, 0),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Active = draggable,
                InputSink = draggable,
                ZIndex = baseZIndex + 2,
            }, panel)
            controller.header = header

            if options.icon then
                image = UI.image(
                    header,
                    options.icon,
                    UDim2.new(0.5, -iconSize / 2, 0, 0),
                    UDim2.fromOffset(iconSize, iconSize)
                )
                image.Name = "Icon"
                controller.icon = image
            end

            titleLabel = UI.label(
                header,
                title,
                UDim2.fromOffset(padding, 0),
                UDim2.new(1, -padding * 2, 0, 24),
                titleSize,
                options.titleColor or colors.text
            )
            titleLabel.Name = "Title"
            titleLabel.TextXAlignment = Enum.TextXAlignment.Center
            titleLabel.TextYAlignment = Enum.TextYAlignment.Center
            titleLabel.TextWrapped = true
            controller.title = titleLabel

            descriptionLabel = UI.label(
                header,
                description,
                UDim2.fromOffset(padding, 0),
                UDim2.new(1, -padding * 2, 0, 0),
                descriptionSize,
                options.descriptionColor or colors.subtext
            )
            descriptionLabel.Name = "Description"
            descriptionLabel.TextXAlignment = Enum.TextXAlignment.Center
            descriptionLabel.TextYAlignment = Enum.TextYAlignment.Center
            descriptionLabel.TextWrapped = true
            controller.description = descriptionLabel

            pcall(function()
                titleLabel.Font = options.titleFont or Enum.Font.GothamBold
                descriptionLabel.Font = options.descriptionFont or Enum.Font.Gotham
            end)

            if options.headerSeparator == true then
                controller.headerSeparator = UI.separator(
                    header,
                    UDim2.fromOffset(padding, 0),
                    UDim2.new(1, -padding * 2, 0, 1),
                    options.separatorColor or colors.border
                )
            end

            if closable then
                if options.closeIcon then
                    closeButton = UI.iconButton(
                        header,
                        options.closeIcon,
                        UDim2.new(1, -32, 0, 10),
                        UDim2.fromOffset(22, 22),
                        function()
                            controller:Close("close")
                        end,
                        {
                            color = panelColor,
                            hoverColor = colors.hover,
                            pressedColor = colors.pressed,
                            iconSize = options.closeIconSize or 11,
                            radius = options.closeRadius or 8,
                            border = false,
                        }
                    )
                else
                    closeButton = UI.button(
                        header,
                        "×",
                        UDim2.new(1, -32, 0, 10),
                        UDim2.fromOffset(22, 22),
                        function()
                            controller:Close("close")
                        end,
                        {
                            color = panelColor,
                            hoverColor = colors.hover,
                            pressedColor = colors.pressed,
                            textColor = colors.subtext,
                            textSize = 16,
                            paddingX = 0,
                            radius = 8,
                            border = false,
                        }
                    )
                end
                controller.closeButton = closeButton
            end
        end

        contentArea = UI.frame(panel, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 0), options.contentColor or panelColor)
        contentArea.Name = "ContentArea"
        contentArea.BackgroundTransparency = option(options.contentTransparency, 1)
        contentArea.ClipsDescendants = options.clipContent == true
        contentArea.ZIndex = baseZIndex + 2
        controller.contentArea = contentArea

        local contentProperties = {
            Name = "Content",
            Position = UDim2.fromOffset(padding, 0),
            Size = UDim2.new(1, -padding * 2, 1, 0),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ClipsDescendants = options.clipContent == true,
            ZIndex = baseZIndex + 3,
        }

        if options.scrollable == true then
            contentProperties.CanvasPosition = options.canvasPosition or Vector2.new(0, 0)
            contentProperties.CanvasSize = options.canvasSize or UDim2.fromOffset(0, 0)
            contentProperties.ScrollingEnabled = options.scrollingEnabled ~= false
            contentProperties.ScrollBarThickness = options.scrollBarThickness or 5
            contentProperties.ScrollBarImageColor3 = options.scrollBarColor or colors.subtext
            contentProperties.ScrollBarImageTransparency = option(options.scrollBarTransparency, 0.4)
            contentProperties.ScrollBarAutoHide = options.scrollBarAutoHide ~= false
            content = UI.create("ScrollingFrame", contentProperties, contentArea)
        else
            content = UI.create("Frame", contentProperties, contentArea)
        end
        controller.content = content

        if showFooter then
            footer = UI.frame(panel, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 0), options.footerColor or panelColor)
            footer.Name = "Footer"
            footer.BackgroundTransparency = option(options.footerTransparency, 1)
            footer.ZIndex = baseZIndex + 2
            controller.footer = footer

            if options.footerSeparator == true then
                controller.footerSeparator = UI.separator(
                    footer,
                    UDim2.fromOffset(buttonInset, 0),
                    UDim2.new(1, -buttonInset * 2, 0, 1),
                    options.separatorColor or colors.border
                )
            end

            buttonGroup = UI.frame(
                footer,
                UDim2.fromOffset(0, 0),
                UDim2.fromOffset(0, 0),
                panelColor
            )
            buttonGroup.Name = "Buttons"
            buttonGroup.BackgroundTransparency = 1
            buttonGroup.ZIndex = baseZIndex + 3
            controller.buttonGroup = buttonGroup
        end

        local animatePrompt = options.animate ~= false
        local promptSpeed = options.animationSpeed or 19
        local promptCloseSpeed = options.closeSpeed or 24
        local promptProgress = 0
        local promptTarget = 0
        local promptHeartbeat
        local promptBaseSize
        local promptVisualActive = false
        local promptBackdropTransparency = backdrop and backdrop.BackgroundTransparency or 1
        local promptBorderTransparency = controller.border and controller.border.Transparency or nil
        local promptShadowTransparency = controller.shadow and controller.shadow.Transparency or nil

        local function updateLayout()
            local availableWidth = width
            if options.size and options.size.X.Offset > 0 then
                availableWidth = options.size.X.Offset
            elseif promptBaseSize and promptBaseSize.X.Offset > 0 then
                availableWidth = promptBaseSize.X.Offset
            end

            if showHeader then
                local charsInTitle = math.max(14, math.floor((availableWidth - padding * 2) / 8.0))
                local charsInDescription = math.max(16, math.floor((availableWidth - padding * 2) / 6.7))
                titleHeight = math.max(23, textLines(title, charsInTitle) * 21)
                descriptionHeight = description ~= "" and math.max(18, textLines(description, charsInDescription) * 17) or 0

                local top = options.headerTopPadding or 22
                if image then
                    image.Position = UDim2.new(0.5, -iconSize / 2, 0, top)
                    top += iconSize + (options.iconGap or 12)
                end

                titleY = top
                descriptionY = titleY + titleHeight + (descriptionHeight > 0 and 8 or 0)
                headerHeight = option(options.headerHeight, descriptionY + descriptionHeight + (options.headerBottomPadding or 11))

                header.Size = UDim2.new(1, 0, 0, headerHeight)
                if controller.headerSeparator then
                    controller.headerSeparator.Position = UDim2.fromOffset(padding, headerHeight - 1)
                end
                titleLabel.Position = UDim2.fromOffset(padding, titleY)
                titleLabel.Size = UDim2.new(1, -padding * 2, 0, titleHeight)
                descriptionLabel.Position = UDim2.fromOffset(padding, descriptionY)
                descriptionLabel.Size = UDim2.new(1, -padding * 2, 0, descriptionHeight)
            else
                headerHeight = 0
            end

            if showFooter then
                if buttonLayout == "horizontal" then
                    footerHeight = option(options.footerHeight, #controller.buttonConfigs > 0 and buttonHeight + 24 or 0)
                else
                    local buttonsHeight = 0
                    for index, config in ipairs(controller.buttonConfigs) do
                        buttonsHeight += (config.height or buttonHeight)
                        if index > 1 then
                            buttonsHeight += buttonGap
                        end
                    end
                    footerHeight = option(options.footerHeight, #controller.buttonConfigs > 0 and footerTop + buttonsHeight + footerBottom or 0)
                end
            else
                footerHeight = 0
            end

            if autoSize then
                local measuredHeight = headerHeight + contentHeight + footerHeight + (options.bottomPadding or 0)
                promptBaseSize = UDim2.fromOffset(width, math.max(110, measuredHeight))
            elseif not promptBaseSize then
                promptBaseSize = options.size or UDim2.fromOffset(width, 220)
            end

            contentArea.Position = UDim2.fromOffset(0, headerHeight)
            contentArea.Size = UDim2.new(1, 0, 1, -(headerHeight + footerHeight))
            content.Position = UDim2.fromOffset(padding, options.contentTopPadding or 0)
            content.Size = UDim2.new(1, -padding * 2, 1, -(options.contentTopPadding or 0) - (options.contentBottomPadding or 0))

            if footer then
                footer.Position = UDim2.new(0, 0, 1, -footerHeight)
                footer.Size = UDim2.new(1, 0, 0, footerHeight)
            end

            if not promptVisualActive then
                panel.Size = promptBaseSize
            end
        end

        local function applyPrompt(alpha)
            alpha = math.clamp(alpha, 0, 1)
            local eased = alpha * alpha * (3 - 2 * alpha)

            if promptBaseSize then
                if animatePrompt and promptVisualActive then
                    panel.Size = scaledSize(promptBaseSize, 0.985 + 0.015 * eased)
                else
                    panel.Size = promptBaseSize
                end
            end

            if backdrop then
                backdrop.BackgroundTransparency = 1 - (1 - promptBackdropTransparency) * eased
            end
            if controller.border and promptBorderTransparency ~= nil then
                controller.border.Transparency = 1 - (1 - promptBorderTransparency) * eased
            end
            if controller.shadow and promptShadowTransparency ~= nil then
                controller.shadow.Transparency = 1 - (1 - promptShadowTransparency) * eased
            end
        end

        local function stopAnimation()
            if promptHeartbeat then
                promptHeartbeat:Disconnect()
                promptHeartbeat = nil
            end
        end

        local function finishClose()
            if promptBaseSize then
                panel.Size = promptBaseSize
            end
            promptVisualActive = false
            if controller.promptDestroyPending then
                controller.promptDestroyPending = false
                if not controller.destroyed then
                    controller:Destroy()
                end
            end
        end

        local function wakePrompt(target)
            promptTarget = target
            if not animatePrompt then
                stopAnimation()
                promptProgress = target
                applyPrompt(target)
                if target <= 0 then
                    screenGui.Enabled = false
                    finishClose()
                end
                return
            end

            if promptHeartbeat then
                return
            end

            promptHeartbeat = RunService.Heartbeat:Connect(function(dt)
                local speed = promptTarget <= 0 and promptCloseSpeed or promptSpeed
                if smoothTowards then
                    promptProgress = smoothTowards(promptProgress, promptTarget, speed, dt)
                else
                    promptProgress += (promptTarget - promptProgress) * (1 - math.exp(-speed * dt))
                end

                local finished = math.abs(promptProgress - promptTarget) < 0.002
                if finished then
                    promptProgress = promptTarget
                end
                applyPrompt(promptProgress)

                if finished then
                    stopAnimation()
                    if promptTarget <= 0 then
                        screenGui.Enabled = false
                        finishClose()
                    end
                end
            end)
        end

        panel.Destroying:Connect(stopAnimation)

        local function buttonColors(config)
            local role = config.role or "secondary"
            if role == "primary" then
                return config.color or colors.accent,
                    config.hoverColor or colors.selectionHover or colors.accent,
                    config.pressedColor or colors.pressed or colors.accent,
                    config.textColor or Color3.fromRGB(255, 255, 255),
                    option(config.backgroundTransparency, 0)
            elseif role == "danger" then
                return config.color or colors.error,
                    config.hoverColor or colors.error,
                    config.pressedColor or colors.pressed,
                    config.textColor or Color3.fromRGB(255, 255, 255),
                    option(config.backgroundTransparency, 0)
            elseif role == "ghost" then
                return config.color or colors.panelRaised,
                    config.hoverColor or colors.hover,
                    config.pressedColor or colors.pressed,
                    config.textColor or colors.subtext,
                    option(config.backgroundTransparency, 1)
            end

            return config.color or colors.panelRaised,
                config.hoverColor or colors.hover,
                config.pressedColor or colors.pressed,
                config.textColor or colors.text,
                option(config.backgroundTransparency, 0.12)
        end

        local function buttonWidth(config)
            if config.width then
                return config.width
            end
            local caption = tostring(config.text or config.label or config.id or "Button")
            return math.max(options.buttonWidth or 84, #caption * (options.buttonCharacterWidth or 7) + 28)
        end

        local function renderButtons()
            if not buttonGroup then
                return
            end

            UI.clear(buttonGroup)
            controller.buttons = {}
            local configs = controller.buttonConfigs

            if buttonLayout == "horizontal" then
                local totalWidth = 0
                for index, config in ipairs(configs) do
                    totalWidth += buttonWidth(config)
                    if index > 1 then
                        totalWidth += buttonGap
                    end
                end

                local alignment = options.buttonAlignment or "right"
                if alignment == "left" then
                    buttonGroup.AnchorPoint = Vector2.new(0, 0)
                    buttonGroup.Position = UDim2.fromOffset(buttonInset, 0)
                elseif alignment == "center" then
                    buttonGroup.AnchorPoint = Vector2.new(0.5, 0)
                    buttonGroup.Position = UDim2.fromScale(0.5, 0)
                else
                    buttonGroup.AnchorPoint = Vector2.new(1, 0)
                    buttonGroup.Position = UDim2.new(1, -buttonInset, 0, 0)
                end
                buttonGroup.Size = UDim2.fromOffset(totalWidth, footerHeight)
            else
                buttonGroup.AnchorPoint = Vector2.new(0, 0)
                buttonGroup.Position = UDim2.fromOffset(buttonInset, 0)
                buttonGroup.Size = UDim2.new(1, -buttonInset * 2, 0, footerHeight)
            end

            local x = 0
            local y = footerTop
            for index, config in ipairs(configs) do
                local id = config.id or config.name or tostring(index)
                local caption = config.text or config.label or tostring(id)
                local height = config.height or buttonHeight
                local bg, hover, pressed, fg, alpha = buttonColors(config)
                local buttonPosition
                local buttonSize

                if buttonLayout == "horizontal" then
                    local w = buttonWidth(config)
                    buttonPosition = UDim2.fromOffset(x, math.floor((footerHeight - height) / 2))
                    buttonSize = UDim2.fromOffset(w, height)
                    x += w + buttonGap
                elseif config.width then
                    buttonPosition = UDim2.new(0.5, -config.width / 2, 0, y)
                    buttonSize = UDim2.fromOffset(config.width, height)
                else
                    buttonPosition = UDim2.fromOffset(0, y)
                    buttonSize = UDim2.new(1, 0, 0, height)
                end

                local button
                local label
                local record
                button, label, record = UI.button(
                    buttonGroup,
                    caption,
                    buttonPosition,
                    buttonSize,
                    function()
                        if not controller.open or controller.busy or (record and not record.enabled) then
                            return
                        end

                        local callbackResult
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
                        color = bg,
                        hoverColor = hover,
                        pressedColor = pressed,
                        textColor = fg,
                        textSize = config.textSize or options.buttonTextSize or 13,
                        radius = config.radius or options.buttonRadius or 7,
                        border = option(config.border, option(options.buttonBorder, false)),
                        borderColor = config.borderColor or options.buttonBorderColor or colors.border,
                        borderTransparency = option(config.borderTransparency, option(options.buttonBorderTransparency, 0.7)),
                        paddingX = config.paddingX or options.buttonPaddingX or UI.tokens.space.md,
                        icon = config.icon,
                        iconSize = config.iconSize or options.buttonIconSize or 14,
                        enabled = config.enabled ~= false,
                    }
                )
                button.Name = tostring(id)
                button.BackgroundTransparency = alpha
                controller.buttons[id] = {
                    id = id,
                    button = button,
                    label = label,
                    record = record,
                    config = config,
                    color = bg,
                    hoverColor = hover,
                    textColor = fg,
                    transparency = alpha,
                    enabled = config.enabled ~= false,
                }
                if buttonLayout ~= "horizontal" then
                    y += height + buttonGap
                end
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
            if options.beforeClose and options.beforeClose(reason, result, self) == false then
                return false
            end

            self.open = false
            self.promptDestroyPending = options.destroyOnClose == true
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
            stopAnimation()
            UI.forgetButtons(self.screenGui)
            self.screenGui:Destroy()
        end

        function controller:SetTitle(value)
            title = tostring(value or "")
            if self.title then
                self.title.Text = title
                updateLayout()
                applyPrompt(promptProgress)
            end
        end

        function controller:SetDescription(value)
            description = tostring(value or "")
            if self.description then
                self.description.Text = description
                updateLayout()
                applyPrompt(promptProgress)
            end
        end

        function controller:SetSize(newSize)
            autoSize = false
            promptBaseSize = newSize
            updateLayout()
            applyPrompt(promptProgress)
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
                data.button.BackgroundTransparency = data.transparency
                data.label.TextColor3 = data.textColor
            else
                data.record.color = options.disabledButtonColor or colors.surface
                data.record.hoverColor = options.disabledButtonColor or colors.surface
                data.button.BackgroundColor3 = options.disabledButtonColor or colors.surface
                data.button.BackgroundTransparency = option(options.disabledButtonTransparency, 0.48)
                data.label.TextColor3 = options.disabledTextColor or colors.muted
            end
            return true
        end

        function controller:SetButtons(buttons)
            self.buttonConfigs = buttons or {}
            updateLayout()
            renderButtons()
            applyPrompt(promptProgress)
        end

        function controller:AddButton(config)
            table.insert(self.buttonConfigs, config)
            updateLayout()
            renderButtons()
            applyPrompt(promptProgress)
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
                for id, wasEnabled in pairs(self._busyStates or {}) do
                    self:SetButtonEnabled(id, wasEnabled)
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
            local startX = 0
            local startY = 0
            local startPosition

            header.MouseButton1Down:Connect(function(x, y)
                dragging = true
                startX = x
                startY = y
                startPosition = panel.Position
                if options.onDragBegin then
                    options.onDragBegin(controller)
                end
            end)

            header.MouseMoved:Connect(function(x, y)
                if not dragging or not startPosition then
                    return
                end
                panel.Position = UDim2.new(
                    startPosition.X.Scale,
                    startPosition.X.Offset + x - startX,
                    startPosition.Y.Scale,
                    startPosition.Y.Offset + y - startY
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

        updateLayout()
        renderButtons()
        panel.Size = promptBaseSize

        if options.build then
            options.build(content, controller)
        end
        if options.onCreated then
            options.onCreated(controller, content)
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
            screenGui.Enabled = false
            applyPrompt(0)
        end

        if controller.open and options.onOpen then
            options.onOpen(controller)
        end

        return panel, content, controller
    end
end

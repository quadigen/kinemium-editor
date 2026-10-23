return function(ctx)
	local UI = ctx.UI
	local RunService = game:GetService("RunService")

	local DEFAULT_CHEVRON = "builtin://global-icons/chevron-down.svg"

	local function smooth(current, target, speed, dt)
		return current + (target - current) * (1 - math.exp(-speed * dt))
	end

	function UI.collapsible(parent, title, position, size, options)
		options = options or {}

		local tokens = UI.tokens
		local colors = tokens.color

		local headerH = options.headerHeight or 30
		local animSpeed = options.animSpeed or 14
		local chevronImage = options.chevron or DEFAULT_CHEVRON
		local bgColor = options.color or colors.panelRaised
		local headerColor = options.headerColor or bgColor
		local radius = options.radius or tokens.radius.sm

		local expanded = options.expanded == true
		local bodyHeight = options.bodyHeight or 100
		local current = expanded and (headerH + bodyHeight) or headerH
		local lastHeight = -1
		local connection = nil
		local destroyed = false

		local frame: Frame =
			UI.frame(parent, position or UDim2.new(), size or UDim2.new(1, 0, 0, headerH), bgColor, radius)
		frame.Name = options.name or title
		frame.ClipsDescendants = true

		if options.layoutOrder then
			frame.LayoutOrder = options.layoutOrder
		end

		if options.border ~= false then
			UI.stroke(frame, colors.borderStrong, 1, 0.6)
		end

		local controller = {
			frame = frame,
			body = nil,
			header = nil,
			headerLabel = nil,
			summary = nil,
			chevron = nil,
		}

		local labelX = options.icon and 30 or 10

		local header, headerLabel = UI.button(
			frame,
			title,
			UDim2.fromOffset(0, 0),
			UDim2.new(1, 0, 0, headerH),
			function()
				local want = not expanded

				if options.onToggle then
					options.onToggle(want, controller)
				end

				if not options.controlled then
					controller:SetExpanded(want)
				end
			end,
			{
				icon = options.icon,
				color = headerColor,
				radius = radius,
				border = false,
				textColor = options.titleColor or colors.text,
			}
		)

		header.Name = "Header"
		headerLabel.Position = UDim2.fromOffset(labelX, 0)
		headerLabel.Size = UDim2.new(1, -(labelX + 30), 1, 0)
		headerLabel.TextXAlignment = Enum.TextXAlignment.Left
		headerLabel.TextYAlignment = Enum.TextYAlignment.Center

		local summary = UI.label(
			header,
			options.summary or "",
			UDim2.new(1, -190, 0, 0),
			UDim2.fromOffset(160, headerH),
			tokens.type.caption,
			options.summaryColor or colors.muted
		)
		summary.Name = "Summary"
		summary.TextXAlignment = Enum.TextXAlignment.Right
		summary.TextYAlignment = Enum.TextYAlignment.Center

		local chevron = UI.image(header, chevronImage, UDim2.new(1, -22, 0.5, -6), UDim2.fromOffset(12, 12))
		chevron.Name = "Chevron"
		chevron.Rotation = expanded and 0 or -90

		local body = UI.frame(frame, UDim2.fromOffset(0, headerH), UDim2.new(1, 0, 0, bodyHeight), colors.panel)
		body.Name = "Body"
		body.BackgroundTransparency = 1
		body.Visible = expanded

		UI.separator(body, UDim2.fromOffset(6, 0), UDim2.new(1, -12, 0, 1), colors.surface)

		controller.header = header
		controller.headerLabel = headerLabel
		controller.summary = summary
		controller.chevron = chevron
		controller.body = body

		local function apply()
			local height = math.floor(current + 0.5)

			if height == lastHeight then
				return
			end

			lastHeight = height

			local width = frame.Size.X
			frame.Size = UDim2.new(width.Scale, width.Offset, 0, height)

			local alpha = bodyHeight > 0 and math.clamp((current - headerH) / bodyHeight, 0, 1) or 0
			chevron.Rotation = -90 * (1 - alpha)
			body.Visible = current > headerH + 1

			if options.onHeightChanged then
				options.onHeightChanged(current, controller)
			end
		end

		local function targetHeight()
			return expanded and (headerH + bodyHeight) or headerH
		end

		local function stopAnimating()
			if connection then
				connection:Disconnect()
				connection = nil
			end
		end

		local function startAnimating()
			if connection or destroyed then
				return
			end

			connection = RunService.Heartbeat:Connect(function(dt)
				local target = targetHeight()

				current = smooth(current, target, animSpeed, dt)

				if math.abs(current - target) < 0.5 then
					current = target
				end

				apply()

				if current == target then
					stopAnimating()
				end
			end)
		end

		function controller:SetExpanded(value, instant)
			value = value == true

			if value == expanded then
				return
			end

			expanded = value

			if instant then
				stopAnimating()
				current = targetHeight()
				apply()
			else
				startAnimating()
			end

			if expanded then
				if options.onOpen then
					options.onOpen(controller)
				end
			else
				if options.onClose then
					options.onClose(controller)
				end
			end
		end

		function controller:IsExpanded()
			return expanded
		end

		function controller:Toggle()
			self:SetExpanded(not expanded)
		end

		function controller:GetHeight()
			return current
		end

		function controller:GetHeaderHeight()
			return headerH
		end

		function controller:GetBodyHeight()
			return bodyHeight
		end

		function controller:SetBodyHeight(height)
			bodyHeight = height
			body.Size = UDim2.new(1, 0, 0, height)

			if expanded then
				startAnimating()
			end
		end

		function controller:SetTitle(text)
			headerLabel.Text = tostring(text or "")
		end

		function controller:SetSummary(text, color)
			summary.Text = tostring(text or "")

			if color then
				summary.TextColor3 = color
			end
		end

		function controller:SetTitleColor(color)
			headerLabel.TextColor3 = color
		end

		function controller:SetSummaryColor(color)
			summary.TextColor3 = color
		end

		function controller:Destroy()
			destroyed = true
			stopAnimating()
			UI.forgetButtons(frame)
			frame:Destroy()
		end

		frame.Destroying:Connect(function()
			destroyed = true
			stopAnimating()
		end)

		apply()

		if options.build then
			options.build(body, controller)
		end

		return frame, controller
	end
end

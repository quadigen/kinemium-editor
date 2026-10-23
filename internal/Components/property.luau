return function(ctx)
	local UI = ctx.UI
	local colors = UI.tokens.color

	function UI.property(parent, text, position, size, value, callback, options)
		options = options or {}

		local colors = UI.tokens.color

		local rowHeight = UI.metrics.propertyRow
		local padding = options.padding or UI.tokens.space.md
		local gap = options.gap or UI.tokens.space.sm
		local fieldGap = options.fieldGap or UI.tokens.space.xs
		local textSize = options.textSize or UI.tokens.type.small
		local innerHeight = rowHeight - 2

		local row: Frame = UI.frame(
			parent,
			position or UDim2.fromOffset(0, 0),
			size or UDim2.new(1, 0, 0, rowHeight),
			options.color or colors.panel,
			options.radius or 0
		)
		row.ClipsDescendants = false
		row.Name = options.name or "Property"
		row.BackgroundTransparency = options.transparent and 1 or 0

		local labelSize, areaPosition, areaSize

		if options.labelWidth then
			labelSize = UDim2.new(0, options.labelWidth, 1, 0)
			areaPosition = UDim2.new(0, padding + options.labelWidth + gap, 0, 0)
			areaSize = UDim2.new(1, -(padding * 2 + options.labelWidth + gap), 1, 0)
		else
			local scale = options.labelScale or 0.45
			labelSize = UDim2.new(scale, -padding, 1, 0)
			areaPosition = UDim2.new(scale, gap, 0, 0)
			areaSize = UDim2.new(1 - scale, -(padding + gap), 1, 0)
		end

		local label =
			UI.label(row, text, UDim2.fromOffset(padding, 0), labelSize, textSize, options.labelColor or colors.subtext)

		label.Name = "Label"
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Center

		local holder = UI.create("Frame", {
			Name = "Content",
			Position = areaPosition,
			Size = areaSize,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, row)

		local controller = {
			frame = row,
			label = label,
			content = holder,
			fields = {},
			custom = nil,
		}

		local enabled = true

		if options.custom then
			controller.custom = options.custom(holder, controller, colors)

			function controller:Fire(newValue)
				if callback then
					callback(newValue, controller)
				end
			end

			function controller:GetValue()
				local custom = self.custom
				if type(custom) == "table" and custom.GetValue then
					return custom:GetValue()
				end
			end

			function controller:SetValue(newValue, silent)
				local custom = self.custom
				if type(custom) == "table" and custom.SetValue then
					custom:SetValue(newValue, silent)
				end
			end

			function controller:SetLabel(newText)
				label.Text = tostring(newText or "")
			end

			function controller:SetEnabled(value)
				enabled = value == true
				label.TextColor3 = enabled and (options.labelColor or colors.subtext) or colors.muted

				local custom = self.custom
				if type(custom) == "table" and custom.SetEnabled then
					custom:SetEnabled(enabled)
				end
			end

			function controller:IsEnabled()
				return enabled
			end

			function controller:Destroy()
				local custom = self.custom
				if type(custom) == "table" and custom.Destroy then
					custom:Destroy()
				end

				UI.forgetButtons(row)
				row:Destroy()
			end

			return row, controller
		end

		local multi = options.fields ~= nil or options.count ~= nil
		local configs = {}

		if options.fields then
			for index, config in ipairs(options.fields) do
				configs[index] = config
			end
		elseif options.count then
			for index = 1, options.count do
				configs[index] = {}
			end
		else
			configs[1] = {}
		end

		local count = #configs

		local function setting(config, key)
			if config[key] ~= nil then
				return config[key]
			end

			return options[key]
		end

		local function formatNumber(config, number)
			local decimals = setting(config, "decimals")

			if decimals then
				local factor = 10 ^ decimals
				number = math.floor(number * factor + 0.5) / factor
			end

			return tostring(number)
		end

		local function normalize(config, raw)
			if setting(config, "numeric") then
				local number = tonumber(raw)

				if number == nil then
					return false
				end

				local minimum, maximum = setting(config, "min"), setting(config, "max")

				if minimum then
					number = math.max(number, minimum)
				end

				if maximum then
					number = math.min(number, maximum)
				end

				return true, formatNumber(config, number)
			end

			local validate = setting(config, "validate")

			if validate then
				local ok, normalized = validate(raw)

				if not ok then
					return false
				end

				return true, normalized ~= nil and tostring(normalized) or raw
			end

			return true, raw
		end

		local function outValue(field)
			if setting(field.config, "numeric") then
				return tonumber(field.current)
			end

			return field.current
		end

		local function collect()
			if not multi then
				return outValue(controller.fields[1])
			end

			local values = {}

			for index, field in ipairs(controller.fields) do
				values[index] = outValue(field)
			end

			return values
		end

		local function notify(index)
			if not callback then
				return
			end

			if multi then
				callback(collect(), controller, index)
			else
				callback(collect(), controller)
			end
		end

		local initial = value

		if not multi then
			initial = { value }
		end

		initial = type(initial) == "table" and initial or {}

		local prefixWidth = options.prefixWidth or 12

		for index, config in ipairs(configs) do
			local cell = UI.create("Frame", {
				Name = "Field" .. index,
				Position = UDim2.new(
					(index - 1) / count,
					(index - 1) * fieldGap / count,
					0.5,
					-math.floor(innerHeight / 2)
				),
				Size = UDim2.new(1 / count, -fieldGap * (count - 1) / count, 0, innerHeight),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
			}, holder)

			local boxX, boxWidth = 0, UDim2.new(1, 0, 1, 0)

			if config.prefix then
				local prefixColor = config.prefixColor
					or (options.prefixColors and options.prefixColors[index])
					or colors.muted

				local prefix = UI.label(
					cell,
					config.prefix,
					UDim2.fromOffset(0, 0),
					UDim2.fromOffset(prefixWidth, innerHeight),
					UI.tokens.type.caption,
					prefixColor
				)

				prefix.Name = "Prefix"
				prefix.TextXAlignment = Enum.TextXAlignment.Center
				prefix.TextYAlignment = Enum.TextYAlignment.Center

				boxX = prefixWidth + 2
				boxWidth = UDim2.new(1, -boxX, 1, 0)
			end

			local startValue = initial[index]
			local startText = startValue ~= nil and tostring(startValue) or ""

			local box =
				UI.input(cell, config.placeholder or options.placeholder or "", UDim2.fromOffset(boxX, 0), boxWidth, {
					text = startText,
					textSize = textSize,
					textColor = setting(config, "textColor"),
					color = setting(config, "inputColor"),
					textEditable = not setting(config, "readOnly"),
					selectAllOnFocus = options.selectAllOnFocus,
				})

			box.Name = "Value"

			local field = { box = box, cell = cell, config = config, current = startText }

			controller.fields[index] = field

			box.FocusLost:Connect(function()
				local ok, normalized = normalize(config, box.Text)

				if not ok then
					box.Text = field.current
					return
				end

				box.Text = normalized

				if normalized == field.current then
					return
				end

				field.current = normalized
				notify(index)
			end)
		end

		controller.box = controller.fields[1].box

		function controller:GetValue()
			return collect()
		end

		function controller:GetField(index)
			local field = self.fields[index]
			return field and outValue(field) or nil
		end

		function controller:SetField(index, newValue, silent)
			local field = self.fields[index]

			if not field then
				return false
			end

			local raw = newValue ~= nil and tostring(newValue) or ""
			local ok, normalized = normalize(field.config, raw)

			if not ok then
				return false
			end

			field.current = normalized
			field.box.Text = normalized

			if not silent then
				notify(index)
			end

			return true
		end

		function controller:SetValue(newValue, silent)
			if not multi then
				return self:SetField(1, newValue, silent)
			end

			if type(newValue) ~= "table" then
				return false
			end

			local changed = false

			for index = 1, count do
				if newValue[index] ~= nil and self:SetField(index, newValue[index], true) then
					changed = true
				end
			end

			if changed and not silent then
				notify(nil)
			end

			return changed
		end

		function controller:SetLabel(newText)
			label.Text = tostring(newText or "")
		end

		function controller:SetEnabled(value)
			enabled = value == true

			label.TextColor3 = enabled and (options.labelColor or colors.subtext) or colors.muted

			for _, field in ipairs(self.fields) do
				field.box.TextEditable = enabled and not setting(field.config, "readOnly")
				field.box.Active = enabled
				field.box.TextColor3 = enabled and (setting(field.config, "textColor") or colors.text) or colors.muted
			end
		end

		function controller:IsEnabled()
			return enabled
		end

		function controller:Focus(index)
			local field = self.fields[index or 1]

			if field then
				field.box:CaptureFocus()
			end
		end

		function controller:Destroy()
			UI.forgetButtons(row)
			row:Destroy()
		end

		return row, controller
	end
end

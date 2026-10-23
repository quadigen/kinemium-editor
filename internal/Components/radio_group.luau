return function(ctx)
	local UI = ctx.UI

	function UI.radioGroup(parent, position, size, items, value, callback, options)
		options = options or {}

		items = items or {}

		local rowHeight = options.itemHeight or UI.metrics.propertyRow
		local gap = options.gap or 4
		local horizontal = options.direction == "horizontal"

		local container = UI.frame(parent, position or UDim2.fromOffset(0, 0), size, UI.tokens.color.panel)

		container.BackgroundTransparency = 1

		local currentValue = value
		local radios = {}

		local function normalize(item)
			if type(item) == "table" then
				local itemValue = item.value
				if itemValue == nil then
					itemValue = item[1]
				end

				return itemValue, tostring(item.text or item.label or item.name or itemValue or "")
			end

			return item, tostring(item)
		end

		local function setSelected(newValue)
			currentValue = newValue

			for radioValue, radio in pairs(radios) do
				radio:SetValue(radioValue == newValue, true)
			end
		end

		local offset = 0

		for _, item in ipairs(items) do
			local itemValue, itemText = normalize(item)

			local itemWidth = options.itemWidth or (#itemText * 7 + 32)

			local itemPosition = horizontal and UDim2.fromOffset(offset, 0) or UDim2.fromOffset(0, offset)

			local itemSize = horizontal and UDim2.fromOffset(itemWidth, rowHeight) or UDim2.new(1, 0, 0, rowHeight)

			local _, radio = UI.radio(container, itemText, itemPosition, itemValue == currentValue, function()
				if currentValue == itemValue then
					return
				end

				setSelected(itemValue)

				if callback then
					callback(itemValue, item)
				end
			end, {
				size = itemSize,
				textSize = options.textSize,
				textColor = options.textColor,
				enabled = options.enabled,
			})

			radios[itemValue] = radio

			offset += (horizontal and itemWidth or rowHeight) + gap
		end

		local controller = {}

		function controller:GetValue()
			return currentValue
		end

		function controller:SetValue(newValue, silent)
			if radios[newValue] == nil or currentValue == newValue then
				return
			end

			setSelected(newValue)

			if not silent and callback then
				callback(newValue)
			end
		end

		function controller:SetEnabled(enabled)
			for _, radio in pairs(radios) do
				radio:SetEnabled(enabled)
			end
		end

		controller.frame = container
		controller.radios = radios

		return container, controller
	end
end

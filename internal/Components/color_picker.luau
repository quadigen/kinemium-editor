return function(ctx)
	local UI = ctx.UI
	local colors = UI.tokens.color
	local UserInputService = game:GetService("UserInputService")

	local recentColors = {}
	local MAX_RECENT = 8

	local PICKER_W = 248
	local PAD = 10
	local INNER_W = PICKER_W - PAD * 2

	local PRESETS = {
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(190, 190, 190),
		Color3.fromRGB(128, 128, 128),
		Color3.fromRGB(64, 64, 64),
		Color3.fromRGB(0, 0, 0),
		Color3.fromRGB(231, 76, 60),
		Color3.fromRGB(230, 126, 34),
		Color3.fromRGB(241, 196, 15),
		Color3.fromRGB(46, 204, 113),
		Color3.fromRGB(26, 188, 156),
		Color3.fromRGB(52, 219, 235),
		Color3.fromRGB(52, 152, 219),
		Color3.fromRGB(88, 101, 242),
		Color3.fromRGB(155, 89, 182),
		Color3.fromRGB(240, 98, 146),
		Color3.fromRGB(121, 85, 72),
	}

	local function round(n)
		return math.floor(n + 0.5)
	end

	local function toHex(c)
		return "#" .. string.upper(c:ToHex())
	end

	local function parseHex(text)
		local raw = string.gsub(text, "[#%s]", "")
		if #raw == 3 then
			raw = string.gsub(raw, ".", "%0%0")
		end
		if #raw ~= 6 or not string.match(raw, "^%x+$") then
			return nil
		end
		return Color3.fromRGB(
			tonumber(string.sub(raw, 1, 2), 16),
			tonumber(string.sub(raw, 3, 4), 16),
			tonumber(string.sub(raw, 5, 6), 16)
		)
	end

	local function contrastText(c)
		local luminance = 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
		return luminance > 0.55 and Color3.new(0, 0, 0) or Color3.new(1, 1, 1)
	end

	local function isPointerBegin(input)
		return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
	end

	local function isPointerMove(input)
		return input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
	end

	local function checker(parent, width, height, cell, radius)
		local holder =
			UI.frame(parent, UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), Color3.fromRGB(255, 255, 255), radius or 0)
		holder.ClipsDescendants = true
		local cols, rows = math.ceil(width / cell), math.ceil(height / cell)
		for row = 0, rows - 1 do
			for col = 0, cols - 1 do
				if (row + col) % 2 == 1 then
					local tile = UI.frame(
						holder,
						UDim2.fromOffset(col * cell, row * cell),
						UDim2.fromOffset(cell, cell),
						Color3.fromRGB(200, 200, 200),
						0
					)
					tile.BorderSizePixel = 0
				end
			end
		end
		return holder
	end

	function UI.colorPicker(parent, position, size, initialColor, callback, options)
		options = options or {}
		local showAlpha = options.alpha ~= false

		local picker =
			UI.frame(parent, position, size or UDim2.fromOffset(PICKER_W, 400), colors.panel, UI.tokens.radius.md)
		picker.Name = "ColorPicker"
		picker.ZIndex = 100000
		UI.stroke(picker, colors.borderStrong, 1, 0)

		local color = initialColor or Color3.new(1, 1, 1)
		local originalColor = color
		local alpha = math.clamp(options.initialAlpha or 1, 0, 1)
		local originalAlpha = alpha
		local hue, saturation, value = color:ToHSV()
		local dragMode = nil
		local fields = {}
		local connections = {}
		local redraw

		local function emit()
			if callback then
				callback(color, alpha)
			end
		end

		local function pushRecent()
			local hex = toHex(color)
			for index = #recentColors, 1, -1 do
				if toHex(recentColors[index]) == hex then
					table.remove(recentColors, index)
				end
			end
			table.insert(recentColors, 1, color)
			while #recentColors > MAX_RECENT do
				table.remove(recentColors)
			end
		end

		local recentButtons = {}
		local function refreshRecent()
			for index, button in ipairs(recentButtons) do
				local recent = recentColors[index]
				button.Visible = recent ~= nil
				if recent then
					button.BackgroundColor3 = recent
				end
			end
		end

		local function commit()
			pushRecent()
			refreshRecent()
			if options.onCommit then
				options.onCommit(color, alpha)
			end
		end

		local function setFromColor(c)
			color = c
			local h, s, v = c:ToHSV()
			if s > 0 and v > 0 then
				hue = h
			end
			saturation, value = s, v
		end

		local function setHSV(notify)
			color = Color3.fromHSV(hue, saturation, value)
			redraw()
			if notify then
				emit()
			end
		end

		local title = UI.label(
			picker,
			options.title or "Color",
			UDim2.fromOffset(PAD, 7),
			UDim2.new(1, -60, 0, 18),
			UI.tokens.type.small,
			colors.text
		)
		title.TextXAlignment = Enum.TextXAlignment.Left

		local closeButton = UI.create("TextButton", {
			Text = "×",
			Position = UDim2.new(1, -30, 0, 5),
			Size = UDim2.fromOffset(22, 22),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			TextColor3 = colors.subtext,
			TextSize = 18,
			AutoButtonColor = false,
			Active = true,
			InputSink = true,
		}, picker)
		closeButton.MouseButton1Click:Connect(function()
			picker.Visible = false
			if options.onClose then
				options.onClose()
			end
		end)

		local y = 30
		local square = UI.frame(
			picker,
			UDim2.fromOffset(PAD, y),
			UDim2.new(1, -PAD * 2, 0, 150),
			Color3.fromHSV(hue, 1, 1),
			UI.tokens.radius.xs
		)

		local whiteOverlay =
			UI.frame(square, UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), Color3.new(1, 1, 1), UI.tokens.radius.xs)
		UI.create("UIGradient", {
			Transparency = NumberSequence.new(0, 1),
			Rotation = 0,
		}, whiteOverlay)
		local blackOverlay =
			UI.frame(square, UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), Color3.new(0, 0, 0), UI.tokens.radius.xs)
		UI.create("UIGradient", {
			Transparency = NumberSequence.new(1, 0),
			Rotation = 90,
		}, blackOverlay)

		local squareInput = UI.create("TextButton", {
			Text = "",
			Position = UDim2.fromScale(0, 0),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Active = true,
			InputSink = true,
		}, square)
		local squareCursor = UI.frame(square, UDim2.fromOffset(0, 0), UDim2.fromOffset(12, 12), Color3.new(1, 1, 1), 6)
		squareCursor.BackgroundTransparency = 1
		UI.stroke(squareCursor, Color3.new(1, 1, 1), 2, 0)
		local squareCursorShadow =
			UI.frame(squareCursor, UDim2.fromOffset(-2, -2), UDim2.fromOffset(16, 16), Color3.new(0, 0, 0), 8)
		squareCursorShadow.BackgroundTransparency = 1
		UI.stroke(squareCursorShadow, Color3.new(0, 0, 0), 1, 0.4)

		y = y + 150 + 8
		local hueBar = UI.frame(
			picker,
			UDim2.fromOffset(PAD, y),
			UDim2.new(1, -PAD * 2, 0, 14),
			Color3.new(1, 1, 1),
			UI.tokens.radius.xs
		)
		UI.create("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
				ColorSequenceKeypoint.new(1 / 6, Color3.fromRGB(255, 255, 0)),
				ColorSequenceKeypoint.new(2 / 6, Color3.fromRGB(0, 255, 0)),
				ColorSequenceKeypoint.new(3 / 6, Color3.fromRGB(0, 255, 255)),
				ColorSequenceKeypoint.new(4 / 6, Color3.fromRGB(0, 0, 255)),
				ColorSequenceKeypoint.new(5 / 6, Color3.fromRGB(255, 0, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
			}),
			Rotation = 0,
		}, hueBar)
		local hueInput = UI.create("TextButton", {
			Text = "",
			Position = UDim2.fromScale(0, 0),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Active = true,
			InputSink = true,
		}, hueBar)
		local hueCursor = UI.frame(hueBar, UDim2.fromOffset(0, -2), UDim2.fromOffset(4, 18), Color3.new(1, 1, 1), 2)
		UI.stroke(hueCursor, Color3.new(0, 0, 0), 1, 0.3)

		local alphaFill, alphaInput, alphaCursor
		if showAlpha then
			y = y + 14 + 8
			local alphaBar = UI.frame(
				picker,
				UDim2.fromOffset(PAD, y),
				UDim2.new(1, -PAD * 2, 0, 14),
				Color3.new(1, 1, 1),
				UI.tokens.radius.xs
			)
			alphaBar.ClipsDescendants = true
			checker(alphaBar, INNER_W, 14, 7, UI.tokens.radius.xs)
			alphaFill = UI.frame(alphaBar, UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), color, UI.tokens.radius.xs)
			UI.create("UIGradient", {
				Transparency = NumberSequence.new(1, 0),
				Rotation = 0,
			}, alphaFill)
			alphaInput = UI.create("TextButton", {
				Text = "",
				Position = UDim2.fromScale(0, 0),
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Active = true,
				InputSink = true,
			}, alphaBar)

			local alphaCursorHolder =
				UI.frame(picker, UDim2.fromOffset(PAD, y), UDim2.new(1, -PAD * 2, 0, 14), colors.panel, 0)
			alphaCursorHolder.BackgroundTransparency = 1
			alphaCursor =
				UI.frame(alphaCursorHolder, UDim2.fromOffset(0, -2), UDim2.fromOffset(4, 18), Color3.new(1, 1, 1), 2)
			UI.stroke(alphaCursor, Color3.new(0, 0, 0), 1, 0.3)
		end

		y = y + 14 + 12
		local previewW = (INNER_W - 8) / 2
		local oldHolder = UI.frame(
			picker,
			UDim2.fromOffset(PAD, y),
			UDim2.fromOffset(previewW, 26),
			colors.input,
			UI.tokens.radius.xs
		)
		oldHolder.ClipsDescendants = true
		checker(oldHolder, previewW, 26, 7)
		local oldSwatch = UI.frame(oldHolder, UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), originalColor, 0)
		oldSwatch.BackgroundTransparency = 1 - originalAlpha
		local oldLabel = UI.label(
			oldHolder,
			"Old (reset)",
			UDim2.fromOffset(0, 0),
			UDim2.fromScale(1, 1),
			11,
			contrastText(originalColor)
		)
		local oldButton = UI.create("TextButton", {
			Text = "",
			Position = UDim2.fromScale(0, 0),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Active = true,
			InputSink = true,
		}, oldHolder)
		UI.stroke(oldHolder, colors.borderStrong, 1, 0)

		local newHolder = UI.frame(
			picker,
			UDim2.fromOffset(PAD + previewW + 8, y),
			UDim2.fromOffset(previewW, 26),
			colors.input,
			UI.tokens.radius.xs
		)
		newHolder.ClipsDescendants = true
		checker(newHolder, previewW, 26, 7)
		local newSwatch = UI.frame(newHolder, UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), color, 0)
		local newLabel =
			UI.label(newHolder, "New", UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), 11, contrastText(color))
		UI.stroke(newHolder, colors.borderStrong, 1, 0)

		local function makeRow(rowY)
			local row = UI.frame(picker, UDim2.fromOffset(PAD, rowY), UDim2.new(1, -PAD * 2, 0, 24), colors.panel, 0)
			row.BackgroundTransparency = 1
			return row
		end

		local function makeField(row, key, labelText, x, labelW, inputW, onCommit)
			local label =
				UI.label(row, labelText, UDim2.fromOffset(x, 2), UDim2.fromOffset(labelW, 20), 11, colors.subtext)
			label.TextXAlignment = Enum.TextXAlignment.Left
			local box = UI.input(row, "", UDim2.fromOffset(x + labelW, 0), UDim2.fromOffset(inputW, 24), {
				text = "",
				maxLength = key == "HEX" and 7 or 5,
				textSize = 12,
			})
			box.FocusLost:Connect(function()
				onCommit(box.Text)
			end)
			fields[key] = box
			return box
		end

		local function numberCommit(minValue, maxValue, apply)
			return function(text)
				local number = tonumber((string.gsub(text, "[%%°]", "")))
				if number then
					apply(math.clamp(number, minValue, maxValue))
					emit()
					commit()
				end
				redraw()
			end
		end

		y = y + 26 + 10
		local hexRow = makeRow(y)
		local hexInputWidth = showAlpha and 102 or (INNER_W - 34)
		makeField(hexRow, "HEX", "HEX", 0, 34, hexInputWidth, function(text)
			local parsed = parseHex(text)
			if parsed then
				setFromColor(parsed)
				emit()
				commit()
			end
			redraw()
		end)
		if showAlpha then
			makeField(
				hexRow,
				"A",
				"A%",
				144,
				22,
				62,
				numberCommit(0, 100, function(n)
					alpha = n / 100
				end)
			)
		end

		y = y + 24 + 6
		local rgbRow = makeRow(y)
		local function setChannel(channel, n)
			local r, g, b = round(color.R * 255), round(color.G * 255), round(color.B * 255)
			if channel == "R" then
				r = round(n)
			elseif channel == "G" then
				g = round(n)
			else
				b = round(n)
			end
			setFromColor(Color3.fromRGB(r, g, b))
		end
		for index, channel in ipairs({ "R", "G", "B" }) do
			makeField(
				rgbRow,
				channel,
				channel,
				(index - 1) * 78,
				14,
				62,
				numberCommit(0, 255, function(n)
					setChannel(channel, n)
				end)
			)
		end

		y = y + 24 + 6
		local hsvRow = makeRow(y)
		makeField(
			hsvRow,
			"H",
			"H",
			0,
			14,
			62,
			numberCommit(0, 360, function(n)
				hue = math.min(n / 360, 0.9999)
				color = Color3.fromHSV(hue, saturation, value)
			end)
		)
		makeField(
			hsvRow,
			"S",
			"S",
			78,
			14,
			62,
			numberCommit(0, 100, function(n)
				saturation = n / 100
				color = Color3.fromHSV(hue, saturation, value)
			end)
		)
		makeField(
			hsvRow,
			"V",
			"V",
			156,
			14,
			62,
			numberCommit(0, 100, function(n)
				value = n / 100
				color = Color3.fromHSV(hue, saturation, value)
			end)
		)

		local function makeSwatch(x, swatchY, swatchColor, onClick)
			local button = UI.create("TextButton", {
				Text = "",
				Position = UDim2.fromOffset(x, swatchY),
				Size = UDim2.fromOffset(24, 20),
				BackgroundColor3 = swatchColor,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Active = true,
				InputSink = true,
			}, picker)
			UI.corner(button, 3)
			UI.stroke(button, colors.borderStrong, 1, 0.3)
			button.MouseButton1Click:Connect(onClick)
			return button
		end

		local function chooseColor(c)
			setFromColor(c)
			redraw()
			emit()
			commit()
		end

		y = y + 24 + 12
		local presetsLabel =
			UI.label(picker, "Presets", UDim2.fromOffset(PAD, y), UDim2.fromOffset(100, 14), 11, colors.subtext)
		presetsLabel.TextXAlignment = Enum.TextXAlignment.Left
		y = y + 16
		for index, preset in ipairs(PRESETS) do
			local col = (index - 1) % 8
			local row = math.floor((index - 1) / 8)
			makeSwatch(PAD + col * 29, y + row * 25, preset, function()
				chooseColor(preset)
			end)
		end
		y = y + 25 * 2 + 4

		local recentLabel =
			UI.label(picker, "Recent", UDim2.fromOffset(PAD, y), UDim2.fromOffset(100, 14), 11, colors.subtext)
		recentLabel.TextXAlignment = Enum.TextXAlignment.Left
		y = y + 16
		for index = 1, MAX_RECENT do
			local button = makeSwatch(PAD + (index - 1) * 29, y, Color3.new(0, 0, 0), function()
				if recentColors[index] then
					chooseColor(recentColors[index])
				end
			end)
			button.Visible = false
			recentButtons[index] = button
		end
		y = y + 20 + PAD

		if not size then
			picker.Size = UDim2.fromOffset(PICKER_W, y)
		end

		redraw = function()
			square.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
			squareCursor.Position = UDim2.new(saturation, -6, 1 - value, -6)
			hueCursor.Position = UDim2.new(hue, -2, 0, -2)

			newSwatch.BackgroundColor3 = color
			newSwatch.BackgroundTransparency = 1 - alpha
			newLabel.TextColor3 = alpha > 0.5 and contrastText(color) or colors.text

			if alphaFill then
				alphaFill.BackgroundColor3 = color
				alphaCursor.Position = UDim2.new(alpha, -2, 0, -2)
			end

			local values = {
				HEX = toHex(color),
				R = tostring(round(color.R * 255)),
				G = tostring(round(color.G * 255)),
				B = tostring(round(color.B * 255)),
				H = tostring(round(hue * 360)),
				S = tostring(round(saturation * 100)),
				V = tostring(round(value * 100)),
				A = tostring(round(alpha * 100)),
			}
			for key, box in pairs(fields) do
				if not box:IsFocused() then
					box.Text = values[key]
				end
			end
		end

		local function setSquareFromPoint(px, py)
			local p, s = square.AbsolutePosition, square.AbsoluteSize
			if s.X <= 0 or s.Y <= 0 then
				return
			end
			saturation = math.clamp((px - p.X) / s.X, 0, 1)
			value = 1 - math.clamp((py - p.Y) / s.Y, 0, 1)
			setHSV(true)
		end

		local function setHueFromPoint(px)
			local p, s = hueBar.AbsolutePosition, hueBar.AbsoluteSize
			if s.X <= 0 then
				return
			end
			hue = math.clamp((px - p.X) / s.X, 0, 0.9999)
			setHSV(true)
		end

		local function setAlphaFromPoint(px)
			if not alphaFill then
				return
			end
			local p, s = alphaFill.AbsolutePosition, alphaFill.AbsoluteSize
			if s.X <= 0 then
				return
			end
			alpha = math.clamp((px - p.X) / s.X, 0, 1)
			redraw()
			emit()
		end

		local function handleDrag(position2d)
			if dragMode == "square" then
				setSquareFromPoint(position2d.X, position2d.Y)
			elseif dragMode == "hue" then
				setHueFromPoint(position2d.X)
			elseif dragMode == "alpha" then
				setAlphaFromPoint(position2d.X)
			end
		end

		local function bindDrag(button, mode)
			button.InputBegan:Connect(function(input)
				if isPointerBegin(input) then
					dragMode = mode
					handleDrag(input.Position)
				end
			end)
		end
		bindDrag(squareInput, "square")
		bindDrag(hueInput, "hue")
		if alphaInput then
			bindDrag(alphaInput, "alpha")
		end

		table.insert(
			connections,
			UserInputService.InputChanged:Connect(function(input)
				if dragMode and isPointerMove(input) then
					handleDrag(input.Position)
				end
			end)
		)
		table.insert(
			connections,
			UserInputService.InputEnded:Connect(function(input)
				if dragMode and isPointerBegin(input) then
					dragMode = nil
					commit()
				end
			end)
		)

		oldButton.MouseButton1Click:Connect(function()
			setFromColor(originalColor)
			alpha = originalAlpha
			redraw()
			emit()
		end)

		picker:GetPropertyChangedSignal("Visible"):Connect(function()
			if not picker.Visible then
				dragMode = nil
			else
				refreshRecent()
			end
		end)

		picker.Destroying:Connect(function()
			for _, connection in ipairs(connections) do
				connection:Disconnect()
			end
			table.clear(connections)
		end)

		for _, child in ipairs(picker:GetDescendants()) do
			if child:IsA("GuiObject") then
				child.ZIndex = 100001
			end
		end

		squareCursor.ZIndex = 100003
		squareCursorShadow.ZIndex = 100003
		squareInput.ZIndex = 100002
		hueCursor.ZIndex = 100003
		if alphaCursor then
			alphaCursor.ZIndex = 100003
		end
		oldLabel.ZIndex = 100003
		newLabel.ZIndex = 100003
		oldButton.ZIndex = 100004

		redraw()
		refreshRecent()

		local controller = { frame = picker }

		function controller:GetColor()
			return color
		end
		function controller:GetAlpha()
			return alpha
		end
		function controller:GetHex()
			return toHex(color)
		end
		function controller:SetColor(nextColor, silent)
			setFromColor(nextColor or Color3.new(1, 1, 1))
			redraw()
			if not silent then
				emit()
			end
		end
		function controller:SetAlpha(nextAlpha, silent)
			alpha = math.clamp(nextAlpha or 1, 0, 1)
			redraw()
			if not silent then
				emit()
			end
		end
		function controller:SetHex(hex, silent)
			local parsed = parseHex(hex or "")
			if parsed then
				controller:SetColor(parsed, silent)
			end
		end
		function controller:Show()
			picker.Visible = true
		end
		function controller:Hide()
			picker.Visible = false
		end
		function controller:Toggle()
			picker.Visible = not picker.Visible
		end
		function controller:IsVisible()
			return picker.Visible
		end
		function controller:Destroy()
			picker:Destroy()
		end

		picker.Visible = false
		return picker, controller
	end
end

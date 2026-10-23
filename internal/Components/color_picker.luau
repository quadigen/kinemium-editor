return function(ctx)
	local UI = ctx.UI
	local colors = UI.tokens.color

	function UI.colorPicker(parent, position, size, initialColor, callback)
		local colors = UI.tokens.color
		local picker = UI.frame(parent, position, size or UDim2.fromOffset(226, 286), colors.panel, UI.tokens.radius.md)
		picker.Name = "ColorPicker"
		picker.ZIndex = 100000
		UI.stroke(picker, colors.borderStrong, 1, 0)

		local title = UI.label(
			picker,
			"Color",
			UDim2.fromOffset(10, 7),
			UDim2.new(1, -20, 0, 18),
			UI.tokens.type.small,
			colors.text
		)
		title.TextXAlignment = Enum.TextXAlignment.Left

		local color = initialColor or Color3.new(1, 1, 1)
		local hue, saturation, value = color:ToHSV()
		local draggingSquare, draggingHue = false, false
		local redraw

		local square = UI.frame(
			picker,
			UDim2.fromOffset(10, 30),
			UDim2.new(1, -20, 0, 142),
			Color3.fromHSV(hue, 1, 1),
			UI.tokens.radius.xs
		)
		square.ClipsDescendants = true
		UI.create("UIGradient", {
			Color = ColorSequence.new(Color3.new(1, 1, 1)),
			Transparency = NumberSequence.new(0, 1),
			Rotation = 0,
		}, square)
		UI.create("UIGradient", {
			Color = ColorSequence.new(Color3.new(0, 0, 0)),
			Transparency = NumberSequence.new(1, 0),
			Rotation = 90,
		}, square)
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
		UI.stroke(squareCursor, Color3.new(0, 0, 0), 1, 0)

		local hueBar =
			UI.frame(picker, UDim2.fromOffset(10, 180), UDim2.new(1, -20, 0, 14), colors.input, UI.tokens.radius.xs)
		for index = 0, 23 do
			local segment = UI.frame(
				hueBar,
				UDim2.new(index / 24, 0, 0, 0),
				UDim2.new(1 / 24, 1, 1, 0),
				Color3.fromHSV(index / 24, 1, 1),
				0
			)
			segment.BorderSizePixel = 0
		end
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
		local hueCursor = UI.frame(hueBar, UDim2.fromOffset(0, -2), UDim2.fromOffset(4, 18), colors.text, 2)

		local hexLabel =
			UI.label(picker, "HEX", UDim2.fromOffset(10, 208), UDim2.fromOffset(28, 20), 11, colors.subtext)
		hexLabel.TextXAlignment = Enum.TextXAlignment.Left
		local hexInput = UI.input(picker, "#FFFFFF", UDim2.fromOffset(42, 205), UDim2.new(1, -52, 0, 24), {
			text = string.format("#%02X%02X%02X", color.R * 255, color.G * 255, color.B * 255),
			maxLength = 7,
			textSize = 12,
		})
		local function applyHex()
			local raw = string.gsub(hexInput.Text, "#", "")
			if #raw == 6 then
				local red, green, blue =
					tonumber(string.sub(raw, 1, 2), 16),
					tonumber(string.sub(raw, 3, 4), 16),
					tonumber(string.sub(raw, 5, 6), 16)
				if red and green and blue then
					color = Color3.fromRGB(red, green, blue)
					hue, saturation, value = color:ToHSV()
					redraw()
					if callback then
						callback(color)
					end
				end
			end
		end
		hexInput.FocusLost:Connect(function()
			applyHex()
		end)
		local swatches = UI.frame(picker, UDim2.fromOffset(10, 240), UDim2.new(1, -20, 0, 34), colors.panel, 0)
		local presetColors = {
			Color3.fromRGB(255, 255, 255),
			Color3.fromRGB(0, 0, 0),
			Color3.fromRGB(231, 76, 60),
			Color3.fromRGB(241, 196, 15),
			Color3.fromRGB(46, 204, 113),
			Color3.fromRGB(52, 152, 219),
			Color3.fromRGB(155, 89, 182),
			Color3.fromRGB(149, 165, 166),
		}

		redraw = function()
			square.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
			squareCursor.Position = UDim2.new(saturation, -6, 1 - value, -6)
			hueCursor.Position = UDim2.new(hue, -2, 0, -2)
			hexInput.Text = string.format("#%02X%02X%02X", color.R * 255, color.G * 255, color.B * 255)
		end

		local function updateColor(notify)
			color = Color3.fromHSV(hue, saturation, value)
			redraw()
			if notify and callback then
				callback(color)
			end
		end

		local function setSquareFromPoint(x, y)
			local p, s = square.AbsolutePosition, square.AbsoluteSize
			if not p or not s or s.X <= 0 or s.Y <= 0 then
				return
			end
			saturation = math.clamp((x - p.X) / s.X, 0, 1)
			value = 1 - math.clamp((y - p.Y) / s.Y, 0, 1)
			updateColor(true)
		end

		local function setHueFromPoint(x)
			local p, s = hueBar.AbsolutePosition, hueBar.AbsoluteSize
			if not p or not s or s.X <= 0 then
				return
			end
			hue = math.clamp((x - p.X) / s.X, 0, 1)
			updateColor(true)
		end

		squareInput.MouseButton1Down:Connect(function(x, y)
			draggingSquare = true
			setSquareFromPoint(x, y)
		end)
		squareInput.MouseMoved:Connect(function(x, y)
			if draggingSquare then
				setSquareFromPoint(x, y)
			end
		end)
		squareInput.MouseButton1Up:Connect(function()
			draggingSquare = false
		end)
		hueInput.MouseButton1Down:Connect(function(x)
			draggingHue = true
			setHueFromPoint(x)
		end)
		hueInput.MouseMoved:Connect(function(x)
			if draggingHue then
				setHueFromPoint(x)
			end
		end)
		hueInput.MouseButton1Up:Connect(function()
			draggingHue = false
		end)
		for index, preset in ipairs(presetColors) do
			local swatchButton = UI.create("TextButton", {
				Text = "",
				Position = UDim2.fromOffset((index - 1) * 25, 0),
				Size = UDim2.fromOffset(20, 20),
				BackgroundColor3 = preset,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Active = true,
				InputSink = true,
			}, swatches)
			UI.corner(swatchButton, 2)
			swatchButton.MouseButton1Click:Connect(function()
				color = preset
				hue, saturation, value = color:ToHSV()
				redraw()
				if callback then
					callback(color)
				end
			end)
		end

		local function setZIndex()
			for _, child in ipairs(picker:GetDescendants()) do
				if child:IsA("GuiObject") then
					child.ZIndex = 100001
				end
			end
		end
		setZIndex()
		redraw()

		local controller = { frame = picker }
		function controller:GetColor()
			return color
		end
		function controller:SetColor(nextColor, silent)
			color = nextColor or Color3.new(1, 1, 1)
			hue, saturation, value = color:ToHSV()
			redraw()
			if not silent and callback then
				callback(color)
			end
		end

		picker.Visible = false
		return picker, controller
	end
end

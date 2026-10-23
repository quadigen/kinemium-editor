return function(ctx)
	local UI = ctx.UI
	local colors = UI.tokens.color

	function UI.point2D(parent, position, size, minimumX, maximumX, minimumY, maximumY, x, y, callback, options)
		options = options or {}

		local colors = UI.tokens.color

		minimumX = minimumX or -1
		maximumX = maximumX or 1
		minimumY = minimumY or -1
		maximumY = maximumY or 1

		x = math.clamp(x or 0, minimumX, maximumX)
		y = math.clamp(y or 0, minimumY, maximumY)

		local dragging = false

		local pad = UI.create("TextButton", {
			Text = "",
			Position = position,
			Size = size or UDim2.fromOffset(160, 120),

			BackgroundColor3 = options.color or colors.input,
			BorderSizePixel = 0,

			Active = true,
			InputSink = true,
			AutoButtonColor = false,
			ClipsDescendants = true,
		}, parent)

		UI.corner(pad, options.radius or UI.tokens.radius.xs)
		UI.stroke(pad, options.borderColor or colors.border, 1, 0)

		local centerX =
			UI.separator(pad, UDim2.new(0.5, 0, 0, 0), UDim2.new(0, 1, 1, 0), options.gridColor or colors.border)

		centerX.BackgroundTransparency = 0.35

		local centerY =
			UI.separator(pad, UDim2.new(0, 0, 0.5, 0), UDim2.new(1, 0, 0, 1), options.gridColor or colors.border)

		centerY.BackgroundTransparency = 0.35

		local cursorSize = options.cursorSize or 10

		local cursor = UI.frame(
			pad,
			UDim2.fromOffset(0, 0),
			UDim2.fromOffset(cursorSize, cursorSize),
			options.cursorColor or colors.text,
			math.floor(cursorSize / 2)
		)

		UI.stroke(cursor, options.cursorBorderColor or colors.borderStrong, 1, 0)

		local function normalizedX()
			if maximumX == minimumX then
				return 0
			end

			return math.clamp((x - minimumX) / (maximumX - minimumX), 0, 1)
		end

		local function normalizedY()
			if maximumY == minimumY then
				return 0
			end

			return math.clamp((y - minimumY) / (maximumY - minimumY), 0, 1)
		end

		local function redraw()
			cursor.Position =
				UDim2.new(normalizedX(), -math.floor(cursorSize / 2), normalizedY(), -math.floor(cursorSize / 2))
		end

		local function updateFromPoint(mouseX, mouseY)
			local absolutePosition = pad.AbsolutePosition
			local absoluteSize = pad.AbsoluteSize

			if not absolutePosition or not absoluteSize then
				return
			end

			if absoluteSize.X <= 0 or absoluteSize.Y <= 0 then
				return
			end

			local alphaX = math.clamp((mouseX - absolutePosition.X) / absoluteSize.X, 0, 1)

			local alphaY = math.clamp((mouseY - absolutePosition.Y) / absoluteSize.Y, 0, 1)

			x = minimumX + (maximumX - minimumX) * alphaX
			y = minimumY + (maximumY - minimumY) * alphaY

			redraw()

			if callback then
				callback(x, y)
			end
		end

		pad.MouseButton1Down:Connect(function(mouseX, mouseY)
			dragging = true

			if options.onBegin then
				options.onBegin()
			end

			updateFromPoint(mouseX, mouseY)
		end)

		pad.MouseMoved:Connect(function(mouseX, mouseY)
			if dragging then
				updateFromPoint(mouseX, mouseY)
			end
		end)

		pad.MouseButton1Up:Connect(function(mouseX, mouseY)
			if dragging then
				updateFromPoint(mouseX, mouseY)
			end

			dragging = false

			if options.onEnd then
				options.onEnd()
			end
		end)

		local controller = {
			frame = pad,
			cursor = cursor,
		}

		function controller:GetValue()
			return x, y
		end

		function controller:SetValue(newX, newY, silent)
			x = math.clamp(newX, minimumX, maximumX)
			y = math.clamp(newY, minimumY, maximumY)

			redraw()

			if not silent and callback then
				callback(x, y)
			end
		end

		redraw()

		return pad, controller
	end
end

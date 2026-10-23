return function(ctx)
	local UI = ctx.UI

	function UI.label(parent, text, position, size, textSize, color)
		return UI.create("TextLabel", {

			Text = tostring(text or ""),

			Position = position or UDim2.fromOffset(0, 0),

			Size = size or UDim2.fromOffset(100, 20),

			BackgroundTransparency = 1,

			TextSize = textSize or UI.tokens.type.body,

			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,

			TextColor3 = color or UI.tokens.color.text,

			BorderSizePixel = 0,
		}, parent)
	end
end

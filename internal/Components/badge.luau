return function(ctx)
	local UI = ctx.UI
	local colors = UI.tokens.color

	function UI.badge(parent, text, position, options)
		options = options or {}

		local colors = UI.tokens.color

		local width = options.width or math.max(36, #tostring(text) * 7 + 12)

		local height = options.height or 18

		local frame = UI.frame(
			parent,
			position,
			UDim2.fromOffset(width, height),
			options.color or colors.accentSoft,
			options.radius or math.floor(height / 2)
		)

		local label = UI.label(
			frame,
			text,
			UDim2.fromOffset(4, 0),
			UDim2.new(1, -8, 1, 0),
			options.textSize or UI.tokens.type.caption,
			options.textColor or colors.text
		)

		return frame, label
	end
end

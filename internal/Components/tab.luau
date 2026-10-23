return function(ctx)
	local UI = ctx.UI
	local colors = UI.tokens.color

	function UI.tab(parent, text, position, size, selected, callback)
		local colors = UI.tokens.color

		local button, label, record = UI.button(parent, text, position, size, callback, {

			color = selected and colors.surfaceAlt or colors.panel,

			hoverColor = colors.hover,

			textColor = selected and colors.text or colors.subtext,

			textSize = UI.tokens.type.small,

			radius = 0,

			border = false,

			paddingX = UI.tokens.space.md,
		})

		if selected then
			UI.frame(button, UDim2.new(0, 5, 1, -2), UDim2.new(1, -10, 0, 2), colors.accent, 1)
		end

		return button, label, record
	end
end

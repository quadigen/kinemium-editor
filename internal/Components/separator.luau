return function(ctx)
	local UI = ctx.UI

	function UI.separator(parent, position, size, color)
		return UI.frame(parent, position, size, color or UI.tokens.color.border)
	end
end

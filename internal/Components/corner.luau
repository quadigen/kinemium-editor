return function(ctx)
	local UI = ctx.UI

	function UI.corner(parent, radius)
		return UI.create("UICorner", { CornerRadius = UDim.new(0, radius or UI.tokens.radius.sm) }, parent)
	end
end

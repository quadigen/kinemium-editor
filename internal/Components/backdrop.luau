return function(ctx)
	local UI = ctx.UI

	function UI.backdrop(parent, radius, TintColor3)
		return UI.create("UIBackdrop", {
			TintColor3 = TintColor3,
			BlurRadius = radius,
		}, parent)
	end
end

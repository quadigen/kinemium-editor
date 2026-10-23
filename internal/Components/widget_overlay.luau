return function(ctx)
	local UI = ctx.UI
	local shared = ctx.shared

	function UI.widgetOverlay()
		if shared.widgetOverlay then
			return shared.widgetOverlay
		end

		local root = UI.create(
			"ScreenGui",
			{ Name = "Widgets", DisplayOrder = 1001, IgnoreGuiInset = true, RenderOnTop = true, Enabled = true },
			game.CoreGui
		)

		shared.widgetOverlay = root

		return root
	end
end

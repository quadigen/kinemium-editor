return function(ctx)
	local UI = ctx.UI
	local shared = ctx.shared

	function UI.contextMenuOverlay()
		if shared.contextMenuOverlay then
			return shared.contextMenuOverlay
		end

		local root = UI.create(
			"ScreenGui",
			{ Name = "Menus", DisplayOrder = 5000, IgnoreGuiInset = true, RenderOnTop = true, Enabled = true },
			game.CoreGui
		)

		shared.contextMenuOverlay = root

		return root
	end
end

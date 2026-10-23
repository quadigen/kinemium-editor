return function(ctx)
	local UI = ctx.UI
	local shared = ctx.shared

	function UI.RootOverlay()
		if shared.overlayRoot then
			return shared.overlayRoot
		end

		local root = UI.create("ScreenGui", {

			Name = "Overlay",

			DisplayOrder = 1000,

			IgnoreGuiInset = true,
		}, game.CoreGui)

		root.RenderOnTop = true

		shared.overlayRoot = root

		return root
	end
end

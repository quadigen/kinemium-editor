return function(ctx)
	local UI = ctx.UI

	function UI.iconButton(parent, icon, position, size, callback, options)
		options = options or {}

		local button, _, record = UI.button(parent, "", position, size, callback, options)

		local iconSize = options.iconSize or 16

		local image = UI.image(
			button,
			icon,
			UDim2.new(0.5, -math.floor(iconSize / 2), 0.5, -math.floor(iconSize / 2)),
			UDim2.fromOffset(iconSize, iconSize)
		)

		return button, record, image
	end
end

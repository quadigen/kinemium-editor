return function(ctx)
	local UI = ctx.UI
	local colors = UI.tokens.color

	function UI.sectionHeader(parent, text, position, size, options)
		options = options or {}

		local colors = UI.tokens.color

		local container = UI.frame(
			parent,
			position,
			size or UDim2.new(1, 0, 0, UI.metrics.sectionRow),
			options.headerColor or colors.panelRaised
		)

		container.BackgroundTransparency = options.transparent and 1 or 0

		local label = UI.label(
			container,
			text,
			UDim2.fromOffset(UI.tokens.space.md, 2),
			UDim2.new(1, -UI.tokens.space.md * 2, 1, -3),
			options.textSize or UI.tokens.type.small,
			options.textColor or colors.text
		)

		if options.separator ~= false then
			UI.separator(
				container,
				UDim2.new(0, UI.tokens.space.sm, 1, -1),
				UDim2.new(1, -UI.tokens.space.sm * 2, 0, 1),
				options.separatorColor or colors.border
			)
		end

		return container, label
	end
end

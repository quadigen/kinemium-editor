return function(ctx)
	local UI = ctx.UI
	local colors = UI.tokens.color

	function UI.card(parent, position, size, options)
		options = options or {}

		local colors = UI.tokens.color

		local card =
			UI.frame(parent, position, size, options.color or colors.surface, options.radius or UI.tokens.radius.md)

		if options.border ~= false then
			UI.stroke(
				card,
				options.borderColor or colors.border,
				options.borderThickness or 1,
				options.borderTransparency or 0
			)
		end

		if options.shadow then
			UI.create("UIShadow", {

				BlurRadius = UDim.new(0, options.shadowBlur or 10),

				Offset = UDim2.fromOffset(0, options.shadowOffset or 3),

				Spread = UDim2.fromOffset(0, 0),

				Color3 = options.shadowColor or Color3.fromRGB(0, 0, 0),

				Transparency = options.shadowTransparency or 0.6,

				Enabled = true,
			}, card)
		end

		return card
	end
end

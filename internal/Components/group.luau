return function(ctx)
	local UI = ctx.UI

	function UI.group(parent, position, size, options)
		options = options or {}

		local group = UI.frame(
			parent,
			position,
			size,
			options.color or UI.tokens.color.surface,
			options.radius or UI.tokens.radius.md
		)

		group.ClipsDescendants = true

		return group
	end
end

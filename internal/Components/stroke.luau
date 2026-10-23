return function(ctx)
	local UI = ctx.UI

	function UI.stroke(parent, color, thickness, transparency)
		return UI.create("UIStroke", {

			Color = color or UI.tokens.color.border,

			Thickness = thickness or 1,

			Transparency = transparency or 0,
		}, parent)
	end
end

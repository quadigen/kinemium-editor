return function(ctx)
	local UI = ctx.UI

	function UI.frame(parent, position, size, color, radius)
		local frame = UI.create("Frame", {

			Position = position or UDim2.fromOffset(0, 0),

			Size = size or UDim2.fromOffset(100, 100),

			BackgroundColor3 = color or UI.tokens.color.panel,

			BorderSizePixel = 0,
		}, parent)

		if radius and radius > 0 then
			UI.corner(frame, radius)
		end

		return frame
	end
end

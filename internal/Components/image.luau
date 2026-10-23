return function(ctx)
	local UI = ctx.UI

	function UI.image(parent, path, position, size)
		return UI.create("ImageLabel", {

			Image = path,

			Position = position,

			Size = size,

			BackgroundTransparency = 1,

			BorderSizePixel = 0,
		}, parent)
	end
end

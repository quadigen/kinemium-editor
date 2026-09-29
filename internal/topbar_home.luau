if (IsServer or IsClient) or IsPlaytest then
	return nil
end
local viewport = require("@internal/viewport")
local UI = require("@internal/editor_ui")
local tokens = UI.tokens
return {
	name = "Home",
	buttons = {
		{
			name = "Select",
			icon = "Cursor.svg",
			callback = function()
				viewport.ActivateTool("select")
			end,
		},
		{
			name = "Move",
			icon = "Move.svg",
			callback = function()
				viewport.ActivateTool("position")
			end,
		},
		{
			name = "Rotate",
			icon = "Rotate.svg",
			callback = function()
				viewport.ActivateTool("rotate")
			end,
		},
		{
			name = "Scale",
			icon = "Size.svg",
			callback = function()
				viewport.ActivateTool("size")
			end,
		},
		{
			type = "separator",
		},
		{
			name = "size_configure",
			type = "custom",
			width = 120,
			create = function(parent, colors)
				local frame = UI.frame(
					parent,
					UDim2.fromOffset(0, 0),
					UDim2.fromOffset(120, 50),
					colors.surface,
					tokens.radius.sm
				)

				UI.label(
					frame,
					"Custom!",
					UDim2.fromOffset(8, 8),
					UDim2.new(1, -16, 0, 20),
					tokens.type.small,
					colors.text
				)

				return frame
			end,
		},
	},
}

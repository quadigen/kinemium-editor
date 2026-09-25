if IsServer or IsClient then
	return nil
end

local viewport = require("@internal/viewport")

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
	},
}

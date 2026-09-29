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
			create = function(parent, colors, position, size)
				local panel = UI.frame(parent, position, size, colors.surface, tokens.radius.sm)

				local layout = Instance.new("UIListLayout")
				layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
				layout.FillDirection = Enum.FillDirection.Vertical
				layout.Padding = UDim.new(0, 5)
				layout.Parent = panel

				local studInput = UI.input(panel, "1 Stud/s", UDim2.fromOffset(0, 0), UDim2.new(1, -10, 0, 23), {})
				local rotation = UI.input(panel, "30°", UDim2.fromOffset(0, 0), UDim2.new(1, -10, 0, 23), {})

				studInput.FocusLost:Connect(function()
					viewport.SetSnap("handles", tonumber(studInput.Text))
				end)

				rotation.FocusLost:Connect(function()
					viewport.SetSnap("archandles", tonumber(rotation.Text))
				end)

				return panel
			end,
		},
	},
}

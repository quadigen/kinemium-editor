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
			name = "Paste",
			icon = "clipboard.svg",
			callback = function()
				viewport.ActivateTool("size")
			end,
		},
		{
			name = "clipboard_actions",
			type = "custom",
			width = 80,
			create = function(parent, colors, position, size)
				UI.buttonList(parent, position, size, {
					{ name = "Cut", icon = "cut.svg", callback = function() end },
					{ name = "Copy", icon = "copy.svg", callback = function() end },
					{ name = "Paste Into", icon = "paste_clipboard.svg", callback = function() end },
				}, { scale = 0.8 })
			end,
		},
		{
			type = "separator",
		},
		{
			name = "3d_actions",
			type = "custom",
			width = 208,
			create = function(parent, colors, position, size)
				local selectedTool = "select"
				local buttons = {
					{
						name = "Select",
						icon = "Cursor.svg",
						callback = function()
							viewport.ActivateTool("select")
							selectedTool = "select"
						end,
					},
					{
						name = "Move",
						icon = "Move.svg",
						callback = function()
							viewport.ActivateTool("position")
							selectedTool = "position"
						end,
					},
					{
						name = "Rotate",
						icon = "Rotate.svg",
						callback = function()
							viewport.ActivateTool("rotate")
							selectedTool = "rotate"
						end,
					},
					{
						name = "Scale",
						icon = "Size.svg",
						callback = function()
							viewport.ActivateTool("size")
							selectedTool = "size"
						end,
					},
				}

				local container = UI.frame(parent, position, size, colors.surface, tokens.radius.sm)
				local layout = Instance.new("UIListLayout")
				layout.FillDirection = Enum.FillDirection.Horizontal
				layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
				layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
				layout.Padding = UDim.new(0, 5)
				layout.Parent = container

				for _, button in pairs(buttons) do
					local new = UI.TopbarButton(container, button, {
						position = UDim2.fromOffset(0, 0),
						size = UDim2.new(0, 52, 1, 0),
						colors = colors,
						hoveringEnabled = false,
						radius = tokens.radius.sm,
					})

					new.MouseButton1Click:Connect(function()
						for _, otherButton in pairs(container:GetChildren()) do
							if otherButton:IsA("TextButton") then
								otherButton.BackgroundColor3 = colors.surface
							end
						end

						new.BackgroundColor3 = colors.accent
					end)
				end
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

				local studInput = UI.input(panel, "1 Stud/s", UDim2.fromOffset(0, 0), UDim2.new(1, -10, 0, 15), {})
				local rotation = UI.input(panel, "30°", UDim2.fromOffset(0, 0), UDim2.new(1, -10, 0, 15), {})

				studInput.FocusLost:Connect(function()
					local value = tonumber(studInput.Text)

					viewport.SetSnap("handles", value)
					studInput.Text = ""
					studInput.PlaceholderText = `{value} Stud/s`
				end)

				rotation.FocusLost:Connect(function()
					local value = tonumber(rotation.Text)

					viewport.SetSnap("archandles", tonumber(rotation.Text))
					rotation.Text = ""
					rotation.PlaceholderText = `{value}°`
				end)

				local frame, checkbox = UI.checkbox(
					panel,
					"Enable Snapping",
					UDim2.fromOffset(8, 8),
					true,
					function(value)
						print(value)
					end
				)

				return panel
			end,
		},
		{
			type = "separator",
		},
		{
			name = "Terrain Editor",
			icon = "Terrain.svg",
			callback = function() end,
		},
		{
			type = "separator",
		},
	},
}

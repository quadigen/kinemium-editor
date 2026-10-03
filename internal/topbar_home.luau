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
			width = 130,
			create = function(parent, colors, position, size)
				local newPos = UDim2.new(position.X.Scale, position.X.Offset, position.Y.Scale, position.Y.Offset + 2)
				local panel = UI.frame(parent, newPos, size, colors.surface, tokens.radius.sm)

				local layout = Instance.new("UIListLayout")
				layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
				layout.FillDirection = Enum.FillDirection.Vertical
				layout.Padding = UDim.new(0, 5)
				layout.Parent = panel

				-- studs
				local studContainer =
					UI.frame(panel, UDim2.fromOffset(0, 0), UDim2.new(1, -20, 0, 22), colors.surface, tokens.radius.sm)

				local studLayout = Instance.new("UIListLayout")
				studLayout.FillDirection = Enum.FillDirection.Horizontal
				studLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
				studLayout.Padding = UDim.new(0, 2)
				studLayout.Parent = studContainer

				local stud_frame, stud_checkbox = UI.checkbox(
					studContainer,
					nil,
					UDim2.fromOffset(8, 8),
					true,
					function(value)
						print(value)
					end
				)
				stud_frame.Size = UDim2.new(0, 22, 0, 22)
				stud_frame.LayoutOrder = -10

				local studInput = UI.input(studContainer, "1 Stud/s", UDim2.fromOffset(0, 0), UDim2.new(1, 0, 1, 0), {})

				-- rotation
				local rotationContainer =
					UI.frame(panel, UDim2.fromOffset(0, 0), UDim2.new(1, -20, 0, 22), colors.surface, tokens.radius.sm)

				local rotationLayout = Instance.new("UIListLayout")
				rotationLayout.FillDirection = Enum.FillDirection.Horizontal
				rotationLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
				rotationLayout.Padding = UDim.new(0, 2)
				rotationLayout.Parent = rotationContainer

				local rotation_frame, rotation_checkbox = UI.checkbox(
					rotationContainer,
					nil,
					UDim2.fromOffset(8, 8),
					true,
					function(value)
						print(value)
					end
				)
				rotation_frame.Size = UDim2.new(0, 22, 0, 22)
				rotation_frame.LayoutOrder = -10

				local rotation = UI.input(rotationContainer, "30°", UDim2.fromOffset(0, 0), UDim2.new(1, 0, 1, 0), {})

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

				return panel
			end,
		},
		{
			type = "separator",
		},
		{
			name = [[Terrain Editor]],
			width = 80,
			icon = "Terrain.svg",
			callback = function() end,
		},
		{
			type = "separator",
		},
	},
}

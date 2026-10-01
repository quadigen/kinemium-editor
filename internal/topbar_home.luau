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
			name = "clipboard",
			type = "custom",
			width = 120,
			create = function(parent, colors, position, size)
				local panel = UI.frame(parent, position, size, colors.surface, tokens.radius.sm)

				local layout = Instance.new("UIListLayout")
				layout.FillDirection = Enum.FillDirection.Vertical
				layout.Padding = UDim.new(0, 4)
				layout.Parent = panel

				-- "Clipboard" Section Label
				local label = UI.label(
					panel,
					"Clipboard",
					UDim2.fromOffset(5, 0),
					UDim2.new(1, -10, 0, 20),
					tokens.type.caption,
					colors.subtext
				)
				label.TextXAlignment = Enum.TextXAlignment.Left

				-- Button Row Container
				local buttonRow = UI.frame(panel, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 24), colors.surface)
				buttonRow.BackgroundTransparency = 1

				local rowLayout = Instance.new("UIListLayout")
				rowLayout.FillDirection = Enum.FillDirection.Horizontal
				rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
				rowLayout.Padding = UDim.new(0, 4)
				rowLayout.Parent = buttonRow

				-- Clipboard Buttons
				local actions = {
					{ Name = "Paste", Icon = "Paste.svg", Action = "paste" },
					{ Name = "Copy", Icon = "Copy.svg", Action = "copy" },
					{ Name = "Cut", Icon = "Cut.svg", Action = "cut" },
					{ Name = "Duplicate", Icon = "Duplicate.svg", Action = "duplicate" },
				}

				for _, actionData in ipairs(actions) do
					UI.iconButton(
						buttonRow,
						actionData.Icon,
						UDim2.fromOffset(0, 0),
						UDim2.fromOffset(24, 24),
						function()
							viewport.ActivateTool(actionData.Action)
						end,
						{
							color = colors.surface,
							hoverColor = colors.hover,
							pressedColor = colors.pressed,
							iconSize = 16,
							radius = tokens.radius.xs,
							border = true,
							borderColor = colors.border,
						}
					)
				end

				return panel
			end,
		},
	},
}

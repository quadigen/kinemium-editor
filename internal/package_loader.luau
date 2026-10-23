local UI = require("./editor_ui")
local Project = game:GetService("Project")
local Filesystem = game:GetService("Filesystem")

local tokens = UI.tokens

local dropdown

UI.prompt({
	title = "Package",
	description = "Install a package in one of your projects.",
	size = UDim2.fromOffset(440, 352),
	destroyOnClose = true,
	closeOnBackdrop = false,

	build = function(content)
		local items = {}

		for _, project in pairs(Project:GetProjects()) do
			local name, path = project.Name, project.Path

			table.insert(items, {
				value = path,
				label = name,
			})
		end

		dropdown = UI.dropdown(
			content,
			"Game",
			UDim2.new(0, 0, 0, 0),
			UDim2.new(1, 0, 0, 30),
			"builtin://global-icons/chevron-down.svg",
			{
				items = items,

				maxVisibleItems = 7,

				color = tokens.color.input,
				hoverColor = tokens.color.hover,
				pressedColor = tokens.color.pressed,

				borderColor = tokens.color.border,
				borderTransparency = 0.15,

				backdrop = true,
				backdropBlur = 14,
				backdropTransparency = 0.88,

				onChanged = function(value) end,
			}
		)
	end,

	buttons = {
		{
			id = "cancel",
			text = "Cancel",
			role = "ghost",
		},
		{
			id = "install",
			text = "Install",
			role = "primary",
			callback = function(controller)
				return true
			end,
		},
	},
})

if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local Selection = game:GetService("Selection")

local icon_lib = require("@internal/icon_lib")
local google_fonts_lib = require("@internal/google_fonts_lib")

local function selectedObject()
	local selected = Selection:Get()
	local object = selected and selected[1]
	return object
end

return {
	name = "UI",
	buttons = {
		{
			name = "Frame",
			icon = "Frame.svg",
			callback = function()
				local selected = selectedObject()
				if selected then
					local object = Instance.new("Frame")
					object.Parent = selected
					Selection:Set({ object })
				end
			end,
		},

		{
			name = "TextButton",
			icon = "TextButton.svg",
			callback = function()
				local selected = selectedObject()
				if selected then
					local object = Instance.new("TextButton")
					object.Parent = selected
					Selection:Set({ object })
				end
			end,
		},

		{
			name = "ImageLabel",
			icon = "ImageLabel.svg",
			callback = function()
				local selected = selectedObject()
				if selected then
					local object = Instance.new("ImageLabel")
					object.Parent = selected
					Selection:Set({ object })
				end
			end,
		},

		{
			name = "ImageButton",
			icon = "ImageButton.svg",
			callback = function()
				local selected = selectedObject()
				if selected then
					local object = Instance.new("ImageButton")
					object.Parent = selected
					Selection:Set({ object })
				end
			end,
		},

		{
			type = "separator",
		},

		{
			name = "UICorner",
			icon = "UICorner.svg",
			callback = function()
				local selected = selectedObject()
				if selected then
					local object = Instance.new("UICorner")
					object.Parent = selected
					Selection:Set({ object })
				end
			end,
		},

		{
			name = "UIStroke",
			icon = "UIStroke.svg",
			callback = function()
				local selected = selectedObject()
				if selected then
					local object = Instance.new("UIStroke")
					object.Parent = selected
					Selection:Set({ object })
				end
			end,
		},

		{
			name = "UIShadow",
			icon = "UIShadow.svg",
			callback = function()
				local selected = selectedObject()
				if selected then
					local object = Instance.new("UIShadow")
					object.Parent = selected
					Selection:Set({ object })
				end
			end,
		},

		{
			name = "UIPadding",
			icon = "UIPadding.svg",
			callback = function()
				local selected = selectedObject()
				if selected then
					local object = Instance.new("UIPadding")
					object.Parent = selected
					Selection:Set({ object })
				end
			end,
		},

		{
			name = "UIGradient",
			icon = "UIGradient.svg",
			callback = function()
				local selected = selectedObject()
				if selected then
					local object = Instance.new("UIGradient")
					object.Parent = selected
					Selection:Set({ object })
				end
			end,
		},

		{
			type = "separator",
		},

		{
			name = "Icon Library",
			icon = "VectorForce.svg",
			callback = function()
				icon_lib.Toggle()
			end,
		},

		{
			name = "Font Library",
			icon = "Font.svg",
			callback = function()
				google_fonts_lib.Toggle()
			end,
		},
	},
}

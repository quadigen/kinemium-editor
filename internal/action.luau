local ServerScriptService = game:GetService("ServerScriptService")

-- Create a new toolbar section and Plugins menu folder titled "Custom"
local toolbar = plugin:CreateToolbar("Custom")

-- Add a toolbar button labeled "Empty Script"
local newScriptButton = toolbar:CreateButton("Empty Script", "Create an empty script", "rbxassetid://14978048121")

-- Make button clickable even if 3D viewport is hidden
newScriptButton.ClickableWhenViewportHidden = true

local function onPluginButtonClicked()
	local newScript = Instance.new("Script")
	newScript.Source = ""
	newScript.Parent = ServerScriptService
end

newScriptButton.Click:Connect(onPluginButtonClicked)

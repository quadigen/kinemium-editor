-- This code can be pasted into the Command Bar, but only once
local pluginMenu = plugin:CreatePluginMenu(math.random(), "Test Menu")
pluginMenu.Name = "Test Menu"

pluginMenu:AddNewAction("ActionA", "A", "rbxasset://textures/loading/robloxTiltRed.png")
pluginMenu:AddNewAction("ActionB", "B", "rbxasset://textures/loading/robloxTilt.png")

local subMenu = plugin:CreatePluginMenu(math.random(), "C", "rbxasset://textures/explosion.png")
subMenu.Name = "Sub Menu"

subMenu:AddNewAction("ActionD", "D", "rbxasset://textures/whiteCircle.png")
subMenu:AddNewAction("ActionE", "E", "rbxasset://textures/icon_ROBUX.png")

pluginMenu:AddMenu(subMenu)
pluginMenu:AddSeparator()

pluginMenu:AddNewAction("ActionF", "F", "rbxasset://textures/sparkle.png")

local toggle = Instance.new("BoolValue")
toggle.Name = "TogglePluginMenu"
toggle.Parent = workspace

local function onToggled()
	if toggle.Value then
		toggle.Value = false

		local selectedAction = pluginMenu:ShowAsync()
		if selectedAction then
			print("Selected Action:", selectedAction.Text, "with ActionId:", selectedAction.ActionId)
		else
			print("User did not select an action!")
		end
	end
end

toggle.Changed:Connect(onToggled)

local ReflectionService = game:GetService("ReflectionService")
local ServerScriptService = game:GetService("ServerScriptService")
task.wait(5)
-- Create a new toolbar section and Plugins menu folder titled "Custom"
local toolbar = plugin:CreateToolbar("Custom")

-- Add a toolbar button labeled "Empty Script"
local newScriptButton = toolbar:CreateButton("Empty Script", "Create an empty script", "rbxassetid://14978048121")

local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Float, -- Widget will be initialized in floating panel
	true, -- Widget will be initially enabled
	false, -- Don't override the previous enabled state
	200, -- Default width of the floating window
	300, -- Default height of the floating window
	150, -- Minimum width of the floating window (optional)
	150 -- Minimum height of the floating window (optional)
)

local testWidget = plugin:CreateDockWidgetPluginGuiAsync("TestWidget", widgetInfo)

local testButton = Instance.new("TextLabel")
testButton.BorderSizePixel = 0
testButton.TextSize = 20
testButton.TextColor3 = Color3.new(1, 0.2, 0.4)
testButton.AnchorPoint = Vector2.new(0.5, 0.5)
testButton.Size = UDim2.new(1, 0, 1, 0)
testButton.Position = UDim2.new(0.5, 0, 0.5, 0)
testButton.Text = "Click Me"
testButton.Parent = testWidget

testWidget.Enabled = true

local function onPluginButtonClicked()
	print("hello world")
	print(ReflectionService:GetPropertiesOfClass("DockWidgetPluginGui"))
	testWidget.Enabled = not testWidget.Enabled
end

newScriptButton.Click:Connect(onPluginButtonClicked)

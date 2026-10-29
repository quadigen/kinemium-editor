local pluginAction = plugin:CreatePluginAction(
	"HelloWorldAction",
	"Hello World",
	"Prints a 'Hello world!'",
	"rbxasset://textures/sparkle.png",
	true
)
pluginAction.Name = "Test Action"

local function actionTriggered()
	print("Hello world!")
end

pluginAction.Triggered:Connect(actionTriggered)

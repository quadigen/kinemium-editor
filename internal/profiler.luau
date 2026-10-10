local RunService = game:GetService("RunService")
local ProfilerService = game:GetService("ProfilerService")
local UI = require("@internal/editor_ui")

return function(content)
	local section1 = Instance.new("Frame")
	section1.Size = UDim2.new(0.2, 0, 1, 0)
	section1.BackgroundTransparency = 1
	section1.Parent = content

	local list = Instance.new("UIListLayout")
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.FillDirection = Enum.FillDirection.Vertical
	list.Parent = section1

	while true do
		local scripts = ProfilerService:GetScripts()

		for _, child in pairs(section1:GetChildren()) do
			child:Destroy()
		end

		for _, script in pairs(scripts) do
			UI.button(section1, script.Name, UDim2.fromOffset(12, 12), UDim2.new(1, 0, 0, 30), function()
				print("Clicked")
			end)
		end
		task.wait(3)
	end
end

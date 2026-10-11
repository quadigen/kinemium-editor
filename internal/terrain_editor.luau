local terrain = game:GetService("Terrain")
local UserInputService = game:GetService("UserInputService")
local mouse: Mouse = UserInputService:GetMouse()
local RunService = game:GetService("RunService")

local terrain_highlight = Instance.new("Part")
terrain_highlight.Size = Vector3.new(4, 4, 4)
terrain_highlight.Shape = Enum.PartType.Ball
terrain_highlight.Anchored = true
terrain_highlight.Transparency = 0.5
terrain_highlight.Color = Color3.new(0, 0.701961, 1)
terrain_highlight.Parent = workspace

RunService.RenderStepped:Connect(function(a0: number)
	if mouse.Hit then
		terrain_highlight.Position = mouse.Hit.Position
	end
end)

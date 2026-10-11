local terrain = workspace.Terrain
local UserInputService = game:GetService("UserInputService")
local mouse: Mouse = UserInputService:GetMouse()
local RunService = game:GetService("RunService")

local radius = 4

local terrain_highlight = Instance.new("Part")
terrain_highlight.Size = Vector3.new(radius, radius, radius)
terrain_highlight.Shape = Enum.PartType.Ball
terrain_highlight.Anchored = true
terrain_highlight.Transparency = 0.5
terrain_highlight.Color = Color3.new(0, 0.701961, 1)
terrain_highlight.Parent = workspace

mouse.TargetFilter = terrain_highlight

mouse.Button1Down:Connect(function()
	local center = terrain_highlight.Position
	terrain:FillBall(center, radius, Enum.Material.Grass)
end)

RunService.RenderStepped:Connect(function(a0: number)
	if mouse.Hit then
		terrain_highlight.Position = mouse.Hit.Position
	end
end)

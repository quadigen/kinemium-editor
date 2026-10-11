local terrain = game:GetService("Terrain")
local UserInputService = game:GetService("UserInputService")
local mouse: Mouse = UserInputService:GetMouse()
local RunService = game:GetService("RunService")

local UI = require("@internal/editor_ui")
local colors = UI.tokens.color
local tokens = UI.tokens

local radius = 4

local gui = Instance.new("ScreenGui")
gui.Name = "TerrainEditor"
gui.Parent = game.CoreGui

local panel, content = UI.window("Terrain", UDim2.fromOffset(40, 40), UDim2.fromOffset(400, 240), "Terrain", {
	closable = true,
})
panel.Parent = gui

local scroller = Instance.new("ScrollingFrame")
scroller.BackgroundTransparency = 1
scroller.Size = UDim2.new(1, 0, 1, 0)
scroller.Parent = content

local padding = Instance.new("UIPadding")
padding.PaddingBottom = UDim.new(0, 5)
padding.PaddingRight = UDim.new(0, 5)
padding.PaddingLeft = UDim.new(0, 5)
padding.PaddingTop = UDim.new(0, 5)
padding.Parent = scroller

local layout1 = Instance.new("UIListLayout")
layout1.FillDirection = Enum.FillDirection.Vertical
layout1.Parent = content

UI.property(content, "Name", UDim2.fromOffset(0, 0), nil, "Part", function(v)
	print("Name:", v)
end)

local terrain_highlight = Instance.new("Part")
terrain_highlight.Size = Vector3.new(radius, radius, radius)
terrain_highlight.Anchored = true
terrain_highlight.Shape = Enum.PartType.Ball
terrain_highlight.Transparency = 1
terrain_highlight.Color = Color3.new(0, 0.701961, 1)
terrain_highlight.Parent = workspace

local highlight = Instance.new("Highlight")
highlight.OutlineTransparency = 1
highlight.FillColor = Color3.new(0, 0.701961, 1)
highlight.Parent = terrain_highlight

mouse.TargetFilter = terrain_highlight

mouse.Button1Up:Connect(function()
	local center = terrain_highlight.CFrame.Position
	terrain:FillBall(center, radius - 2, Enum.Material.Grass)
end)

RunService.RenderStepped:Connect(function(a0: number)
	if mouse.Hit then
		terrain_highlight.Position = mouse.Hit.Position
	end
end)

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
gui.RenderOnTop = true
gui.Parent = game.CoreGui

local panel, content = UI.window("Terrain", UDim2.fromOffset(40, 40), UDim2.fromOffset(400, 240), "Terrain", {
	closable = true,
})
panel.Parent = gui

local scroller = Instance.new("ScrollingFrame")
scroller.BackgroundTransparency = 1
scroller.Size = UDim2.new(1, 0, 1, 0)
scroller.Parent = content

local layout1 = Instance.new("UIListLayout")
layout1.FillDirection = Enum.FillDirection.Vertical
layout1.PaddingBottom = UDim.new(0, 10)
layout1.PaddingTop = UDim.new(0, 10)
layout1.PaddingLeft = UDim.new(0, 10)
layout1.PaddingRight = UDim.new(0, 10)
layout1.Parent = content

UI.property(scroller, "Name", UDim2.fromOffset(0, 0), nil, "Part", function(v)
	print("Name:", v)
end)

local _, tint = UI.property(scroller, "Tint", UDim2.fromOffset(0, 44), nil, nil, function(color)
	print("Color picked:", color)
end, {
	custom = function(holder, ctrl, colors)
		local current = Color3.new(1, 1, 1)

		local swatch = UI.button(holder, "", UDim2.new(0, 0, 0.5, -10), UDim2.fromOffset(40, 20), function()
			current = Color3.fromHSV(math.random(), 1, 1)
			ctrl.custom.swatch.BackgroundColor3 = current
			ctrl:Fire(current) -- triggers the callback above
		end, { color = current, border = true })

		return {
			swatch = swatch,
			GetValue = function()
				return current
			end,
			SetValue = function(_, c, silent)
				current = c
				swatch.BackgroundColor3 = c
				if not silent then
					ctrl:Fire(c)
				end
			end,
		}
	end,
})

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

local terrain = game:GetService("Terrain")
local UserInputService = game:GetService("UserInputService")
local mouse: Mouse = UserInputService:GetMouse()
local RunService = game:GetService("RunService")

local CHEVRON = "builtin://global-icons/chevron-down.svg"

local UI = require("@internal/editor_ui")
local colors = UI.tokens.color
local tokens = UI.tokens

local radius = 4
local material = Enum.Material.Grass

local matMap = {
	["Plastic"] = Enum.Material.Grass,
	["Wood"] = Enum.Material.Wood,
	["Glass"] = Enum.Material.Glass,
	["Neon"] = Enum.Material.Neon,
}

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
scroller.Size = UDim2.new(1, -10, 1, 0)
scroller.Parent = content

local layout1 = Instance.new("UIListLayout")
layout1.FillDirection = Enum.FillDirection.Vertical
layout1.PaddingBottom = UDim.new(0, 10)
layout1.PaddingTop = UDim.new(0, 10)
layout1.PaddingLeft = UDim.new(0, 10)
layout1.PaddingRight = UDim.new(0, 10)
layout1.Parent = scroller

UI.property(scroller, "Name", UDim2.fromOffset(0, 0), nil, "Radius", function(v)
	radius = tonumber(v)
end)

local _, material = UI.property(scroller, "Material", UDim2.fromOffset(0, 66), nil, "Plastic", function(newValue)
	material = matMap[newValue]
end, {
	custom = function(holder, ctrl, colors)
		local innerHeight = UI.metrics.propertyRow - 2

		local dropOptions = {
			items = {
				{ value = "Plastic", label = "Plastic" },
				{ value = "Wood", label = "Wood" },
				{ value = "Glass", label = "Glass" },
				{ value = "Neon", label = "Neon" },
			},
			menuWidth = 140,
			showSearch = false,

			menuPosition = function()
				local button = ctrl.custom.button
				local p, s = button.AbsolutePosition, button.AbsoluteSize
				return UDim2.fromOffset(p.X, p.Y + s.Y + 2)
			end,

			onChanged = function(newValue)
				ctrl:Fire(newValue) -- runs the property callback
			end,
		}

		local button, label, dropdown = UI.dropdown(
			holder,
			"Plastic", -- initial value
			UDim2.new(0, 0, 0.5, -math.floor(innerHeight / 2)),
			UDim2.new(1, 0, 0, innerHeight),
			CHEVRON,
			dropOptions
		)

		local function syncWidth()
			local width = button.AbsoluteSize.X
			if width > 0 then
				dropOptions.menuWidth = width
			end
		end

		syncWidth()
		button:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncWidth)

		return {
			button = button,
			GetValue = function()
				return dropdown:GetValue()
			end,
			SetValue = function(_, newValue, silent)
				dropdown:SetValue(newValue, true) -- updates label
				if not silent then
					ctrl:Fire(newValue)
				end
			end,
			SetEnabled = function(_, enabled)
				dropdown.record.enabled = enabled
				button.Active = enabled
				label.TextColor3 = enabled and colors.subtext or colors.muted
			end,
			Destroy = function()
				dropdown:Close()
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
	terrain:FillBall(center, radius - 2, material)
end)

RunService.RenderStepped:Connect(function(a0: number)
	if mouse.Hit then
		terrain_highlight.Size = Vector3.new(radius, radius, radius)
		terrain_highlight.Position = mouse.Hit.Position
	end
end)

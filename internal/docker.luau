if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local UI = require("@internal/editor_ui")
local corner_Radius = UI.tokens.radius.sm

local overlay = Instance.new("ScreenGui")
overlay.RenderOnTop = true
overlay.Name = "DockingOverlay"
overlay.Parent = game.CoreGui

local center = Instance.new("Frame")
center.AnchorPoint = Vector2.new(0.5, 0.5)
center.BackgroundTransparency = 1
center.Position = UDim2.new(0.5, 0, 0.5, 0)
center.Size = UDim2.new(1, 0, 1, 0)
center.Parent = overlay

local center_dock = UI.frame(
	center,
	UDim2.new(0.5, 0, 0.5, 0),
	UDim2.new(0, 50, 0, 50),
	Color3.new(0.058824, 0.058824, 0.862745),
	corner_Radius
)

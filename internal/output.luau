local Preferences = require("@internal/preferences")
if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local UI = require("@internal/editor_ui")
local StudioThemeService = game:GetService("StudioThemeService")
local theme = StudioThemeService.SelectedTheme

local console = require("@internal/console")
local docker = require("@internal/docker")

local panel = console.createConsole()
local output = theme.OutputCoordinates
panel.window.AnchorPoint = Vector2.new(0, 0)
UI.applyWindowLayout(panel.window, output.Position, output.Size)
panel.window.Parent = UI.root()
panel.window:GetPropertyChangedSignal("Visible"):Connect(function()
	StudioThemeService:SetDockWindowVisible("Output", panel.window.Visible)
end)
Preferences.observe("showOutput", function(value) panel.window.Visible = value end)
panel.gui:Destroy()

renderer.Pool.new("2d", function()
	local coordinates = StudioThemeService.SelectedTheme.OutputCoordinates
	if not docker.Update(panel.window, "Output") then
		UI.applyWindowLayout(panel.window, coordinates.Position, coordinates.Size)
	end
end)

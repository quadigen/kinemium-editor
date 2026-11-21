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
panel.window.Position = output.Position
panel.window.Size = output.Size
panel.window.Parent = UI.root()
Preferences.observe("showOutput", function(value) panel.window.Visible = value end)
panel.gui:Destroy()

local lastPosition = output.Position
local lastSize = output.Size

renderer.Pool.new("2d", function()
	local coordinates = StudioThemeService.SelectedTheme.OutputCoordinates
	local dragging = docker.Update(panel.window, "Output")
	if not dragging and (coordinates.Position ~= lastPosition or coordinates.Size ~= lastSize) then
		lastPosition = coordinates.Position
		lastSize = coordinates.Size
		panel.window.AnchorPoint = Vector2.new(0, 0)
		panel.window.Position = lastPosition
		panel.window.Size = lastSize
	end
end)

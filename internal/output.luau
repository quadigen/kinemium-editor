if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local UI = require("@internal/editor_ui")
local StudioThemeService = game:GetService("StudioThemeService")
local theme = StudioThemeService.SelectedTheme
local LogService = game:GetService("LogService")
local colors = UI.colors
local tokens = UI.tokens
local console = require("@internal/console")
local docker = require("@internal/docker")

local panel = console.createConsole()
local output = theme.OutputCoordinates
panel.window.AnchorPoint = Vector2.new(0, 0)
panel.window.Position = output.Position
panel.window.Size = output.Size
panel.window.Parent = UI.root()
panel.gui:Destroy()

renderer.Pool.new("2d", function()
	local output = theme.OutputCoordinates
	local dragging = docker.Update(panel.window, "Output")

	if not dragging then
		panel.window.AnchorPoint = Vector2.new(0, 0)
		panel.window.Position = output.Position
		panel.window.Size = output.Size
	end
end)

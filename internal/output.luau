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

local panel = console.createConsole()
local output = theme.OutputCoordinates
panel.window.Position = UDim2.fromOffset(output.Position.X.Offset, output.Position.Y.Offset)
panel.window.Size = UDim2.fromOffset(output.Size.X.Offset, output.Size.Y.Offset)

renderer.Pool.new("2d", function()
	panel.window.Size = theme.OutputCoordinates.Size
	panel.window.Position = theme.OutputCoordinates.Position
end)

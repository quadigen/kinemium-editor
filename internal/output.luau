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
panel.window.Position = UDim2.fromOffset(theme.OutputCoordinates.Position.X, theme.OutputCoordinates.Position.Y)
panel.window.Size = UDim2.fromOffset(theme.OutputCoordinates.Size.X, theme.OutputCoordinates.Size.Y)

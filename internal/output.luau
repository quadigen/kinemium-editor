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
panel.window.Position = theme.OutputCoordinates.Position
panel.window.Size = theme.OutputCoordinates.Size

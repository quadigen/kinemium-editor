if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local UI = require("@internal/editor_ui")
local viewport = require("@internal/viewport")
local docker = require("@internal/docker")
local files = require("@internal/files")

local StudioThemeService = game:GetService("StudioThemeService")
local theme = StudioThemeService.SelectedTheme

local panel, content, header, windowControls =
	UI.window("Files", theme.ExplorerCoordinates.Position, theme.ExplorerCoordinates.Size, "Files", {
		tabs = { "Files" },
		selectedTab = "Files",
		closable = true,
	})

local filesPage = windowControls.pages.Files
local filesController = files(filesPage, windowControls)

panel.Position = UDim2.new(panel.Position.X.Scale, panel.Position.X.Offset, panel.Position.Y.Scale, panel.Position.Y.Offset)

renderer.Pool.new("2d", function()
	local dragging = docker.Update(panel, "Files")

	if not dragging then
		panel.Size = theme.ExplorerCoordinates.Size
		panel.Position = theme.ExplorerCoordinates.Position
	end
end)

return {
	panel = panel,
	filesController = filesController,
}
if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local UI = require("@internal/editor_ui")
local plugin_marketplace = require("@internal/marketplace")
local credits_page = require("@internal/credits")
local settings_page = require("@internal/settings")

local gui = Instance.new("ScreenGui")
gui.Name = "Home"
gui.RenderOnTop = true
gui.Parent = game.CoreGui

local size = UDim2.new(0.7, 0, 0.9, 0)
local position = UDim2.new(0.5, 0, 0.5, 0)

local MarketplaceWindow, _, _, Marketplace_windowControls = UI.window("Marketplace", position, size, "Marketplace", {
	tabs = {
		"Marketplace",
	},
	selectedTab = "Marketplace",
})
MarketplaceWindow.AnchorPoint = Vector2.new(0.5, 0.5)
MarketplaceWindow.Visible = false
MarketplaceWindow.Parent = gui

local CreditsWindow, _, _, Credits_windowControls = UI.window("Credits", position, size, "Credits", {
	tabs = {
		"Credits",
	},
	selectedTab = "Credits",
})
CreditsWindow.AnchorPoint = Vector2.new(0.5, 0.5)
CreditsWindow.Visible = false
CreditsWindow.Parent = gui

local SettingsWindow, _, _, Settings_windowControls = UI.window("Settings", position, size, "Settings", {
	tabs = {
		"Settings",
	},
	selectedTab = "Settings",
})
SettingsWindow.AnchorPoint = Vector2.new(0.5, 0.5)
SettingsWindow.Visible = false
SettingsWindow.Parent = gui

plugin_marketplace(Marketplace_windowControls.pages.Marketplace, Marketplace_windowControls, gui)
credits_page(Credits_windowControls.pages.Credits, Credits_windowControls, gui)
settings_page(Settings_windowControls.pages.Settings, Settings_windowControls, gui)

return {
	name = "Studio",
	buttons = {
		{
			name = "Settings",
			callback = function()
				MarketplaceWindow.Visible = false
				CreditsWindow.Visible = false
				SettingsWindow.Visible = true
			end,
		},
		{
			name = "Credits",
			callback = function()
				MarketplaceWindow.Visible = false
				CreditsWindow.Visible = true
				SettingsWindow.Visible = false
			end,
		},
		{
			name = "Marketplace",
			callback = function()
				MarketplaceWindow.Visible = true
				CreditsWindow.Visible = false
				SettingsWindow.Visible = false
			end,
		},
	},
}

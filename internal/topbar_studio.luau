if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local UI = require("@internal/editor_ui")
local plugin_marketplace = require("@internal/marketplace")
local credits_page = require("@internal/credits")
local settings_page = require("@internal/settings")

local gui = Instance.new("ScreenGui")
gui.Name = "Home"
gui.Parent = game.CoreGui

local MarketplaceWindow, _, _, Marketplace_windowControls =
	UI.window("Marketplace", UDim2.new(0, 15, 0, 15), UDim2.new(1, -30, 1, -30), "Marketplace", {
		tabs = {
			"Marketplace",
		},
		selectedTab = "Marketplace",
	})
MarketplaceWindow.Visible = false
MarketplaceWindow.Parent = gui

local CreditsWindow, _, _, Credits_windowControls =
	UI.window("Credits", UDim2.new(0, 15, 0, 15), UDim2.new(1, -30, 1, -30), "Credits", {
		tabs = {
			"Credits",
		},
		selectedTab = "Credits",
	})
CreditsWindow.Visible = false
CreditsWindow.Parent = gui

local SettingsWindow, _, _, Settings_windowControls =
	UI.window("Settings", UDim2.new(0, 15, 0, 15), UDim2.new(1, -30, 1, -30), "Settings", {
		tabs = {
			"Settings",
		},
		selectedTab = "Settings",
	})
SettingsWindow.Visible = false
SettingsWindow.Parent = gui

plugin_marketplace(MarketplaceWindow.pages.Marketplace, Marketplace_windowControls, gui)
credits_page(CreditsWindow.pages.Credits, Credits_windowControls, gui)
settings_page(SettingsWindow.pages.Settings, Settings_windowControls, gui)

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

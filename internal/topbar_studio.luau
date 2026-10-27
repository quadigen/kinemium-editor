if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local UI = require("@internal/editor_ui")
local plugin_marketplace = require("@internal/marketplace")
local credits_page = require("@internal/credits")
local user = require("@internal/user")

local size = UDim2.new(0, 600, 0.6, 0)
local position = UDim2.new(0.5, 0, 0.5, 0)

local MarketplaceWindow, _, _, Marketplace_windowControls = UI.window("Marketplace", position, size, "Marketplace", {
	tabs = {
		"Marketplace",
	},
	selectedTab = "Marketplace",
	closable = true,
})
MarketplaceWindow.AnchorPoint = Vector2.new(0.5, 0.5)
MarketplaceWindow.Visible = false
MarketplaceWindow.Parent = UI.widgetOverlay()

local CreditsWindow, _, _, Credits_windowControls = UI.window("Credits", position, size, "Credits", {
	tabs = {
		"Credits",
	},
	selectedTab = "Credits",
	closable = true,
})
CreditsWindow.AnchorPoint = Vector2.new(0.5, 0.5)
CreditsWindow.Visible = false
CreditsWindow.Parent = UI.widgetOverlay()

local SettingsWindow, _, _, Settings_windowControls =
	UI.window("Settings", position, UDim2.new(0.5, 0, 0.9, 0), "Settings", {
		tabs = {
			"Settings",
		},
		selectedTab = "Settings",
		closable = true,
	})
SettingsWindow.AnchorPoint = Vector2.new(0.5, 0.5)
SettingsWindow.Visible = false
SettingsWindow.Parent = UI.widgetOverlay()

plugin_marketplace(Marketplace_windowControls.pages.Marketplace, Marketplace_windowControls, gui)
credits_page(Credits_windowControls.pages.Credits, Credits_windowControls, gui)
user(Settings_windowControls.pages.Settings, false)

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

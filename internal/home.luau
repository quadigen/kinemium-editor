if (IsServer or IsClient) or IsPlaytest then
	return nil
end
local UI = require("@internal/editor_ui")
local project_manager = require("@internal/projects")
local plugin_marketplace = require("@internal/marketplace")
local credits_page = require("@internal/credits")
local user = require("@internal/user")
local Studio = game:GetService("Studio")

local gui = Instance.new("ScreenGui")
gui.Name = "Home"
gui.Parent = game.CoreGui
UI.trackRoot(gui)

local DiscordRPC = game:GetService("DiscordRPC")

DiscordRPC:SetPresence({
	Details = "Running Kinemium",
	State = _RUNTIME.version.display,
	LargeText = _RUNTIME.url,
})

local window, _, _, windowControls = UI.window("Projects", UDim2.new(0, 15, 0, 15), UDim2.new(1, -30, 1, -30), "Home", {
	tabs = {
		"Projects",
		"Marketplace",
		"Settings",
		"Credits",
	},
	selectedTab = "Projects",
})

window.Parent = gui

UI.widgetOverlay().Enabled = false
UI.root().Enabled = false
UI.RootOverlay().Enabled = false

project_manager(windowControls.pages.Projects, windowControls, gui)
plugin_marketplace(windowControls.pages.Marketplace, windowControls, gui)
credits_page(windowControls.pages.Credits, windowControls, gui)
user(windowControls.pages.Settings, false)

local CocainePipe = Studio.Pipe :: RBXScriptSignal

CocainePipe:Connect(function(signal, value)
	if signal == "WidgetOverlayVisible" then
		if type(value) == "boolean" then
			UI.widgetOverlay().Enabled = value
		end
	end

	if signal == "RootVisible" then
		if type(value) == "boolean" then
			UI.root().Enabled = value
		end
	end

	if signal == "RootOverlayVisible" then
		if type(value) == "boolean" then
			UI.RootOverlay().Enabled = value
		end
	end
end)

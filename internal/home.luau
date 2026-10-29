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

local SignalPipe = Studio.Pipe :: RBXScriptSignal
local windowIndex = {}

SignalPipe:Connect(function(signal, value)
	print(signal, value)
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

	if signal == "RootOverlayVisible" then
		if type(value) == "boolean" then
			UI.RootOverlay().Enabled = value
		end
	end

	if signal == "ChangeTheme" then
		if type(value) == "string" then
			UI.setTheme(value)
		end
	end

	if signal == "NewTheme" then
		if type(value) == "table" then
			local color = value.Color or {}
			local function c(key, fallback)
				return color[key] or fallback
			end

			UI.registerTheme(value.Name, {
				color = {
					canvas = c("Canvas", Color3.fromRGB(30, 30, 46)),
					panel = c("Panel", Color3.fromRGB(30, 30, 46)),
					panelRaised = c("PanelRaised", Color3.fromRGB(49, 50, 68)),
					surface = c("Surface", Color3.fromRGB(69, 71, 90)),
					surfaceAlt = c("SurfaceAlt", Color3.fromRGB(49, 50, 68)),
					rowEven = c("RowEven", Color3.fromRGB(24, 24, 37)),
					rowOdd = c("RowOdd", Color3.fromRGB(35, 35, 52)),
					hover = c("Hover", Color3.fromRGB(49, 50, 68)),
					pressed = c("Pressed", Color3.fromRGB(69, 71, 90)),
					input = c("Input", Color3.fromRGB(24, 24, 37)),
					border = c("Border", Color3.fromRGB(88, 91, 112)),
					borderStrong = c("BorderStrong", Color3.fromRGB(203, 166, 247)),
					text = c("Text", Color3.fromRGB(205, 214, 244)),
					subtext = c("Subtext", Color3.fromRGB(186, 194, 222)),
					muted = c("Muted", Color3.fromRGB(127, 132, 156)),
					accent = c("Accent", Color3.fromRGB(203, 166, 247)),
					accentSoft = c("AccentSoft", Color3.fromRGB(69, 61, 91)),
					selection = c("Selection", Color3.fromRGB(88, 91, 112)),
					selectionHover = c("SelectionHover", Color3.fromRGB(108, 112, 134)),
					focus = c("Focus", Color3.fromRGB(180, 190, 254)),
					warning = c("Warning", Color3.fromRGB(249, 226, 175)),
					error = c("Error", Color3.fromRGB(243, 139, 168)),
					success = c("Success", Color3.fromRGB(166, 227, 161)),
				},
			})
		end
	end

	if signal == "NewWindow" then
		if type(value) == "table" then
			local content = value.Content
			local windowName = value.Name
			local tabs = value.Tabs
			local id = value.Id
			local selectedTab = value.selectedTab
			local size = value.Size
			local position = value.Position

			local window, _, _, windowControls = UI.window(windowName, size, position, windowName, {
				tabs = tabs,
				selectedTab = selectedTab,
			})
			window.Parent = UI.widgetOverlay()

			windowIndex[id] = window

			if content then
				content.Parent = windowControls.pages[selectedTab]
			end
		end
	end
end)

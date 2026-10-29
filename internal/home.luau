if (IsServer or IsClient) or IsPlaytest then
	return nil
end
local UI = require("@internal/editor_ui")
local project_manager = require("@internal/projects")
local plugin_marketplace = require("@internal/marketplace")
local credits_page = require("@internal/credits")
local user = require("@internal/user")
local Studio = game:GetService("Studio")
local pluginService = game:GetService("Plugin")
local UserInputService = game:GetService("UserInputService")
local topbar = require("@internal/topbar")
local explorer = require("@internal/explorer")
local console = require("@internal/console")
local exporter = require("@internal/exporter")
local terrain_editor = require("@internal/terrain_editor")
local google_fonts_lib = require("@internal/google_fonts_lib")
local icon_lib = require("@internal/icon_lib")
local viewport = require("@internal/viewport")
local image_viewer = require("@internal/image_viewer")
local auth = require("@internal/auth")
local picker = require("@internal/picker")
local docker = require("@internal/docker")

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
local pluginActions = {}
local pluginDockWindows = {}
local pluginMenu = nil

local function pluginIcon(icon)
	if type(icon) ~= "string" or icon == "" then
		return "Script.svg"
	end

	if string.find(icon, "://", 1, true) then
		return "Script.svg"
	end

	return icon
end

local function pluginButtonName(category, text, fallback)
	local base = type(text) == "string" and text ~= "" and text or fallback or "Plugin Action"
	local name = base

	for index = 2, 64 do
		local existing = topbar.GetButton(category, name)

		if not existing then
			return name
		end

		name = base .. " (" .. index .. ")"
	end

	return base
end

local function buildPluginMenuItems(items)
	local result = {}

	for _, item in ipairs(type(items) == "table" and items or {}) do
		if item.Separator then
			table.insert(result, { separator = true })
		elseif type(item.Children) == "table" then
			table.insert(result, {
				label = item.Label or "Submenu",
				icon = type(item.Icon) == "string" and item.Icon ~= "" and pluginIcon(item.Icon) or nil,
				submenu = buildPluginMenuItems(item.Children),
			})
		else
			local actionId = item.ActionId

			table.insert(result, {
				label = item.Label or "Action",
				icon = type(item.Icon) == "string" and item.Icon ~= "" and pluginIcon(item.Icon) or nil,
				enabled = item.Enabled ~= false,
				callback = function()
					pcall(function()
						pluginService:__PluginActionClicked(actionId)
					end)
				end,
			})
		end
	end

	return result
end

local pipeModules = {
	UI = UI,
	topbar = topbar,
	explorer = explorer,
	files = explorer and explorer.filesController or nil,
	console = console,
	exporter = exporter,
	terrain = terrain_editor,
	google_fonts = google_fonts_lib,
	icons = icon_lib,
	viewport = viewport,
	image_viewer = image_viewer,
	auth = auth,
	picker = picker,
	docker = docker,
}

local function callModule(name, method, ...)
	local api = pipeModules[name]

	if type(api) ~= "table" or type(api[method]) ~= "function" then
		warn("[home] pipe call failed: " .. tostring(name) .. "." .. tostring(method) .. " is unavailable")
		return false
	end

	local ok, result = pcall(api[method], ...)

	if not ok then
		warn("[home] pipe call failed: " .. tostring(name) .. "." .. tostring(method) .. ": " .. tostring(result))
		return false
	end

	return true, result
end

local function callModuleWithArgs(name, method, args)
	if type(args) == "table" then
		return callModule(name, method, table.unpack(args))
	end

	return callModule(name, method)
end

SignalPipe:Connect(function(signal, value)
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

	if signal == "NewCategory" then
		if type(value) == "table" and type(value.Name) == "string" and type(value.Buttons) == "table" then
			topbar.AddCategory(value.Name, value.Buttons)
		end
	end

	if signal == "RemoveCategory" then
		local categoryName = type(value) == "string" and value or type(value) == "table" and value.Name

		if type(categoryName) == "string" then
			topbar.RemoveCategory(categoryName)
		end
	end

	if signal == "NewTopbarButton" then
		if type(value) == "table" and type(value.Category) == "string" and type(value.Button) == "table" then
			topbar.AddButton(value.Category, value.Button, value.Index)
		end
	end

	if signal == "RemoveTopbarButton" then
		if type(value) == "table" and type(value.Category) == "string" and type(value.Name) == "string" then
			topbar.RemoveButton(value.Category, value.Name)
		end
	end

	if signal == "UpdateTopbarButton" then
		if
			type(value) == "table"
			and type(value.Category) == "string"
			and type(value.Name) == "string"
			and type(value.Properties) == "table"
		then
			topbar.UpdateButton(value.Category, value.Name, value.Properties)
		end
	end

	if signal == "MoveTopbarButton" then
		if
			type(value) == "table"
			and type(value.Category) == "string"
			and type(value.Name) == "string"
			and type(value.Index) == "number"
		then
			topbar.MoveButton(value.Category, value.Name, value.Index)
		end
	end

	if signal == "AddTopbarSeparator" then
		if type(value) == "table" and type(value.Category) == "string" then
			topbar.AddSeparator(value.Category, value.Index)
		end
	end

	if signal == "SelectTopbarCategory" then
		if type(value) == "string" then
			topbar.SelectCategory(value)
		end
	end

	if signal == "SetTopbarExpanded" then
		if type(value) == "boolean" then
			topbar.SetExpanded(value)
		end
	end

	if signal == "ToggleTopbarExpanded" then
		topbar.ToggleExpanded()
	end

	if signal == "RefreshTopbar" then
		topbar.Refresh()
	end

	if signal == "ToggleWindow" then
		if type(value) == "string" then
			UI.toggleWindow(value)
		elseif type(value) == "table" and type(value.Name) == "string" then
			UI.toggleWindow(value.Name)
		end
	end

	if signal == "SetWindowVisible" then
		if type(value) == "table" and type(value.Name) == "string" and type(value.Visible) == "boolean" then
			local target = UI.getWindow(value.Name)

			if target then
				target.Visible = value.Visible
			end
		end
	end

	if signal == "Toast" then
		if type(value) == "table" then
			UI.toast(value.name or value.title or "engine", value)
		elseif type(value) == "string" then
			UI.toast(value)
		end
	end

	if signal == "SetReduceMotion" then
		if type(value) == "boolean" then
			UI.setReduceMotion(value)
		end
	end

	if signal == "OpenScript" then
		if type(value) == "table" and value.Script ~= nil then
			callModule("viewport", "OpenScript", value.Script, value.Line)
		else
			callModule("viewport", "OpenScript", value)
		end
	end

	if signal == "CloseScript" then
		callModule("viewport", "CloseScript", value)
	end

	if signal == "CloseAllScripts" then
		callModule("viewport", "CloseAllScripts")
	end

	if signal == "OpenFile" then
		if type(value) == "table" and type(value.Path) == "string" then
			callModule("viewport", "OpenFile", value.Path, value.Name)
		elseif type(value) == "string" then
			callModule("viewport", "OpenFile", value)
		end
	end

	if signal == "CloseFile" then
		if type(value) == "string" then
			callModule("viewport", "CloseFile", value)
		elseif type(value) == "table" and type(value.Path) == "string" then
			callModule("viewport", "CloseFile", value.Path)
		end
	end

	if signal == "ActivateTool" then
		if type(value) == "string" then
			callModule("viewport", "ActivateTool", value)
		elseif type(value) == "table" and type(value.Tool) == "string" then
			callModule("viewport", "ActivateTool", value.Tool)
		end
	end

	if signal == "SetSnap" then
		if type(value) == "table" and type(value.Tool) == "string" and type(value.Value) == "number" then
			callModule("viewport", "SetSnap", value.Tool, value.Value)
		end
	end

	if signal == "SetDropHighlight" then
		if type(value) == "boolean" then
			callModule("viewport", "SetDropHighlight", value)
		end
	end

	if signal == "RefreshFiles" then
		callModule("files", "Refresh")
	end

	if signal == "RegisterFileType" then
		if type(value) == "table" then
			callModule("files", "RegisterFileType", value)
		end
	end

	if signal == "ToggleExplorer" then
		UI.toggleWindow("Explorer")
	end

	if signal == "ToggleInspector" then
		UI.toggleWindow("Inspector")
	end

	if signal == "ToggleOutput" or signal == "ToggleConsole" then
		UI.toggleWindow("Console")
	end

	if signal == "ShowExporter" then
		callModule("exporter", "Enable")
	end

	if signal == "HideExporter" then
		callModule("exporter", "Disable")
	end

	if signal == "ToggleExporter" then
		callModule("exporter", "Toggle")
	end

	if signal == "ShowTerrainEditor" then
		callModule("terrain", "Enable")
	end

	if signal == "HideTerrainEditor" then
		callModule("terrain", "Disable")
	end

	if signal == "ToggleTerrainEditor" then
		callModule("terrain", "Toggle")
	end

	if signal == "ShowFontPicker" then
		callModule("google_fonts", "Enable")
	end

	if signal == "HideFontPicker" then
		callModule("google_fonts", "Disable")
	end

	if signal == "ToggleFontPicker" then
		callModule("google_fonts", "Toggle")
	end

	if signal == "ShowIconPicker" then
		callModule("icons", "Enable")
	end

	if signal == "HideIconPicker" then
		callModule("icons", "Disable")
	end

	if signal == "ToggleIconPicker" then
		callModule("icons", "Toggle")
	end

	if signal == "ShowImage" then
		if type(value) == "table" and type(value.Path) == "string" then
			callModule("image_viewer", "Open", value)
		end
	end

	if signal == "Login" then
		callModule("auth", "Login", type(value) == "table" and value or {})
	end

	if signal == "SignUp" then
		callModule("auth", "SignUp", type(value) == "table" and value or {})
	end

	if signal == "ModuleCall" or signal == "ModuleRequest" then
		if type(value) == "table" and type(value.Module) == "string" and type(value.Method) == "string" then
			local ok = callModuleWithArgs(value.Module, value.Method, value.Args)

			if not ok and value.Method == "Refresh" then
				UI.refreshComponent(value.Module)
			end
		end
	end

	if signal == "SetComponentProps" or signal == "RefreshComponent" then
		local component = type(value) == "table" and value.Component or value
		local props = type(value) == "table" and value.Props or nil

		if type(component) == "string" then
			local base, scope = string.match(component, "^([%w_]+):(.+)$")

			if base then
				component = base .. ":" .. string.lower(scope)
			end

			if signal == "SetComponentProps" then
				if type(props) == "table" then
					UI.setComponentProps(component, props)
				end
			else
				UI.refreshComponent(component, props)
			end
		end
	end

	if signal == "RefreshComponents" then
		UI.refreshComponents()
	end

	if signal == "RefreshModule" then
		local moduleName = type(value) == "table" and value.Module or value

		if type(moduleName) == "string" then
			local ok = callModule(moduleName, "Refresh")

			if not ok then
				UI.refreshComponent(moduleName)
			end
		end
	end

	if signal == "PluginToolbarButtonAdded" then
		if type(value) == "table" and type(value.Id) == "number" then
			local category = "Plugins"

			if not topbar.HasCategory(category) then
				topbar.AddCategory(category, {})
			end

			local name = pluginButtonName(category, value.Text, "Plugin Action")
			local section = type(value.Toolbar) == "string" and value.Toolbar ~= "" and value.Toolbar or category

			local added = topbar.AddButton(category, {
				name = name,
				section = section,
				width = math.max(52, #name * 6 + 12),
				icon = pluginIcon(value.Icon),
				enabled = value.Enabled ~= false,
				selected = value.Active == true,
				route = nil,
				callback = function()
					pcall(function()
						pluginService:__PluginActionClicked(value.Id)
					end)
				end,
			})

			if added then
				pluginActions[value.Id] = {
					category = category,
					name = name,
				}
			end
		end
	end

	if signal == "PluginToolbarButtonUpdated" then
		if type(value) == "table" and type(value.Id) == "number" then
			local entry = pluginActions[value.Id]

			if entry then
				local nextName = entry.name

				if type(value.Text) == "string" and value.Text ~= "" then
					nextName = value.Text
				end

				if nextName ~= entry.name then
					nextName = pluginButtonName(entry.category, nextName, entry.name)
				end

				local props = {
					name = nextName,
					width = math.max(52, #nextName * 6 + 12),
					enabled = value.Enabled ~= false,
					selected = value.Active == true,
				}

				if type(value.Toolbar) == "string" and value.Toolbar ~= "" then
					props.section = value.Toolbar
				end

				if type(value.Icon) == "string" and value.Icon ~= "" then
					props.icon = pluginIcon(value.Icon)
				end

				topbar.UpdateButton(entry.category, entry.name, props)

				entry.name = nextName
			end
		end
	end

	if signal == "PluginToolbarButtonRemoved" then
		if type(value) == "table" and type(value.Id) == "number" then
			local entry = pluginActions[value.Id]

			if entry then
				topbar.RemoveButton(entry.category, entry.name)
				pluginActions[value.Id] = nil
			end
		end
	end

	if signal == "PluginMenuShow" then
		if type(value) == "table" and type(value.Items) == "table" then
			if pluginMenu then
				pluginMenu:Destroy()
				pluginMenu = nil
			end

			pluginMenu = UI.contextMenu(UI.contextMenuOverlay(), "", nil, nil, nil, {
				items = buildPluginMenuItems(value.Items),
				menuWidth = 200,
				closeOnOutsideClick = true,
			})

			pluginMenu:Open()
		end
	end

	if signal == "PluginDockWidgetCreated" then
		if type(value) == "table" and type(value.Id) == "number" and value.Object then
			local existing = pluginDockWindows[value.Id]

			if existing then
				existing:Destroy()
				pluginDockWindows[value.Id] = nil
			end

			local windowName = "PluginDock" .. tostring(value.Id)
			local width = tonumber(value.Width)
			local height = tonumber(value.Height)

			if not width or width <= 0 then
				width = 420
			end

			if not height or height <= 0 then
				height = 320
			end

			local window, _, _, windowControls = UI.window(
				windowName,
				UDim2.fromOffset(120, 140),
				UDim2.fromOffset(width, height),
				type(value.Title) == "string" and value.Title or "Plugin",
				{
					tabs = { "Content" },
					selectedTab = "Content",
					closable = true,
					onClose = function(panel)
						pcall(function()
							pluginService:__PluginDockWidgetClosed(value.Id)
						end)

						panel.Visible = false
					end,
				}
			)

			window.Parent = UI.widgetOverlay()
			window.Visible = value.Visible ~= false

			local page = windowControls and windowControls.pages and windowControls.pages.Content

			if page then
				value.Object.Parent = page
				value.Object.Position = UDim2.new()
				value.Object.Size = UDim2.new(1, 0, 1, 0)
			end

			pluginDockWindows[value.Id] = window
		end
	end

	if signal == "PluginDockWidgetClosed" then
		if type(value) == "table" and type(value.Id) == "number" then
			local window = pluginDockWindows[value.Id]

			if window then
				window.Visible = false
			end
		end
	end

	if signal == "PluginDockWidgetVisible" then
		if type(value) == "table" and type(value.Id) == "number" then
			local window = pluginDockWindows[value.Id]

			if window then
				window.Visible = value.Visible ~= false
			end
		end
	end

	if signal == "PluginDockWidgetTitle" then
		if type(value) == "table" and type(value.Id) == "number" and type(value.Title) == "string" then
			UI.setWindowProps("PluginDock" .. tostring(value.Id), {
				title = value.Title,
			})
		end
	end
end)

-- Plugin scripts may run before the editor connects to the pipe. Replay the
-- buttons that already exist so early toolbars still appear.
pcall(function()
	pluginService:__SyncPluginToolbars()
end)

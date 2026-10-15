local UI = require("@internal/editor_ui")
local viewport = require("@internal/viewport")

local Project = game:GetService("Project")
local dialog = game:GetService("DialogService")
local export_service = game:GetService("ExportService")
local filesystem = game:GetService("Filesystem")
local util = require("@internal/util")

local StudioThemeService = game:GetService("StudioThemeService")
local Selection = game:GetService("Selection")
local theme = StudioThemeService.SelectedTheme

local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local colors = UI.colors
local tokens = UI.tokens

local gui = UI.widgetOverlay()

local panel, content, _, windowControls =
	UI.window("Export Game", UDim2.new(0.5, 0, 0.5, 0), UDim2.new(0.4, 0, 0.5, 0), "Export Game", {})
panel.Parent = gui

local listLayout = Instance.new("UIListLayout")
listLayout.FillDirection = Enum.FillDirection.Horizontal
listLayout.Parent = content

local targetsScroll = Instance.new("ScrollingFrame")
targetsScroll.Size = UDim2.new(0.5, 0, 1, 0)
targetsScroll.BackgroundTransparency = 1
targetsScroll.Parent = content

local targetsLayout = Instance.new("UIListLayout")
targetsLayout.FillDirection = Enum.FillDirection.Vertical
targetsLayout.Padding = UDim.new(0, 5)
targetsLayout.PaddingTop = UDim.new(0, 10)
targetsLayout.PaddingLeft = UDim.new(0, 10)
targetsLayout.Parent = targetsScroll

local pages = {
	{
		Name = "Windows",
		Icon = "builtin://global-icons/windows.png",
		OpenCallback = function() end,
		CloseCallback = function() end,
	},

	{
		Name = "Linux",
		Icon = "builtin://global-icons/linux.png",
		OpenCallback = function() end,
		CloseCallback = function() end,
	},

	{
		Name = "MacOS",
		Icon = "builtin://global-icons/apple.png",
		OpenCallback = function() end,
		CloseCallback = function() end,
	},

	{
		Name = "Android",
		Icon = "builtin://global-icons/android.png",
		OpenCallback = function() end,
		CloseCallback = function() end,
	},

	{
		Name = "Emscripten",
		Icon = "builtin://global-icons/emscripten.png",
		OpenCallback = function() end,
		CloseCallback = function() end,
	},
}

for _, entry in pairs(pages) do
	UI.button(
		targetsScroll,
		entry.Name,
		UDim2.new(0, 0, 0, 0),
		UDim2.new(1, 0, 0, 30),
		function() end,
		{ icon = entry.Icon }
	)
end

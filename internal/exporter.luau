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

local panel, _, _, windowControls =
	UI.window("Export Game", UDim2.new(0.5, 0, 0.5, 0), UDim2.new(0.4, 0, 0.5, 0), "Export Game", {})
panel.Parent = gui

local listLayout = Instance.new("UIListLayout")
listLayout.FillDirection = Enum.FillDirection.Horizontal
listLayout.Parent = panel

local targetsScroll = Instance.new("ScrollingFrame")
targetsScroll.Size = UDim2.new(0.5, 0, 1, 0)
targetsScroll.BackgroundTransparency = 1
targetsScroll.Parent = panel

local targetsLayout = Instance.new("UIListLayout")
targetsLayout.FillDirection = Enum.FillDirection.Vertical
targetsLayout.Padding = UDim.new(0, 5)
targetsLayout.Parent = targetsScroll

UI.iconButton(
	targetsScroll,
	"builtin://global-icons/windows.png",
	UDim2.new(0, 0, 0, 0),
	UDim2.new(1, 0, 0, 30),
	function() end,
	{}
)

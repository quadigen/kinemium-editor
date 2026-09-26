if not IsPlaytest then
	return
end

local UI = require("@internal/editor_ui")
local StudioThemeService = game:GetService("StudioThemeService")
local theme = StudioThemeService.SelectedTheme
local LogService = game:GetService("LogService")
local colors = UI.colors
local tokens = UI.tokens

local profiler_gui = Instance.new("ScreenGui")
profiler_gui.Parent = game.CoreGui

local list = Instance.new("Frame")
list.AnchorPoint = Vector2.new(1, 0)
list.Position = UDim2.new(1, 0, 0, 0)
list.Size = UDim2.new(0, 300, 0, 400)
list.BackgroundTransparency = 0.3
list.BackgroundColor3 = Color3.new(0, 0, 0)
list.Parent = profiler_gui

local backdrop = Instance.new("UIBackdrop")
backdrop.Parent = list

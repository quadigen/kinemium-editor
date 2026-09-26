if not IsPlaytest then
	return
end

local UI = require("@internal/editor_ui")
local StudioThemeService = game:GetService("StudioThemeService")
local theme = StudioThemeService.SelectedTheme
local LogService = game:GetService("LogService")
local RunService = game:GetService("RunService")
local ProfilerService = game:GetService("ProfilerService")
local colors = UI.colors
local tokens = UI.tokens

local profiler_gui = Instance.new("ScreenGui")
profiler_gui.Parent = game:GetService("StarterGui")

local list = Instance.new("Frame")
list.AnchorPoint = Vector2.new(1, 0)
list.Position = UDim2.new(1, 0, 0, 0)
list.Size = UDim2.new(0.3, 0, 0.4, 0)
list.BackgroundTransparency = 0.3
list.BackgroundColor3 = Color3.new(0, 0, 0)
list.Parent = profiler_gui

local backdrop = Instance.new("UIBackdrop")
backdrop.Parent = list

local layout = Instance.new("UIListLayout")
layout.Parent = list

local counters = {}

local function create_counter(name, value)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 30)
	label.Text = name
	label.Parent = list

	table.insert(counters, { label = label, name = name, cb = value })
end

create_counter("FPS", function()
	return ProfilerService.FPS
end)

RunService.Heartbeat:Connect(function(a0: number)
	for _, label in pairs(counters) do
		local val = label.cb()
		if val then
			label.label.Text = `{label.name}: {tostring(val)}`
		end
	end
end)

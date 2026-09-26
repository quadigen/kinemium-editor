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

create_counter("Frame Time", function()
	return ProfilerService.FrameTime
end)

create_counter("FPS", function()
	return string.format("%.1f", ProfilerService.FPS)
end)

create_counter("Frame Count", function()
	return ProfilerService.FrameCount
end)

create_counter("Profiler", function()
	return ProfilerService.Enabled and "Enabled" or "Disabled"
end)

create_counter("Paused", function()
	return ProfilerService.Paused and "Yes" or "No"
end)

create_counter("Avg Frame Time", function()
	local stats = ProfilerService:GetFrameStats()
	local history = stats.history

	if not history or #history == 0 then
		return "--"
	end

	local total = 0
	local count = 0

	for _, ms in ipairs(history) do
		if ms > 0 then
			total += ms
			count += 1
		end
	end

	if count == 0 then
		return "--"
	end

	return string.format("%.3f ms", total / count)
end)

create_counter("Min Frame Time", function()
	local stats = ProfilerService:GetFrameStats()
	local history = stats.history

	local min = math.huge

	for _, ms in ipairs(history) do
		if ms > 0 and ms < min then
			min = ms
		end
	end

	if min == math.huge then
		return "--"
	end

	return string.format("%.3f ms", min)
end)

create_counter("Max Frame Time", function()
	local stats = ProfilerService:GetFrameStats()
	local history = stats.history

	local max = 0

	for _, ms in ipairs(history) do
		if ms > max then
			max = ms
		end
	end

	if max == 0 then
		return "--"
	end

	return string.format("%.3f ms", max)
end)

create_counter("Zones", function()
	local stats = ProfilerService:GetFrameStats()
	return stats.zones and #stats.zones or 0
end)

RunService.Heartbeat:Connect(function(a0: number)
	for _, label in pairs(counters) do
		local val = label.cb()
		if val then
			if label.label == nil then
				continue
			end
			pcall(function(...)
				label.label.Text = `{label.name}: {tostring(val)}`
			end)
		end
	end
end)

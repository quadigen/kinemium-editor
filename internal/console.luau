-- @internal/editor_ui
local UI = require("@internal/editor_ui")

local gui = Instance.new("ScreenGui")
gui.Name = "KinemiumConsole"
gui.Parent = game.CoreGui

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0.5, 0, 0.4, 0)
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.Position = UDim2.new(0.5, 0, 0.5, 0)
frame.BackgroundColor3 = Color3.new(0, 0, 0)
frame.BorderSizePixel = 0
frame.BackgroundTransparency = 0.5
frame.Parent = gui

local corner = Instance.new("UICorner")
corner.Parent = frame

local backdrop = Instance.new("UIBackdrop")
backdrop.Parent = frame

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, 0, 1, -30) -- leave space for textbox search
scroll.AnchorPoint = Vector2.new(0.5, 1)
scroll.Position = UDim2.new(0.5, 0, 1, 0)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 6
scroll.Parent = frame

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 2)
layout.Parent = scroll

local textbox = Instance.new("TextBox")
textbox.Size = UDim2.new(1, 0, 0, 30)
textbox.AnchorPoint = Vector2.new(0.5, 0)
textbox.Position = UDim2.new(0.5, 0, 0, 0)
textbox.BackgroundColor3 = Color3.new(0, 0, 0)
textbox.BorderSizePixel = 0
textbox.BackgroundTransparency = 0.5
textbox.PlaceholderText = "Search..."
textbox.Text = ""
textbox.TextColor3 = Color3.new(1, 1, 1)
textbox.TextSize = 18
textbox.ClearTextOnFocus = false
textbox.Parent = frame

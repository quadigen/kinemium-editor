local UI = require("@internal/editor_ui")

local LogService = game:GetService("LogService")
local UserInputService = game:GetService("UserInputService")

local colors = UI.tokens.color

local MAX_ENTRIES = 1000
local ROW_HEIGHT = 16
local TOOLBAR_HEIGHT = 30
local TOGGLE_KEY = Enum.KeyCode.F9

local TYPE_INFO = {
	[Enum.MessageType.MessageOutput] = { key = "Output", color = colors.text },
	[Enum.MessageType.MessageInfo] = { key = "Info", color = Color3.fromRGB(110, 170, 255) },
	[Enum.MessageType.MessageWarning] = { key = "Warn", color = colors.warning },
	[Enum.MessageType.MessageError] = { key = "Error", color = colors.error },
}

local filters = { Output = true, Info = true, Warn = true, Error = true }
local searchQuery = ""

local entries = {} -- { message, kind, color, time }

local gui = Instance.new("ScreenGui")
gui.Name = "KinemiumConsole"
gui.DisplayOrder = 5000
gui.RenderOnTop = true
gui.Parent = game.CoreGui

local frame = Instance.new("Frame")
frame.Name = "Console"
frame.Size = UDim2.new(0.5, 0, 0.4, 0)
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.Position = UDim2.new(0.5, 0, 0.5, 0)
frame.BackgroundColor3 = Color3.new(0, 0, 0)
frame.BorderSizePixel = 0
frame.BackgroundTransparency = 0.5
frame.ClipsDescendants = true
frame.Parent = gui

local corner = Instance.new("UICorner")
corner.Parent = frame

local backdrop = Instance.new("UIBackdrop")
backdrop.Parent = frame

UI.stroke(frame, colors.borderStrong, 1, 0.5)

local scroll = Instance.new("ScrollingFrame")
scroll.Name = "Log"
scroll.Size = UDim2.new(1, 0, 1, -TOOLBAR_HEIGHT)
scroll.AnchorPoint = Vector2.new(0.5, 1)
scroll.Position = UDim2.new(0.5, 0, 1, 0)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 6
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.ClipsDescendants = true
scroll.Parent = frame

local BUTTON_WIDTH, BUTTON_GAP, RIGHT_PAD = 52, 4, 6
local buttonNames = { "Output", "Info", "Warn", "Error" }
local buttonsWidth = (#buttonNames + 1) * BUTTON_WIDTH + #buttonNames * BUTTON_GAP + RIGHT_PAD

local search = UI.input(
	frame,
	"Search...",
	UDim2.fromOffset(4, 3),
	UDim2.new(1, -(buttonsWidth + 8), 0, TOOLBAR_HEIGHT - 6),
	{ color = Color3.new(0, 0, 0), textSize = 14 }
)
search.BackgroundTransparency = 0.5
search.ClearTextOnFocus = false

local filterRecords = {}

local function rebuild() end -- assigned below

for index, name in ipairs(buttonNames) do
	local x = RIGHT_PAD + (#buttonNames + 1 - index) * (BUTTON_WIDTH + BUTTON_GAP) - BUTTON_GAP
	local record
	local _, _, rec = UI.button(
		frame,
		name,
		UDim2.new(1, -(x + BUTTON_WIDTH - BUTTON_GAP + 0), 0, 3),
		UDim2.fromOffset(BUTTON_WIDTH, TOOLBAR_HEIGHT - 6),
		function()
			filters[name] = not filters[name]
			UI.setButtonState(record, filters[name] and "selected" or nil)
			rebuild()
		end,
		{ textSize = 12, paddingX = 4 }
	)
	record = rec
	filterRecords[name] = rec
	UI.setButtonState(rec, "selected")
end

UI.button(
	frame,
	"Clear",
	UDim2.new(1, -(RIGHT_PAD + BUTTON_WIDTH), 0, 3),
	UDim2.fromOffset(BUTTON_WIDTH, TOOLBAR_HEIGHT - 6),
	function()
		table.clear(entries)
		rebuild()
	end,
	{ textSize = 12, paddingX = 4 }
)

local rowCount = 0

local function passes(entry)
	if not filters[entry.kind] then
		return false
	end

	if searchQuery ~= "" and not string.find(string.lower(entry.message), searchQuery, 1, true) then
		return false
	end

	return true
end

local function isNearBottom()
	local canvasHeight = scroll.CanvasSize.Y.Offset
	return scroll.CanvasPosition.Y + scroll.AbsoluteSize.Y >= canvasHeight - ROW_HEIGHT * 2
end

local function scrollToBottom()
	local canvasHeight = scroll.CanvasSize.Y.Offset
	scroll.CanvasPosition = Vector2.new(0, math.max(0, canvasHeight - scroll.AbsoluteSize.Y))
end

local function addRow(entry)
	local label = Instance.new("TextLabel")
	label.Name = "Row"
	label.Position = UDim2.fromOffset(6, rowCount * ROW_HEIGHT)
	label.Size = UDim2.new(1, -18, 0, ROW_HEIGHT)
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Text = string.format("[%s] %s", entry.time, entry.message)
	label.TextColor3 = entry.color
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = false
	label.Parent = scroll

	rowCount += 1
	scroll.CanvasSize = UDim2.new(0, 0, 0, rowCount * ROW_HEIGHT)
end

rebuild = function()
	UI.clear(scroll)
	rowCount = 0

	for _, entry in ipairs(entries) do
		if passes(entry) then
			addRow(entry)
		end
	end

	scrollToBottom()
end

local function pushEntry(message, messageType, timestamp)
	local info = TYPE_INFO[messageType] or TYPE_INFO[Enum.MessageType.MessageOutput]

	local entry = {
		message = tostring(message),
		kind = info.key,
		color = info.color,
		time = os.date("%H:%M:%S", type(timestamp) == "number" and timestamp or os.time()),
	}

	table.insert(entries, entry)

	-- Over the cap: drop the oldest and redraw once.
	if #entries > MAX_ENTRIES then
		table.remove(entries, 1)
		rebuild()
		return
	end

	if passes(entry) then
		local stick = isNearBottom()
		addRow(entry)

		if stick then
			scrollToBottom()
		end
	end
end

search:GetPropertyChangedSignal("Text"):Connect(function()
	searchQuery = string.lower(search.Text)
	rebuild()
end)

-- Backfill anything logged before the console was created.
for _, item in ipairs(LogService:GetLogHistory()) do
	pushEntry(item.message, item.messageType, item.timestamp)
end

LogService.MessageOut:Connect(function(message, messageType)
	pushEntry(message, messageType)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or UserInputService:GetFocusedTextBox() then
		return
	end

	if input.KeyCode == TOGGLE_KEY then
		gui.Enabled = not gui.Enabled
	end
end)

rebuild()

return {
	gui = gui,
	frame = frame,
	clear = function()
		table.clear(entries)
		rebuild()
	end,
	toggle = function()
		gui.Enabled = not gui.Enabled
	end,
}

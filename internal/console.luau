local UI = require("@internal/editor_ui")

local LogService = game:GetService("LogService")
local RunService = game:GetService("RunService")

local colors = UI.tokens.color

local WINDOW_NAME = "Console"
local MAX_ENTRIES = 1000 -- matches LOG_HISTORY_LIMIT in LogService
local ROW_HEIGHT = 16
local TOOLBAR_HEIGHT = 30
local POLL_INTERVAL = 0.1

local KIND_COLORS = {
	Log = colors.text,
	Info = Color3.fromRGB(110, 170, 255),
	Warn = colors.warning,
	Error = colors.error,
}

local filters = { Log = true, Info = true, Warn = true, Error = true }
local filterOrder = { "Log", "Info", "Warn", "Error" }

local searchQuery = ""
local entries = {} -- { message, kind, color, time }
local lastSeenCount = 0

local panel, content = UI.window(WINDOW_NAME, UDim2.fromOffset(40, 80), UDim2.fromOffset(720, 360), "Console", {
	closable = true,
})

local BUTTON_WIDTH, BUTTON_GAP, PAD = 52, 4, 6
local buttonCount = #filterOrder + 1 -- filters + Clear
local buttonsWidth = buttonCount * BUTTON_WIDTH + (buttonCount - 1) * BUTTON_GAP

local search = UI.input(
	content,
	"Search...",
	UDim2.fromOffset(PAD, 4),
	UDim2.new(1, -(buttonsWidth + PAD * 3), 0, UI.metrics.inputHeight),
	{ textSize = UI.tokens.type.small }
)

local rebuild -- forward declaration

local function buttonX(index) -- index 1 = leftmost of the right-aligned group
	local fromRight = buttonCount - index
	return UDim2.new(1, -(PAD + BUTTON_WIDTH + fromRight * (BUTTON_WIDTH + BUTTON_GAP)), 0, 4)
end

for index, kind in ipairs(filterOrder) do
	local record
	local _, _, created = UI.button(
		content,
		kind,
		buttonX(index),
		UDim2.fromOffset(BUTTON_WIDTH, UI.metrics.buttonHeight),
		function()
			filters[kind] = not filters[kind]
			UI.setButtonState(record, filters[kind] and "selected" or nil)
			rebuild()
		end,
		{ paddingX = 4 }
	)

	record = created
	UI.setButtonState(record, "selected")
end

UI.button(content, "Clear", buttonX(buttonCount), UDim2.fromOffset(BUTTON_WIDTH, UI.metrics.buttonHeight), function()
	table.clear(entries)
	lastSeenCount = LogService.MessageCount
	rebuild()
end, { paddingX = 4 })

local scroll = UI.create("ScrollingFrame", {
	Name = "Log",
	Position = UDim2.fromOffset(0, TOOLBAR_HEIGHT),
	Size = UDim2.new(1, 0, 1, -TOOLBAR_HEIGHT),
	BackgroundColor3 = colors.input,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	ScrollBarImageColor3 = colors.subtext,
	ScrollBarImageTransparency = 0.4,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	ClipsDescendants = true,
}, content)

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
	return scroll.CanvasPosition.Y + scroll.AbsoluteSize.Y >= scroll.CanvasSize.Y.Offset - ROW_HEIGHT * 2
end

local function scrollToBottom()
	scroll.CanvasPosition = Vector2.new(0, math.max(0, scroll.CanvasSize.Y.Offset - scroll.AbsoluteSize.Y))
end

local function addRow(entry)
	local row = UI.label(
		scroll,
		string.format("[%s] %s", entry.time, entry.message),
		UDim2.fromOffset(PAD, rowCount * ROW_HEIGHT),
		UDim2.new(1, -(PAD * 2 + 8), 0, ROW_HEIGHT),
		UI.tokens.type.small,
		entry.color
	)

	row.Name = "Row"
	row.TextXAlignment = Enum.TextXAlignment.Left

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

local function makeEntry(item)
	local kind = KIND_COLORS[item.type] and item.type or "Log"

	return {
		message = tostring(item.message),
		kind = kind,
		color = KIND_COLORS[kind],
		time = os.date("%H:%M:%S", item.timestamp),
	}
end

local function poll()
	local count = LogService.MessageCount

	if count == lastSeenCount then
		return
	end

	-- Counter went backwards: someone called LogService:Clear()
	if count < lastSeenCount then
		table.clear(entries)
		lastSeenCount = 0
	end

	local history = LogService:GetLogHistory()
	local newCount = math.min(count - lastSeenCount, #history)

	lastSeenCount = count

	if newCount <= 0 then
		return
	end

	local stick = isNearBottom()
	local needsRebuild = false

	for index = #history - newCount + 1, #history do
		local entry = makeEntry(history[index])

		table.insert(entries, entry)

		if #entries > MAX_ENTRIES then
			table.remove(entries, 1)
			needsRebuild = true
		end

		if not needsRebuild and passes(entry) then
			addRow(entry)
		end
	end

	if needsRebuild then
		rebuild()
	elseif stick then
		scrollToBottom()
	end
end

local elapsed = 0

RunService.Heartbeat:Connect(function(dt)
	if not panel.Visible then
		return
	end

	elapsed += dt

	if elapsed < POLL_INTERVAL then
		return
	end

	elapsed = 0
	poll()
end)

search:GetPropertyChangedSignal("Text"):Connect(function()
	searchQuery = string.lower(search.Text)
	rebuild()
end)

-- Initial backfill
do
	lastSeenCount = 0
	poll()
end

return {
	window = panel,
	toggle = function()
		UI.toggleWindow(WINDOW_NAME)
	end,
}

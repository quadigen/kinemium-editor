if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local UI = require("@internal/editor_ui")
local ThemeService = game:GetService("StudioThemeService")
local UserInputService = game:GetService("UserInputService")

local radius = UI.tokens.radius.sm

local DOCK_BLUE = Color3.new(0.058824, 0.552941, 0.862745)
local DOCK_BLUE_HOVER = Color3.new(0.2, 0.68, 0.95)
local DOCK_BLUE_PRESSED = Color3.new(0.04, 0.42, 0.7)
local WHITE = Color3.new(1, 1, 1)

local BUTTON_SIZE = 50

local ANCHORS = {
	{ name = "TopLeft", col = 0, row = 0 },
	{ name = "TopCenter", col = 1, row = 0 },
	{ name = "TopRight", col = 2, row = 0 },
	{ name = "MiddleLeft", col = 0, row = 1 },
	{ name = "Center", col = 1, row = 1 },
	{ name = "MiddleRight", col = 2, row = 1 },
	{ name = "BottomLeft", col = 0, row = 2 },
	{ name = "BottomCenter", col = 1, row = 2 },
	{ name = "BottomRight", col = 2, row = 2 },
}

local overlay = Instance.new("ScreenGui")
overlay.RenderOnTop = true
overlay.Name = "DockingOverlay"
overlay.Parent = game.CoreGui

local container = UI.frame(overlay, UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), Color3.new(0, 0, 0), 0)
container.BackgroundTransparency = 1
container.Visible = false

local Dock = {}
local pendingWindow: string? = nil

function Dock.Hide()
	container.Visible = false
	pendingWindow = nil
end

local function dockTo(anchor: string, fullSpan: boolean)
	local windowName = pendingWindow
	if not windowName then
		return
	end

	local ok, err = pcall(function()
		ThemeService:DockWindow(windowName, anchor, fullSpan)
	end)

	if not ok then
		warn("[Docking] DockWindow failed:", err)
	end

	Dock.Hide()
end

local backdrop = UI.button(container, "", UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), function()
	Dock.Hide()
end, {
	color = Color3.new(0, 0, 0),
	hoverColor = Color3.new(0, 0, 0),
	pressedColor = Color3.new(0, 0, 0),
	bgTransparency = 0.6,
	border = false,
	radius = 0,
})
backdrop.ZIndex = 1

local preview = UI.frame(container, UDim2.fromOffset(0, 0), UDim2.fromScale(1 / 3, 1 / 3), DOCK_BLUE, radius)
preview.BackgroundTransparency = 0.75
preview.Visible = false
preview.ZIndex = 2
UI.stroke(preview, DOCK_BLUE, 2)

local function showPreview(col: number, row: number)
	preview.Position = UDim2.fromScale(col / 3, row / 3)
	preview.Size = UDim2.fromScale(1 / 3, 1 / 3)
	preview.Visible = true
end

local function showBarPreview(top: boolean)
	preview.Position = UDim2.fromScale(0, top and 0 or 0.9)
	preview.Size = UDim2.fromScale(1, 0.1)
	preview.Visible = true
end

local function hidePreview()
	preview.Visible = false
end

local function buildMiniGrid(parent: GuiObject, activeCol: number, activeRow: number)
	local cell, gap = 8, 2
	local total = cell * 3 + gap * 2

	local holder = UI.frame(parent, UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(total, total), WHITE, 0)
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.BackgroundTransparency = 1
	holder.ZIndex = 4

	for row = 0, 2 do
		for col = 0, 2 do
			local active = col == activeCol and row == activeRow
			local square = UI.frame(
				holder,
				UDim2.fromOffset(col * (cell + gap), row * (cell + gap)),
				UDim2.fromOffset(cell, cell),
				WHITE,
				2
			)
			square.BackgroundTransparency = active and 0 or 0.72
			square.ZIndex = 5
		end
	end
end

for _, anchor in ANCHORS do
	local button = UI.button(
		container,
		"",
		UDim2.fromScale((anchor.col + 0.5) / 3, (anchor.row + 0.5) / 3),
		UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE),
		function()
			dockTo(anchor.name, false)
		end,
		{
			color = DOCK_BLUE,
			hoverColor = DOCK_BLUE_HOVER,
			pressedColor = DOCK_BLUE_PRESSED,
			bgTransparency = 0.5,
			border = false,
			radius = radius,
		}
	)
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.ZIndex = 3
	UI.stroke(button, WHITE, 2)

	buildMiniGrid(button, anchor.col, anchor.row)

	button.MouseEnter:Connect(function()
		showPreview(anchor.col, anchor.row)
	end)
	button.MouseLeave:Connect(hidePreview)
end

local function makeBarButton(text: string, top: boolean, anchorName: string)
	local button = UI.button(
		container,
		text,
		UDim2.new(0.5, 0, top and 0 or 1, top and 16 or -16),
		UDim2.fromOffset(220, 28),
		function()
			dockTo(anchorName, true)
		end,
		{
			color = DOCK_BLUE,
			hoverColor = DOCK_BLUE_HOVER,
			pressedColor = DOCK_BLUE_PRESSED,
			textColor = WHITE,
			bgTransparency = 0.5,
			border = false,
			radius = radius,
		}
	)
	button.AnchorPoint = Vector2.new(0.5, top and 0 or 1)
	button.ZIndex = 3
	UI.stroke(button, WHITE, 2)

	button.MouseEnter:Connect(function()
		showBarPreview(top)
	end)
	button.MouseLeave:Connect(hidePreview)
end

makeBarButton("Full-width top bar", true, "TopCenter")
makeBarButton("Full-width bottom bar", false, "BottomCenter")

local HiddenSignal = Signal.new()

local title = UI.label(container, "", UDim2.new(0.5, 0, 0, 56), UDim2.fromOffset(420, 20), UI.tokens.type.body, WHITE)
title.AnchorPoint = Vector2.new(0.5, 0)
title.TextXAlignment = Enum.TextXAlignment.Center
title.ZIndex = 3

UserInputService.InputBegan:Connect(function(input, processed)
	if container.Visible and input.KeyCode == Enum.KeyCode.Escape then
		Dock.Hide()
		HiddenSignal:Fire()
	end
end)

function Dock.Show(windowName: string)
	pendingWindow = windowName
	title.Text = `Dock {windowName}  (Esc to cancel)`
	hidePreview()
	container.Visible = true
end

function Dock.IsVisible(): boolean
	return container.Visible
end

Dock.HiddenSignal = HiddenSignal

return Dock

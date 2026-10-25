if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local UI = require("@internal/editor_ui")
local gameCategory = require("@internal/topbar_game")
local projectsCategory = require("@internal/topbar_projects")
local homeCategory = require("@internal/topbar_home")
local fileCategory = require("@internal/topbar_file")
local UICategory = require("@internal/topbar_ui")
local modelCategory = require("@internal/topbar_model")
local testCategory = require("@internal/topbar_test")
local viewCategory = require("@internal/topbar_view")
local pluginsCategory = require("@internal/topbar_plugins")
local studioCategory = require("@internal/topbar_studio")
local menuBarController
local user = require("@internal/user")

local StudioThemeService = game:GetService("StudioThemeService")
local theme = StudioThemeService.SelectedTheme

local root = UI.widgetOverlay()

local tokens = UI.tokens

local FLYOUT_HEIGHT = 70
local FLYOUT_GAP = 5
local FLYOUT_BOTTOM_PADDING = 5

local expanded = true
local selectedCategory

local lastTheme = theme

local topbar
local topbarStroke
local headerSurface
local headerBottomFill
local logoPlate
local flyout
local flyoutStroke
local collapseButton
local collapseIcon

local toolbarTabs

local categoryByName = {}
local pageKeep = {}

local rebuildFlyout
local setExpanded

local function safeAction(callback)
	return function()
		if not callback then
			return
		end

		local ok, message = pcall(callback)

		if not ok then
			warn("Editor command failed: " .. tostring(message))
		end
	end
end

local engineCategories = {
	fileCategory,
	gameCategory,
	projectsCategory,
	studioCategory,
}

local toolbarCategories = {
	homeCategory,
	modelCategory,
	testCategory,
	viewCategory,
	UICategory,
	pluginsCategory,
}

UI.buttonCategories = {
	{
		name = "Engine",
		buttons = engineCategories,
	},
	{
		name = "Toolbar",
		buttons = toolbarCategories,
	},
}

selectedCategory = homeCategory

local function themeColor(value, fallback)
	if value == nil then
		return fallback
	end

	if typeof(value) == "Color3" then
		return value
	end

	if type(value) == "table" and value.R ~= nil and value.G ~= nil and value.B ~= nil then
		return Color3.new(value.R, value.G, value.B)
	end

	return fallback
end

local function palette()
	local colors = tokens.color

	return {
		base = colors.canvas,

		panel = colors.panel,

		raised = colors.panelRaised,

		surface = colors.surface,

		input = colors.input,

		border = colors.borderStrong,

		accent = colors.accent,

		text = colors.text,

		subtext = colors.subtext,

		muted = colors.muted,
	}
end

local function windowRadius()
	return tokens.radius.md
end

local function buttonRadius()
	return tokens.radius.sm
end

local function copyUDim2(value)
	return UDim2.new(value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset)
end

local function applyUpperPaneLayout(name, extraHeight)
	local coordinates = theme[name]

	if not coordinates then
		return
	end

	coordinates.Position = UDim2.new(
		coordinates.Position.X.Scale,
		coordinates.Position.X.Offset,
		coordinates.Position.Y.Scale,
		coordinates.Position.Y.Offset + extraHeight
	)

	coordinates.Size = UDim2.new(
		coordinates.Size.X.Scale,
		coordinates.Size.X.Offset,
		coordinates.Size.Y.Scale,
		coordinates.Size.Y.Offset - extraHeight
	)
end

local function layoutExtraHeight()
	if not expanded then
		return 0
	end

	return FLYOUT_GAP + FLYOUT_HEIGHT + FLYOUT_BOTTOM_PADDING
end

local function applyWorkspaceLayout()
	local extraHeight = layoutExtraHeight()

	applyUpperPaneLayout("ExplorerCoordinates", extraHeight)

	applyUpperPaneLayout("ViewportCoordinates", extraHeight)

	applyUpperPaneLayout("CodeEditorCoordinates", extraHeight)
end

local function fireRoute(route)
	if not route then
		return
	end

	if UI.StudioSystem then
		UI.StudioSystem:Fire(route)
		return
	end

	local windowName = string.match(route, "^toggle_(.+)$")

	if windowName then
		UI.toggleWindow(windowName)
	end
end

local function baseHeaderHeight()
	local coordinates = theme.TopbarCoordinates

	if not coordinates then
		return 33
	end

	return coordinates.Size.Y.Offset
end

local function expandedTopbarHeight()
	return baseHeaderHeight() + layoutExtraHeight()
end

local function updateTopbarGeometry()
	local coordinates = theme.TopbarCoordinates

	if not coordinates then
		return
	end

	topbar.Position = coordinates.Position

	topbar.Size = UDim2.new(
		coordinates.Size.X.Scale,
		coordinates.Size.X.Offset,
		coordinates.Size.Y.Scale,
		expanded and expandedTopbarHeight() or baseHeaderHeight()
	)

	local headerHeight = baseHeaderHeight()

	headerSurface.Size = UDim2.new(1, 0, 0, headerHeight)

	flyout.Position = UDim2.fromOffset(5, headerHeight + FLYOUT_GAP)

	flyout.Size = UDim2.new(1, -10, 0, FLYOUT_HEIGHT)

	flyout.Visible = expanded
end

local function applyTabColors()
	if not toolbarTabs then
		return
	end

	local colors = palette()

	toolbarTabs.setColors({
		bar = colors.panel,
		content = colors.surface,
		activeTab = colors.surface,
		inactiveTab = colors.panel,
		hover = colors.raised,
		pressed = colors.input,
		activeText = colors.text,
		inactiveText = colors.subtext,
		accent = colors.accent,
	})
end

local function applyTheme()
	local colors = palette()

	topbar.BackgroundColor3 = colors.panel

	headerSurface.BackgroundColor3 = colors.panel

	if headerBottomFill then
		headerBottomFill.BackgroundColor3 = colors.panel
	end

	if logoPlate then
		logoPlate.BackgroundColor3 = colors.surface
	end

	flyout.BackgroundColor3 = colors.surface

	topbarStroke.Color = colors.border

	topbarStroke.Transparency = 0.45

	if flyoutStroke then
		flyoutStroke.Color = colors.border

		flyoutStroke.Transparency = 0.55
	end

	if collapseButton then
		collapseButton.BackgroundColor3 = colors.panel
	end

	if menuBarController then
		menuBarController:SetColors({
			bar = colors.panel,
			border = colors.border,
			hover = colors.raised,
			text = colors.text,
			subtext = colors.subtext,
		})
	end

	applyTabColors()
end

setExpanded = function(value)
	expanded = value == true

	updateTopbarGeometry()
	applyWorkspaceLayout()

	if collapseIcon then
		collapseIcon.Image = "builtin://icons/" .. (expanded and "ArrowUp.svg" or "ArrowDown.svg")
	end
end

local initialColors = palette()

topbar =
	UI.frame(root, theme.TopbarCoordinates.Position, theme.TopbarCoordinates.Size, initialColors.panel, windowRadius())

topbar.Name = "Topbar"
topbar.ClipsDescendants = true
topbar.ZIndex = 100

topbarStroke = UI.stroke(topbar, initialColors.border, 1, 0.45)

headerSurface = UI.frame(
	topbar,
	UDim2.fromOffset(0, 0),
	UDim2.new(1, 0, 0, baseHeaderHeight()),
	initialColors.panel,
	windowRadius()
)

headerSurface.Name = "Header"

headerBottomFill = UI.frame(
	headerSurface,
	UDim2.new(0, 0, 1, -windowRadius()),
	UDim2.new(1, 0, 0, windowRadius()),
	initialColors.panel
)

logoPlate =
	UI.frame(headerSurface, UDim2.fromOffset(5, 4), UDim2.fromOffset(25, 25), initialColors.surface, buttonRadius())

logoPlate.Name = "Logo"

UI.image(logoPlate, "builtin://global-icons/KinemiumWhite.png", UDim2.fromOffset(2, 2), UDim2.fromOffset(21, 21))

flyout = UI.group(topbar, UDim2.fromOffset(5, baseHeaderHeight() + FLYOUT_GAP), UDim2.new(1, -10, 0, FLYOUT_HEIGHT), {
	color = initialColors.surface,

	radius = windowRadius(),
})

flyout.Name = "CategoryDropdown"

flyout.ClipsDescendants = true

flyoutStroke = UI.stroke(flyout, initialColors.border, 1, 0.55)

rebuildFlyout = function()
	local page = toolbarTabs and toolbarTabs.pages[selectedCategory.name]

	if not page then
		return
	end

	UI.clear(page, pageKeep[page])

	local colors = palette()

	if #selectedCategory.buttons == 0 then
		UI.label(
			page,
			"No tools in this category",
			UDim2.new(),
			UDim2.new(1, -24, 0, 18),
			tokens.type.small,
			colors.muted
		)

		return
	end

	for _, definition in ipairs(selectedCategory.buttons) do
		if definition.type == "separator" then
			local holder = UI.create("Frame", {
				Name = "Separator",
				Size = UDim2.fromOffset(10, FLYOUT_HEIGHT - 20),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
			}, page)

			UI.separator(holder, UDim2.fromOffset(4, 0), UDim2.new(0, 1, 1, 0), colors.border)
		elseif definition.type == "custom" then
			local width = definition.width or 100

			local element = definition.create(page, colors, UDim2.new(), UDim2.fromOffset(width, FLYOUT_HEIGHT - 12))

			if element then
				element.Name = definition.name or "CustomElement"
			end
		else
			UI.TopbarButton(page, definition, {
				position = UDim2.new(),
				size = UDim2.fromOffset(definition.width or 52, FLYOUT_HEIGHT - 12),
				colors = colors,
				radius = buttonRadius(),
				onClick = safeAction(function(item)
					fireRoute(definition.route)

					if definition.callback then
						definition.callback(item)
					end
				end),
			})
		end
	end
end

local headerX = 35

local function iconPath(icon)
	if not icon or icon == "" then
		return nil
	end

	if string.find(icon, "://", 1, true) then
		return icon
	end

	return "builtin://icons/" .. icon
end

local function buildMenuItems(category)
	local items = {}

	for _, definition in ipairs(category.buttons) do
		if definition.type == "separator" then
			table.insert(items, { separator = true })
		elseif definition.type ~= "custom" then
			table.insert(items, {
				label = definition.name,
				icon = iconPath(definition.icon),
				shortcut = definition.shortcut,
				submenu = definition.submenu,
				enabled = definition.enabled,
				callback = safeAction(function()
					fireRoute(definition.route)

					if definition.callback then
						definition.callback()
					end
				end),
			})
		end
	end

	return items
end

local menuDefinitions = {}

for _, category in ipairs(engineCategories) do
	table.insert(menuDefinitions, {
		name = category.name,
		items = function()
			return buildMenuItems(category)
		end,
	})
end

local menuBar
menuBar, menuBarController = UI.menuBar(headerSurface, UDim2.fromOffset(headerX, 3), nil, menuDefinitions, {
	height = baseHeaderHeight() - 6,
	inset = 2,
	radius = buttonRadius() + 2,
	triggerRadius = buttonRadius(),
	color = initialColors.panel,
	borderColor = initialColors.border,
	hoverColor = initialColors.raised,
	textColor = initialColors.text,
	subtextColor = initialColors.subtext,
	menuWidth = 200,
})

headerX += menuBarController:GetWidth() + 6

local tabDefinitions = {}

for _, category in ipairs(toolbarCategories) do
	categoryByName[category.name] = category

	table.insert(tabDefinitions, {
		name = category.name,
		text = category.name,
		width = #category.name * 8 + 22,
	})
end

local _
_, toolbarTabs = UI.tabs(nil, nil, nil, {
	tabs = tabDefinitions,
	selectedTab = selectedCategory.name,

	barFrame = headerSurface,
	contentFrame = flyout,
	startX = headerX,

	barHeight = 28,
	tabTop = 4,
	tabGap = 2,
	tabPaddingX = 8,
	tabRadius = buttonRadius(),
	tabTextSize = tokens.type.small,
	tabFilletRadius = 0,

	barColor = initialColors.panel,
	contentColor = initialColors.surface,
	activeTabColor = initialColors.surface,
	inactiveTabColor = initialColors.panel,
	tabHoverColor = initialColors.raised,
	tabPressedColor = initialColors.input,
	activeTabTextColor = initialColors.text,
	inactiveTabTextColor = initialColors.subtext,
	tabAccentColor = initialColors.accent,

	onTabChanged = function(tabName)
		selectedCategory = categoryByName[tabName] or selectedCategory

		if not toolbarTabs then
			return
		end

		rebuildFlyout()

		if not expanded then
			setExpanded(true)
		end
	end,

	onTabClicked = function(_, wasSelected)
		if wasSelected then
			setExpanded(not expanded)
		end
	end,
})

for _, category in ipairs(toolbarCategories) do
	local page = toolbarTabs.pages[category.name]

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.Padding = UDim.new(0, 3)
	layout.Parent = page

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 6)
	padding.Parent = page

	pageKeep[page] = {
		[layout] = true,
		[padding] = true,
	}
end

local collapseSize = 24

local collapseRecord

do
	local button, _, record = UI.button(
		headerSurface,
		"",
		UDim2.new(1, -(collapseSize + 5), 0, 4),
		UDim2.fromOffset(collapseSize, 24),
		function()
			setExpanded(not expanded)
		end,
		{
			color = initialColors.panel,

			hoverColor = initialColors.raised,

			pressedColor = initialColors.input,

			border = false,

			radius = buttonRadius(),
		}
	)

	collapseButton = button

	collapseRecord = record

	collapseIcon =
		UI.image(button, "builtin://icons/ArrowUp.svg", UDim2.new(0.5, -5, 0.5, -5), UDim2.fromOffset(10, 10))
end

local function refreshTheme()
	local selectedTheme = StudioThemeService.SelectedTheme

	local themeChanged = selectedTheme ~= lastTheme

	if themeChanged then
		theme = selectedTheme

		lastTheme = selectedTheme
	end

	local colors = palette()

	if collapseRecord then
		collapseRecord.color = colors.panel

		collapseRecord.defaultColor = colors.panel

		collapseRecord.hoverColor = colors.raised

		collapseRecord.defaultHoverColor = colors.raised

		collapseRecord.pressedColor = colors.input

		if UI.isAlive(collapseRecord.gui) then
			collapseRecord.gui.BackgroundColor3 = colors.panel
		end
	end

	if themeChanged then
		rebuildFlyout()
	end

	applyTheme()
	updateTopbarGeometry()
	applyWorkspaceLayout()
end

UI.EngineTopbar = {
	AddCategory = function(categoryName, buttons)
		if type(categoryName) ~= "string" or type(buttons) ~= "table" then
			return
		end

		local category = {
			name = categoryName,
			buttons = buttons,
		}

		table.insert(toolbarCategories, category)
	end,

	SetExpanded = function(value)
		setExpanded(value)
	end,

	IsExpanded = function()
		return expanded
	end,

	GetConsumedHeight = function()
		return layoutExtraHeight()
	end,
}

user(topbar)
rebuildFlyout()
setExpanded(true)
applyTheme()

renderer.Pool.new("2d", function()
	refreshTheme()
end)

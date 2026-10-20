local Auth = require("@internal/auth")
local UI = require("@internal/editor_ui")
local MatrixService = game:GetService("MatrixService")
local http = game:GetService("HttpService")

local colors = UI.tokens.color
local tokens = UI.tokens

shared.CurrentSession = MatrixService:GetSession()

local function svgIcon(body)
	return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='24' height='24' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'>"
		.. body
		.. "</svg>"
end

local ICONS = {
	general = "builtin://icons/Settings.svg",
	account = "builtin://icons/Player.svg",
	notifications = "builtin://icons/UINotificationLayout.svg",
	devices = "builtin://icons/MultipleDevices.svg",
	emojis = "builtin://icons/Sparkles.svg",
	developer = "builtin://icons/Script.svg",
	about = "builtin://global-icons/Info.svg",
	power = svgIcon("<path d='M12 2v10'/><path d='M18.4 6.6a9 9 0 1 1-12.77.04'/>"),
}

local state = {
	systemTheme = true,
	lightTheme = "Light",
	darkTheme = "Dark",
	theme = "Dark",
	monochrome = false,
	twitterEmoji = true,
	pageZoom = "100%",
	hour24 = false,
	dateFormat = "19 Oct 2026",
	enterNewline = false,
	tabSpaces = true,
	tabSize = "4",
	rememberSession = MatrixService.RememberSession ~= false,

	notifyDirect = true,
	notifyMentions = true,
	notifyInvites = true,
	notifySounds = false,
	notificationSound = "Chime",

	verifyDevices = true,
	offlineDevices = false,

	emojiAutocomplete = true,
	largeEmoji = true,
	stickerSuggestions = true,
	emojiSet = "Twitter",

	developerMode = false,
	syncLogging = false,
	debugLabels = false,
}

local function SetImage(session, image)
	local ok, profile = MatrixService:GetProfile(session)

	if not ok or not profile.avatarUrl then
		return
	end

	local url = MatrixService:MxcToHttp(session.homeserver, profile.avatarUrl, {
		authenticated = true,
		width = 128,
		height = 128,
		method = "crop",
	})

	if not url then
		return
	end

	local content = http:GetImageBytes(url, {
		Authorization = "Bearer " .. session.accessToken,
	})

	image.Image = content
end

local function dropdownItems(values)
	local result = {}

	for _, value in ipairs(values) do
		table.insert(result, {
			value = value,
			label = value,
		})
	end

	return result
end

local function buildCategories(session, onLogout)
	return {
		{
			name = "General",
			icon = ICONS.general,
			description = "Studio appearance, behavior, and preferences.",
			sections = {
				{
					title = "Appearance",
					rows = {
						{
							kind = "switch",
							key = "systemTheme",
							title = "System Theme",
							description = "Follow your operating system's theme.",
							rerender = true,
						},
						{
							kind = "dropdown",
							key = "lightTheme",
							title = "Light Theme",
							items = { "Light", "Dark" },
						},
						{
							kind = "dropdown",
							key = "darkTheme",
							title = "Dark Theme",
							items = { "Light", "Dark" },
						},
						{
							kind = "dropdown",
							key = "theme",
							title = "Theme",
							description = "Theme used when system theme is disabled.",
							items = { "Light", "Dark" },
							disabledKey = "systemTheme",
						},
						{
							kind = "switch",
							key = "monochrome",
							title = "Monochrome Mode",
							description = "Use a monochromatic interface appearance.",
						},
						{
							kind = "switch",
							key = "reduceMotion",
							title = "Reduce Motion",
							description = "Reduce nonessential interface animations.",
						},
						{
							kind = "dropdown",
							key = "pageZoom",
							title = "UI Scale",
							description = "Adjust the scale of Studio's interface.",
							items = { "75%", "90%", "100%", "110%", "125%", "150%", "200%" },
							width = 110,
						},
					},
				},
				{
					title = "Behavior",
					rows = {
						{
							kind = "switch",
							key = "restoreSession",
							title = "Restore Previous Session",
							description = "Restore the previous workspace when Studio starts.",
						},
						{
							kind = "switch",
							key = "autoSave",
							title = "Auto Save",
							description = "Periodically save changes to the project.",
						},
						{
							kind = "dropdown",
							key = "autoSaveInterval",
							title = "Auto Save Interval",
							items = { "1 minute", "3 minutes", "5 minutes", "10 minutes", "15 minutes" },
							width = 130,
						},
						{
							kind = "switch",
							key = "confirmExit",
							title = "Confirm Before Exiting",
							description = "Ask before closing Studio with unsaved changes.",
						},
						{
							kind = "switch",
							key = "showStartPage",
							title = "Show Start Page",
							description = "Display the start page when Studio launches.",
						},
					},
				},
				{
					title = "Date & Time",
					rows = {
						{
							kind = "switch",
							key = "hour24",
							title = "24-Hour Time Format",
						},
						{
							kind = "dropdown",
							key = "dateFormat",
							title = "Date Format",
							items = { "19 Oct 2026", "Oct 19, 2026", "2026-10-19", "19/10/2026" },
							width = 152,
						},
					},
				},
			},
		},

		{
			name = "Editor",
			icon = ICONS.editor or ICONS.general,
			description = "Code editing, formatting, and scripting preferences.",
			sections = {
				{
					title = "Text Editor",
					rows = {
						{
							kind = "switch",
							key = "enterNewline",
							title = "Enter for Newline",
							description = "Insert a newline when pressing Enter.",
						},
						{
							kind = "switch",
							key = "tabSpaces",
							title = "Insert Spaces on Tab",
							description = "Insert spaces instead of tab characters.",
						},
						{
							kind = "dropdown",
							key = "tabSize",
							title = "Tab Size",
							items = { "2", "4", "8" },
							width = 90,
						},
						{
							kind = "switch",
							key = "lineNumbers",
							title = "Line Numbers",
						},
						{
							kind = "switch",
							key = "relativeLineNumbers",
							title = "Relative Line Numbers",
						},
						{
							kind = "switch",
							key = "wordWrap",
							title = "Word Wrap",
							description = "Wrap long lines within the editor.",
						},
						{
							kind = "switch",
							key = "minimap",
							title = "Show Minimap",
							description = "Display a code overview beside the editor.",
						},
						{
							kind = "switch",
							key = "highlightCurrentLine",
							title = "Highlight Current Line",
						},
						{
							kind = "switch",
							key = "bracketMatching",
							title = "Bracket Matching",
						},
						{
							kind = "switch",
							key = "autoIndent",
							title = "Automatic Indentation",
						},
						{
							kind = "switch",
							key = "autoClosingBrackets",
							title = "Auto-Close Brackets",
						},
						{
							kind = "switch",
							key = "autoClosingQuotes",
							title = "Auto-Close Quotes",
						},
					},
				},
				{
					title = "Code Assistance",
					rows = {
						{
							kind = "switch",
							key = "autocomplete",
							title = "Autocomplete",
							description = "Suggest identifiers and API members while typing.",
						},
						{
							kind = "switch",
							key = "parameterHints",
							title = "Parameter Hints",
						},
						{
							kind = "switch",
							key = "hoverDocumentation",
							title = "Hover Documentation",
						},
						{
							kind = "switch",
							key = "diagnostics",
							title = "Live Diagnostics",
							description = "Show syntax and type diagnostics while editing.",
						},
						{
							kind = "switch",
							key = "formatOnSave",
							title = "Format on Save",
						},
					},
				},
			},
		},

		{
			name = "Studio",
			icon = ICONS.studio or ICONS.general,
			description = "Workspace layout, panels, and viewport behavior.",
			sections = {
				{
					title = "Workspace",
					rows = {
						{
							kind = "switch",
							key = "restoreLayout",
							title = "Restore Workspace Layout",
						},
						{
							kind = "switch",
							key = "showStatusBar",
							title = "Show Status Bar",
						},
						{
							kind = "switch",
							key = "showToolbar",
							title = "Show Toolbar",
						},
						{
							kind = "switch",
							key = "showExplorer",
							title = "Show Explorer",
						},
						{
							kind = "switch",
							key = "showProperties",
							title = "Show Properties",
						},
						{
							kind = "switch",
							key = "showOutput",
							title = "Show Output",
						},
					},
				},
				{
					title = "Viewport",
					rows = {
						{
							kind = "switch",
							key = "viewportGrid",
							title = "Show Grid",
						},
						{
							kind = "switch",
							key = "viewportAxes",
							title = "Show Axes",
						},
						{
							kind = "switch",
							key = "viewportGizmos",
							title = "Show Gizmos",
						},
						{
							kind = "switch",
							key = "viewportSelectionOutline",
							title = "Selection Outline",
						},
						{
							kind = "switch",
							key = "viewportCameraControls",
							title = "Camera Controls",
						},
					},
				},
			},
		},

		{
			name = "Projects",
			icon = ICONS.projects or ICONS.general,
			description = "Project files, saving, and asset handling.",
			sections = {
				{
					title = "Project Management",
					rows = {
						{
							kind = "switch",
							key = "showRecentProjects",
							title = "Recent Projects",
						},
						{
							kind = "switch",
							key = "confirmDelete",
							title = "Confirm Before Deleting",
							description = "Ask before deleting project objects or files.",
						},
						{
							kind = "switch",
							key = "showFileExtensions",
							title = "Show File Extensions",
						},
						{
							kind = "switch",
							key = "reopenLastProject",
							title = "Reopen Last Project",
						},
					},
				},
			},
		},

		{
			name = "Playtest",
			icon = ICONS.playtest or ICONS.general,
			description = "Configure local testing and simulation.",
			sections = {
				{
					title = "Testing",
					rows = {
						{
							kind = "dropdown",
							key = "playtestMode",
							title = "Default Playtest Mode",
							items = { "Client", "Server", "Local Server" },
							width = 140,
						},
						{
							kind = "switch",
							key = "playtestHeadlessServer",
							title = "Headless Server",
						},
						{
							kind = "switch",
							key = "playtestHeadlessClient",
							title = "Headless Client",
						},
						{
							kind = "switch",
							key = "playtestSingleplayer",
							title = "Launch singleplayer",
						},
						{
							kind = "switch",
							key = "playtestPauseOnError",
							title = "Pause on Error",
						},
						{
							kind = "switch",
							key = "playtestOutput",
							title = "Show Playtest Output",
						},
						{
							kind = "switch",
							key = "playtestClearOutput",
							title = "Clear Output on Start",
						},
					},
				},
			},
		},

		{
			name = "Shortcuts",
			icon = ICONS.shortcuts or ICONS.general,
			description = "Keyboard shortcuts and input preferences.",
			sections = {
				{
					title = "Keyboard",
					rows = {
						{
							kind = "switch",
							key = "enableKeyboardShortcuts",
							title = "Enable Keyboard Shortcuts",
						},
						{
							kind = "switch",
							key = "vimMode",
							title = "Vim Mode",
							description = "Use Vim-style editing controls.",
						},
					},
				},
			},
		},

		{
			name = "Developer Tools",
			icon = ICONS.developer,
			description = "Diagnostics, profiling, and development options.",
			sections = {
				{
					title = "Development",
					rows = {
						{
							kind = "switch",
							key = "developerMode",
							title = "Developer Mode",
							description = "Expose additional development tools.",
						},
						{
							kind = "switch",
							key = "debugLabels",
							title = "Show Debug Labels",
							description = "Display internal identifiers in the interface.",
						},
						{
							kind = "switch",
							key = "verboseLogging",
							title = "Verbose Logging",
						},
						{
							kind = "switch",
							key = "showPerformanceStats",
							title = "Show Performance Statistics",
						},
						{
							kind = "switch",
							key = "profilerEnabled",
							title = "Enable Profiler",
						},
					},
				},
			},
		},

		{
			name = "About",
			icon = ICONS.about,
			description = "Version and project information.",
			sections = {
				{
					title = "Kinemium Studio",
					rows = {
						{
							kind = "value",
							title = "Version",
							value = "Development build",
							valueWidth = 180,
						},
						{
							kind = "value",
							title = "Application",
							value = "Kinemium Studio",
							valueWidth = 180,
						},
					},
				},
			},
		},
	}
end

return function(parent)
	local tooltip
	local profileButton, image
	local settingsOpen = false
	local settingsWindow
	local settingsPage
	local dropdowns = {}

	local function closeDropdowns()
		local active = dropdowns

		dropdowns = {}

		for _, controller in ipairs(active) do
			if controller and controller.Close then
				controller:Close()
			end
		end
	end

	local function handleLogout(session)
		shared.CurrentSession = nil
		settingsOpen = false

		image.Image = "builtin://icons/Play.svg"

		if tooltip then
			tooltip:SetText("Not logged in")
		end

		if settingsWindow then
			settingsWindow.Visible = false
		end

		task.spawn(function()
			if session then
				MatrixService:Logout(session)
			end
		end)
	end

	local function performLogout(session)
		closeDropdowns()
		handleLogout(session)
	end

	local function buildSettings(page, session)
		closeDropdowns()
		UI.clear(page)

		local SIDEBAR_WIDTH = 214
		local INSET = tokens.space.md

		local categories = buildCategories(session, function()
			performLogout(session)
		end)

		local sidebar = UI.card(page, UDim2.fromOffset(INSET, INSET), UDim2.new(0, SIDEBAR_WIDTH, 1, -INSET * 2), {
			color = colors.panel,
			radius = tokens.radius.md,
			border = true,
			borderColor = colors.border,
			borderTransparency = 0.35,
		})

		local contentPanel = UI.card(
			page,
			UDim2.fromOffset(SIDEBAR_WIDTH + INSET * 2, INSET),
			UDim2.new(1, -(SIDEBAR_WIDTH + INSET * 3), 1, -INSET * 2),
			{
				color = colors.panelRaised,
				radius = tokens.radius.md,
				border = true,
				borderColor = colors.border,
				borderTransparency = 0.35,
			}
		)

		contentPanel.ClipsDescendants = true

		local search = UI.input(
			sidebar,
			"Search settings...",
			UDim2.fromOffset(INSET, INSET),
			UDim2.new(1, -INSET * 2, 0, UI.metrics.inputHeight),
			{
				textSize = tokens.type.small,
			}
		)

		local optionsLabel = UI.label(
			sidebar,
			"Options",
			UDim2.fromOffset(INSET + 3, 41),
			UDim2.new(1, -(INSET * 2 + 6), 0, 16),
			tokens.type.caption,
			colors.muted
		)

		optionsLabel.TextXAlignment = Enum.TextXAlignment.Left

		local header = UI.group(contentPanel, UDim2.fromOffset(INSET, INSET), UDim2.new(1, -INSET * 2, 0, 60), {
			color = colors.surface,
			radius = tokens.radius.sm,
		})

		UI.stroke(header, colors.border, 1, 0.45)

		UI.frame(header, UDim2.fromOffset(0, 10), UDim2.fromOffset(3, 40), colors.accent, 2)

		local titleLabel = UI.label(
			header,
			"General",
			UDim2.fromOffset(16, 10),
			UDim2.new(1, -32, 0, 20),
			tokens.type.title,
			colors.text
		)

		titleLabel.TextXAlignment = Enum.TextXAlignment.Left

		local descriptionLabel = UI.label(
			header,
			"",
			UDim2.fromOffset(16, 31),
			UDim2.new(1, -32, 0, 20),
			tokens.type.caption,
			colors.subtext
		)

		descriptionLabel.TextXAlignment = Enum.TextXAlignment.Left
		descriptionLabel.TextWrapped = true

		local scroller = UI.create("ScrollingFrame", {
			Name = "SettingsScroller",
			Position = UDim2.fromOffset(INSET, 76),
			Size = UDim2.new(1, -INSET * 2, 1, -84),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasPosition = Vector2.new(0, 0),
			CanvasSize = UDim2.new(0, 0, 0, 0),
			ScrollingEnabled = true,
			ScrollSpeed = 38,
			SmoothScrollingEnabled = true,
			ScrollSmoothness = 18,
			ScrollBarThickness = 5,
			ScrollBarImageColor3 = colors.subtext,
			ScrollBarImageTransparency = 0.4,
			ScrollBarAutoHide = true,
			ScrollBarFadeDelay = 0.45,
			ScrollBarFadeSpeed = 12,
			ScrollBarMinimumHandleSize = 24,
			ClipsDescendants = true,
			Active = true,
			InputSink = true,
		}, contentPanel)

		local navItems = {}
		local selectedCategory = categories[1]
		local renderCategory

		local function updateNavigation()
			for _, nav in ipairs(navItems) do
				local selected = nav.category == selectedCategory

				nav.record.color = selected and colors.surface or colors.panel
				nav.record.defaultColor = nav.record.color
				nav.record.hoverColor = colors.hover
				nav.record.defaultHoverColor = colors.hover

				nav.button.BackgroundColor3 = nav.record.color
				nav.label.TextColor3 = selected and colors.text or colors.subtext
				nav.icon.ImageColor3 = selected and colors.text or colors.subtext
				nav.accent.Visible = selected
			end
		end

		local function rowHeight(row)
			return row.description and 58 or 44
		end

		local function controlWidth(row)
			if row.kind == "switch" then
				return 34
			elseif row.kind == "dropdown" then
				return row.width or 152
			elseif row.kind == "button" then
				return row.width or 90
			elseif row.kind == "value" then
				return row.valueWidth or 220
			end

			return 0
		end

		local function rowTitle(card, row, y)
			local width = UDim2.new(1, -(16 + controlWidth(row) + 24), 0, 18)
			local position =
				UDim2.fromOffset(16, row.description and y + 7 or y + math.floor((rowHeight(row) - 18) / 2))

			local title = UI.label(card, row.title, position, width, tokens.type.body, colors.text)

			title.TextXAlignment = Enum.TextXAlignment.Left

			if row.description then
				local description = UI.label(
					card,
					row.description,
					UDim2.fromOffset(16, y + 27),
					UDim2.new(1, -(16 + controlWidth(row) + 24), 0, 28),
					tokens.type.caption,
					colors.subtext
				)

				description.TextXAlignment = Enum.TextXAlignment.Left
				description.TextYAlignment = Enum.TextYAlignment.Top
				description.TextWrapped = true
			end
		end

		local function createControl(card, row, y)
			local height = rowHeight(row)
			local width = controlWidth(row)

			if row.kind == "switch" then
				UI.switch(
					card,
					UDim2.new(1, -(width + 16), 0, y + math.floor((height - 18) / 2)),
					state[row.key] == true,
					function(value)
						state[row.key] = value

						if row.key == "diagnostics" then
							UI.shared().scriptDiagnostics = value
						end

						if row.onChanged then
							row.onChanged(value)
						end

						if row.rerender then
							task.defer(function()
								if settingsWindow and settingsWindow.Visible then
									renderCategory(selectedCategory, true)
								end
							end)
						end
					end,
					{
						width = 34,
						height = 18,
						enabledColor = colors.accent,
						disabledColor = colors.input,
					}
				)

				return
			end

			if row.kind == "dropdown" then
				local enabled = row.disabledKey == nil or not state[row.disabledKey]

				local dropdown
				local label
				local controller

				dropdown, label, controller = UI.dropdown(
					card,
					state[row.key],
					UDim2.new(1, -(width + 16), 0, y + math.floor((height - UI.metrics.inputHeight) / 2)),
					UDim2.fromOffset(width, UI.metrics.inputHeight),
					"builtin://global-icons/chevron-down.svg",
					{
						items = dropdownItems(row.items),
						showSearch = false,
						menuWidth = width,
						maxVisibleItems = 8,
						color = colors.input,
						hoverColor = colors.hover,
						pressedColor = colors.pressed,
						textColor = colors.subtext,
						menuColor = colors.panelRaised,
						borderColor = colors.border,
						borderTransparency = 0.2,
						radius = tokens.radius.sm,
						textSize = tokens.type.small,
						backdrop = true,
						backdropBlur = 14,
						backdropTransparency = 0.88,
						menuPosition = function()
							local position = dropdown.AbsolutePosition
							local size = dropdown.AbsoluteSize

							return UDim2.fromOffset(math.floor(position.X), math.floor(position.Y + size.Y + 2))
						end,
						onChanged = function(value)
							state[row.key] = value

							if row.onChanged then
								row.onChanged(value)
							end
						end,
					}
				)

				local openDropdown = controller.record.callback

				controller.record.callback = function()
					openDropdown()

					local active = shared.activeDropdown

					if active and active.controller == controller and active.menu then
						active.menu.Parent = UI.widgetOverlay()
					end
				end

				table.insert(dropdowns, controller)

				if not enabled then
					controller.record.enabled = false
					controller.record.color = colors.input
					dropdown.Active = false
					dropdown.BackgroundColor3 = colors.input
					dropdown.BackgroundTransparency = 0.25
					label.TextColor3 = colors.muted
				end

				return
			end

			if row.kind == "button" then
				UI.button(
					card,
					row.buttonText or "Open",
					UDim2.new(1, -(width + 16), 0, y + math.floor((height - UI.metrics.buttonHeight) / 2)),
					UDim2.fromOffset(width, UI.metrics.buttonHeight),
					row.callback,
					{
						color = colors.panelRaised,
						hoverColor = colors.hover,
						pressedColor = colors.pressed,
						textColor = row.danger and colors.error or colors.text,
						textSize = tokens.type.small,
						radius = tokens.radius.sm,
						border = true,
						borderColor = colors.border,
						paddingX = tokens.space.md,
					}
				)

				return
			end

			if row.kind == "value" then
				local value = UI.label(
					card,
					tostring(row.value or ""),
					UDim2.new(1, -(width + 16), 0, y),
					UDim2.fromOffset(width, height),
					tokens.type.small,
					colors.subtext
				)

				value.TextXAlignment = Enum.TextXAlignment.Right
				value.TextYAlignment = Enum.TextYAlignment.Center
			end
		end

		local function renderRow(card, row, y)
			rowTitle(card, row, y)
			createControl(card, row, y)
		end

		local function createSection(section, y)
			local sectionTitle = UI.label(
				scroller,
				section.title,
				UDim2.fromOffset(4, y),
				UDim2.new(1, -8, 0, 20),
				tokens.type.small,
				colors.subtext
			)

			sectionTitle.TextXAlignment = Enum.TextXAlignment.Left

			y += 26

			local cardHeight = 8

			for _, row in ipairs(section.rows) do
				cardHeight += rowHeight(row)
			end

			local card = UI.card(scroller, UDim2.fromOffset(0, y), UDim2.new(1, -8, 0, cardHeight), {
				color = colors.surface,
				radius = tokens.radius.md,
				border = true,
				borderColor = colors.border,
				borderTransparency = 0.35,
			})

			local rowY = 4

			for index, row in ipairs(section.rows) do
				renderRow(card, row, rowY)

				if index < #section.rows then
					local separator = UI.separator(
						card,
						UDim2.fromOffset(16, rowY + rowHeight(row) - 1),
						UDim2.new(1, -32, 0, 1),
						colors.border
					)

					separator.BackgroundTransparency = 0.5
				end

				rowY += rowHeight(row)
			end

			return y + cardHeight + 18
		end

		local function layoutNavigation(autoselect)
			local query = string.lower(search.Text or "")
			local y = 60
			local firstMatch
			local selectedVisible = false

			for _, nav in ipairs(navItems) do
				local matches = query == "" or string.find(string.lower(nav.category.name), query, 1, true) ~= nil

				nav.button.Visible = matches

				if matches then
					nav.button.Position = UDim2.fromOffset(INSET, y)
					y += 33

					firstMatch = firstMatch or nav.category

					if nav.category == selectedCategory then
						selectedVisible = true
					end
				end
			end

			if autoselect and not selectedVisible and firstMatch then
				renderCategory(firstMatch)
			end
		end

		renderCategory = function(category, keepScroll)
			local canvasPosition = keepScroll and scroller.CanvasPosition or Vector2.new(0, 0)

			selectedCategory = category

			closeDropdowns()

			titleLabel.Text = category.name
			descriptionLabel.Text = category.description or ""

			UI.clear(scroller)

			local y = 4

			for _, section in ipairs(category.sections) do
				y = createSection(section, y)
			end

			scroller.CanvasSize = UDim2.new(0, 0, 0, y)
			scroller.CanvasPosition = canvasPosition

			updateNavigation()
		end

		for _, category in ipairs(categories) do
			local button, label, record = UI.button(
				sidebar,
				category.name,
				UDim2.fromOffset(INSET, 0),
				UDim2.new(1, -INSET * 2, 0, 30),
				function()
					renderCategory(category)
				end,
				{
					color = colors.panel,
					hoverColor = colors.hover,
					pressedColor = colors.pressed,
					textColor = colors.subtext,
					textSize = tokens.type.small,
					radius = tokens.radius.sm,
					border = false,
					paddingX = 32,
				}
			)

			local icon = UI.image(button, category.icon, UDim2.fromOffset(9, 8), UDim2.fromOffset(14, 14))
			icon.ImageColor3 = colors.subtext

			local accent = UI.frame(button, UDim2.fromOffset(3, 7), UDim2.fromOffset(2, 16), colors.accent, 1)
			accent.Visible = false

			table.insert(navItems, {
				category = category,
				button = button,
				label = label,
				record = record,
				icon = icon,
				accent = accent,
			})
		end

		local logoutButton = UI.button(
			sidebar,
			"Log out",
			UDim2.fromOffset(INSET, 0),
			UDim2.new(1, -INSET * 2, 0, 30),
			function()
				performLogout(session)
			end,
			{
				color = colors.panel,
				hoverColor = colors.hover,
				pressedColor = colors.pressed,
				textColor = colors.error,
				textSize = tokens.type.small,
				radius = tokens.radius.sm,
				border = false,
				paddingX = 32,
			}
		)

		logoutButton.Position = UDim2.new(0, INSET, 1, -40)

		local logoutIcon = UI.image(logoutButton, ICONS.power, UDim2.fromOffset(9, 8), UDim2.fromOffset(14, 14))
		logoutIcon.ImageColor3 = colors.error

		scroller:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			local active = shared.activeDropdown

			if not active then
				return
			end

			for _, controller in ipairs(dropdowns) do
				if active.controller == controller then
					controller:Close()
					return
				end
			end
		end)

		search.TextChanged:Connect(function()
			layoutNavigation(true)
		end)

		search.FocusLost:Connect(function()
			layoutNavigation(true)
		end)

		layoutNavigation(false)
		renderCategory(selectedCategory)
	end

	local function ensureWindow()
		if settingsWindow then
			return
		end

		local screen = workspace:GetWindowDimensions()
		local screenWidth = screen and screen.X or 960
		local screenHeight = screen and screen.Y or 720
		local width = math.clamp(screenWidth - 120, 660, 820)
		local height = math.clamp(screenHeight - 120, 500, 620)
		local position = UDim2.fromOffset(
			math.max(0, math.floor((screenWidth - width) / 2)),
			math.max(0, math.floor((screenHeight - height) / 2))
		)

		local panel, content = UI.window("MatrixSettings", position, UDim2.fromOffset(width, height), "Settings", {
			closable = true,
			onClose = function(window)
				closeDropdowns()
				window.Visible = false
				settingsOpen = false
			end,
		})

		panel.Parent = UI.widgetOverlay()
		panel.Visible = false

		settingsWindow = panel
		settingsPage = content
	end

	local function open()
		local session = shared.CurrentSession

		if not session then
			return
		end

		ensureWindow()

		if settingsOpen then
			settingsWindow.Visible = true
			return
		end

		buildSettings(settingsPage, session)

		settingsOpen = true
		settingsWindow.Visible = true
	end

	profileButton, _, image = UI.iconButton(
		parent,
		"assets/icons/Play.svg",
		UDim2.new(1, -5, 0, 5),
		UDim2.fromOffset(25, 25),
		function()
			if shared.CurrentSession then
				open()
				return
			end

			Auth.Login({
				onSuccess = function(session)
					shared.CurrentSession = session

					if tooltip then
						tooltip:SetText(session.userId)
					end

					task.spawn(function()
						SetImage(session, image)
					end)
				end,
			})
		end
	)

	image.Size = UDim2.new(1, 0, 1, 0)
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	profileButton.ClipsDescendants = true
	image.Position = UDim2.new(0.5, 0, 0.5, 0)

	local session = shared.CurrentSession

	tooltip = UI.tooltip(profileButton, session and session.userId or "Not logged in", {
		placement = "below",
		hoverDelay = 0.35,
	})

	if session then
		SetImage(session, image)
	end

	profileButton.AnchorPoint = Vector2.new(1, 0)
end

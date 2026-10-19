local Auth = require("@internal/auth")
local UI = require("@internal/editor_ui")
local Matrix = require("@internal/matrix")
local http = game:GetService("HttpService")

shared.CurrentSession = nil

local FONT_BOLD = "builtin://fonts/Montserrat-Bold.ttf"
local FONT_MEDIUM = "builtin://fonts/Montserrat-Medium.ttf"
local FONT_REGULAR = "builtin://fonts/Montserrat-Regular.ttf"

local function svgIcon(body)
	return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='24' height='24' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'>"
		.. body
		.. "</svg>"
end

local ICONS = {
	logo = svgIcon(
		"<path d='M21 8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16Z'/><path d='m3.3 7 8.7 5 8.7-5'/><path d='M12 22V12'/>"
	),
	settings = svgIcon(
		"<path d='M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z'/><circle cx='12' cy='12' r='3'/>"
	),
	user = svgIcon("<path d='M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2'/><circle cx='12' cy='7' r='4'/>"),
	bell = svgIcon(
		"<path d='M10.268 21a2 2 0 0 0 3.464 0'/><path d='M3.262 15.326A1 1 0 0 0 4 17h16a1 1 0 0 0 .74-1.673C19.41 13.956 18 12.499 18 8A6 6 0 0 0 6 8c0 4.499-1.411 5.956-2.738 7.326'/>"
	),
	monitor = svgIcon(
		"<rect width='20' height='14' x='2' y='3' rx='2'/><line x1='8' x2='16' y1='21' y2='21'/><line x1='12' x2='12' y1='17' y2='21'/>"
	),
	smile = svgIcon(
		"<circle cx='12' cy='12' r='10'/><path d='M8 14s1.5 2 4 2 4-2 4-2'/><line x1='9' x2='9.01' y1='9' y2='9'/><line x1='15' x2='15.01' y1='9' y2='9'/>"
	),
	terminal = svgIcon("<polyline points='4 17 10 11 4 5'/><line x1='12' x2='20' y1='19' y2='19'/>"),
	info = svgIcon("<circle cx='12' cy='12' r='10'/><path d='M12 16v-4'/><path d='M12 8h.01'/>"),
	power = svgIcon("<path d='M12 2v10'/><path d='M18.4 6.6a9 9 0 1 1-12.77.04'/>"),
	x = svgIcon("<path d='M18 6 6 18'/><path d='m6 6 12 12'/>"),
	check = svgIcon("<path d='M20 6 9 17l-5-5'/>"),
	chevronDown = svgIcon("<path d='m6 9 6 6 6-6'/>"),
	chevronUp = svgIcon("<path d='m18 15-6-6-6 6'/>"),
}

local palette = {
	window = Color3.fromRGB(35, 33, 37),
	sidebar = Color3.fromRGB(35, 33, 37),
	content = Color3.fromRGB(43, 41, 46),
	card = Color3.fromRGB(51, 49, 55),
	menu = Color3.fromRGB(55, 52, 60),

	input = Color3.fromRGB(63, 60, 69),
	inputHover = Color3.fromRGB(70, 67, 77),
	inputPressed = Color3.fromRGB(58, 55, 64),
	inputMuted = Color3.fromRGB(58, 55, 63),

	border = Color3.fromRGB(64, 61, 69),
	borderStrong = Color3.fromRGB(80, 77, 88),

	selected = Color3.fromRGB(60, 57, 66),
	hover = Color3.fromRGB(55, 52, 60),
	pressed = Color3.fromRGB(48, 46, 52),

	text = Color3.fromRGB(242, 240, 244),
	subtext = Color3.fromRGB(176, 171, 181),
	muted = Color3.fromRGB(128, 123, 135),

	accent = Color3.fromRGB(124, 108, 242),
	accentHover = Color3.fromRGB(138, 123, 247),
	switchOff = Color3.fromRGB(73, 70, 80),
	switchOffHover = Color3.fromRGB(82, 79, 90),

	danger = Color3.fromRGB(239, 103, 103),
	dangerHover = Color3.fromRGB(58, 42, 45),
}

local state = {
	systemTheme = true,
	lightTheme = "Light",
	darkTheme = "Dark",
	theme = "Light",
	monochrome = false,
	twitterEmoji = true,
	pageZoom = 100,
	hour24 = false,
	dateFormat = "19 Oct 2026",
	enterNewline = false,
	tabSpaces = true,
	tabSize = "4",

	rememberSession = true,

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

local function makeLabel(parent, text, position, size, textSize, color, font)
	local label = UI.label(parent, text, position, size, textSize, color)

	if font then
		label.Font = font
	end

	return label
end

local function SetImage(session, image)
	local ok, profile = Matrix.getProfile(session)

	if not ok or not profile.avatarUrl then
		return
	end

	local url = Matrix.mxcToHttp(session.homeserver, profile.avatarUrl, {
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

local function buildCategories(session, onLogout)
	local deviceId = session and session.deviceId or "Unknown"

	return {
		{
			name = "General",
			icon = ICONS.settings,
			sections = {
				{
					title = "Appearance",
					rows = {
						{
							kind = "switch",
							key = "systemTheme",
							title = "System Theme",
							description = "Choose between light and dark theme based on system preference.",
							height = 53,
							rerender = true,
						},
						{
							kind = "themes",
							height = 51,
						},
						{
							kind = "dropdown",
							key = "theme",
							title = "Theme",
							description = "Theme to use when system theme is not enabled.",
							items = { "Light", "Dark" },
							width = 80,
							height = 64,
							disabledKey = "systemTheme",
						},
						{
							kind = "switch",
							key = "monochrome",
							title = "Monochrome Mode",
							height = 49,
						},
						{
							kind = "switch",
							key = "twitterEmoji",
							title = "Twitter Emoji",
							height = 49,
						},
						{
							kind = "zoom",
							key = "pageZoom",
							title = "Page Zoom",
							height = 58,
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
							height = 50,
						},
						{
							kind = "dropdown",
							key = "dateFormat",
							title = "Date Format",
							items = { "19 Oct 2026", "Oct 19, 2026", "2026-10-19", "19/10/2026" },
							width = 128,
							height = 50,
						},
					},
				},
				{
					title = "Editor",
					rows = {
						{
							kind = "switch",
							key = "enterNewline",
							title = "ENTER for Newline",
							height = 50,
						},
						{
							kind = "switch",
							key = "tabSpaces",
							title = "Tab inserts spaces",
							height = 50,
						},
						{
							kind = "dropdown",
							key = "tabSize",
							title = "Tab Size",
							items = { "2", "4", "8" },
							width = 80,
							height = 50,
						},
					},
				},
			},
		},

		{
			name = "Account",
			icon = ICONS.user,
			sections = {
				{
					title = "Profile",
					rows = {
						{
							kind = "value",
							title = "Matrix ID",
							value = session and session.userId or "Not logged in",
							valueWidth = 250,
							height = 50,
						},
						{
							kind = "value",
							title = "Homeserver",
							value = session and session.homeserver or "Unknown",
							valueWidth = 250,
							height = 50,
						},
						{
							kind = "value",
							title = "Device ID",
							value = deviceId,
							valueWidth = 250,
							height = 50,
						},
					},
				},
				{
					title = "Session",
					rows = {
						{
							kind = "switch",
							key = "rememberSession",
							title = "Remember this session",
							description = "Keep your Matrix account signed in between launches.",
							height = 58,
						},
						{
							kind = "button",
							title = "Log out",
							description = "Sign out of this Matrix account.",
							buttonText = "Log out",
							width = 90,
							height = 56,
							danger = true,
							callback = onLogout,
						},
					},
				},
			},
		},

		{
			name = "Notifications",
			icon = ICONS.bell,
			sections = {
				{
					title = "Messages",
					rows = {
						{
							kind = "switch",
							key = "notifyDirect",
							title = "Direct messages",
							description = "Notify me when a direct message arrives.",
							height = 56,
						},
						{
							kind = "switch",
							key = "notifyMentions",
							title = "Mentions",
							description = "Notify me when someone mentions my name.",
							height = 56,
						},
						{
							kind = "switch",
							key = "notifyInvites",
							title = "Room invites",
							description = "Notify me when I am invited to a room.",
							height = 56,
						},
					},
				},
				{
					title = "Alerts",
					rows = {
						{
							kind = "switch",
							key = "notifySounds",
							title = "Notification sounds",
							height = 50,
						},
						{
							kind = "dropdown",
							key = "notificationSound",
							title = "Sound",
							items = { "Chime", "Ping", "Pop", "None" },
							width = 110,
							height = 50,
						},
					},
				},
			},
		},

		{
			name = "Devices",
			icon = ICONS.monitor,
			sections = {
				{
					title = "Current Device",
					rows = {
						{
							kind = "value",
							title = "Device ID",
							value = deviceId,
							valueWidth = 250,
							height = 50,
						},
						{
							kind = "switch",
							key = "verifyDevices",
							title = "Verify new devices",
							description = "Ask for verification when a new device signs in.",
							height = 56,
						},
						{
							kind = "switch",
							key = "offlineDevices",
							title = "Show offline devices",
							description = "Include devices that are not currently connected.",
							height = 56,
						},
					},
				},
			},
		},

		{
			name = "Emojis & Stickers",
			icon = ICONS.smile,
			sections = {
				{
					title = "Emoji",
					rows = {
						{
							kind = "switch",
							key = "emojiAutocomplete",
							title = "Emoji autocomplete",
							description = "Suggest emoji while typing a colon and a name.",
							height = 56,
						},
						{
							kind = "switch",
							key = "largeEmoji",
							title = "Large emoji",
							description = "Display emoji-only messages at a larger size.",
							height = 56,
						},
						{
							kind = "dropdown",
							key = "emojiSet",
							title = "Emoji set",
							items = { "Twitter", "Native", "Twemoji" },
							width = 110,
							height = 50,
						},
					},
				},
				{
					title = "Stickers",
					rows = {
						{
							kind = "switch",
							key = "stickerSuggestions",
							title = "Sticker suggestions",
							description = "Show sticker suggestions while composing messages.",
							height = 56,
						},
					},
				},
			},
		},

		{
			name = "Developer Tools",
			icon = ICONS.terminal,
			sections = {
				{
					title = "Development",
					rows = {
						{
							kind = "switch",
							key = "developerMode",
							title = "Developer mode",
							description = "Expose additional Matrix debugging tools.",
							height = 56,
						},
						{
							kind = "switch",
							key = "syncLogging",
							title = "Matrix sync logging",
							description = "Print sync responses to the output console.",
							height = 56,
						},
						{
							kind = "switch",
							key = "debugLabels",
							title = "Show debug labels",
							description = "Display internal identifiers in the interface.",
							height = 56,
						},
					},
				},
			},
		},

		{
			name = "About",
			icon = ICONS.info,
			sections = {
				{
					title = "Kinemium",
					rows = {
						{
							kind = "value",
							title = "Version",
							value = "Development build",
							valueWidth = 200,
							height = 50,
						},
						{
							kind = "value",
							title = "Matrix profile",
							value = session and session.userId or "Not logged in",
							valueWidth = 250,
							height = 50,
						},
						{
							kind = "button",
							title = "Documentation",
							description = "Open the Kinemium documentation.",
							buttonText = "Open",
							width = 80,
							height = 56,
							callback = function()
								print("Open documentation")
							end,
						},
						{
							kind = "button",
							title = "Report an issue",
							description = "Open the Kinemium issue tracker.",
							buttonText = "Open",
							width = 80,
							height = 56,
							callback = function()
								print("Open issue tracker")
							end,
						},
					},
				},
			},
		},
	}
end

local function buildSettings(content, controller, width, height, session, onLogout)
	local SIDEBAR_WIDTH = 228
	local CONTENT_WIDTH = width - SIDEBAR_WIDTH
	local CARD_WIDTH = CONTENT_WIDTH - 28

	local sidebar = UI.frame(content, UDim2.fromOffset(0, 0), UDim2.fromOffset(SIDEBAR_WIDTH, height), palette.sidebar)

	local contentPane =
		UI.frame(content, UDim2.fromOffset(SIDEBAR_WIDTH, 0), UDim2.new(1, -SIDEBAR_WIDTH, 1, 0), palette.content)

	contentPane.ClipsDescendants = false

	UI.separator(content, UDim2.fromOffset(SIDEBAR_WIDTH - 1, 0), UDim2.fromOffset(1, height), palette.border).BackgroundTransparency =
		0.35

	local logo = UI.image(sidebar, ICONS.logo, UDim2.fromOffset(17, 14), UDim2.fromOffset(28, 28))
	logo.ImageColor3 = palette.text

	local sidebarTitle =
		makeLabel(sidebar, "Settings", UDim2.fromOffset(54, 11), UDim2.fromOffset(160, 34), 19, palette.text, FONT_BOLD)
	sidebarTitle.TextYAlignment = Enum.TextYAlignment.Center

	local closeButton = UI.button(contentPane, "", UDim2.new(1, -40, 0, 14), UDim2.fromOffset(28, 28), function()
		controller:Close("close")
	end, {
		color = palette.content,
		hoverColor = palette.hover,
		pressedColor = palette.pressed,
		radius = 6,
		border = false,
		paddingX = 0,
	})

	local closeIcon = UI.image(closeButton, ICONS.x, UDim2.fromOffset(8, 8), UDim2.fromOffset(12, 12))
	closeIcon.ImageColor3 = palette.subtext

	local titleLabel = makeLabel(
		contentPane,
		"General",
		UDim2.fromOffset(16, 15),
		UDim2.new(1, -80, 0, 30),
		20,
		palette.text,
		FONT_BOLD
	)
	titleLabel.TextYAlignment = Enum.TextYAlignment.Center

	local scroller = UI.create("ScrollingFrame", {
		Name = "SettingsScroller",
		Position = UDim2.fromOffset(0, 64),
		Size = UDim2.new(1, 0, 1, -64),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasPosition = Vector2.new(0, 0),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ScrollingEnabled = true,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = palette.subtext,
		ScrollBarImageTransparency = 0.4,
		ScrollBarAutoHide = true,
		ClipsDescendants = true,
	}, contentPane)

	local activeMenu = nil

	local function closeMenu()
		if activeMenu then
			activeMenu()
			activeMenu = nil
		end
	end

	local function createToggle(parent, position, value, onChanged)
		local enabled = value == true

		local track
		local record
		local knob
		local check

		track, _, record = UI.button(parent, "", position, UDim2.fromOffset(46, 24), function()
			enabled = not enabled

			track.BackgroundColor3 = enabled and palette.accent or palette.switchOff
			record.color = track.BackgroundColor3
			record.defaultColor = record.color
			record.hoverColor = enabled and palette.accentHover or palette.switchOffHover
			record.defaultHoverColor = record.hoverColor

			if knob then
				knob.Position = enabled and UDim2.new(1, -22, 0.5, -10) or UDim2.fromOffset(2, 2)
			end

			if check then
				check.Visible = enabled
			end

			if onChanged then
				onChanged(enabled)
			end
		end, {
			color = palette.switchOff,
			hoverColor = palette.switchOffHover,
			pressedColor = palette.pressed,
			radius = 12,
			border = false,
			paddingX = 0,
		})

		knob = UI.frame(track, UDim2.fromOffset(2, 2), UDim2.fromOffset(20, 20), Color3.new(1, 1, 1), 10)
		knob.Name = "Knob"

		check = UI.image(knob, ICONS.check, UDim2.fromOffset(4, 4), UDim2.fromOffset(12, 12))
		check.Name = "Check"
		check.ImageColor3 = palette.accent

		if enabled then
			track.BackgroundColor3 = palette.accent
			record.color = palette.accent
			record.defaultColor = palette.accent
			record.hoverColor = palette.accentHover
			record.defaultHoverColor = palette.accentHover
			knob.Position = UDim2.new(1, -22, 0.5, -10)
			check.Visible = true
		else
			check.Visible = false
		end

		return track
	end

	local function createDropdown(parent, value, position, size, items, onChanged, options)
		options = options or {}

		local enabled = options.enabled ~= false
		local current = value
		local menu = nil
		local catcher = nil

		local button
		local label
		local record

		local function closeThis()
			if catcher then
				catcher:Destroy()
				catcher = nil
			end

			if menu then
				menu:Destroy()
				menu = nil
			end

			if activeMenu == closeThis then
				activeMenu = nil
			end
		end

		local function openThis()
			if not enabled then
				return
			end

			if menu then
				closeThis()
				return
			end

			closeMenu()

			activeMenu = closeThis

			catcher = UI.create("TextButton", {
				Name = "DropdownCatcher",
				Position = UDim2.fromOffset(0, 0),
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Text = "",
				Active = true,
				InputSink = true,
				AutoButtonColor = false,
				ZIndex = 499998,
			}, contentPane)

			catcher.MouseButton1Click:Connect(closeThis)

			local menuHeight = #items * 30 + 8
			local absolute = button.AbsolutePosition - contentPane.AbsolutePosition
			local menuX = absolute.X
			local menuY = absolute.Y + size.Y.Offset + 3

			if menuY + menuHeight > contentPane.AbsoluteSize.Y - 8 then
				menuY = absolute.Y - menuHeight - 3
			end

			menuX = math.clamp(menuX, 6, math.max(6, contentPane.AbsoluteSize.X - size.X.Offset - 6))
			menuY = math.max(6, menuY)

			menu = UI.frame(
				contentPane,
				UDim2.fromOffset(menuX, menuY),
				UDim2.fromOffset(size.X.Offset, menuHeight),
				palette.menu,
				6
			)

			menu.Name = "DropdownMenu"
			menu.ZIndex = 499999

			UI.stroke(menu, palette.borderStrong, 1, 0.15)

			for index, item in ipairs(items) do
				local rowButton = UI.button(
					menu,
					tostring(item),
					UDim2.fromOffset(4, 4 + (index - 1) * 30),
					UDim2.new(1, -8, 0, 28),
					function()
						current = item
						label.Text = tostring(item)

						closeThis()

						if onChanged then
							onChanged(item)
						end
					end,
					{
						color = palette.menu,
						hoverColor = palette.hover,
						pressedColor = palette.pressed,
						textColor = palette.text,
						textSize = 12,
						radius = 4,
						border = false,
						paddingX = 8,
					}
				)

				rowButton.ZIndex = 500000
			end
		end

		button, label, record = UI.button(parent, tostring(value), position, size, openThis, {
			color = enabled and palette.input or palette.inputMuted,
			hoverColor = enabled and palette.inputHover or palette.inputMuted,
			pressedColor = enabled and palette.inputPressed or palette.inputMuted,
			textColor = enabled and palette.subtext or palette.muted,
			textSize = 12,
			radius = 5,
			border = true,
			borderColor = palette.border,
			paddingX = 10,
			enabled = enabled,
		})

		local chevron = UI.image(button, ICONS.chevronDown, UDim2.new(1, -19, 0.5, -5), UDim2.fromOffset(10, 10))
		chevron.ImageColor3 = enabled and palette.subtext or palette.muted

		label.Size = UDim2.new(1, -30, 1, 0)
		label.TextYAlignment = Enum.TextYAlignment.Center

		local dropdown = {
			button = button,
			label = label,
			record = record,
		}

		function dropdown:GetValue()
			return current
		end

		function dropdown:SetValue(newValue, silent)
			current = newValue
			label.Text = tostring(newValue)

			if not silent and onChanged then
				onChanged(newValue)
			end
		end

		function dropdown:Close()
			closeThis()
		end

		return dropdown
	end

	local function createNumber(parent, position, size, value, minimum, maximum, step, onChanged)
		local container = UI.frame(parent, position, size, palette.input, 5)
		container.ClipsDescendants = true

		UI.stroke(container, palette.border, 1, 0.2)

		local box = UI.create("TextBox", {
			Name = "Value",
			Position = UDim2.fromOffset(8, 0),
			Size = UDim2.new(1, -32, 1, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = tostring(value),
			TextSize = 12,
			TextColor3 = palette.text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			ClearTextOnFocus = false,
			Active = true,
			InputSink = true,
		}, container)

		local spinner =
			UI.frame(container, UDim2.new(1, -24, 0, 0), UDim2.fromOffset(24, size.Y.Offset), palette.input, 0)

		UI.separator(spinner, UDim2.new(0, 4, 0.5, 0), UDim2.new(1, -4, 0, 1), palette.border).BackgroundTransparency =
			0.4

		local current = tonumber(value) or minimum

		local function commit(newValue)
			current = math.clamp(newValue, minimum, maximum)
			box.Text = tostring(current)

			if onChanged then
				onChanged(current)
			end
		end

		local up = UI.create("TextButton", {
			Text = "",
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.new(1, 0, 0.5, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Active = true,
			AutoButtonColor = false,
		}, spinner)

		local upIcon = UI.image(up, ICONS.chevronUp, UDim2.fromOffset(7, 3), UDim2.fromOffset(10, 10))
		upIcon.ImageColor3 = palette.subtext

		local down = UI.create("TextButton", {
			Text = "",
			Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.new(1, 0, 0.5, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Active = true,
			AutoButtonColor = false,
		}, spinner)

		local downIcon = UI.image(down, ICONS.chevronDown, UDim2.fromOffset(7, 4), UDim2.fromOffset(10, 10))
		downIcon.ImageColor3 = palette.subtext

		up.MouseButton1Click:Connect(function()
			commit(current + step)
		end)

		down.MouseButton1Click:Connect(function()
			commit(current - step)
		end)

		box.FocusLost:Connect(function()
			local number = tonumber(box.Text)

			if not number then
				box.Text = tostring(current)
				return
			end

			commit(number)
		end)

		return container
	end

	local doLogout = function()
		if onLogout then
			onLogout(session)
		end

		controller:Close("logout")
	end

	local categories = buildCategories(session, doLogout)
	local navItems = {}
	local currentCategory = nil
	local renderCurrent = nil

	local function updateNavigation()
		for _, nav in ipairs(navItems) do
			local selected = nav.category == currentCategory

			nav.button.BackgroundColor3 = selected and palette.selected or palette.sidebar
			nav.record.color = selected and palette.selected or palette.sidebar
			nav.record.defaultColor = nav.record.color
			nav.record.hoverColor = palette.hover
			nav.record.defaultHoverColor = palette.hover
			nav.label.TextColor3 = selected and palette.text or palette.subtext
			nav.icon.ImageColor3 = selected and palette.text or palette.subtext
		end
	end

	local function rowTitle(card, row, y)
		local title

		if row.description then
			title = makeLabel(
				card,
				row.title,
				UDim2.fromOffset(16, y + 10),
				UDim2.new(1, -200, 0, 20),
				14,
				palette.text,
				FONT_REGULAR
			)

			local description = makeLabel(
				card,
				row.description,
				UDim2.fromOffset(16, y + 31),
				UDim2.new(1, -200, 0, 18),
				12,
				palette.subtext,
				FONT_REGULAR
			)

			description.TextYAlignment = Enum.TextYAlignment.Center
		else
			title = makeLabel(
				card,
				row.title,
				UDim2.fromOffset(16, y),
				UDim2.new(1, -190, 0, row.height),
				14,
				palette.text,
				FONT_REGULAR
			)

			title.TextYAlignment = Enum.TextYAlignment.Center
		end

		return title
	end

	local function renderRow(card, row, y)
		rowTitle(card, row, y)

		if row.kind == "switch" then
			createToggle(
				card,
				UDim2.fromOffset(CARD_WIDTH - 16 - 46, y + math.floor((row.height - 24) / 2)),
				state[row.key],
				function(value)
					state[row.key] = value

					if row.onChanged then
						row.onChanged(value)
					end

					if row.rerender and renderCurrent then
						task.defer(function()
							if UI.isAlive(scroller) then
								renderCurrent()
							end
						end)
					end
				end
			)
		elseif row.kind == "dropdown" then
			local dropdownWidth = row.width or 100
			local enabled = row.disabledKey == nil or not state[row.disabledKey]

			createDropdown(
				card,
				state[row.key],
				UDim2.fromOffset(CARD_WIDTH - 16 - dropdownWidth, y + math.floor((row.height - 28) / 2)),
				UDim2.fromOffset(dropdownWidth, 28),
				row.items,
				function(value)
					state[row.key] = value

					if row.onChanged then
						row.onChanged(value)
					end
				end,
				{ enabled = enabled }
			)
		elseif row.kind == "themes" then
			local gap = 6
			local darkWidth = 76
			local darkLabelWidth = 82
			local lightWidth = 72
			local lightLabelWidth = 90
			local darkX = CARD_WIDTH - 16 - darkWidth
			local darkLabelX = darkX - gap - darkLabelWidth
			local lightX = darkLabelX - gap - lightWidth
			local lightLabelX = lightX - gap - lightLabelWidth
			local controlY = y + math.floor((row.height - 28) / 2)

			local lightLabel = makeLabel(
				card,
				"Light Theme:",
				UDim2.fromOffset(lightLabelX, controlY),
				UDim2.fromOffset(lightLabelWidth, 28),
				12,
				palette.subtext,
				FONT_REGULAR
			)

			lightLabel.TextXAlignment = Enum.TextXAlignment.Right
			lightLabel.TextYAlignment = Enum.TextYAlignment.Center

			local darkLabel = makeLabel(
				card,
				"Dark Theme:",
				UDim2.fromOffset(darkLabelX, controlY),
				UDim2.fromOffset(darkLabelWidth, 28),
				12,
				palette.subtext,
				FONT_REGULAR
			)

			darkLabel.TextXAlignment = Enum.TextXAlignment.Right
			darkLabel.TextYAlignment = Enum.TextYAlignment.Center

			createDropdown(
				card,
				state.lightTheme,
				UDim2.fromOffset(lightX, controlY),
				UDim2.fromOffset(lightWidth, 28),
				{ "Light", "Dark" },
				function(value)
					state.lightTheme = value
				end
			)

			createDropdown(
				card,
				state.darkTheme,
				UDim2.fromOffset(darkX, controlY),
				UDim2.fromOffset(darkWidth, 28),
				{ "Light", "Dark" },
				function(value)
					state.darkTheme = value
				end
			)
		elseif row.kind == "zoom" then
			local inputWidth = 82
			local percentWidth = 14
			local percentX = CARD_WIDTH - 10 - percentWidth
			local inputX = percentX - 6 - inputWidth
			local controlY = y + math.floor((row.height - 28) / 2)

			createNumber(
				card,
				UDim2.fromOffset(inputX, controlY),
				UDim2.fromOffset(inputWidth, 28),
				state[row.key],
				25,
				300,
				10,
				function(value)
					state[row.key] = value
				end
			)

			local percent = makeLabel(
				card,
				"%",
				UDim2.fromOffset(percentX, y + math.floor((row.height - 20) / 2)),
				UDim2.fromOffset(percentWidth, 20),
				12,
				palette.subtext,
				FONT_REGULAR
			)

			percent.TextXAlignment = Enum.TextXAlignment.Right
			percent.TextYAlignment = Enum.TextYAlignment.Center
		elseif row.kind == "value" then
			local valueWidth = row.valueWidth or 220
			local value = makeLabel(
				card,
				tostring(row.value or ""),
				UDim2.fromOffset(CARD_WIDTH - 16 - valueWidth, y),
				UDim2.fromOffset(valueWidth, row.height),
				12,
				palette.subtext,
				FONT_REGULAR
			)

			value.TextXAlignment = Enum.TextXAlignment.Right
			value.TextYAlignment = Enum.TextYAlignment.Center
		elseif row.kind == "button" then
			local buttonWidth = row.width or 90

			UI.button(
				card,
				row.buttonText or "Open",
				UDim2.fromOffset(CARD_WIDTH - 16 - buttonWidth, y + math.floor((row.height - 28) / 2)),
				UDim2.fromOffset(buttonWidth, 28),
				row.callback,
				{
					color = row.danger and palette.dangerHover or palette.input,
					hoverColor = row.danger and palette.danger or palette.inputHover,
					pressedColor = palette.inputPressed,
					textColor = row.danger and palette.danger or palette.text,
					textSize = 12,
					radius = 5,
					border = true,
					borderColor = palette.border,
					paddingX = 8,
				}
			)
		end
	end

	local function createSection(section, y)
		local sectionLabel = makeLabel(
			scroller,
			section.title,
			UDim2.fromOffset(16, y),
			UDim2.new(1, -32, 0, 18),
			13,
			palette.subtext,
			FONT_MEDIUM
		)

		sectionLabel.TextYAlignment = Enum.TextYAlignment.Center
		y += 25

		local cardHeight = 8

		for _, row in ipairs(section.rows) do
			cardHeight += row.height
		end

		local card = UI.frame(scroller, UDim2.fromOffset(16, y), UDim2.new(1, -28, 0, cardHeight), palette.card, 7)

		local rowY = 4

		for _, row in ipairs(section.rows) do
			renderRow(card, row, rowY)
			rowY += row.height
		end

		return y + cardHeight + 26
	end

	local function renderCategory(category)
		currentCategory = category

		closeMenu()

		titleLabel.Text = category.name

		UI.clear(scroller)

		local y = 22

		for _, section in ipairs(category.sections) do
			y = createSection(section, y)
		end

		scroller.CanvasPosition = Vector2.new(0, 0)
		scroller.CanvasSize = UDim2.new(0, 0, 0, y)

		updateNavigation()
	end

	renderCurrent = function()
		if currentCategory then
			renderCategory(currentCategory)
		end
	end

	local navY = 64

	for _, category in ipairs(categories) do
		local button
		local record

		button, _, record = UI.button(sidebar, "", UDim2.fromOffset(8, navY), UDim2.new(1, -16, 0, 34), function()
			renderCategory(category)
		end, {
			color = palette.sidebar,
			hoverColor = palette.hover,
			pressedColor = palette.pressed,
			radius = 6,
			border = false,
			paddingX = 0,
		})

		local icon = UI.image(button, category.icon, UDim2.fromOffset(12, 9), UDim2.fromOffset(16, 16))
		icon.ImageColor3 = palette.subtext

		local label = makeLabel(
			button,
			category.name,
			UDim2.fromOffset(36, 0),
			UDim2.new(1, -44, 1, 0),
			14,
			palette.subtext,
			FONT_REGULAR
		)

		label.TextYAlignment = Enum.TextYAlignment.Center

		table.insert(navItems, {
			category = category,
			button = button,
			record = record,
			label = label,
			icon = icon,
		})

		navY += 37
	end

	local logoutButton = UI.button(sidebar, "", UDim2.new(0, 8, 1, -50), UDim2.new(1, -16, 0, 34), doLogout, {
		color = palette.sidebar,
		hoverColor = palette.dangerHover,
		pressedColor = palette.pressed,
		radius = 6,
		border = false,
		paddingX = 0,
	})

	local logoutIcon = UI.image(logoutButton, ICONS.power, UDim2.fromOffset(12, 9), UDim2.fromOffset(16, 16))
	logoutIcon.ImageColor3 = palette.danger

	local logoutLabel = makeLabel(
		logoutButton,
		"Logout",
		UDim2.fromOffset(36, 0),
		UDim2.new(1, -44, 1, 0),
		14,
		palette.danger,
		FONT_REGULAR
	)

	logoutLabel.TextYAlignment = Enum.TextYAlignment.Center

	renderCategory(categories[1])
end

local function openSettings(session, onLogout, onClose)
	if not session then
		return
	end

	local screen = workspace:GetWindowDimensions()
	local width = math.min(800, math.max(600, (screen and screen.X or 832) - 32))
	local height = math.min(650, math.max(520, (screen and screen.Y or 671) - 32))

	return UI.prompt({
		title = "Settings",
		size = UDim2.fromOffset(width, height),
		position = UDim2.fromScale(0.5, 0.5),
		showHeader = false,
		showFooter = false,
		padding = 0,
		color = palette.window,
		radius = 10,
		border = true,
		borderColor = palette.borderStrong,
		borderTransparency = 0.35,
		shadow = true,
		shadowBlur = 30,
		shadowOffsetY = 10,
		shadowTransparency = 0.45,
		clip = true,
		destroyOnClose = true,
		closeOnBackdrop = false,
		dimTransparency = 0.55,
		screenGuiName = "MatrixSettings",
		build = function(content, controller)
			buildSettings(content, controller, width, height, session, onLogout)
		end,
		onClose = function()
			if onClose then
				onClose()
			end
		end,
	})
end

return function(parent)
	local id = ""
	local tooltip
	local profileButton, _, image
	local clicked = false
	local settingsOpen = false

	local function handleLogout(session)
		shared.CurrentSession = nil
		settingsOpen = false

		image.Image = "assets/icons/Play.svg"

		if tooltip then
			tooltip:SetText("Not logged in")
		end

		task.spawn(function()
			if session then
				Matrix.logout(session)
			end
		end)
	end

	local function open()
		local session = shared.CurrentSession

		if not session then
			return
		end

		if settingsOpen then
			return
		end

		settingsOpen = true

		openSettings(session, handleLogout, function()
			settingsOpen = false
		end)
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

			if clicked then
				return
			end

			clicked = true

			local controller = Auth.Login({
				onSuccess = function(session)
					shared.CurrentSession = session
					clicked = false

					id = session.userId

					if tooltip then
						tooltip:SetText(id)
					end

					SetImage(session, image)

					task.defer(function()
						open()
					end)
				end,
			})

			clicked = false

			return controller
		end
	)

	image.Size = UDim2.new(1, 0, 1, 0)
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.ClipsDescendants = true
	image.Position = UDim2.new(0.5, 0, 0.5, 0)

	tooltip = UI.tooltip(profileButton, "Not logged in", {
		placement = "below",
		hoverDelay = 0.35,
	})

	profileButton.AnchorPoint = Vector2.new(1, 0)
end

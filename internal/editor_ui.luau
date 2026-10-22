local UI = {}

local StudioThemeService = game:GetService("StudioThemeService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local shared = {
	buttons = {},
	root = nil,
	background = nil,
	windows = {},
	windowControllers = {},
	scriptDiagnostics = true,

	themeObjects = setmetatable({}, { __mode = "k" }),
	themeBindings = setmetatable({}, { __mode = "k" }),
	themeFontFaces = setmetatable({}, { __mode = "k" }),
	themes = {},
	themeOrder = {},
	themeListeners = {},
	themeName = "Dark",
	trackedRoots = setmetatable({}, { __mode = "k" }),
}
local MIN_SPAN = 0.0005
local MAX_TICKS = 16
local THEME_ANIMATION_DURATION = 0.24
local EMPTY_MAP = {}

local function tooltipLerp(a, b, t)
	return a + (b - a) * t
end

local function tooltipSmoothTowards(current, target, speed, dt)
	local t = 1 - math.exp(-speed * dt)

	return tooltipLerp(current, target, t)
end

local function copyTable(source)
	local result = {}

	for key, value in pairs(source) do
		result[key] = value
	end

	return result
end

UI.tokens = {
	color = {
		canvas = Color3.new(
			StudioThemeService.SelectedTheme.BaseColor.R,
			StudioThemeService.SelectedTheme.BaseColor.G,
			StudioThemeService.SelectedTheme.BaseColor.B
		),

		panel = Color3.new(
			StudioThemeService.SelectedTheme.BgColor.R,
			StudioThemeService.SelectedTheme.BgColor.G,
			StudioThemeService.SelectedTheme.BgColor.B
		),

		panelRaised = Color3.new(
			StudioThemeService.SelectedTheme.SecondaryColor.R,
			StudioThemeService.SelectedTheme.SecondaryColor.G,
			StudioThemeService.SelectedTheme.SecondaryColor.B
		),

		surface = Color3.new(
			StudioThemeService.SelectedTheme.ThirdColor.R,
			StudioThemeService.SelectedTheme.ThirdColor.G,
			StudioThemeService.SelectedTheme.ThirdColor.B
		),

		surfaceAlt = Color3.new(
			StudioThemeService.SelectedTheme.SecondaryColor.R,
			StudioThemeService.SelectedTheme.SecondaryColor.G,
			StudioThemeService.SelectedTheme.SecondaryColor.B
		),

		rowEven = Color3.new(
			StudioThemeService.SelectedTheme.AlternatingColor1.R,
			StudioThemeService.SelectedTheme.AlternatingColor1.G,
			StudioThemeService.SelectedTheme.AlternatingColor1.B
		),

		rowOdd = Color3.new(
			StudioThemeService.SelectedTheme.AlternatingColor2.R,
			StudioThemeService.SelectedTheme.AlternatingColor2.G,
			StudioThemeService.SelectedTheme.AlternatingColor2.B
		),

		hover = Color3.new(
			StudioThemeService.SelectedTheme.SecondaryColor.R,
			StudioThemeService.SelectedTheme.SecondaryColor.G,
			StudioThemeService.SelectedTheme.SecondaryColor.B
		),

		pressed = Color3.new(
			StudioThemeService.SelectedTheme.ThirdColor.R,
			StudioThemeService.SelectedTheme.ThirdColor.G,
			StudioThemeService.SelectedTheme.ThirdColor.B
		),

		input = Color3.new(
			StudioThemeService.SelectedTheme.InputColor.R,
			StudioThemeService.SelectedTheme.InputColor.G,
			StudioThemeService.SelectedTheme.InputColor.B
		),

		border = Color3.new(
			StudioThemeService.SelectedTheme.SecondaryColor.R,
			StudioThemeService.SelectedTheme.SecondaryColor.G,
			StudioThemeService.SelectedTheme.SecondaryColor.B
		),

		borderStrong = Color3.new(
			StudioThemeService.SelectedTheme.InputFocusColor.R,
			StudioThemeService.SelectedTheme.InputFocusColor.G,
			StudioThemeService.SelectedTheme.InputFocusColor.B
		),

		text = Color3.new(
			StudioThemeService.SelectedTheme.TextColor.R,
			StudioThemeService.SelectedTheme.TextColor.G,
			StudioThemeService.SelectedTheme.TextColor.B
		),

		subtext = Color3.new(
			StudioThemeService.SelectedTheme.SecondaryTextColor.R,
			StudioThemeService.SelectedTheme.SecondaryTextColor.G,
			StudioThemeService.SelectedTheme.SecondaryTextColor.B
		),

		muted = Color3.new(
			StudioThemeService.SelectedTheme.TextColorDimmed.R,
			StudioThemeService.SelectedTheme.TextColorDimmed.G,
			StudioThemeService.SelectedTheme.TextColorDimmed.B
		),

		accent = Color3.new(
			StudioThemeService.SelectedTheme.AccentColor.R,
			StudioThemeService.SelectedTheme.AccentColor.G,
			StudioThemeService.SelectedTheme.AccentColor.B
		),

		accentSoft = Color3.new(
			StudioThemeService.SelectedTheme.SecondaryColor.R,
			StudioThemeService.SelectedTheme.SecondaryColor.G,
			StudioThemeService.SelectedTheme.SecondaryColor.B
		),

		selection = Color3.new(
			StudioThemeService.SelectedTheme.AccentColor.R,
			StudioThemeService.SelectedTheme.AccentColor.G,
			StudioThemeService.SelectedTheme.AccentColor.B
		),

		selectionHover = Color3.new(
			StudioThemeService.SelectedTheme.AccentColor.R,
			StudioThemeService.SelectedTheme.AccentColor.G,
			StudioThemeService.SelectedTheme.AccentColor.B
		),

		focus = Color3.new(
			StudioThemeService.SelectedTheme.InputFocusColor.R,
			StudioThemeService.SelectedTheme.InputFocusColor.G,
			StudioThemeService.SelectedTheme.InputFocusColor.B
		),

		warning = Color3.fromRGB(224, 168, 74),

		error = Color3.fromRGB(231, 91, 91),

		success = Color3.fromRGB(81, 184, 122),
	},

	space = { xs = 3, sm = 5, md = 8, lg = 12 },
	radius = { xs = 3, sm = 4, md = 6 },
	type = { caption = 11, small = 12, body = 13, title = 14 },
	font = { family = "builtin://fonts/Montserrat-Regular.ttf" },
}

local colors = UI.tokens.color

local function themedFont(font)
	if not font or not font.family then
		return nil
	end

	if font.weight then
		local ok, face = pcall(Font.new, font.family, font.weight)

		if ok then
			return face
		end
	end

	local ok, face = pcall(Font.new, font.family)

	return ok and face or nil
end

local function fontFaceKey(face)
	if not face then
		return nil
	end

	local ok, family = pcall(function()
		return face.Family
	end)

	if not ok then
		return nil
	end

	local weightOk, weight = pcall(function()
		return face.Weight
	end)

	return tostring(family) .. "|" .. tostring(weightOk and weight or "")
end

local function isAlive(instance)
	if instance == nil then
		return false
	end

	return pcall(function()
		return instance:IsDescendantOf(instance)
	end)
end

local function findContainingWindow(gui)
	local current = gui

	while current do
		for _, window in pairs(shared.windows) do
			if current == window then
				return window
			end
		end

		current = current.Parent
	end

	return nil
end

UI.metrics = {

	windowHeader = 27,

	buttonHeight = 24,

	inputHeight = 24,

	tabHeight = 28,

	toolbarButton = 30,

	treeRow = 20,

	propertyRow = 22,

	sectionRow = 23,

	panelInset = 6,
}

UI.colors = {

	base = UI.tokens.color.canvas,

	panel = UI.tokens.color.panel,

	secondary = UI.tokens.color.panelRaised,

	hover = UI.tokens.color.hover,

	pressed = UI.tokens.color.pressed,

	input = UI.tokens.color.input,

	line = UI.tokens.color.border,

	text = UI.tokens.color.text,

	subtext = UI.tokens.color.subtext,

	muted = UI.tokens.color.muted,

	accent = UI.tokens.color.accent,

	selection = UI.tokens.color.selection,

	warning = UI.tokens.color.warning,

	error = UI.tokens.color.error,
}

local function assign(object, properties)
	for key, value in pairs(properties or {}) do
		local ok, message = pcall(function()
			object[key] = value
		end)

		if not ok then
			error(object.ClassName .. "." .. key .. ": " .. tostring(message))
		end
	end

	return object
end

function UI.track(object)
	if
		object
		and (
			object:IsA("GuiObject")
			or object:IsA("UIBase")
			or object:IsA("UICorner")
			or object:IsA("UIStroke")
			or object:IsA("UIGradient")
			or object:IsA("UIShadow")
			or object:IsA("UIBackdrop")
		)
	then
		shared.themeObjects[object] = true
	end

	return object
end

function UI.create(className, properties, parent)
	local object = Instance.new(className)

	if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
		local face = themedFont(UI.tokens.font)

		if face then
			pcall(function()
				object.FontFace = face
			end)

			shared.themeFontFaces[object] = fontFaceKey(object.FontFace)
		end
	end

	assign(object, properties)

	if parent then
		object.Parent = parent
	end

	UI.track(object)

	if object:IsA("ScreenGui") and UI.trackRoot then
		UI.trackRoot(object)
	end

	return object
end

do
	local function systemThemeSpec()
		local theme = StudioThemeService.SelectedTheme

		return {
			color = {
				canvas = Color3.new(theme.BaseColor.R, theme.BaseColor.G, theme.BaseColor.B),
				panel = Color3.new(theme.BgColor.R, theme.BgColor.G, theme.BgColor.B),
				panelRaised = Color3.new(theme.SecondaryColor.R, theme.SecondaryColor.G, theme.SecondaryColor.B),
				surface = Color3.new(theme.ThirdColor.R, theme.ThirdColor.G, theme.ThirdColor.B),
				surfaceAlt = Color3.new(theme.SecondaryColor.R, theme.SecondaryColor.G, theme.SecondaryColor.B),
				rowEven = Color3.new(theme.AlternatingColor1.R, theme.AlternatingColor1.G, theme.AlternatingColor1.B),
				rowOdd = Color3.new(theme.AlternatingColor2.R, theme.AlternatingColor2.G, theme.AlternatingColor2.B),
				hover = Color3.new(theme.SecondaryColor.R, theme.SecondaryColor.G, theme.SecondaryColor.B),
				pressed = Color3.new(theme.ThirdColor.R, theme.ThirdColor.G, theme.ThirdColor.B),
				input = Color3.new(theme.InputColor.R, theme.InputColor.G, theme.InputColor.B),
				border = Color3.new(theme.SecondaryColor.R, theme.SecondaryColor.G, theme.SecondaryColor.B),
				borderStrong = Color3.new(theme.InputFocusColor.R, theme.InputFocusColor.G, theme.InputFocusColor.B),
				text = Color3.new(theme.TextColor.R, theme.TextColor.G, theme.TextColor.B),
				subtext = Color3.new(
					theme.SecondaryTextColor.R,
					theme.SecondaryTextColor.G,
					theme.SecondaryTextColor.B
				),
				muted = Color3.new(theme.TextColorDimmed.R, theme.TextColorDimmed.G, theme.TextColorDimmed.B),
				accent = Color3.new(theme.AccentColor.R, theme.AccentColor.G, theme.AccentColor.B),
				accentSoft = Color3.new(theme.SecondaryColor.R, theme.SecondaryColor.G, theme.SecondaryColor.B),
				selection = Color3.new(theme.AccentColor.R, theme.AccentColor.G, theme.AccentColor.B),
				selectionHover = Color3.new(theme.AccentColor.R, theme.AccentColor.G, theme.AccentColor.B),
				focus = Color3.new(theme.InputFocusColor.R, theme.InputFocusColor.G, theme.InputFocusColor.B),
				warning = Color3.fromRGB(224, 168, 74),
				error = Color3.fromRGB(231, 91, 91),
				success = Color3.fromRGB(81, 184, 122),
			},
			space = { xs = 3, sm = 5, md = 8, lg = 12 },
			radius = {
				xs = 3,
				sm = theme.ButtonCornerRadius or 4,
				md = theme.CornerRadius or 6,
			},
			type = { caption = 11, small = 12, body = 13, title = 14 },
			font = { family = "builtin://fonts/Montserrat-Regular.ttf" },
		}
	end

	local function syncLegacyColors()
		local tokens = UI.tokens.color

		UI.colors.base = tokens.canvas
		UI.colors.panel = tokens.panel
		UI.colors.secondary = tokens.panelRaised
		UI.colors.hover = tokens.hover
		UI.colors.pressed = tokens.pressed
		UI.colors.input = tokens.input
		UI.colors.line = tokens.border
		UI.colors.text = tokens.text
		UI.colors.subtext = tokens.subtext
		UI.colors.muted = tokens.muted
		UI.colors.accent = tokens.accent
		UI.colors.selection = tokens.selection
		UI.colors.warning = tokens.warning
		UI.colors.error = tokens.error
	end

	local function packColor(color)
		return math.floor(color.R * 255 + 0.5) * 65536
			+ math.floor(color.G * 255 + 0.5) * 256
			+ math.floor(color.B * 255 + 0.5)
	end

	local BACKGROUND_KEYS = {
		"canvas",
		"panel",
		"panelRaised",
		"accentSoft",
		"surface",
		"surfaceAlt",
		"input",
		"rowEven",
		"rowOdd",
		"accent",
		"selection",
		"selectionHover",
		"hover",
		"pressed",
		"muted",
		"border",
		"borderStrong",
		"text",
		"subtext",
		"error",
		"warning",
		"success",
	}

	local TEXT_KEYS = { "text", "subtext", "muted", "accent", "error", "warning", "success", "selection" }

	local STROKE_KEYS = { "border", "borderStrong", "focus", "accent", "selection", "muted" }

	local IMAGE_KEYS = { "text", "subtext", "muted", "accent", "warning", "error", "success" }

	local PLACEHOLDER_KEYS = { "muted", "subtext" }

	local CARET_KEYS = { "accent", "focus" }

	local SELECTION_KEYS = { "selection", "selectionHover", "accent" }

	local HOVER_KEYS = { "hover", "panelRaised" }

	local PRESSED_KEYS = { "pressed", "surface" }

	local function buildKeyMap(oldColors, newColors, keys)
		local map = {}

		for _, key in ipairs(keys) do
			local oldColor = oldColors[key]
			local newColor = newColors[key]

			if oldColor and newColor and oldColor ~= newColor then
				local packed = packColor(oldColor)

				if map[packed] == nil then
					map[packed] = newColor
				end
			end
		end

		return map
	end

	local function buildNumberMap(oldValues, newValues)
		local map = {}

		for key, oldValue in pairs(oldValues) do
			local newValue = newValues[key]

			if newValue and oldValue ~= newValue then
				map[oldValue] = newValue
			end
		end

		return map
	end

	function UI.registerTheme(name, spec)
		if type(name) ~= "string" or name == "" then
			error("theme name must be a non-empty string")
		end

		spec = spec or {}

		local theme = {
			name = name,
			basedOn = spec.basedOn,
			color = copyTable(spec.color or {}),
			space = copyTable(spec.space or {}),
			radius = copyTable(spec.radius or {}),
			type = copyTable(spec.type or {}),
			font = copyTable(spec.font or {}),
		}

		if not shared.themes[name] then
			table.insert(shared.themeOrder, name)
		end

		shared.themes[name] = theme

		return theme
	end

	local function mergeSpec(base, overrides)
		local result = { color = {}, space = {}, radius = {}, type = {}, font = {} }

		for _, section in ipairs({ "color", "space", "radius", "type", "font" }) do
			for key, value in pairs(base[section] or {}) do
				result[section][key] = value
			end

			for key, value in pairs(overrides[section] or {}) do
				result[section][key] = value
			end
		end

		return result
	end

	local function resolveTheme(name)
		local theme = shared.themes[name]

		if not theme then
			return nil
		end

		local base = systemThemeSpec()

		if theme.basedOn and theme.basedOn ~= name then
			base = resolveTheme(theme.basedOn) or base
		end

		return mergeSpec(base, theme)
	end

	shared.themeOrder = {}

	UI.registerTheme("Dark", {
		color = UI.tokens.color,
	})

	UI.registerTheme("Red", {
		color = {
			canvas = Color3.fromRGB(20, 20, 20),
			panel = Color3.fromRGB(26, 26, 26),
			panelRaised = Color3.fromRGB(32, 32, 32),
			surface = Color3.fromRGB(40, 40, 40),
			surfaceAlt = Color3.fromRGB(32, 32, 32),
			rowEven = Color3.fromRGB(26, 26, 26),
			rowOdd = Color3.fromRGB(29, 29, 29),
			hover = Color3.fromRGB(43, 43, 43),
			pressed = Color3.fromRGB(50, 38, 38),
			input = Color3.fromRGB(22, 22, 22),

			border = Color3.fromRGB(52, 52, 52),
			borderStrong = Color3.fromRGB(210, 55, 55),

			text = Color3.fromRGB(235, 235, 235),
			subtext = Color3.fromRGB(185, 185, 185),
			muted = Color3.fromRGB(125, 125, 125),

			accent = Color3.fromRGB(220, 50, 50),
			accentSoft = Color3.fromRGB(55, 30, 30),
			selection = Color3.fromRGB(100, 35, 35),
			selectionHover = Color3.fromRGB(125, 42, 42),
			focus = Color3.fromRGB(245, 75, 75),

			warning = Color3.fromRGB(230, 175, 75),
			error = Color3.fromRGB(245, 85, 85),
			success = Color3.fromRGB(100, 195, 125),
		},
	})

	UI.registerTheme("Void", {
		color = {
			canvas = Color3.fromRGB(5, 5, 8),
			panel = Color3.fromRGB(9, 9, 13),
			panelRaised = Color3.fromRGB(13, 13, 19),
			surface = Color3.fromRGB(18, 18, 25),
			surfaceAlt = Color3.fromRGB(13, 13, 19),
			rowEven = Color3.fromRGB(9, 9, 13),
			rowOdd = Color3.fromRGB(11, 11, 16),
			hover = Color3.fromRGB(22, 22, 32),
			pressed = Color3.fromRGB(29, 26, 43),
			input = Color3.fromRGB(11, 11, 16),

			-- No visible outlines
			border = Color3.fromRGB(9, 9, 13),
			borderStrong = Color3.fromRGB(9, 9, 13),

			text = Color3.fromRGB(235, 235, 245),
			subtext = Color3.fromRGB(165, 165, 185),
			muted = Color3.fromRGB(100, 100, 120),

			accent = Color3.fromRGB(155, 110, 255),
			accentSoft = Color3.fromRGB(30, 22, 46),
			selection = Color3.fromRGB(48, 35, 75),
			selectionHover = Color3.fromRGB(62, 45, 95),
			focus = Color3.fromRGB(180, 145, 255),

			warning = Color3.fromRGB(245, 190, 100),
			error = Color3.fromRGB(245, 100, 125),
			success = Color3.fromRGB(100, 210, 155),
		},
	})

	UI.registerTheme("Catppuccin Mocha", {
		color = {
			canvas = Color3.fromRGB(30, 30, 46), -- Base
			panel = Color3.fromRGB(24, 24, 37), -- Mantle
			panelRaised = Color3.fromRGB(49, 50, 68), -- Surface 0
			surface = Color3.fromRGB(69, 71, 90), -- Surface 1
			surfaceAlt = Color3.fromRGB(49, 50, 68), -- Surface 0
			rowEven = Color3.fromRGB(24, 24, 37), -- Mantle
			rowOdd = Color3.fromRGB(35, 35, 52),
			hover = Color3.fromRGB(49, 50, 68), -- Surface 0
			pressed = Color3.fromRGB(69, 71, 90), -- Surface 1
			input = Color3.fromRGB(24, 24, 37), -- Mantle
			border = Color3.fromRGB(88, 91, 112), -- Surface 2
			borderStrong = Color3.fromRGB(203, 166, 247), -- Mauve
			text = Color3.fromRGB(205, 214, 244), -- Text
			subtext = Color3.fromRGB(186, 194, 222), -- Subtext 1
			muted = Color3.fromRGB(127, 132, 156), -- Overlay 0
			accent = Color3.fromRGB(203, 166, 247), -- Mauve
			accentSoft = Color3.fromRGB(69, 61, 91),
			selection = Color3.fromRGB(88, 91, 112), -- Surface 2
			selectionHover = Color3.fromRGB(108, 112, 134), -- Overlay 0
			focus = Color3.fromRGB(180, 190, 254), -- Lavender
			warning = Color3.fromRGB(249, 226, 175), -- Yellow
			error = Color3.fromRGB(243, 139, 168), -- Red
			success = Color3.fromRGB(166, 227, 161), -- Green
		},
	})

	UI.registerTheme("Night", {
		color = {
			canvas = Color3.fromRGB(12, 12, 18),
			panel = Color3.fromRGB(18, 18, 27),
			panelRaised = Color3.fromRGB(25, 25, 37),
			surface = Color3.fromRGB(31, 31, 46),
			surfaceAlt = Color3.fromRGB(25, 25, 37),
			rowEven = Color3.fromRGB(18, 18, 27),
			rowOdd = Color3.fromRGB(22, 22, 33),
			hover = Color3.fromRGB(35, 35, 51),
			pressed = Color3.fromRGB(43, 43, 62),
			input = Color3.fromRGB(23, 23, 35),
			border = Color3.fromRGB(47, 47, 65),
			borderStrong = Color3.fromRGB(124, 108, 255),
			text = Color3.fromRGB(240, 240, 250),
			subtext = Color3.fromRGB(180, 180, 200),
			muted = Color3.fromRGB(115, 115, 140),
			accent = Color3.fromRGB(124, 108, 255),
			accentSoft = Color3.fromRGB(39, 35, 65),
			selection = Color3.fromRGB(75, 65, 150),
			selectionHover = Color3.fromRGB(91, 79, 175),
			focus = Color3.fromRGB(145, 132, 255),
			warning = Color3.fromRGB(240, 180, 90),
			error = Color3.fromRGB(245, 100, 115),
			success = Color3.fromRGB(80, 205, 145),
		},
	})

	UI.registerTheme("Blue", {
		color = {
			canvas = Color3.fromRGB(30, 30, 30),
			panel = Color3.fromRGB(37, 37, 38),
			panelRaised = Color3.fromRGB(45, 45, 48),
			surface = Color3.fromRGB(51, 51, 55),
			surfaceAlt = Color3.fromRGB(45, 45, 48),
			rowEven = Color3.fromRGB(37, 37, 38),
			rowOdd = Color3.fromRGB(42, 42, 45),
			hover = Color3.fromRGB(45, 45, 48),
			pressed = Color3.fromRGB(51, 51, 55),
			input = Color3.fromRGB(60, 60, 60),
			border = Color3.fromRGB(63, 63, 70),
			borderStrong = Color3.fromRGB(0, 122, 204),
			text = Color3.fromRGB(255, 255, 255),
			subtext = Color3.fromRGB(204, 204, 204),
			muted = Color3.fromRGB(128, 128, 128),
			accent = Color3.fromRGB(0, 122, 204),
			accentSoft = Color3.fromRGB(45, 45, 48),
			selection = Color3.fromRGB(0, 122, 204),
			selectionHover = Color3.fromRGB(0, 122, 204),
			focus = Color3.fromRGB(0, 122, 204),
			warning = Color3.fromRGB(224, 168, 74),
			error = Color3.fromRGB(231, 91, 91),
			success = Color3.fromRGB(81, 184, 122),
		},
	})

	UI.registerTheme("Light", {
		color = {
			canvas = Color3.fromRGB(243, 243, 243),
			panel = Color3.fromRGB(255, 255, 255),
			panelRaised = Color3.fromRGB(236, 236, 236),
			surface = Color3.fromRGB(245, 245, 245),
			surfaceAlt = Color3.fromRGB(236, 236, 236),
			rowEven = Color3.fromRGB(255, 255, 255),
			rowOdd = Color3.fromRGB(245, 245, 245),
			hover = Color3.fromRGB(229, 229, 229),
			pressed = Color3.fromRGB(218, 218, 218),
			input = Color3.fromRGB(255, 255, 255),
			border = Color3.fromRGB(212, 212, 212),
			borderStrong = Color3.fromRGB(0, 120, 212),
			text = Color3.fromRGB(31, 31, 31),
			subtext = Color3.fromRGB(97, 97, 97),
			muted = Color3.fromRGB(138, 138, 138),
			accent = Color3.fromRGB(0, 120, 212),
			accentSoft = Color3.fromRGB(236, 236, 236),
			selection = Color3.fromRGB(204, 228, 247),
			selectionHover = Color3.fromRGB(187, 222, 251),
			focus = Color3.fromRGB(0, 120, 212),
			warning = Color3.fromRGB(183, 121, 31),
			error = Color3.fromRGB(209, 52, 56),
			success = Color3.fromRGB(16, 124, 16),
		},
	})

	function UI.getTheme()
		return shared.themeName
	end

	function UI.getThemes()
		local list = {}

		for index, name in ipairs(shared.themeOrder) do
			list[index] = name
		end

		return list
	end

	function UI.bindTheme(instance, property, key)
		if not instance then
			return instance
		end

		local bindings = shared.themeBindings[instance]

		if not bindings then
			bindings = {}
			shared.themeBindings[instance] = bindings
		end

		for _, binding in ipairs(bindings) do
			if binding.property == property then
				binding.key = key

				return instance
			end
		end

		table.insert(bindings, { property = property, key = key })

		return instance
	end

	local function resolveToken(key)
		local value = UI.tokens

		for part in string.gmatch(key, "[^%.]+") do
			if type(value) ~= "table" then
				return nil
			end

			value = value[part]
		end

		return value
	end

	local function applyColorProperty(instance, property, colorMap)
		local ok, value = pcall(function()
			return instance[property]
		end)

		if not ok or typeof(value) ~= "Color3" then
			return
		end

		local mapped = colorMap[packColor(value)]

		if mapped then
			pcall(function()
				instance[property] = mapped
			end)
		end
	end

	local function applyFont(instance, font)
		if not font or not font.family then
			return
		end

		local previousKey = shared.themeFontFaces[instance]

		if previousKey == nil then
			return
		end

		local ok, currentKey = pcall(function()
			return fontFaceKey(instance.FontFace)
		end)

		if not ok or currentKey ~= previousKey then
			shared.themeFontFaces[instance] = nil

			return
		end

		local face = themedFont(font)

		if not face then
			return
		end

		pcall(function()
			instance.FontFace = face
		end)

		shared.themeFontFaces[instance] = fontFaceKey(instance.FontFace)
	end

	local function applyGradient(gradient, colorMap)
		local ok, sequence = pcall(function()
			return gradient.ColorSequence
		end)

		if not ok or typeof(sequence) ~= "ColorSequence" then
			return
		end

		local keypoints = {}

		for index, keypoint in ipairs(sequence.Keypoints) do
			keypoints[index] =
				ColorSequenceKeypoint.new(keypoint.Time, colorMap[packColor(keypoint.Value)] or keypoint.Value)
		end

		pcall(function()
			gradient.ColorSequence = ColorSequence.new(keypoints)
		end)
	end

	local function applyToInstance(instance, maps, radiusMap, typeMap, font)
		if instance == nil then
			return
		end

		if not isAlive(instance) then
			shared.themeObjects[instance] = nil
			shared.themeFontFaces[instance] = nil

			return
		end

		local className = instance.ClassName

		if instance:IsA("GuiObject") then
			applyColorProperty(instance, "BackgroundColor3", maps.background)
			applyColorProperty(instance, "BorderColor3", maps.stroke)
		end

		if instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
			applyColorProperty(instance, "ImageColor3", maps.image)

			if instance.ImageColor3 == Color3.new(1, 1, 1) then
				local image = instance.Image

				if
					type(image) == "string"
					and (string.find(image, "^builtin://") ~= nil or string.find(image, "^data:image/svg") ~= nil)
				then
					instance.ImageColor3 = UI.tokens.color.text
				end
			end
		end

		if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
			applyColorProperty(instance, "TextColor3", maps.text)
			applyColorProperty(instance, "TextStrokeColor3", maps.text)
			applyFont(instance, font)

			local newSize = typeMap[instance.TextSize]

			if newSize then
				pcall(function()
					instance.TextSize = newSize
				end)
			end
		end

		if instance:IsA("TextBox") then
			applyColorProperty(instance, "PlaceholderColor3", maps.placeholder)
			applyColorProperty(instance, "CaretColor3", maps.caret)
			applyColorProperty(instance, "SelectionColor3", maps.selection)
			applyColorProperty(instance, "FocusColor3", maps.focus)
		end

		if instance:IsA("ScrollingFrame") then
			applyColorProperty(instance, "ScrollBarImageColor3", maps.stroke)
		end

		if className == "UICorner" then
			local ok, corner = pcall(function()
				return instance.CornerRadius
			end)

			if ok and typeof(corner) == "UDim" and corner.Scale == 0 then
				local mapped = radiusMap[corner.Offset]

				if mapped then
					pcall(function()
						instance.CornerRadius = UDim.new(0, mapped)
					end)
				end
			end
		elseif className == "UIStroke" then
			applyColorProperty(instance, "Color", maps.stroke)
		elseif className == "UIShadow" then
			applyColorProperty(instance, "Color3", maps.background)
		elseif className == "UIBackdrop" then
			applyColorProperty(instance, "TintColor3", maps.background)
		elseif className == "UIGradient" then
			applyGradient(instance, maps.background)
		end
	end

	local function remapRecordColor(record, field, map)
		local value = record[field]

		if typeof(value) ~= "Color3" then
			return
		end

		local mapped = map[packColor(value)]

		if mapped then
			record[field] = mapped
		end
	end

	local function applyButtonRecords(maps)
		local colors = UI.tokens.color

		for _, record in ipairs(shared.buttons) do
			local previous = {
				record.color,
				record.hoverColor,
				record.pressedColor,
				record.defaultColor,
				record.defaultHoverColor,
			}

			remapRecordColor(record, "defaultColor", maps.background)
			remapRecordColor(record, "defaultHoverColor", maps.hover)
			remapRecordColor(record, "pressedColor", maps.pressed)

			if record.state == "selected" then
				record.color = colors.selection
				record.hoverColor = colors.selectionHover
			elseif record.state == "accent" then
				record.color = colors.accentSoft
				record.hoverColor = colors.accent
			else
				record.color = record.defaultColor
				record.hoverColor = record.defaultHoverColor
			end

			local current = UI.isAlive(record.gui) and record.gui.BackgroundColor3 or nil
			local known = false

			for _, value in ipairs(previous) do
				if current and current == value then
					known = true

					break
				end
			end

			if known then
				if current == previous[3] then
					record.gui.BackgroundColor3 = record.pressedColor
				elseif current == previous[2] then
					record.gui.BackgroundColor3 = record.hoverColor
				else
					record.gui.BackgroundColor3 = record.color
				end
			end
		end
	end

	local function applyThemeBindings()
		for instance, bindings in pairs(shared.themeBindings) do
			if isAlive(instance) then
				for _, binding in ipairs(bindings) do
					local value = resolveToken(binding.key)

					if value ~= nil then
						pcall(function()
							instance[binding.property] = value
						end)
					end
				end
			end
		end
	end

	local function buildColorMaps(oldColors, newColors)
		return {
			background = buildKeyMap(oldColors, newColors, BACKGROUND_KEYS),
			text = buildKeyMap(oldColors, newColors, TEXT_KEYS),
			stroke = buildKeyMap(oldColors, newColors, STROKE_KEYS),
			image = buildKeyMap(oldColors, newColors, IMAGE_KEYS),
			placeholder = buildKeyMap(oldColors, newColors, PLACEHOLDER_KEYS),
			caret = buildKeyMap(oldColors, newColors, CARET_KEYS),
			selection = buildKeyMap(oldColors, newColors, SELECTION_KEYS),
			hover = buildKeyMap(oldColors, newColors, HOVER_KEYS),
			pressed = buildKeyMap(oldColors, newColors, PRESSED_KEYS),
			focus = buildKeyMap(oldColors, newColors, CARET_KEYS),
		}
	end

	local function mapsHaveChanges(maps)
		for _, map in pairs(maps) do
			if next(map) ~= nil then
				return true
			end
		end

		return false
	end

	local function applyThemeDimensions(spec)
		for key, value in pairs(spec.space) do
			UI.tokens.space[key] = value
		end

		for key, value in pairs(spec.radius) do
			UI.tokens.radius[key] = value
		end

		for key, value in pairs(spec.type) do
			UI.tokens.type[key] = value
		end

		for key, value in pairs(spec.font) do
			UI.tokens.font[key] = value
		end
	end

	local function notifyThemeChanged(name)
		for _, callback in ipairs(shared.themeListeners) do
			pcall(callback, name, UI.tokens)
		end
	end

	local function applyThemeNow(spec, maps, radiusMap, typeMap)
		for key, value in pairs(spec.color) do
			UI.tokens.color[key] = value
		end

		applyThemeDimensions(spec)
		syncLegacyColors()

		for instance in pairs(shared.themeObjects) do
			applyToInstance(instance, maps, radiusMap, typeMap, spec.font)
		end

		applyButtonRecords(maps)
		applyThemeBindings()
	end

	local function finishThemeTransition(notify)
		local transition = shared.themeTransition

		if not transition then
			return
		end

		shared.themeTransition = nil

		if transition.connection then
			transition.connection:Disconnect()
		end

		local maps = buildColorMaps(transition.previous, transition.target)

		for key, value in pairs(transition.target) do
			UI.tokens.color[key] = value
		end

		syncLegacyColors()

		for instance in pairs(shared.themeObjects) do
			applyToInstance(instance, maps, transition.radiusMap, transition.typeMap, transition.font)
		end

		applyButtonRecords(maps)
		applyThemeBindings()

		if notify then
			notifyThemeChanged(transition.name)
		end
	end

	local function beginThemeTransition(name, spec, old, radiusMap, typeMap)
		local transition = {
			name = name,
			target = spec.color,
			previous = old.color,
			radiusMap = radiusMap,
			typeMap = typeMap,
			font = spec.font,
			elapsed = 0,
			duration = THEME_ANIMATION_DURATION,
		}

		applyThemeDimensions(spec)

		shared.themeName = name
		shared.themeTransition = transition

		local firstStep = true

		transition.connection = RunService.Heartbeat:Connect(function(dt)
			if shared.themeTransition ~= transition then
				return
			end

			transition.elapsed += dt

			local alpha = math.min(transition.elapsed / transition.duration, 1)
			local eased = alpha * alpha * (3 - 2 * alpha)
			local current = {}

			for key, targetValue in pairs(transition.target) do
				local oldValue = old.color[key] or targetValue

				current[key] = oldValue:Lerp(targetValue, eased)
			end

			local maps = buildColorMaps(transition.previous, current)

			for key, value in pairs(current) do
				UI.tokens.color[key] = value
			end

			syncLegacyColors()

			local stepRadiusMap = firstStep and radiusMap or EMPTY_MAP
			local stepTypeMap = firstStep and typeMap or EMPTY_MAP
			local stepFont = firstStep and spec.font or nil

			for instance in pairs(shared.themeObjects) do
				applyToInstance(instance, maps, stepRadiusMap, stepTypeMap, stepFont)
			end

			applyButtonRecords(maps)
			applyThemeBindings()

			transition.previous = current
			firstStep = false

			if alpha >= 1 then
				finishThemeTransition(true)
			end
		end)
	end

	function UI.setTheme(name)
		if name == "System" then
			return false, "system theme is disabled"
		end

		local spec = resolveTheme(name)

		if not spec then
			return false, "unknown theme: " .. tostring(name)
		end

		finishThemeTransition(false)

		local old = {
			color = copyTable(UI.tokens.color),
			radius = copyTable(UI.tokens.radius),
			type = copyTable(UI.tokens.type),
		}

		local maps = buildColorMaps(old.color, spec.color)
		local radiusMap = buildNumberMap(old.radius, spec.radius)
		local typeMap = buildNumberMap(old.type, spec.type)

		local animate = THEME_ANIMATION_DURATION > 0 and mapsHaveChanges(maps) and next(shared.themeObjects) ~= nil

		if not animate then
			applyThemeNow(spec, maps, radiusMap, typeMap)

			shared.themeName = name

			notifyThemeChanged(name)

			return true
		end

		beginThemeTransition(name, spec, old, radiusMap, typeMap)

		return true
	end

	function UI.refreshTheme()
		return UI.setTheme(shared.themeName)
	end

	function UI.onThemeChanged(callback)
		if type(callback) ~= "function" then
			error("callback must be a function")
		end

		table.insert(shared.themeListeners, callback)

		return {
			Disconnect = function()
				for index, value in ipairs(shared.themeListeners) do
					if value == callback then
						table.remove(shared.themeListeners, index)

						break
					end
				end
			end,
		}
	end

	local function trackTree(root)
		if not root then
			return
		end

		for _, descendant in ipairs(root:GetDescendants()) do
			UI.track(descendant)
		end

		if shared.trackedRoots[root] then
			return
		end

		shared.trackedRoots[root] = true

		pcall(function()
			root.DescendantAdded:Connect(function(descendant)
				UI.track(descendant)
			end)
		end)
	end

	function UI.trackRoot(root)
		pcall(trackTree, root)

		return root
	end

	UI.setTheme("Dark")
end

function UI.corner(parent, radius)
	return UI.create("UICorner", { CornerRadius = UDim.new(0, radius or UI.tokens.radius.sm) }, parent)
end

function UI.backdrop(parent, radius, TintColor3)
	return UI.create("UIBackdrop", {
		TintColor3 = TintColor3,
		BlurRadius = radius,
	}, parent)
end

function UI.stroke(parent, color, thickness, transparency)
	return UI.create("UIStroke", {

		Color = color or UI.tokens.color.border,

		Thickness = thickness or 1,

		Transparency = transparency or 0,
	}, parent)
end

function UI.frame(parent, position, size, color, radius)
	local frame = UI.create("Frame", {

		Position = position or UDim2.fromOffset(0, 0),

		Size = size or UDim2.fromOffset(100, 100),

		BackgroundColor3 = color or UI.tokens.color.panel,

		BorderSizePixel = 0,
	}, parent)

	if radius and radius > 0 then
		UI.corner(frame, radius)
	end

	return frame
end

function UI.prompt(options)
	options = options or {}

	local colors = UI.tokens.color

	local title = options.title or "Prompt"
	local description = options.description

	local modal = options.modal ~= false
	local dim = options.dim ~= false
	local closable = options.closable ~= false
	local draggable = options.draggable ~= false
	local showHeader = options.showHeader ~= false
	local showFooter = options.showFooter ~= false

	local radius = options.radius or UI.tokens.radius.md
	local padding = options.padding or 12

	local headerHeight = showHeader and (options.headerHeight or (description and 54 or 38)) or 0
	local footerHeight = showFooter and (options.footerHeight or 52) or 0

	local size = options.size or UDim2.fromOffset(440, 260)
	local position = options.position or UDim2.fromScale(0.5, 0.5)
	local anchorPoint = options.anchorPoint or Vector2.new(0.5, 0.5)

	shared.promptSerial = (shared.promptSerial or 0) + 1

	local promptId = shared.promptSerial
	local baseZIndex = options.zIndex or (200000 + promptId * 20)

	local screenGui = UI.create("ScreenGui", {
		Name = options.screenGuiName or ("PromptGui" .. tostring(promptId)),
		RenderOnTop = options.renderOnTop ~= false,
		DisplayOrder = 4000,
	}, options.parent or game.CoreGui)

	local host = UI.create("Frame", {
		Name = options.name or ("Prompt" .. tostring(promptId)),

		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromScale(1, 1),

		BackgroundTransparency = 1,
		BorderSizePixel = 0,

		Active = false,
		InputSink = false,
		Selectable = false,

		ZIndex = baseZIndex,
	}, screenGui)

	local controller = {
		screenGui = screenGui,

		frame = nil,
		host = host,

		backdrop = nil,

		header = nil,
		contentArea = nil,
		content = nil,
		footer = nil,

		title = nil,
		description = nil,

		buttons = {},
		buttonConfigs = {},

		open = options.startVisible ~= false,
		promptDestroyPending = false,
		busy = false,
		destroyed = false,
	}

	local needsBackdrop = modal or dim or options.closeOnBackdrop == true or options.blur ~= nil

	local backdrop = nil

	if needsBackdrop then
		backdrop = UI.create("Frame", {
			Name = "Backdrop",
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = options.dimColor or Color3.new(0, 0, 0),
			BackgroundTransparency = dim and (options.dimTransparency or 0.45) or 1,
			BorderSizePixel = 0,
			InputSink = modal,
			ZIndex = baseZIndex,
		}, host)

		controller.backdrop = backdrop

		if options.blur then
			UI.create("UIBackdrop", {
				Enabled = true,

				BlurRadius = options.blur,

				TintColor3 = options.blurTintColor or Color3.new(0, 0, 0),

				TintTransparency = options.blurTintTransparency or 1,
			}, backdrop)
		end

		if options.closeOnBackdrop == true then
			backdrop.MouseButton1Click:Connect(function()
				controller:Close("backdrop")
			end)
		end
	end

	local panel = UI.frame(host, position, size, options.color or colors.panel, radius)

	panel.Name = "PromptPanel"

	panel.AnchorPoint = anchorPoint
	panel.ClipsDescendants = options.clip == true
	panel.ZIndex = baseZIndex + 1

	if options.transparency ~= nil then
		panel.BackgroundTransparency = options.transparency
	end

	controller.frame = panel

	if options.border ~= false then
		controller.border = UI.stroke(
			panel,
			options.borderColor or colors.borderStrong,
			options.borderThickness or 1,
			options.borderTransparency or 0.25
		)
	end

	if options.shadow ~= false then
		controller.shadow = UI.create("UIShadow", {
			BlurRadius = UDim.new(0, options.shadowBlur or 18),

			Offset = UDim2.fromOffset(options.shadowOffsetX or 0, options.shadowOffsetY or 6),

			Spread = UDim2.fromOffset(options.shadowSpread or 0, options.shadowSpread or 0),

			Color3 = options.shadowColor or Color3.new(0, 0, 0),

			Transparency = options.shadowTransparency or 0.45,

			Enabled = true,
		}, panel)
	end

	if options.glass == true then
		controller.panelBackdrop = UI.create("UIBackdrop", {
			Enabled = true,

			BlurRadius = options.glassBlur or 20,

			TintColor3 = options.glassColor or colors.panel,

			TintTransparency = options.glassTransparency or 0.82,
		}, panel)

		if options.transparency == nil then
			panel.BackgroundTransparency = 0.12
		end
	end

	local animatePrompt = options.animate ~= false
	local promptSpeed = options.animationSpeed or 18
	local promptCloseSpeed = options.closeSpeed or 28
	local promptProgress = 0
	local promptTarget = 0
	local promptHeartbeat = nil
	local promptScale = nil
	local promptBackdropTransparency = backdrop and backdrop.BackgroundTransparency or 1
	local promptBorderTransparency = controller.border and controller.border.Transparency or nil
	local promptShadowTransparency = controller.shadow and controller.shadow.Transparency or nil

	if animatePrompt then
		promptScale = UI.create("UIScale", { Scale = 1 }, panel)
	end

	local function applyPrompt(alpha)
		alpha = math.clamp(alpha, 0, 1)

		local eased = alpha * alpha * (3 - 2 * alpha)

		if promptScale then
			promptScale.Scale = 0.965 + 0.035 * eased
		end

		if backdrop then
			backdrop.BackgroundTransparency = 1 - (1 - promptBackdropTransparency) * eased
		end

		if controller.border and promptBorderTransparency then
			controller.border.Transparency = 1 - (1 - promptBorderTransparency) * eased
		end

		if controller.shadow and promptShadowTransparency then
			controller.shadow.Transparency = 1 - (1 - promptShadowTransparency) * eased
		end
	end

	local function stopPromptAnimation()
		if promptHeartbeat then
			promptHeartbeat:Disconnect()
			promptHeartbeat = nil
		end
	end

	local function finishPromptClose()
		if not controller.promptDestroyPending then
			return
		end

		controller.promptDestroyPending = false

		if not controller.destroyed then
			controller:Destroy()
		end
	end

	local function wakePrompt(target)
		promptTarget = target

		if not animatePrompt then
			stopPromptAnimation()

			promptProgress = target

			applyPrompt(target)

			if target <= 0 then
				screenGui.Enabled = false

				finishPromptClose()
			end

			return
		end

		if promptHeartbeat then
			return
		end

		promptHeartbeat = RunService.Heartbeat:Connect(function(dt)
			local speed = promptTarget <= 0 and promptCloseSpeed or promptSpeed

			promptProgress = tooltipSmoothTowards(promptProgress, promptTarget, speed, dt)

			local finished = math.abs(promptProgress - promptTarget) < 0.002

			if finished then
				promptProgress = promptTarget
			end

			applyPrompt(promptProgress)

			if finished then
				stopPromptAnimation()

				if promptTarget <= 0 then
					screenGui.Enabled = false

					finishPromptClose()
				end
			end
		end)
	end

	panel.Destroying:Connect(stopPromptAnimation)

	local header = nil

	if showHeader then
		header = UI.create("TextButton", {
			Name = "Header",

			Text = "",

			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.new(1, 0, 0, headerHeight),

			BackgroundColor3 = options.headerColor or colors.panelRaised,
			BackgroundTransparency = options.headerTransparency or 0,

			BorderSizePixel = 0,

			Active = draggable,
			InputSink = true,
			AutoButtonColor = false,

			ZIndex = baseZIndex + 2,
		}, panel)

		UI.corner(header, radius)

		UI.frame(
			header,
			UDim2.new(0, 0, 1, -radius),
			UDim2.new(1, 0, 0, radius),
			options.headerColor or colors.panelRaised
		)

		controller.header = header

		if options.accent ~= false then
			controller.accent = UI.frame(
				header,
				UDim2.fromOffset(0, options.accentInset or 7),
				UDim2.fromOffset(options.accentWidth or 3, headerHeight - (options.accentInset or 7) * 2),
				options.accentColor or colors.accent,
				1
			)
		end

		local titleX = options.titleX or 12

		if options.icon then
			local iconSize = options.iconSize or 18

			controller.icon = UI.image(
				header,
				options.icon,
				UDim2.fromOffset(titleX, math.floor((headerHeight - iconSize) / 2)),
				UDim2.fromOffset(iconSize, iconSize)
			)

			titleX += iconSize + (options.iconGap or 8)
		end

		local titleHeight = description and 20 or headerHeight

		local titleLabel = UI.label(
			header,
			title,
			description and UDim2.fromOffset(titleX, 7) or UDim2.fromOffset(titleX, 0),
			UDim2.new(1, -(titleX + (closable and 42 or 12)), 0, titleHeight),
			options.titleSize or UI.tokens.type.body,
			options.titleColor or colors.text
		)

		titleLabel.Name = "Title"
		titleLabel.TextXAlignment = Enum.TextXAlignment.Left

		controller.title = titleLabel

		if description then
			local descriptionLabel = UI.label(
				header,
				description,
				UDim2.fromOffset(titleX, 27),
				UDim2.new(1, -(titleX + (closable and 42 or 12)), 0, headerHeight - 30),
				options.descriptionSize or UI.tokens.type.caption,
				options.descriptionColor or colors.muted
			)

			descriptionLabel.Name = "Description"
			descriptionLabel.TextXAlignment = Enum.TextXAlignment.Left

			controller.description = descriptionLabel
		end

		if options.headerSeparator ~= false then
			controller.headerSeparator = UI.separator(
				header,
				UDim2.new(0, 8, 1, -1),
				UDim2.new(1, -16, 0, 1),
				options.separatorColor or colors.border
			)
		end
	end

	if showHeader and closable then
		local closeButton

		if options.closeIcon then
			closeButton = UI.iconButton(
				header,
				options.closeIcon,
				UDim2.new(1, -31, 0.5, -11),
				UDim2.fromOffset(22, 22),
				function()
					controller:Close("close")
				end,
				{
					color = options.closeColor or colors.panelRaised,

					hoverColor = options.closeHoverColor or colors.hover,

					pressedColor = options.closePressedColor or colors.pressed,

					iconSize = options.closeIconSize or 11,

					radius = options.closeRadius or UI.tokens.radius.sm,

					border = false,
				}
			)
		else
			closeButton = UI.button(header, "", UDim2.new(1, -31, 0.5, -11), UDim2.fromOffset(22, 22), function()
				controller:Close("close")
			end, {
				color = options.closeColor or colors.panelRaised,

				hoverColor = options.closeHoverColor or colors.hover,

				pressedColor = options.closePressedColor or colors.pressed,

				textColor = options.closeTextColor or colors.subtext,

				textSize = options.closeTextSize or 16,

				paddingX = 0,

				radius = options.closeRadius or UI.tokens.radius.sm,

				border = false,
			})
		end

		controller.closeButton = closeButton
	end

	local contentArea = UI.frame(
		panel,
		UDim2.fromOffset(0, headerHeight),
		UDim2.new(1, 0, 1, -(headerHeight + footerHeight)),
		options.contentColor or colors.panel
	)

	contentArea.Name = "ContentArea"

	contentArea.BackgroundTransparency = options.contentTransparency or 0
	contentArea.ClipsDescendants = options.clipContent == true

	controller.contentArea = contentArea

	local contentProperties = {
		Name = "Content",

		Position = UDim2.fromOffset(padding, padding),

		Size = UDim2.new(1, -padding * 2, 1, -padding * 2),

		BackgroundTransparency = 1,

		BorderSizePixel = 0,

		ClipsDescendants = options.clipContent == true,

		ZIndex = baseZIndex + 2,
	}

	local content

	if options.scrollable == true then
		contentProperties.CanvasPosition = options.canvasPosition or Vector2.new(0, 0)

		contentProperties.CanvasSize = options.canvasSize or UDim2.new(0, 0, 0, 0)

		contentProperties.ScrollingEnabled = options.scrollingEnabled ~= false

		contentProperties.ScrollBarThickness = options.scrollBarThickness or 5

		contentProperties.ScrollBarImageColor3 = options.scrollBarColor or colors.subtext

		contentProperties.ScrollBarImageTransparency = options.scrollBarTransparency or 0.4

		contentProperties.ScrollBarAutoHide = options.scrollBarAutoHide ~= false

		content = UI.create("ScrollingFrame", contentProperties, contentArea)
	else
		content = UI.create("Frame", contentProperties, contentArea)
	end

	controller.content = content

	local footer = nil
	local buttonGroup = nil

	if showFooter then
		footer = UI.frame(
			panel,
			UDim2.new(0, 0, 1, -footerHeight),
			UDim2.new(1, 0, 0, footerHeight),
			options.footerColor or colors.panelRaised
		)

		footer.Name = "Footer"

		footer.BackgroundTransparency = options.footerTransparency or 0

		controller.footer = footer

		if options.footerSeparator ~= false then
			controller.footerSeparator = UI.separator(
				footer,
				UDim2.fromOffset(8, 0),
				UDim2.new(1, -16, 0, 1),
				options.separatorColor or colors.border
			)
		end

		buttonGroup = UI.frame(footer, UDim2.fromOffset(0, 0), UDim2.fromOffset(0, footerHeight), Color3.new(0, 0, 0))

		buttonGroup.Name = "Buttons"
		buttonGroup.BackgroundTransparency = 1

		controller.buttonGroup = buttonGroup
	end

	local function getButtonColors(config)
		local role = config.role or "secondary"

		if role == "primary" then
			return config.color or colors.accent,
				config.hoverColor or colors.selectionHover,
				config.pressedColor or colors.pressed,
				config.textColor or colors.text,
				config.backgroundTransparency or 0
		elseif role == "danger" then
			return config.color or colors.error,
				config.hoverColor or colors.error,
				config.pressedColor or colors.pressed,
				config.textColor or colors.text,
				config.backgroundTransparency or 0
		elseif role == "ghost" then
			return config.color or colors.panelRaised,
				config.hoverColor or colors.hover,
				config.pressedColor or colors.pressed,
				config.textColor or colors.subtext,
				config.backgroundTransparency or 1
		end

		return config.color or colors.panelRaised,
			config.hoverColor or colors.hover,
			config.pressedColor or colors.pressed,
			config.textColor or colors.subtext,
			config.backgroundTransparency or 0
	end

	local function calculateButtonWidth(config)
		if config.width then
			return config.width
		end

		local text = tostring(config.text or config.label or config.id or "Button")

		return math.max(options.buttonWidth or 82, #text * (options.buttonCharacterWidth or 7) + 28)
	end

	local function renderButtons()
		if not buttonGroup then
			return
		end

		UI.clear(buttonGroup)

		controller.buttons = {}

		local configs = controller.buttonConfigs

		local gap = options.buttonGap or 7
		local totalWidth = 0

		for index, config in ipairs(configs) do
			totalWidth += calculateButtonWidth(config)

			if index > 1 then
				totalWidth += gap
			end
		end

		local alignment = options.buttonAlignment or "right"

		if alignment == "left" then
			buttonGroup.AnchorPoint = Vector2.new(0, 0)

			buttonGroup.Position = UDim2.fromOffset(options.footerPadding or 10, 0)
		elseif alignment == "center" then
			buttonGroup.AnchorPoint = Vector2.new(0.5, 0)

			buttonGroup.Position = UDim2.new(0.5, 0, 0, 0)
		else
			buttonGroup.AnchorPoint = Vector2.new(1, 0)

			buttonGroup.Position = UDim2.new(1, -(options.footerPadding or 10), 0, 0)
		end

		buttonGroup.Size = UDim2.fromOffset(totalWidth, footerHeight)

		local x = 0

		for index, config in ipairs(configs) do
			local id = config.id or config.name or tostring(index)

			local text = config.text or config.label or tostring(id)

			local width = calculateButtonWidth(config)

			local height = config.height or options.buttonHeight or UI.metrics.buttonHeight

			local color, hoverColor, pressedColor, textColor, backgroundTransparency = getButtonColors(config)

			local button
			local label
			local record

			button, label, record = UI.button(
				buttonGroup,
				text,
				UDim2.fromOffset(x, math.floor((footerHeight - height) / 2)),
				UDim2.fromOffset(width, height),
				function()
					if record and not record.enabled then
						return
					end

					local callbackResult = nil

					if config.callback then
						callbackResult = config.callback(controller, config, content)
					end

					local resultValue = id

					if config.value ~= nil then
						resultValue = config.value
					end

					if options.onResult then
						options.onResult(id, resultValue, config, controller, callbackResult)
					end

					if callbackResult ~= false and config.close ~= false then
						controller:Close(id, resultValue)
					end
				end,
				{
					color = color,

					hoverColor = hoverColor,

					pressedColor = pressedColor,

					textColor = textColor,

					textSize = config.textSize or options.buttonTextSize or UI.tokens.type.small,

					radius = config.radius or options.buttonRadius or UI.tokens.radius.sm,

					border = config.border ~= false,

					borderColor = config.borderColor or options.buttonBorderColor or colors.border,

					borderTransparency = config.borderTransparency or options.buttonBorderTransparency or 0,

					paddingX = config.paddingX or options.buttonPaddingX or UI.tokens.space.md,

					icon = config.icon,

					iconSize = config.iconSize or options.buttonIconSize or 14,

					enabled = config.enabled ~= false,
				}
			)

			button.Name = tostring(id)

			button.BackgroundTransparency = backgroundTransparency

			controller.buttons[id] = {
				id = id,

				button = button,
				label = label,
				record = record,

				config = config,

				color = color,
				hoverColor = hoverColor,

				textColor = textColor,

				enabled = config.enabled ~= false,
			}

			x += width + gap
		end
	end

	function controller:IsOpen()
		return self.open and not self.destroyed
	end

	function controller:Open()
		if self.destroyed then
			return false
		end

		if self.open then
			return true
		end

		self.open = true
		self.promptDestroyPending = false

		self.screenGui.Enabled = true

		wakePrompt(1)

		if options.onOpen then
			options.onOpen(self)
		end

		return true
	end

	function controller:Close(reason, result)
		if self.destroyed or not self.open then
			return false
		end

		if options.beforeClose then
			local allowed = options.beforeClose(reason, result, self)

			if allowed == false then
				return false
			end
		end

		self.open = false
		self.promptDestroyPending = options.destroyOnClose == true

		if options.onClose then
			options.onClose(reason, result, self)
		end

		wakePrompt(0)

		return true
	end

	function controller:Destroy()
		if self.destroyed then
			return
		end

		self.destroyed = true
		self.open = false
		self.promptDestroyPending = false

		stopPromptAnimation()

		UI.forgetButtons(self.screenGui)

		self.screenGui:Destroy()
	end

	function controller:SetTitle(text)
		if self.title then
			self.title.Text = tostring(text or "")
		end
	end

	function controller:SetDescription(text)
		if not self.description then
			return
		end

		self.description.Text = tostring(text or "")
	end

	function controller:SetSize(newSize)
		panel.Size = newSize
	end

	function controller:SetPosition(newPosition)
		panel.Position = newPosition
	end

	function controller:SetModal(value)
		modal = value == true

		if backdrop then
			backdrop.Active = modal or options.closeOnBackdrop == true
			backdrop.InputSink = modal
		end
	end

	function controller:GetButton(id)
		return self.buttons[id]
	end

	function controller:SetButtonEnabled(id, enabled)
		local data = self.buttons[id]

		if not data then
			return false
		end

		enabled = enabled == true

		data.enabled = enabled
		data.record.enabled = enabled

		data.button.Active = enabled

		if enabled then
			data.record.color = data.color
			data.record.hoverColor = data.hoverColor

			data.button.BackgroundColor3 = data.color
			data.label.TextColor3 = data.textColor
		else
			data.button.BackgroundColor3 = options.disabledButtonColor or colors.surface

			data.label.TextColor3 = options.disabledTextColor or colors.muted
		end

		return true
	end

	function controller:SetButtons(buttons)
		self.buttonConfigs = buttons or {}

		renderButtons()
	end

	function controller:AddButton(config)
		table.insert(self.buttonConfigs, config)

		renderButtons()

		return self.buttons[config.id or config.name or tostring(#self.buttonConfigs)]
	end

	function controller:SetBusy(value, targetButton, busyText)
		value = value == true

		if self.busy == value then
			return
		end

		self.busy = value

		if value then
			self._busyStates = {}

			for id, data in pairs(self.buttons) do
				self._busyStates[id] = data.enabled

				self:SetButtonEnabled(id, false)
			end

			if targetButton and self.buttons[targetButton] then
				local data = self.buttons[targetButton]

				data._normalText = data.label.Text

				if busyText then
					data.label.Text = busyText
				end
			end
		else
			for id, enabled in pairs(self._busyStates or {}) do
				self:SetButtonEnabled(id, enabled)
			end

			if targetButton and self.buttons[targetButton] then
				local data = self.buttons[targetButton]

				if data._normalText then
					data.label.Text = data._normalText
					data._normalText = nil
				end
			end

			self._busyStates = nil
		end
	end

	if header and draggable then
		local dragging = false

		local startMouseX = 0
		local startMouseY = 0

		local startPosition = nil

		header.MouseButton1Down:Connect(function(x, y)
			dragging = true

			startMouseX = x
			startMouseY = y

			startPosition = panel.Position

			if options.onDragBegin then
				options.onDragBegin(controller)
			end
		end)

		header.MouseMoved:Connect(function(x, y)
			if not dragging or not startPosition then
				return
			end

			local deltaX = x - startMouseX
			local deltaY = y - startMouseY

			panel.Position = UDim2.new(
				startPosition.X.Scale,
				startPosition.X.Offset + deltaX,
				startPosition.Y.Scale,
				startPosition.Y.Offset + deltaY
			)

			if options.onDrag then
				options.onDrag(panel.Position, controller)
			end
		end)

		header.MouseButton1Up:Connect(function()
			if not dragging then
				return
			end

			dragging = false

			if options.onDragEnd then
				options.onDragEnd(panel.Position, controller)
			end
		end)
	end

	local initialButtons = options.buttons

	if initialButtons == nil and showFooter then
		initialButtons = {
			{
				id = "ok",
				text = options.defaultButtonText or "OK",
				role = "primary",
			},
		}
	end

	controller.buttonConfigs = initialButtons or {}

	renderButtons()

	if options.build then
		options.build(content, controller)
	end

	if options.onCreated then
		options.onCreated(controller, content)
	end

	if controller.open then
		screenGui.Enabled = true

		if animatePrompt then
			applyPrompt(0)
			wakePrompt(1)
		else
			promptProgress = 1

			applyPrompt(1)
		end
	else
		screenGui.Enabled = false

		applyPrompt(0)
	end

	if controller.open and options.onOpen then
		options.onOpen(controller)
	end

	return panel, content, controller
end

function UI.rangeSlider(parent, position, size, minimum, maximum, low, high, callback, options)
	options = options or {}

	local colors = UI.tokens.color

	minimum = minimum or 0
	maximum = maximum or 1

	low = math.clamp(low or minimum, minimum, maximum)
	high = math.clamp(high or maximum, minimum, maximum)

	if low > high then
		low, high = high, low
	end

	local step = options.step or 0
	local dragging = nil

	local animate = options.animate ~= false
	local animationSpeed = options.animationSpeed or 18

	local displayLow, displayHigh = low, high
	local heartbeat = nil

	local container = UI.create("TextButton", {
		Text = "",
		Position = position or UDim2.fromOffset(0, 0),
		Size = size or UDim2.fromOffset(160, UI.metrics.inputHeight),

		BackgroundTransparency = 1,
		BorderSizePixel = 0,

		Active = true,
		InputSink = true,
		AutoButtonColor = false,
	}, parent)

	local trackHeight = options.trackHeight or 4

	local track = UI.frame(
		container,
		UDim2.new(0, 0, 0.5, -math.floor(trackHeight / 2)),
		UDim2.new(1, 0, 0, trackHeight),
		options.trackColor or colors.input,
		math.floor(trackHeight / 2)
	)

	local fill = UI.frame(
		track,
		UDim2.fromOffset(0, 0),
		UDim2.fromOffset(0, trackHeight),
		options.fillColor or colors.accent,
		math.floor(trackHeight / 2)
	)

	local knobSize = options.knobSize or 12

	local lowKnob = UI.frame(
		container,
		UDim2.fromOffset(0, 0),
		UDim2.fromOffset(knobSize, knobSize),
		options.knobColor or colors.text,
		math.floor(knobSize / 2)
	)

	local highKnob = UI.frame(
		container,
		UDim2.fromOffset(0, 0),
		UDim2.fromOffset(knobSize, knobSize),
		options.knobColor or colors.text,
		math.floor(knobSize / 2)
	)

	UI.stroke(lowKnob, options.knobBorderColor or colors.borderStrong, 1, 0)
	UI.stroke(highKnob, options.knobBorderColor or colors.borderStrong, 1, 0)

	local function alpha(value)
		if maximum == minimum then
			return 0
		end

		return math.clamp((value - minimum) / (maximum - minimum), 0, 1)
	end

	local function redraw()
		local lowAlpha = alpha(displayLow)
		local highAlpha = alpha(displayHigh)

		fill.Position = UDim2.new(lowAlpha, 0, 0, 0)
		fill.Size = UDim2.new(math.max(highAlpha - lowAlpha, 0), 0, 1, 0)

		lowKnob.Position = UDim2.new(lowAlpha, -math.floor(knobSize / 2), 0.5, -math.floor(knobSize / 2))

		highKnob.Position = UDim2.new(highAlpha, -math.floor(knobSize / 2), 0.5, -math.floor(knobSize / 2))
	end

	local function stopAnimation()
		if heartbeat then
			heartbeat:Disconnect()
			heartbeat = nil
		end
	end

	local function snapVisual()
		stopAnimation()

		displayLow, displayHigh = low, high

		redraw()
	end

	local function wake()
		if not animate or dragging then
			snapVisual()

			return
		end

		if heartbeat then
			return
		end

		heartbeat = RunService.Heartbeat:Connect(function(dt)
			displayLow = tooltipSmoothTowards(displayLow, low, animationSpeed, dt)
			displayHigh = tooltipSmoothTowards(displayHigh, high, animationSpeed, dt)

			local finished = math.abs(displayLow - low) < 0.0005 and math.abs(displayHigh - high) < 0.0005

			if finished then
				displayLow, displayHigh = low, high
			end

			redraw()

			if finished then
				stopAnimation()
			end
		end)
	end

	container.Destroying:Connect(stopAnimation)

	local function valueFromPoint(x)
		local position = track.AbsolutePosition
		local absoluteSize = track.AbsoluteSize

		if not position or not absoluteSize or absoluteSize.X <= 0 then
			return nil
		end

		local a = math.clamp((x - position.X) / absoluteSize.X, 0, 1)
		local value = minimum + (maximum - minimum) * a

		if step > 0 then
			value = math.floor((value - minimum) / step + 0.5) * step + minimum
		end

		return math.clamp(value, minimum, maximum)
	end

	local function chooseKnob(x)
		local value = valueFromPoint(x)

		if value == nil then
			return
		end

		if math.abs(value - low) <= math.abs(value - high) then
			dragging = "low"
		else
			dragging = "high"
		end
	end

	local function updateFromPoint(x, silent)
		local value = valueFromPoint(x)

		if value == nil then
			return
		end

		if dragging == "low" then
			low = math.min(value, high)
		elseif dragging == "high" then
			high = math.max(value, low)
		else
			return
		end

		displayLow, displayHigh = low, high

		redraw()

		if not silent and callback then
			callback(low, high)
		end
	end

	container.MouseButton1Down:Connect(function(x)
		stopAnimation()

		chooseKnob(x)

		if options.onBegin then
			options.onBegin()
		end

		updateFromPoint(x)
	end)

	container.MouseMoved:Connect(function(x)
		if dragging then
			updateFromPoint(x)
		end
	end)

	container.MouseButton1Up:Connect(function(x)
		if dragging then
			updateFromPoint(x)
		end

		dragging = nil

		if options.onEnd then
			options.onEnd()
		end
	end)

	local controller = {
		frame = container,
		track = track,
		fill = fill,
		lowKnob = lowKnob,
		highKnob = highKnob,
	}

	function controller:GetValues()
		return low, high
	end

	function controller:SetValues(newLow, newHigh, silent, instant)
		low = math.clamp(newLow, minimum, maximum)
		high = math.clamp(newHigh, minimum, maximum)

		if low > high then
			low, high = high, low
		end

		if instant then
			snapVisual()
		else
			wake()
		end

		if not silent and callback then
			callback(low, high)
		end
	end

	function controller:SetRange(newMinimum, newMaximum)
		minimum = newMinimum
		maximum = newMaximum

		low = math.clamp(low, minimum, maximum)
		high = math.clamp(high, minimum, maximum)

		snapVisual()
	end

	redraw()

	return container, controller
end

function UI.point2D(parent, position, size, minimumX, maximumX, minimumY, maximumY, x, y, callback, options)
	options = options or {}

	local colors = UI.tokens.color

	minimumX = minimumX or -1
	maximumX = maximumX or 1
	minimumY = minimumY or -1
	maximumY = maximumY or 1

	x = math.clamp(x or 0, minimumX, maximumX)
	y = math.clamp(y or 0, minimumY, maximumY)

	local dragging = false

	local pad = UI.create("TextButton", {
		Text = "",
		Position = position,
		Size = size or UDim2.fromOffset(160, 120),

		BackgroundColor3 = options.color or colors.input,
		BorderSizePixel = 0,

		Active = true,
		InputSink = true,
		AutoButtonColor = false,
		ClipsDescendants = true,
	}, parent)

	UI.corner(pad, options.radius or UI.tokens.radius.xs)
	UI.stroke(pad, options.borderColor or colors.border, 1, 0)

	local centerX =
		UI.separator(pad, UDim2.new(0.5, 0, 0, 0), UDim2.new(0, 1, 1, 0), options.gridColor or colors.border)

	centerX.BackgroundTransparency = 0.35

	local centerY =
		UI.separator(pad, UDim2.new(0, 0, 0.5, 0), UDim2.new(1, 0, 0, 1), options.gridColor or colors.border)

	centerY.BackgroundTransparency = 0.35

	local cursorSize = options.cursorSize or 10

	local cursor = UI.frame(
		pad,
		UDim2.fromOffset(0, 0),
		UDim2.fromOffset(cursorSize, cursorSize),
		options.cursorColor or colors.text,
		math.floor(cursorSize / 2)
	)

	UI.stroke(cursor, options.cursorBorderColor or colors.borderStrong, 1, 0)

	local function normalizedX()
		if maximumX == minimumX then
			return 0
		end

		return math.clamp((x - minimumX) / (maximumX - minimumX), 0, 1)
	end

	local function normalizedY()
		if maximumY == minimumY then
			return 0
		end

		return math.clamp((y - minimumY) / (maximumY - minimumY), 0, 1)
	end

	local function redraw()
		cursor.Position =
			UDim2.new(normalizedX(), -math.floor(cursorSize / 2), normalizedY(), -math.floor(cursorSize / 2))
	end

	local function updateFromPoint(mouseX, mouseY)
		local absolutePosition = pad.AbsolutePosition
		local absoluteSize = pad.AbsoluteSize

		if not absolutePosition or not absoluteSize then
			return
		end

		if absoluteSize.X <= 0 or absoluteSize.Y <= 0 then
			return
		end

		local alphaX = math.clamp((mouseX - absolutePosition.X) / absoluteSize.X, 0, 1)

		local alphaY = math.clamp((mouseY - absolutePosition.Y) / absoluteSize.Y, 0, 1)

		x = minimumX + (maximumX - minimumX) * alphaX
		y = minimumY + (maximumY - minimumY) * alphaY

		redraw()

		if callback then
			callback(x, y)
		end
	end

	pad.MouseButton1Down:Connect(function(mouseX, mouseY)
		dragging = true

		if options.onBegin then
			options.onBegin()
		end

		updateFromPoint(mouseX, mouseY)
	end)

	pad.MouseMoved:Connect(function(mouseX, mouseY)
		if dragging then
			updateFromPoint(mouseX, mouseY)
		end
	end)

	pad.MouseButton1Up:Connect(function(mouseX, mouseY)
		if dragging then
			updateFromPoint(mouseX, mouseY)
		end

		dragging = false

		if options.onEnd then
			options.onEnd()
		end
	end)

	local controller = {
		frame = pad,
		cursor = cursor,
	}

	function controller:GetValue()
		return x, y
	end

	function controller:SetValue(newX, newY, silent)
		x = math.clamp(newX, minimumX, maximumX)
		y = math.clamp(newY, minimumY, maximumY)

		redraw()

		if not silent and callback then
			callback(x, y)
		end
	end

	redraw()

	return pad, controller
end

function UI.label(parent, text, position, size, textSize, color)
	return UI.create("TextLabel", {

		Text = tostring(text or ""),

		Position = position or UDim2.fromOffset(0, 0),

		Size = size or UDim2.fromOffset(100, 20),

		BackgroundTransparency = 1,

		TextSize = textSize or UI.tokens.type.body,

		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,

		TextColor3 = color or UI.tokens.color.text,

		BorderSizePixel = 0,
	}, parent)
end

function UI.image(parent, path, position, size)
	return UI.create("ImageLabel", {

		Image = path,

		Position = position,

		Size = size,

		BackgroundTransparency = 1,

		BorderSizePixel = 0,
	}, parent)
end

function UI.isAlive(gui)
	return isAlive(gui)
end

function UI.forgetButtons(container)
	if container == nil then
		return
	end

	local retained = {}

	for _, item in ipairs(shared.buttons) do
		local gui = item.gui

		if gui ~= nil and gui ~= container and UI.isAlive(gui) and not gui:IsDescendantOf(container) then
			table.insert(retained, item)
		else
			item.destroyed = true
		end
	end

	shared.buttons = retained
end

function UI.clear(parent, keep)
	local doomedChildren = {}
	local doomed = {}

	for _, child in ipairs(parent:GetChildren()) do
		local decoration = child:IsA("UICorner")
			or child:IsA("UIStroke")
			or child:IsA("UIShadow")
			or child:IsA("UIBackdrop")

		if not decoration and (not keep or not keep[child]) then
			table.insert(doomedChildren, child)

			doomed[child] = true

			for _, descendant in ipairs(child:GetDescendants()) do
				doomed[descendant] = true
			end
		end
	end

	local retained = {}

	for _, item in ipairs(shared.buttons) do
		local gui = item.gui

		if gui ~= nil and not doomed[gui] and UI.isAlive(gui) then
			table.insert(retained, item)
		else
			item.destroyed = true
		end
	end

	shared.buttons = retained

	for _, child in ipairs(doomedChildren) do
		child:Destroy()
	end
end

function UI.property(parent, text, position, size, value, callback, options)
	options = options or {}

	local colors = UI.tokens.color

	local rowHeight = UI.metrics.propertyRow
	local padding = options.padding or UI.tokens.space.md
	local gap = options.gap or UI.tokens.space.sm
	local fieldGap = options.fieldGap or UI.tokens.space.xs
	local textSize = options.textSize or UI.tokens.type.small
	local innerHeight = rowHeight - 2

	local row: Frame = UI.frame(
		parent,
		position or UDim2.fromOffset(0, 0),
		size or UDim2.new(1, 0, 0, rowHeight),
		options.color or colors.panel,
		options.radius or 0
	)
	row.ClipsDescendants = false
	row.Name = options.name or "Property"
	row.BackgroundTransparency = options.transparent and 1 or 0

	local labelSize, areaPosition, areaSize

	if options.labelWidth then
		labelSize = UDim2.new(0, options.labelWidth, 1, 0)
		areaPosition = UDim2.new(0, padding + options.labelWidth + gap, 0, 0)
		areaSize = UDim2.new(1, -(padding * 2 + options.labelWidth + gap), 1, 0)
	else
		local scale = options.labelScale or 0.45
		labelSize = UDim2.new(scale, -padding, 1, 0)
		areaPosition = UDim2.new(scale, gap, 0, 0)
		areaSize = UDim2.new(1 - scale, -(padding + gap), 1, 0)
	end

	local label =
		UI.label(row, text, UDim2.fromOffset(padding, 0), labelSize, textSize, options.labelColor or colors.subtext)

	label.Name = "Label"
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center

	local holder = UI.create("Frame", {
		Name = "Content",
		Position = areaPosition,
		Size = areaSize,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, row)

	local controller = {
		frame = row,
		label = label,
		content = holder,
		fields = {},
		custom = nil,
	}

	local enabled = true

	if options.custom then
		controller.custom = options.custom(holder, controller, colors)

		function controller:Fire(newValue)
			if callback then
				callback(newValue, controller)
			end
		end

		function controller:GetValue()
			local custom = self.custom
			if type(custom) == "table" and custom.GetValue then
				return custom:GetValue()
			end
		end

		function controller:SetValue(newValue, silent)
			local custom = self.custom
			if type(custom) == "table" and custom.SetValue then
				custom:SetValue(newValue, silent)
			end
		end

		function controller:SetLabel(newText)
			label.Text = tostring(newText or "")
		end

		function controller:SetEnabled(value)
			enabled = value == true
			label.TextColor3 = enabled and (options.labelColor or colors.subtext) or colors.muted

			local custom = self.custom
			if type(custom) == "table" and custom.SetEnabled then
				custom:SetEnabled(enabled)
			end
		end

		function controller:IsEnabled()
			return enabled
		end

		function controller:Destroy()
			local custom = self.custom
			if type(custom) == "table" and custom.Destroy then
				custom:Destroy()
			end

			UI.forgetButtons(row)
			row:Destroy()
		end

		return row, controller
	end

	local multi = options.fields ~= nil or options.count ~= nil
	local configs = {}

	if options.fields then
		for index, config in ipairs(options.fields) do
			configs[index] = config
		end
	elseif options.count then
		for index = 1, options.count do
			configs[index] = {}
		end
	else
		configs[1] = {}
	end

	local count = #configs

	local function setting(config, key)
		if config[key] ~= nil then
			return config[key]
		end

		return options[key]
	end

	local function formatNumber(config, number)
		local decimals = setting(config, "decimals")

		if decimals then
			local factor = 10 ^ decimals
			number = math.floor(number * factor + 0.5) / factor
		end

		return tostring(number)
	end

	local function normalize(config, raw)
		if setting(config, "numeric") then
			local number = tonumber(raw)

			if number == nil then
				return false
			end

			local minimum, maximum = setting(config, "min"), setting(config, "max")

			if minimum then
				number = math.max(number, minimum)
			end

			if maximum then
				number = math.min(number, maximum)
			end

			return true, formatNumber(config, number)
		end

		local validate = setting(config, "validate")

		if validate then
			local ok, normalized = validate(raw)

			if not ok then
				return false
			end

			return true, normalized ~= nil and tostring(normalized) or raw
		end

		return true, raw
	end

	local function outValue(field)
		if setting(field.config, "numeric") then
			return tonumber(field.current)
		end

		return field.current
	end

	local function collect()
		if not multi then
			return outValue(controller.fields[1])
		end

		local values = {}

		for index, field in ipairs(controller.fields) do
			values[index] = outValue(field)
		end

		return values
	end

	local function notify(index)
		if not callback then
			return
		end

		if multi then
			callback(collect(), controller, index)
		else
			callback(collect(), controller)
		end
	end

	local initial = value

	if not multi then
		initial = { value }
	end

	initial = type(initial) == "table" and initial or {}

	local prefixWidth = options.prefixWidth or 12

	for index, config in ipairs(configs) do
		local cell = UI.create("Frame", {
			Name = "Field" .. index,
			Position = UDim2.new(
				(index - 1) / count,
				(index - 1) * fieldGap / count,
				0.5,
				-math.floor(innerHeight / 2)
			),
			Size = UDim2.new(1 / count, -fieldGap * (count - 1) / count, 0, innerHeight),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, holder)

		local boxX, boxWidth = 0, UDim2.new(1, 0, 1, 0)

		if config.prefix then
			local prefixColor = config.prefixColor
				or (options.prefixColors and options.prefixColors[index])
				or colors.muted

			local prefix = UI.label(
				cell,
				config.prefix,
				UDim2.fromOffset(0, 0),
				UDim2.fromOffset(prefixWidth, innerHeight),
				UI.tokens.type.caption,
				prefixColor
			)

			prefix.Name = "Prefix"
			prefix.TextXAlignment = Enum.TextXAlignment.Center
			prefix.TextYAlignment = Enum.TextYAlignment.Center

			boxX = prefixWidth + 2
			boxWidth = UDim2.new(1, -boxX, 1, 0)
		end

		local startValue = initial[index]
		local startText = startValue ~= nil and tostring(startValue) or ""

		local box =
			UI.input(cell, config.placeholder or options.placeholder or "", UDim2.fromOffset(boxX, 0), boxWidth, {
				text = startText,
				textSize = textSize,
				textColor = setting(config, "textColor"),
				color = setting(config, "inputColor"),
				textEditable = not setting(config, "readOnly"),
				selectAllOnFocus = options.selectAllOnFocus,
			})

		box.Name = "Value"

		local field = { box = box, cell = cell, config = config, current = startText }

		controller.fields[index] = field

		box.FocusLost:Connect(function()
			local ok, normalized = normalize(config, box.Text)

			if not ok then
				box.Text = field.current
				return
			end

			box.Text = normalized

			if normalized == field.current then
				return
			end

			field.current = normalized
			notify(index)
		end)
	end

	controller.box = controller.fields[1].box

	function controller:GetValue()
		return collect()
	end

	function controller:GetField(index)
		local field = self.fields[index]
		return field and outValue(field) or nil
	end

	function controller:SetField(index, newValue, silent)
		local field = self.fields[index]

		if not field then
			return false
		end

		local raw = newValue ~= nil and tostring(newValue) or ""
		local ok, normalized = normalize(field.config, raw)

		if not ok then
			return false
		end

		field.current = normalized
		field.box.Text = normalized

		if not silent then
			notify(index)
		end

		return true
	end

	function controller:SetValue(newValue, silent)
		if not multi then
			return self:SetField(1, newValue, silent)
		end

		if type(newValue) ~= "table" then
			return false
		end

		local changed = false

		for index = 1, count do
			if newValue[index] ~= nil and self:SetField(index, newValue[index], true) then
				changed = true
			end
		end

		if changed and not silent then
			notify(nil)
		end

		return changed
	end

	function controller:SetLabel(newText)
		label.Text = tostring(newText or "")
	end

	function controller:SetEnabled(value)
		enabled = value == true

		label.TextColor3 = enabled and (options.labelColor or colors.subtext) or colors.muted

		for _, field in ipairs(self.fields) do
			field.box.TextEditable = enabled and not setting(field.config, "readOnly")
			field.box.Active = enabled
			field.box.TextColor3 = enabled and (setting(field.config, "textColor") or colors.text) or colors.muted
		end
	end

	function controller:IsEnabled()
		return enabled
	end

	function controller:Focus(index)
		local field = self.fields[index or 1]

		if field then
			field.box:CaptureFocus()
		end
	end

	function controller:Destroy()
		UI.forgetButtons(row)
		row:Destroy()
	end

	return row, controller
end

function UI.toast(text, options)
	options = options or {}

	local colors = UI.tokens.color

	shared.toasts = shared.toasts or {}
	shared.toastSerial = (shared.toastSerial or 0) + 1

	shared.toastMargin = shared.toastMargin or (options.margin or 20)
	shared.toastGap = shared.toastGap or (options.gap or 10)

	local margin = shared.toastMargin
	local gap = shared.toastGap

	if not shared.toastRoot then
		shared.toastRoot = UI.create("ScreenGui", {
			Name = "ToastOverlay",

			DisplayOrder = options.displayOrder or 3000,

			IgnoreGuiInset = true,
			RenderOnTop = true,
		}, options.parent or game.CoreGui)
	end

	local root = shared.toastRoot

	local kind = options.type or "info"

	local typeConfigs = {
		info = {
			color = colors.accent,
			icon = "builtin://global-icons/info.svg",
		},

		success = {
			color = colors.success,
			icon = "builtin://global-icons/check.svg",
		},

		warning = {
			color = colors.warning,
			icon = "builtin://global-icons/warning.svg",
		},

		error = {
			color = colors.error,
			icon = "builtin://global-icons/error",
		},
	}

	local typeConfig = typeConfigs[kind] or typeConfigs.info

	local accentColor = options.accentColor or typeConfig.color
	local iconCharacter = options.icon or typeConfig.icon
	local blur
	local controller = {}

	local title = options.title or tostring(text or "Notification")
	local messagePrefix = options.message or ""

	local details = tostring(options.details or "")

	local hasDetails = details ~= "" or options.buildDetails ~= nil

	local width = options.width or 520

	local headerHeight = options.headerHeight or 52
	local summaryHeight = options.summaryHeight or 40
	local progressHeight = options.progressHeight or 4

	local collapsedHeight = options.height or (headerHeight + summaryHeight + progressHeight)

	local expandedHeight = options.expandedHeight or (collapsedHeight + 120)

	expandedHeight = math.max(expandedHeight, collapsedHeight + 50)

	local duration = options.duration

	if duration == nil then
		duration = 9
	end

	local fadeSpeed = options.fadeSpeed or 14
	local moveSpeed = options.moveSpeed or 16
	local slideDistance = options.slideDistance or 18

	local backgroundTransparency = options.backgroundTransparency or 0
	local borderTransparency = options.borderTransparency or 0.25

	local zIndex = options.zIndex or (150000 + shared.toastSerial * 10)

	local frame = UI.create("Frame", {
		Name = "Toast" .. tostring(shared.toastSerial),
		ClipsDescendants = true,

		AnchorPoint = Vector2.new(0.5, 0),

		Position = UDim2.new(0.5, 0, 0, margin - slideDistance),

		Size = UDim2.fromOffset(width, collapsedHeight),

		BackgroundColor3 = options.backgroundColor or colors.panelRaised,
		BackgroundTransparency = 1,

		BorderSizePixel = 0,

		Active = false,
		InputSink = false,

		ZIndex = zIndex,
	}, root)

	UI.corner(frame, options.radius or UI.tokens.radius.md)

	local border = UI.stroke(frame, options.borderColor or colors.borderStrong, options.borderThickness or 1, 1)

	local shadow = nil

	if options.shadow ~= false then
		shadow = UI.create("UIShadow", {
			BlurRadius = UDim.new(0, options.shadowBlur or 18),

			Offset = UDim2.fromOffset(0, options.shadowOffset or 6),

			Spread = UDim2.fromOffset(0, 0),

			Color3 = options.shadowColor or Color3.new(0, 0, 0),

			Transparency = 1,

			Enabled = true,
		}, frame)
	end

	if options.blur ~= false then
		blur = UI.create("UIBackdrop", {
			TintColor3 = options.shadowColor or Color3.new(0, 0, 0),
		}, frame)
	end

	local titleLabel = UI.label(
		frame,
		title,
		UDim2.fromOffset(20, 15),
		UDim2.new(1, -155, 0, headerHeight),
		options.titleSize or 15,
		options.titleColor or colors.text
	)

	titleLabel.Name = "Title"

	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextTransparency = 1

	titleLabel.ZIndex = zIndex + 2

	local summaryButton = UI.create("TextButton", {
		Name = "Summary",

		Text = "",

		Position = UDim2.fromOffset(0, headerHeight + 1),

		Size = UDim2.new(1, 0, 0, summaryHeight - 1),

		BackgroundTransparency = 1,

		BorderSizePixel = 0,

		Active = true,
		InputSink = true,
		AutoButtonColor = false,

		ZIndex = zIndex + 2,
	}, frame)

	local summaryLabel = UI.create("TextLabel", {
		Name = "Message",

		Text = "",

		Position = UDim2.fromOffset(20, 0),

		Size = UDim2.new(1, -40, 1, 0),

		BackgroundTransparency = 1,

		BorderSizePixel = 0,

		TextSize = options.textSize or UI.tokens.type.body,

		TextColor3 = options.textColor or colors.subtext,

		TextTransparency = 1,

		TextWrapped = true,

		TextXAlignment = Enum.TextXAlignment.Left,

		ZIndex = zIndex + 3,
	}, summaryButton)

	local detailsFrame = UI.create("Frame", {
		Name = "Details",

		Position = UDim2.fromOffset(0, headerHeight + summaryHeight),

		Size = UDim2.new(1, 0, 0, expandedHeight - collapsedHeight),

		BackgroundTransparency = 1,

		BorderSizePixel = 0,

		Visible = false,

		ZIndex = zIndex + 2,
	}, frame)

	local detailsTitle = nil

	if options.detailsTitle then
		detailsTitle = UI.label(
			detailsFrame,
			options.detailsTitle,
			UDim2.fromOffset(20, 12),
			UDim2.new(1, -40, 0, 20),
			options.detailsTitleSize or UI.tokens.type.small,
			options.detailsTitleColor or colors.text
		)

		detailsTitle.TextXAlignment = Enum.TextXAlignment.Left

		detailsTitle.TextTransparency = 1

		detailsTitle.ZIndex = zIndex + 3
	end

	local detailsY = options.detailsTitle and 38 or 12

	local detailsLabel = UI.create("TextLabel", {
		Name = "DetailsText",

		Text = details,

		Position = UDim2.fromOffset(20, detailsY),

		Size = UDim2.new(1, -40, 1, -(detailsY + 12)),

		BackgroundTransparency = 1,

		BorderSizePixel = 0,

		TextSize = options.detailsTextSize or UI.tokens.type.small,

		TextColor3 = options.detailsTextColor or colors.subtext,

		TextTransparency = 1,

		TextWrapped = true,

		TextXAlignment = Enum.TextXAlignment.Left,

		ZIndex = zIndex + 3,
	}, detailsFrame)

	local expandIconImage = options.expandIcon or "builtin://global-icons/chevron-down.svg"
	local collapseIconImage = options.collapseIcon or "builtin://global-icons/chevron-up.svg"

	local expandButton, _, expandIcon = UI.iconButton(
		frame,
		expandIconImage,
		UDim2.new(1, -70, 0, 10),
		UDim2.fromOffset(32, 32),
		function() end,
		{
			color = colors.panelRaised,
			bgTransparency = 1,
			hoverColor = colors.hover,
			pressedColor = colors.pressed,
			iconSize = options.closeIconSize or 16,
			border = false,
		}
	)

	local closeButton, _, closeIcon = UI.iconButton(
		frame,
		options.closeIcon or "builtin://global-icons/x.svg",
		UDim2.new(1, -46, 0, 10),
		UDim2.fromOffset(32, 32),
		function() end,
		{
			color = colors.panelRaised,
			bgTransparency = 1,
			hoverColor = colors.hover,
			pressedColor = colors.pressed,
			iconSize = options.closeIconSize or 16,
			border = false,
		}
	)

	local progressBackground = UI.frame(
		frame,
		UDim2.new(0, 0, 1, -progressHeight),
		UDim2.new(1, 0, 0, progressHeight),
		options.progressBackgroundColor or colors.input
	)

	progressBackground.ZIndex = zIndex + 4
	progressBackground.BackgroundTransparency = 1

	local progress = UI.frame(progressBackground, UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), accentColor)

	progress.ZIndex = zIndex + 5
	progress.BackgroundTransparency = 1

	local state = {
		alpha = 0,

		y = margin - slideDistance,
		targetY = margin,

		elapsed = 0,

		timerStopped = false,

		expanded = false,

		closing = false,
		destroyed = false,

		reason = nil,
	}

	local record = {
		frame = frame,
		state = state,
		controller = controller,
	}

	table.insert(shared.toasts, 1, record)

	local function reflowToasts()
		local y = margin

		for _, toast in ipairs(shared.toasts) do
			if not toast.state.destroyed then
				toast.state.targetY = y

				y += toast.frame.Size.Y.Offset + gap
			end
		end
	end

	local function removeToast()
		for index, toast in ipairs(shared.toasts) do
			if toast == record then
				table.remove(shared.toasts, index)

				break
			end
		end

		reflowToasts()
	end

	local function updateSummary()
		if duration <= 0 then
			if messagePrefix ~= "" then
				summaryLabel.Text = messagePrefix
			else
				summaryLabel.Text = "Click  to close."
			end

			return
		end

		if state.timerStopped then
			if messagePrefix ~= "" then
				summaryLabel.Text = messagePrefix .. " Automatic closing stopped."
			else
				summaryLabel.Text = "Automatic closing stopped."
			end

			return
		end

		local remaining = math.max(duration - state.elapsed, 0)

		local seconds = math.ceil(remaining)

		local timerText =
			string.format("This message will close in %d second%s. Click to stop.", seconds, seconds == 1 and "" or "s")

		if messagePrefix ~= "" then
			summaryLabel.Text = messagePrefix .. " " .. timerText
		else
			summaryLabel.Text = timerText
		end
	end

	local function setExpanded(expanded)
		if not hasDetails then
			return false
		end

		expanded = expanded == true

		if state.expanded == expanded then
			return true
		end

		state.expanded = expanded

		if expanded then
			frame.Size = UDim2.fromOffset(width, expandedHeight)

			detailsFrame.Visible = true

			expandIcon.Image = collapseIconImage

			if options.stopOnExpand ~= false and duration > 0 then
				state.timerStopped = true
			end
		else
			frame.Size = UDim2.fromOffset(width, collapsedHeight)

			detailsFrame.Visible = false

			expandIcon.Image = expandIconImage
		end

		updateSummary()
		reflowToasts()

		if options.onExpand then
			options.onExpand(expanded, controller)
		end

		return true
	end

	local heartbeatConnection = nil

	controller.frame = frame
	controller.detailsFrame = detailsFrame
	controller.summary = summaryLabel
	controller.details = detailsLabel

	function controller:IsOpen()
		return not state.destroyed and not state.closing
	end

	function controller:IsExpanded()
		return state.expanded
	end

	function controller:Expand()
		return setExpanded(true)
	end

	function controller:Collapse()
		return setExpanded(false)
	end

	function controller:Toggle()
		return setExpanded(not state.expanded)
	end

	function controller:StopTimer()
		if state.timerStopped then
			return
		end

		state.timerStopped = true

		updateSummary()

		if options.onStop then
			options.onStop(controller)
		end
	end

	function controller:SetTitle(newTitle)
		title = tostring(newTitle or "")

		titleLabel.Text = title
	end

	function controller:SetMessage(newMessage)
		messagePrefix = tostring(newMessage or "")

		updateSummary()
	end

	function controller:SetDetails(newDetails)
		details = tostring(newDetails or "")

		detailsLabel.Text = details

		hasDetails = details ~= "" or options.buildDetails ~= nil

		expandButton.Visible = hasDetails
		expandButton.Active = hasDetails
		expandButton.InputSink = hasDetails

		if not hasDetails and state.expanded then
			setExpanded(false)
		end
	end

	function controller:SetDuration(seconds)
		duration = math.max(tonumber(seconds) or 0, 0)

		state.elapsed = 0
		state.timerStopped = false

		updateSummary()
	end

	function controller:SetType(newType)
		local config = typeConfigs[newType]

		if not config then
			return false
		end

		kind = newType
		typeConfig = config

		accentColor = config.color

		progress.BackgroundColor3 = accentColor

		return true
	end

	function controller:Close(reason)
		if state.destroyed or state.closing then
			return false
		end

		state.closing = true

		state.reason = reason or "closed"

		return true
	end

	function controller:Destroy()
		if state.destroyed then
			return
		end

		state.destroyed = true

		if heartbeatConnection then
			heartbeatConnection:Disconnect()
			heartbeatConnection = nil
		end

		removeToast()

		UI.forgetButtons(frame)

		frame:Destroy()
	end

	summaryButton.MouseButton1Click:Connect(function()
		controller:StopTimer()
	end)

	expandButton.MouseButton1Click:Connect(function()
		controller:Toggle()
	end)

	closeButton.MouseButton1Click:Connect(function()
		controller:Close("close")
	end)

	if options.buildDetails then
		options.buildDetails(detailsFrame, controller)
	end

	updateSummary()
	reflowToasts()

	heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		if state.destroyed then
			if heartbeatConnection then
				heartbeatConnection:Disconnect()
				heartbeatConnection = nil
			end

			return
		end

		if not state.closing and not state.timerStopped and duration > 0 then
			state.elapsed += dt

			if state.elapsed >= duration then
				state.elapsed = duration

				controller:Close("timeout")
			end
		end

		updateSummary()

		local progressAlpha = 0

		if duration > 0 then
			progressAlpha = math.clamp((duration - state.elapsed) / duration, 0, 1)
		end

		progress.Size = UDim2.new(progressAlpha, 0, 1, 0)

		local targetAlpha = state.closing and 0 or 1

		state.alpha = tooltipSmoothTowards(state.alpha, targetAlpha, fadeSpeed, dt)

		state.y = tooltipSmoothTowards(state.y, state.targetY, moveSpeed, dt)

		if math.abs(state.alpha - targetAlpha) < 0.005 then
			state.alpha = targetAlpha
		end

		if math.abs(state.y - state.targetY) < 0.1 then
			state.y = state.targetY
		end

		local slide = (1 - state.alpha) * -slideDistance

		frame.Position = UDim2.new(0.5, 0, 0, state.y + slide)

		frame.BackgroundTransparency = 1 - state.alpha * (1 - backgroundTransparency)

		border.Transparency = 1 - state.alpha * (1 - borderTransparency)

		titleLabel.TextTransparency = 1 - state.alpha

		summaryLabel.TextTransparency = 1 - state.alpha

		progressBackground.BackgroundTransparency = 1 - state.alpha

		progress.BackgroundTransparency = 1 - state.alpha

		if state.expanded then
			detailsLabel.TextTransparency = 1 - state.alpha

			if detailsTitle then
				detailsTitle.TextTransparency = 1 - state.alpha
			end
		end

		if shadow then
			local wantedShadowTransparency = options.shadowTransparency or 0.5

			shadow.Transparency = 1 - state.alpha * (1 - wantedShadowTransparency)
		end

		if state.closing and state.alpha <= 0.001 then
			if heartbeatConnection then
				heartbeatConnection:Disconnect()
				heartbeatConnection = nil
			end

			state.destroyed = true

			removeToast()

			UI.forgetButtons(frame)

			frame:Destroy()

			if options.onClose then
				options.onClose(state.reason, controller)
			end
		end
	end)

	return controller
end

local function pointInside(gui, point)
	local position, size = gui.AbsolutePosition, gui.AbsoluteSize

	return position
		and size
		and point.X >= position.X
		and point.Y >= position.Y
		and point.X <= position.X + size.X
		and point.Y <= position.Y + size.Y
end

UI.pointInside = pointInside

local closeActiveDropdown

local function wireNativeButton(button, record, enableHovering)
	button.MouseEnter:Connect(function()
		if record.enabled and enableHovering then
			button.BackgroundColor3 = record.hoverColor
		end
	end)

	button.MouseLeave:Connect(function()
		if enableHovering then
			button.BackgroundColor3 = record.color
		end
	end)

	button.MouseButton1Down:Connect(function()
		if not record.enabled then
			return
		end

		button.BackgroundColor3 = record.pressedColor
	end)

	button.MouseButton1Up:Connect(function(x, y)
		if not record.enabled then
			button.BackgroundColor3 = record.color
			return
		end

		local point = Vector2.new(x, y)

		if enableHovering and pointInside(button, point) then
			button.BackgroundColor3 = record.hoverColor
		else
			button.BackgroundColor3 = record.color
		end
	end)

	button.MouseButton1Click:Connect(function()
		if not record.enabled then
			return
		end

		local active = shared.activeDropdown

		if active and closeActiveDropdown and active.closeOnOutsideClick ~= false then
			local insideButton = button == active.button or button:IsDescendantOf(active.button)

			local insideMenu = active.menu and (button == active.menu or button:IsDescendantOf(active.menu))

			if not insideButton and not insideMenu then
				closeActiveDropdown()
			end
		end

		record.callback()
	end)
end

function UI.setButtonState(record, state)
	if not record or record.destroyed or not UI.isAlive(record.gui) then
		return
	end

	local colors = UI.tokens.color

	if state == "selected" then
		record.state = "selected"
		record.color, record.hoverColor = colors.selection, colors.selectionHover
	elseif state == "accent" then
		record.state = "accent"
		record.color, record.hoverColor = colors.accentSoft, colors.accent
	else
		record.state = nil
		record.color, record.hoverColor = record.defaultColor, record.defaultHoverColor
	end

	record.gui.BackgroundColor3 = record.color
end

function UI.menuBar(parent, position, size, menus, options)
	options = options or {}

	local tokens = UI.tokens
	local colors = tokens.color

	local height = (size and size.Y.Offset) or options.height or 28
	local inset = options.inset or 3
	local gap = options.gap or 1
	local paddingX = options.paddingX or 10
	local textSize = options.textSize or tokens.type.small
	local charWidth = options.charWidth or (textSize * 0.6)
	local radius = options.radius or tokens.radius.md
	local triggerRadius = options.triggerRadius or tokens.radius.sm
	local menuGap = options.menuGap or 4

	local palette = {
		bar = options.color or colors.panel,
		border = options.borderColor or colors.border,
		hover = options.hoverColor or colors.hover,
		text = options.textColor or colors.text,
		subtext = options.subtextColor or colors.subtext,
	}

	local entries = {}
	local connections = {}
	local state = { open = nil, destroyed = false }

	-- width of the whole bar
	local totalWidth = inset * 2
	local widths = {}

	for index, definition in ipairs(menus or {}) do
		local width = definition.width or (math.ceil(#tostring(definition.name) * charWidth) + paddingX * 2)

		widths[index] = width
		totalWidth += width + (index > 1 and gap or 0)
	end

	local container = UI.frame(
		parent,
		position or UDim2.fromOffset(0, 0),
		UDim2.fromOffset(size and size.X.Offset > 0 and size.X.Offset or totalWidth, height),
		palette.bar,
		radius
	)

	container.Name = options.name or "MenuBar"
	container.BackgroundTransparency = options.transparent and 1 or 0

	local stroke = UI.stroke(container, palette.border, 1, options.borderTransparency or 0.45)

	local function paint(entry)
		local active = state.open == entry.index

		entry.button.BackgroundColor3 = palette.hover

		if active then
			entry.button.BackgroundTransparency = 0
		elseif entry.hovered then
			entry.button.BackgroundTransparency = 0.4
		else
			entry.button.BackgroundTransparency = 1
		end

		entry.label.TextColor3 = (active or entry.hovered) and palette.text or palette.subtext
	end

	local function repaintAll()
		for _, entry in ipairs(entries) do
			paint(entry)
		end
	end

	local function closeOpen(reason)
		local entry = state.open and entries[state.open]

		state.open = nil

		if entry then
			entry.menu:Close(reason or "menubar")
		end

		repaintAll()
	end

	local function openMenu(index)
		local entry = entries[index]

		if not entry or state.open == index then
			return
		end

		local previous = state.open and entries[state.open]

		state.open = index

		if previous then
			previous.menu:Close("switch")
		end

		entry.menu:Open()

		repaintAll()
	end

	local x = inset

	for index, definition in ipairs(menus or {}) do
		local width = widths[index]

		local button = UI.create("TextButton", {
			Name = tostring(definition.name) .. "Trigger",
			Text = "",
			Position = UDim2.fromOffset(x, inset),
			Size = UDim2.fromOffset(width, height - inset * 2),
			BackgroundColor3 = palette.hover,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Active = true,
			InputSink = true,
		}, container)

		UI.corner(button, triggerRadius)

		local label =
			UI.label(button, definition.name, UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), textSize, palette.subtext)

		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextYAlignment = Enum.TextYAlignment.Center

		local menuOptions = {
			items = definition.items,
			menuWidth = definition.menuWidth or options.menuWidth or 200,
			itemHeight = options.itemHeight or 28,
			maxVisibleItems = options.maxVisibleItems or 12,

			menuPosition = function()
				local buttonPosition = button.AbsolutePosition
				local barPosition = container.AbsolutePosition

				return Vector2.new(buttonPosition.X, barPosition.Y + container.AbsoluteSize.Y + menuGap)
			end,

			onClose = function()
				if state.open == index then
					state.open = nil
					repaintAll()
				end
			end,
		}

		for key, value in pairs(options.menuOptions or {}) do
			menuOptions[key] = value
		end

		local entry = {
			index = index,
			name = definition.name,
			button = button,
			label = label,
			hovered = false,
			menu = UI.contextMenu(menuOptions),
		}

		entries[index] = entry

		button.MouseButton1Click:Connect(function()
			if state.open == index then
				closeOpen("toggle")
			else
				openMenu(index)
			end
		end)

		button.MouseEnter:Connect(function()
			entry.hovered = true

			-- once any menu is open, hovering another trigger switches to it
			if state.open ~= nil and state.open ~= index then
				openMenu(index)
			else
				paint(entry)
			end
		end)

		button.MouseLeave:Connect(function()
			entry.hovered = false
			paint(entry)
		end)

		x += width + gap
	end

	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input)
			if state.open == nil or state.destroyed then
				return
			end

			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				local mouse = UserInputService:GetMouseLocation()
				local entry = entries[state.open]

				if entry and entry.menu:ContainsPoint(mouse.X, mouse.Y) then
					return
				end

				if UI.pointInside(container, mouse) then
					return -- the trigger's own click handler deals with this
				end

				closeOpen("outside")
			elseif input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.Right then
				local step = input.KeyCode == Enum.KeyCode.Right and 1 or -1
				local count = #entries

				if count > 1 then
					openMenu(((state.open - 1 + step) % count) + 1)
				end
			end
		end)
	)

	local controller = { frame = container, entries = entries }

	function controller:GetWidth()
		return container.Size.X.Offset
	end

	function controller:IsOpen()
		return state.open ~= nil
	end

	function controller:Open(nameOrIndex)
		if type(nameOrIndex) == "number" then
			openMenu(nameOrIndex)

			return
		end

		for index, entry in ipairs(entries) do
			if entry.name == nameOrIndex then
				openMenu(index)

				return
			end
		end
	end

	function controller:Close()
		closeOpen("api")
	end

	function controller:SetColors(new)
		for key, value in pairs(new or {}) do
			if palette[key] ~= nil then
				palette[key] = value
			end
		end

		container.BackgroundColor3 = palette.bar
		stroke.Color = palette.border

		repaintAll()
	end

	function controller:Destroy()
		if state.destroyed then
			return
		end

		state.destroyed = true

		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end

		for _, entry in ipairs(entries) do
			entry.menu:Destroy()
		end

		UI.forgetButtons(container)
		container:Destroy()
	end

	repaintAll()

	return container, controller
end

function UI.button(parent, text, position, size, callback, options)
	options = options or {}

	local colors, padding = UI.tokens.color, options.paddingX or UI.tokens.space.md

	local color = options.color or colors.panelRaised

	local button = UI.create("TextButton", {
		Text = "",
		Position = position or UDim2.fromOffset(0, 0),
		Size = size or UDim2.fromOffset(100, UI.metrics.buttonHeight),
		BackgroundColor3 = color,
		BackgroundTransparency = options.bgTransparency,
		BorderSizePixel = 0,
		Active = options.enabled ~= false,
		InputSink = true,
		AutoButtonColor = false,
	}, parent)

	local radius = options.radius or UI.tokens.radius.sm

	if radius and radius > 0 then
		UI.corner(button, radius)
	end

	local label = UI.label(
		button,
		text,
		UDim2.fromOffset(padding, options.textY or 3),
		UDim2.new(1, -padding * 2, 1, -(options.textY or 3)),
		options.textSize or UI.tokens.type.small,
		options.textColor or colors.subtext
	)

	if options.icon then
		local iconSize = options.iconSize or 16

		UI.image(
			button,
			options.icon,
			UDim2.fromOffset(6, math.floor((((size and size.Y.Offset) or UI.metrics.buttonHeight) - iconSize) / 2)),
			UDim2.fromOffset(iconSize, iconSize)
		)

		label.Position = UDim2.fromOffset(iconSize + 12, options.textY or 3)
	end

	if options.border ~= false then
		UI.stroke(button, options.borderColor or colors.border, 1, options.borderTransparency or 0)
	end

	local record = {

		gui = button,

		callback = callback or function() end,

		color = color,

		defaultColor = color,

		hoverColor = options.hoverColor or colors.hover,

		defaultHoverColor = options.hoverColor or colors.hover,

		pressedColor = options.pressedColor or colors.pressed,

		enabled = options.enabled ~= false,
	}

	table.insert(shared.buttons, record)

	wireNativeButton(button, record, options.hoveringEnabled ~= false)

	if options.selected then
		UI.setButtonState(record, "selected")
	end

	return button, label, record
end

function UI.iconButton(parent, icon, position, size, callback, options)
	options = options or {}

	local button, _, record = UI.button(parent, "", position, size, callback, options)

	local iconSize = options.iconSize or 16

	local image = UI.image(
		button,
		icon,
		UDim2.new(0.5, -math.floor(iconSize / 2), 0.5, -math.floor(iconSize / 2)),
		UDim2.fromOffset(iconSize, iconSize)
	)

	return button, record, image
end

function UI.graph(parent, position, size, options)
	options = options or {}

	local colors = UI.tokens.color
	local UserInputService = game:GetService("UserInputService")

	local palette = {
		Color3.fromRGB(76, 114, 176),
		Color3.fromRGB(221, 132, 82),
		Color3.fromRGB(85, 168, 104),
		Color3.fromRGB(196, 78, 82),
		Color3.fromRGB(129, 114, 179),
		Color3.fromRGB(147, 120, 96),
		Color3.fromRGB(218, 139, 195),
		Color3.fromRGB(140, 140, 140),
	}

	local interactive = options.interactive ~= false
	local tickTextSize = options.tickTextSize or UI.tokens.type.caption
	local legendMode = options.legend
	if legendMode == nil then
		legendMode = "top-left"
	end

	local marginLeft = options.leftMargin or (options.yLabel and 58 or 42)
	local marginRight = options.rightMargin or 14
	local marginTop = options.topMargin or (options.title and 30 or 12)
	local marginBottom = options.bottomMargin or (options.xLabel and 42 or 26)

	local state = {
		series = {},
		title = options.title,
		xLabel = options.xLabel,
		yLabel = options.yLabel,
		fixed = { xMin = options.xMin, xMax = options.xMax, yMin = options.yMin, yMax = options.yMax },
		auto = { xMin = 0, xMax = 1, yMin = 0, yMax = 1 },
		xMin = 0,
		xMax = 1,
		yMin = 0,
		yMax = 1,
		target = nil,
		clearAfter = false,
		dirty = false,
		cache = nil,
		destroyed = false,
	}

	local function getX(s, i)
		if s.xs then
			return s.xs[i]
		end
		return s.x0 + i - 1
	end

	local function niceStep(range, count)
		if range <= 0 then
			return 1
		end

		local rough = range / math.max(count - 1, 1)
		local exponent = math.floor(math.log10(rough))
		local fraction = rough / 10 ^ exponent

		local nice
		if fraction <= 1 then
			nice = 1
		elseif fraction <= 2 then
			nice = 2
		elseif fraction <= 5 then
			nice = 5
		else
			nice = 10
		end

		return nice * 10 ^ exponent
	end

	local function formatTick(value, step)
		if step >= 1 then
			return string.format("%d", math.floor(value + 0.5))
		end

		local decimals = math.clamp(-math.floor(math.log10(step)), 0, 8)
		return string.format("%." .. decimals .. "f", value)
	end

	local function formatValue(value)
		return string.format("%.4g", value)
	end

	local function clearChildren(frame)
		for _, child in ipairs(frame:GetChildren()) do
			if not (child:IsA("UICorner") or child:IsA("UIStroke") or child:IsA("UIGradient")) then
				child:Destroy()
			end
		end
	end

	local function makeLabel(layer, text, pos, sz, textSize, color, alignX)
		local label = UI.label(layer, text, pos, sz, textSize, color)
		label.TextXAlignment = alignX or Enum.TextXAlignment.Center
		label.TextYAlignment = Enum.TextYAlignment.Center
		return label
	end

	local function line(layer, x1, y1, x2, y2, thickness, color)
		local dx, dy = x2 - x1, y2 - y1
		local length = math.sqrt(dx * dx + dy * dy)

		if length < 0.01 then
			return
		end

		UI.create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2),
			Size = UDim2.fromOffset(length + thickness * 0.5, thickness),
			Rotation = math.deg(math.atan2(dy, dx)),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
		}, layer)
	end

	local function clipSegment(x1, y1, x2, y2, w, h)
		local dx, dy = x2 - x1, y2 - y1
		local t0, t1 = 0, 1

		local p = { -dx, dx, -dy, dy }
		local q = { x1 + 2, w + 2 - x1, y1 + 2, h + 2 - y1 }

		for i = 1, 4 do
			if p[i] == 0 then
				if q[i] < 0 then
					return nil
				end
			else
				local r = q[i] / p[i]

				if p[i] < 0 then
					if r > t1 then
						return nil
					end
					if r > t0 then
						t0 = r
					end
				else
					if r < t0 then
						return nil
					end
					if r < t1 then
						t1 = r
					end
				end
			end
		end

		return x1 + t0 * dx, y1 + t0 * dy, x1 + t1 * dx, y1 + t1 * dy
	end

	local container = UI.frame(
		parent,
		position or UDim2.fromOffset(0, 0),
		size or UDim2.fromOffset(500, 300),
		options.color or colors.panel
	)

	container.Name = options.name or "Graph"
	container.BackgroundTransparency = options.color and 0 or 1

	local tickLayer = UI.create("Frame", {
		Name = "Ticks",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, container)

	local plot = UI.frame(
		container,
		UDim2.fromOffset(marginLeft, marginTop),
		UDim2.new(1, -(marginLeft + marginRight), 1, -(marginTop + marginBottom)),
		options.plotColor or colors.input,
		UI.tokens.radius.xs
	)

	plot.Name = "Plot"
	plot.ClipsDescendants = true
	UI.stroke(plot, colors.border, 1, 0)

	local function newLayer(name)
		return UI.create("Frame", {
			Name = name,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, plot)
	end

	local gridLayer = newLayer("Grid")
	local seriesLayer = newLayer("Series")
	local overlayLayer = newLayer("Overlay")

	local crossLine = UI.frame(overlayLayer, UDim2.fromOffset(0, 0), UDim2.new(0, 1, 1, 0), colors.subtext)
	crossLine.BackgroundTransparency = 0.5
	crossLine.Visible = false

	local dots = {}

	local selFrame = UI.frame(overlayLayer, UDim2.fromOffset(0, 0), UDim2.fromOffset(0, 0), colors.accent)
	selFrame.Name = "Selection"
	selFrame.BackgroundTransparency = 0.8
	selFrame.Visible = false
	UI.stroke(selFrame, colors.accent, 1, 0.1)

	local selLabel = UI.label(overlayLayer, "", UDim2.fromOffset(0, 0), UDim2.fromOffset(120, 16), 11, colors.text)
	selLabel.Name = "SelectionLabel"
	selLabel.Visible = false
	selLabel.TextXAlignment = Enum.TextXAlignment.Center
	selLabel.BackgroundTransparency = 0.15
	selLabel.BackgroundColor3 = colors.panelRaised

	local hit = UI.create("TextButton", {
		Name = "Hit",
		Text = "",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Active = true,
		InputSink = false,
	}, plot)

	local legendFrame = nil

	local function plotSize()
		local s = plot.AbsoluteSize
		return math.max(s.X, 1), math.max(s.Y, 1)
	end

	local function invalidate()
		state.cache = nil
	end

	local function scanExtent(x0, x1)
		local function run(onlyVisible)
			local xMin, xMax, yMin, yMax = math.huge, -math.huge, math.huge, -math.huge

			for _, s in ipairs(state.series) do
				if not onlyVisible or s.visible then
					for i, v in ipairs(s.values) do
						local x = getX(s, i)

						if not x0 or (x >= x0 and x <= x1) then
							xMin = math.min(xMin, x)
							xMax = math.max(xMax, x)
							yMin = math.min(yMin, v)
							yMax = math.max(yMax, v)
						end
					end
				end
			end

			if xMin == math.huge then
				return nil
			end

			return { xMin = xMin, xMax = xMax, yMin = yMin, yMax = yMax }
		end

		return run(true) or run(false)
	end

	local function niceY(yMin, yMax)
		if options.includeZero ~= false then
			yMin = math.min(yMin, 0)
			yMax = math.max(yMax, 0)
		end

		if yMax - yMin < 1e-9 then
			yMin -= 1
			yMax += 1
		end

		local _, ph = plotSize()
		local count = math.clamp(math.floor(ph / 40) + 1, 3, 11)
		local step = niceStep(yMax - yMin, count)

		return math.floor(yMin / step) * step, math.ceil(yMax / step) * step
	end

	local function computeBounds()
		local full = state.cache

		if not full then
			full = scanExtent() or { xMin = 0, xMax = 1, yMin = 0, yMax = 1 }
			state.cache = full
		end

		local axMin, axMax = full.xMin, full.xMax

		if axMax - axMin < 1e-9 then
			axMin -= 1
			axMax += 1
		end

		local ayMin, ayMax = niceY(full.yMin, full.yMax)

		state.auto = { xMin = axMin, xMax = axMax, yMin = ayMin, yMax = ayMax }

		local fixed = state.fixed

		state.xMin = fixed.xMin or axMin
		state.xMax = fixed.xMax or axMax

		if state.xMax - state.xMin < 1e-12 then
			state.xMax = state.xMin + 1e-12
		end

		if fixed.yMin and fixed.yMax then
			state.yMin, state.yMax = fixed.yMin, fixed.yMax
		else
			local yMin, yMax = ayMin, ayMax

			if options.autoFitY and (fixed.xMin or fixed.xMax) then
				local visible = scanExtent(state.xMin, state.xMax)

				if visible then
					yMin, yMax = niceY(visible.yMin, visible.yMax)
				end
			end

			state.yMin = fixed.yMin or yMin
			state.yMax = fixed.yMax or yMax
		end

		if state.yMax - state.yMin < 1e-12 then
			state.yMax = state.yMin + 1e-12
		end
	end

	local redraw

	local function buildLegend()
		if legendFrame then
			UI.forgetButtons(legendFrame)
			legendFrame:Destroy()
			legendFrame = nil
		end

		if not legendMode or #state.series == 0 then
			return
		end

		local rowHeight = 20
		local widest = 0

		for _, s in ipairs(state.series) do
			widest = math.max(widest, #s.name)
		end

		local width = widest * 7 + 38
		local height = #state.series * rowHeight + 6

		local anchor = Vector2.new(0, 0)
		local pos = UDim2.fromOffset(marginLeft + 8, marginTop + 8)

		if legendMode == "top-right" then
			anchor = Vector2.new(1, 0)
			pos = UDim2.new(1, -(marginRight + 8), 0, marginTop + 8)
		end

		legendFrame = UI.frame(container, pos, UDim2.fromOffset(width, height), colors.panel, UI.tokens.radius.xs)
		legendFrame.Name = "Legend"
		legendFrame.AnchorPoint = anchor
		legendFrame.BackgroundTransparency = 0.1
		UI.stroke(legendFrame, colors.border, 1, 0)

		for index, s in ipairs(state.series) do
			local row, label = UI.button(
				legendFrame,
				s.name,
				UDim2.fromOffset(3, 3 + (index - 1) * rowHeight),
				UDim2.new(1, -6, 0, rowHeight),
				function()
					s.visible = not s.visible
					invalidate()
					buildLegend()
					redraw()
				end,
				{
					color = colors.panel,
					hoverColor = colors.hover,
					pressedColor = colors.pressed,
					textColor = s.visible and colors.text or colors.muted,
					textSize = UI.tokens.type.small,
					radius = UI.tokens.radius.xs,
					border = false,
					bgTransparency = 1,
				}
			)

			row.Name = s.name

			label.Position = UDim2.fromOffset(24, 0)
			label.Size = UDim2.new(1, -28, 1, 0)
			label.TextXAlignment = Enum.TextXAlignment.Left

			local swatch = UI.frame(row, UDim2.fromOffset(6, 5), UDim2.fromOffset(11, 11), s.color, 2)
			swatch.BackgroundTransparency = s.visible and 0 or 0.7
		end
	end

	local function lowerBound(s, x)
		local lo, hi = 1, #s.values + 1

		while lo < hi do
			local mid = math.floor((lo + hi) / 2)

			if getX(s, mid) < x then
				lo = mid + 1
			else
				hi = mid
			end
		end

		return lo
	end

	local lastNotified = nil

	redraw = function()
		if state.destroyed then
			return
		end

		clearChildren(tickLayer)
		clearChildren(gridLayer)
		clearChildren(seriesLayer)

		computeBounds()

		local pw, ph = plotSize()
		local xMin, xMax, yMin, yMax = state.xMin, state.xMax, state.yMin, state.yMax

		local function toX(x)
			return (x - xMin) / (xMax - xMin) * pw
		end

		local function toY(y)
			return ph - (y - yMin) / (yMax - yMin) * ph
		end

		local yTicks = math.clamp(math.floor(ph / 40) + 1, 3, 11)
		local yStep = niceStep(yMax - yMin, yTicks)
		local yStart = math.ceil(yMin / yStep - 1e-9) * yStep

		local labelX = options.yLabel and 18 or 0

		local value = yStart
		local guard = 0
		while value <= yMax + yStep * 1e-6 and guard < 64 do
			guard += 1
			local py = toY(value)

			if options.grid ~= false then
				local g = UI.frame(gridLayer, UDim2.fromOffset(0, math.floor(py)), UDim2.new(1, 0, 0, 1), colors.border)
				g.BackgroundTransparency = 0.45
			end

			makeLabel(
				tickLayer,
				formatTick(value, yStep),
				UDim2.fromOffset(labelX, marginTop + py - 8),
				UDim2.fromOffset(marginLeft - 6 - labelX, 16),
				tickTextSize,
				colors.subtext,
				Enum.TextXAlignment.Right
			)

			value += yStep
		end

		local xTicks = math.clamp(math.floor(pw / 70) + 1, 3, 11)
		local xStep = niceStep(xMax - xMin, xTicks)
		local xStart = math.ceil(xMin / xStep - 1e-9) * xStep

		value = xStart
		guard = 0
		while value <= xMax + xStep * 1e-6 and guard < 64 do
			guard += 1
			local px = toX(value)

			if options.grid ~= false then
				local g = UI.frame(gridLayer, UDim2.fromOffset(math.floor(px), 0), UDim2.new(0, 1, 1, 0), colors.border)
				g.BackgroundTransparency = 0.45
			end

			makeLabel(
				tickLayer,
				formatTick(value, xStep),
				UDim2.fromOffset(marginLeft + px - 25, marginTop + ph + 4),
				UDim2.fromOffset(50, 14),
				tickTextSize,
				colors.subtext
			)

			value += xStep
		end

		if state.title then
			makeLabel(
				tickLayer,
				state.title,
				UDim2.fromOffset(marginLeft, 4),
				UDim2.fromOffset(pw, 20),
				UI.tokens.type.body,
				colors.text
			)
		end

		if state.xLabel then
			makeLabel(
				tickLayer,
				state.xLabel,
				UDim2.fromOffset(marginLeft, marginTop + ph + 20),
				UDim2.fromOffset(pw, 16),
				UI.tokens.type.small,
				colors.text
			)
		end

		if state.yLabel then
			local yl = makeLabel(
				tickLayer,
				state.yLabel,
				UDim2.fromOffset(9, marginTop + ph / 2),
				UDim2.fromOffset(ph, 16),
				UI.tokens.type.small,
				colors.text
			)
			yl.AnchorPoint = Vector2.new(0.5, 0.5)
			yl.Rotation = -90
		end

		for _, s in ipairs(state.series) do
			local n = #s.values

			if s.visible and n > 0 then
				local first = math.max(1, lowerBound(s, xMin) - 1)
				local last = math.min(n, lowerBound(s, xMax))

				if last >= first then
					local count = last - first + 1
					local stride = math.max(1, math.floor(count / (pw * 1.5)))
					local px, py = {}, {}

					local function addPoint(i)
						table.insert(px, toX(getX(s, i)))
						table.insert(py, toY(s.values[i]))
					end

					local i = first
					local lastAdded = first

					while i <= last do
						addPoint(i)
						lastAdded = i
						i += stride
					end

					if lastAdded ~= last then
						addPoint(last)
					end

					if s.fill and #px >= 2 then
						local colW = 2
						local j = 1

						local c0 = math.max(math.floor(px[1]), 0)
						local c1 = math.min(math.ceil(px[#px]), pw) - 1

						for col = c0, c1, colW do
							local cx = col + colW / 2

							while j < #px - 1 and px[j + 1] < cx do
								j += 1
							end

							local span = px[j + 1] - px[j]
							local t = span > 0 and math.clamp((cx - px[j]) / span, 0, 1) or 0
							local y = py[j] + (py[j + 1] - py[j]) * t

							if y < ph then
								y = math.max(y, -1)

								local c = UI.frame(
									seriesLayer,
									UDim2.fromOffset(col, y),
									UDim2.fromOffset(colW, ph - y),
									s.color
								)
								c.BackgroundTransparency = s.fillTransparency
							end
						end
					end

					for k = 1, #px - 1 do
						local ax, ay, bx, by = clipSegment(px[k], py[k], px[k + 1], py[k + 1], pw, ph)

						if ax then
							line(seriesLayer, ax, ay, bx, by, s.thickness, s.color)
						end
					end

					if #px == 1 then
						local dot = UI.frame(
							seriesLayer,
							UDim2.fromOffset(px[1] - 2, py[1] - 2),
							UDim2.fromOffset(4, 4),
							s.color,
							2
						)
						dot.Name = "Point"
					end
				end
			end
		end

		if options.onViewChanged then
			local v = lastNotified

			if not v or v[1] ~= state.xMin or v[2] ~= state.xMax or v[3] ~= state.yMin or v[4] ~= state.yMax then
				lastNotified = { state.xMin, state.xMax, state.yMin, state.yMax }
				options.onViewChanged(state.xMin, state.xMax, state.yMin, state.yMax)
			end
		end
	end

	local function clampAxis(lo, hi, aLo, aHi)
		local aSpan = math.max(aHi - aLo, 1e-9)
		local minSpan = aSpan * 1e-7
		local maxSpan = aSpan * (options.maxZoomOut or 4)

		local span = hi - lo
		local clamped = math.clamp(span, minSpan, maxSpan)

		if clamped ~= span then
			local center = (lo + hi) / 2
			lo = center - clamped / 2
			hi = center + clamped / 2
			span = clamped
		end

		local keep = span * 0.1

		if hi < aLo + keep then
			local shift = aLo + keep - hi
			lo += shift
			hi += shift
		elseif lo > aHi - keep then
			local shift = lo - (aHi - keep)
			lo -= shift
			hi -= shift
		end

		return lo, hi
	end

	local function setTarget(partial, clearAfter)
		if options.smooth == false then
			for key, value in pairs(partial) do
				state.fixed[key] = value
			end

			state.target = nil

			if clearAfter then
				state.fixed = {}
			end

			state.dirty = true
			return
		end

		state.target = state.target or {}

		for key, value in pairs(partial) do
			state.target[key] = value
		end

		state.clearAfter = clearAfter == true
	end

	local function zoomAxis(axis, fraction, factor)
		local target = state.target
		local lo = (target and target[axis .. "Min"]) or state[axis .. "Min"]
		local hi = (target and target[axis .. "Max"]) or state[axis .. "Max"]

		local anchor = lo + fraction * (hi - lo)
		local span = (hi - lo) * factor

		lo, hi = anchor - fraction * span, anchor + (1 - fraction) * span
		lo, hi = clampAxis(lo, hi, state.auto[axis .. "Min"], state.auto[axis .. "Max"])

		return { [axis .. "Min"] = lo, [axis .. "Max"] = hi }
	end

	local function nearestIndex(s, x)
		local n = #s.values

		if n == 0 then
			return nil
		end

		local hi = math.min(lowerBound(s, x), n)
		local lo = math.max(hi - 1, 1)

		if math.abs(getX(s, lo) - x) <= math.abs(getX(s, hi) - x) then
			return lo
		end

		return hi
	end

	local function hideHover()
		crossLine.Visible = false

		for _, dot in ipairs(dots) do
			dot.Visible = false
		end
	end

	local tip = nil
	local hovering = false
	local lastMouse = Vector2.new(0, 0)
	local panning = nil
	local selecting = nil
	local lastClick = 0
	local connections = {}
	local controller_AutoFit

	local function isShift()
		return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
	end

	local function isCtrl()
		return UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
	end

	if options.crosshair ~= false then
		tip = UI.tooltip(hit, "", { followCursor = true, hoverDelay = 0, placement = "cursor" })
	end

	local function updateHover(mx)
		local pw, ph = plotSize()
		local lx = mx - plot.AbsolutePosition.X

		local dataX = state.xMin + math.clamp(lx / pw, 0, 1) * (state.xMax - state.xMin)

		local lines = {}
		local snapped = nil
		local dotIndex = 0

		for _, s in ipairs(state.series) do
			if s.visible then
				local i = nearestIndex(s, dataX)

				if i then
					local x, y = getX(s, i), s.values[i]

					snapped = snapped or x

					if #lines == 0 then
						table.insert(lines, (state.xLabel or "x") .. ": " .. formatValue(x))
					end

					table.insert(lines, s.name .. ": " .. formatValue(y))

					dotIndex += 1

					local dot = dots[dotIndex]

					if not dot then
						dot = UI.frame(overlayLayer, UDim2.fromOffset(0, 0), UDim2.fromOffset(7, 7), s.color, 4)
						dots[dotIndex] = dot
					end

					dot.BackgroundColor3 = s.color
					dot.Visible = true
					dot.Position = UDim2.fromOffset(
						(x - state.xMin) / (state.xMax - state.xMin) * pw - 3,
						ph - (y - state.yMin) / (state.yMax - state.yMin) * ph - 3
					)
				end
			end
		end

		for k = dotIndex + 1, #dots do
			dots[k].Visible = false
		end

		if snapped then
			crossLine.Visible = true
			crossLine.Position =
				UDim2.fromOffset(math.floor((snapped - state.xMin) / (state.xMax - state.xMin) * pw), 0)

			if tip then
				tip:SetText(table.concat(lines, "\n"))
			end
		else
			hideHover()
		end
	end

	hit.MouseEnter:Connect(function(x, y)
		hovering = true
		lastMouse = Vector2.new(x, y)
	end)

	hit.MouseLeave:Connect(function()
		hovering = false
		hideHover()
	end)

	hit.MouseMoved:Connect(function(x, y)
		lastMouse = Vector2.new(x, y)

		if panning or selecting then
			hideHover()
			return
		end

		if options.crosshair ~= false then
			updateHover(x)
		end
	end)

	local function updateSelection()
		if not selecting then
			selFrame.Visible = false
			selLabel.Visible = false
			return
		end

		local pw, ph = plotSize()
		local origin = plot.AbsolutePosition

		local x0 = math.clamp(selecting.start.X - origin.X, 0, pw)
		local x1 = math.clamp(selecting.current.X - origin.X, 0, pw)
		local y0 = math.clamp(selecting.start.Y - origin.Y, 0, ph)
		local y1 = math.clamp(selecting.current.Y - origin.Y, 0, ph)

		local left, right = math.min(x0, x1), math.max(x0, x1)
		local top, bottom = math.min(y0, y1), math.max(y0, y1)

		selecting.box = isShift()

		if not selecting.box then
			top, bottom = 0, ph
		end

		selecting.rect = { left = left, right = right, top = top, bottom = bottom }

		selFrame.Visible = true
		selFrame.Position = UDim2.fromOffset(left, top)
		selFrame.Size = UDim2.fromOffset(right - left, bottom - top)

		local width = (right - left) / pw * (state.xMax - state.xMin)

		selLabel.Visible = true
		selLabel.Text = " " .. formatValue(width)
		selLabel.Position = UDim2.fromOffset(
			math.clamp((left + right) / 2 - 60, 0, math.max(pw - 120, 0)),
			math.clamp(top + 4, 0, math.max(ph - 20, 0))
		)
	end

	if interactive then
		hit.MouseButton1Down:Connect(function(x, y)
			lastMouse = Vector2.new(x, y)

			local now = os.clock()

			if now - lastClick < 0.3 then
				lastClick = 0
				panning = nil
				controller_AutoFit()
				return
			end

			lastClick = now

			state.target = nil

			panning = {
				loc = UserInputService:GetMouseLocation(),
				view = { xMin = state.xMin, xMax = state.xMax, yMin = state.yMin, yMax = state.yMax },
				movedY = false,
			}

			if tip then
				tip:Hide()
			end

			hideHover()
		end)

		hit.MouseButton2Down:Connect(function(x, y)
			lastMouse = Vector2.new(x, y)

			state.target = nil

			selecting = {
				start = Vector2.new(x, y),
				current = Vector2.new(x, y),
				loc = UserInputService:GetMouseLocation(),
			}

			if tip then
				tip:Hide()
			end

			hideHover()
			updateSelection()
		end)

		table.insert(
			connections,
			UserInputService.InputChanged:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseWheel then
					if not hovering or panning or selecting then
						return
					end

					local steps = input.Position.Z

					if steps == 0 then
						return
					end

					local factor = (options.zoomSpeed or 0.8) ^ steps

					local pw, ph = plotSize()
					local origin = plot.AbsolutePosition

					local fx = math.clamp((lastMouse.X - origin.X) / pw, 0, 1)
					local fy = 1 - math.clamp((lastMouse.Y - origin.Y) / ph, 0, 1)

					local shift, ctrl = isShift(), isCtrl()

					local partial = {}

					if (not shift or ctrl) and options.zoomX ~= false then
						for k, v in pairs(zoomAxis("x", fx, factor)) do
							partial[k] = v
						end
					end

					if (shift or ctrl) and options.zoomY ~= false then
						for k, v in pairs(zoomAxis("y", fy, factor)) do
							partial[k] = v
						end
					end

					if next(partial) then
						setTarget(partial, false)
						hideHover()
					end
				elseif input.UserInputType == Enum.UserInputType.MouseMovement then
					if panning then
						local loc = UserInputService:GetMouseLocation()
						local dx, dy = loc.X - panning.loc.X, loc.Y - panning.loc.Y

						local pw, ph = plotSize()
						local v = panning.view
						local a = state.auto

						local shiftX = dx / pw * (v.xMax - v.xMin)
						local nx0, nx1 = clampAxis(v.xMin - shiftX, v.xMax - shiftX, a.xMin, a.xMax)

						state.fixed.xMin, state.fixed.xMax = nx0, nx1

						if options.panY ~= false and (panning.movedY or math.abs(dy) > 4) then
							panning.movedY = true

							local shiftY = dy / ph * (v.yMax - v.yMin)
							local ny0, ny1 = clampAxis(v.yMin + shiftY, v.yMax + shiftY, a.yMin, a.yMax)

							state.fixed.yMin, state.fixed.yMax = ny0, ny1
						end

						state.dirty = true
					elseif selecting then
						local loc = UserInputService:GetMouseLocation()

						selecting.current = selecting.start + (loc - selecting.loc)

						updateSelection()
					end
				end
			end)
		)

		table.insert(
			connections,
			UserInputService.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					if panning then
						panning = nil

						if tip and hovering then
							tip:Show()
						end
					end
				elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
					if selecting then
						local sel = selecting
						selecting = nil

						updateSelection()

						local rect = sel.rect

						if rect and rect.right - rect.left >= 4 then
							local pw, ph = plotSize()
							local a = state.auto

							local dx = state.xMax - state.xMin
							local x0 = state.xMin + rect.left / pw * dx
							local x1 = state.xMin + rect.right / pw * dx

							x0, x1 = clampAxis(x0, x1, a.xMin, a.xMax)

							local partial = { xMin = x0, xMax = x1 }

							if sel.box and rect.bottom - rect.top >= 4 then
								local dy = state.yMax - state.yMin
								local y1 = state.yMax - rect.top / ph * dy
								local y0 = state.yMax - rect.bottom / ph * dy

								y0, y1 = clampAxis(y0, y1, a.yMin, a.yMax)

								partial.yMin, partial.yMax = y0, y1
							end

							setTarget(partial, false)
						end

						if tip and hovering then
							tip:Show()
						end
					end
				end
			end)
		)
	end

	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(dt)
			if state.destroyed then
				return
			end

			local target = state.target

			if target then
				local speed = options.smoothSpeed or 16
				local done = true

				for key, goal in pairs(target) do
					local axis = string.sub(key, 1, 1)
					local span = math.max(state[axis .. "Max"] - state[axis .. "Min"], 1e-12)

					local current = state.fixed[key]

					if current == nil then
						current = state[key]
					end

					local nextValue = tooltipSmoothTowards(current, goal, speed, dt)

					if math.abs(nextValue - goal) < span * 1e-4 then
						nextValue = goal
					else
						done = false
					end

					state.fixed[key] = nextValue
				end

				if done then
					state.target = nil

					if state.clearAfter then
						state.fixed = {}
						state.clearAfter = false
					end
				end

				state.dirty = true
			end

			if state.dirty then
				state.dirty = false
				redraw()
			end
		end)
	)

	pcall(function()
		plot:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			state.dirty = true
		end)
	end)

	local function normalize(config, index)
		return {
			name = tostring(config.name or ("Series " .. index)),
			values = config.values or {},
			xs = config.xs,
			x0 = config.xStart or 0,
			color = config.color or palette[((index - 1) % #palette) + 1],
			fill = config.fill ~= nil and config.fill or options.fill ~= false,
			fillTransparency = config.fillTransparency or options.fillTransparency or 0.8,
			thickness = config.thickness or options.thickness or 1.5,
			visible = config.visible ~= false,
		}
	end

	local function find(name)
		for _, s in ipairs(state.series) do
			if s.name == name then
				return s
			end
		end

		return nil
	end

	local controller = { frame = container, plot = plot }

	function controller:SetSeries(list)
		state.series = {}

		for index, config in ipairs(list or {}) do
			table.insert(state.series, normalize(config, index))
		end

		invalidate()
		buildLegend()
		redraw()
	end

	function controller:AddSeries(config)
		table.insert(state.series, normalize(config, #state.series + 1))

		invalidate()
		buildLegend()
		redraw()
	end

	function controller:SetValues(name, values, xs)
		local s = find(name)

		if not s then
			return false
		end

		s.values = values or {}
		s.xs = xs

		invalidate()
		redraw()

		return true
	end

	function controller:Push(name, value, maxPoints)
		local s = find(name)

		if not s then
			return false
		end

		table.insert(s.values, value)

		if s.xs then
			table.insert(s.xs, (s.xs[#s.xs] or -1) + 1)
		end

		if maxPoints then
			while #s.values > maxPoints do
				table.remove(s.values, 1)

				if s.xs then
					table.remove(s.xs, 1)
				else
					s.x0 += 1
				end
			end
		end

		invalidate()
		state.dirty = true

		return true
	end

	function controller:SetRange(xMin, xMax, yMin, yMax)
		state.fixed = { xMin = xMin, xMax = xMax, yMin = yMin, yMax = yMax }
		state.target = nil

		redraw()
	end

	function controller:SetView(xMin, xMax, yMin, yMax, animate)
		local partial = { xMin = xMin, xMax = xMax, yMin = yMin, yMax = yMax }

		if animate == false then
			for key, value in pairs(partial) do
				state.fixed[key] = value
			end

			state.target = nil
			redraw()
		else
			setTarget(partial, false)
		end
	end

	function controller:ZoomTo(x0, x1, animate)
		self:SetView(x0, x1, nil, nil, animate)
	end

	function controller:GetView()
		return state.xMin, state.xMax, state.yMin, state.yMax
	end

	function controller:AutoFit(animate)
		if animate == false then
			state.fixed = {}
			state.target = nil
			redraw()
			return
		end

		local a = state.auto

		setTarget({ xMin = a.xMin, xMax = a.xMax, yMin = a.yMin, yMax = a.yMax }, true)
	end

	controller_AutoFit = function()
		controller:AutoFit()
	end

	function controller:SetTitle(text)
		state.title = text
		redraw()
	end

	function controller:SetLabels(xLabel, yLabel)
		state.xLabel = xLabel
		state.yLabel = yLabel
		redraw()
	end

	function controller:SetSeriesVisible(name, visible)
		local s = find(name)

		if not s then
			return false
		end

		s.visible = visible == true

		invalidate()
		buildLegend()
		redraw()

		return true
	end

	function controller:GetSeries(name)
		return find(name)
	end

	function controller:Redraw()
		redraw()
	end

	function controller:Destroy()
		if state.destroyed then
			return
		end

		state.destroyed = true

		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end

		if tip then
			tip:Destroy()
		end

		UI.forgetButtons(container)
		container:Destroy()
	end

	for index, config in ipairs(options.series or {}) do
		table.insert(state.series, normalize(config, index))
	end

	buildLegend()
	redraw()

	return container, controller
end

local function niceStep(range, count)
	if range <= 0 then
		return 1
	end

	local rough = range / math.max(count - 1, 1)
	local exponent = math.floor(math.log10(rough))
	local fraction = rough / 10 ^ exponent

	local nice

	if fraction <= 1 then
		nice = 1
	elseif fraction <= 2 then
		nice = 2
	elseif fraction <= 5 then
		nice = 5
	else
		nice = 10
	end

	return nice * 10 ^ exponent
end

local function formatTick(value, step)
	if step >= 1 then
		return string.format("%d ms", math.floor(value + 0.5))
	end

	local decimals = math.clamp(-math.floor(math.log10(step)), 0, 6)

	return string.format("%." .. decimals .. "f ms", value)
end

local function colorFromRGB(c)
	if not c or c == 0 then
		return colors.accent
	end

	return Color3.new(math.floor(c / 65536) / 255, math.floor((c % 65536) / 256) / 255, (c % 256) / 255)
end

local function textColorFor(background)
	local luminance = 0.299 * background.R + 0.587 * background.G + 0.114 * background.B

	return luminance > 0.62 and Color3.new(0.06, 0.07, 0.09) or Color3.new(1, 1, 1)
end

local function analyze(zones)
	local items = {}

	for i, z in ipairs(zones) do
		items[i] = {
			name = z.name,
			color = z.color,
			start = z.startMs or 0,
			ms = z.ms,
			idx = i,
			childMs = 0,
			depth = 0,
		}
	end

	table.sort(items, function(a, b)
		if a.start ~= b.start then
			return a.start < b.start
		end

		if a.ms ~= b.ms then
			return a.ms > b.ms
		end

		return a.idx > b.idx
	end)

	local stack = {}
	local maxEnd = 0

	for _, it in ipairs(items) do
		while #stack > 0 do
			local top = stack[#stack]

			if top.start + top.ms <= it.start + 1e-9 then
				stack[#stack] = nil
			else
				break
			end
		end

		it.depth = #stack

		local parent = stack[#stack]

		if parent then
			parent.childMs += it.ms
		end

		stack[#stack + 1] = it
		maxEnd = math.max(maxEnd, it.start + it.ms)
	end

	local byName = {}
	local rows = {}

	for _, it in ipairs(items) do
		it.self = math.max(it.ms - it.childMs, 0)

		local row = byName[it.name]

		if not row then
			row = { name = it.name, color = it.color, total = 0, self = 0, calls = 0, max = 0 }
			byName[it.name] = row
			rows[#rows + 1] = row
		end

		row.total += it.ms
		row.self += it.self
		row.calls += 1
		row.max = math.max(row.max, it.ms)
	end

	return items, rows, maxEnd
end

function UI.flamegraph(parent, position, size, options)
	options = options or {}

	local rowHeight = options.rowHeight or 18
	local rulerHeight = options.ruler == false and 0 or 18
	local maxBoxes = options.maxBoxes or 800
	local labelMinWidth = options.labelMinWidth or 36
	local zoomEnabled = options.zoom ~= false

	local container = UI.frame(
		parent,
		position or UDim2.fromOffset(0, 0),
		size or UDim2.fromOffset(600, 240),
		options.color or colors.input,
		UI.tokens.radius.xs
	)

	container.Name = options.name or "Flamegraph"
	container.ClipsDescendants = true
	UI.stroke(container, colors.border, 1, 0)

	local data = { items = {}, rows = {}, maxEnd = 0 }
	local viewLo, viewHi = 0, 1
	local selectedName = nil
	local panning = nil
	local lastMouse = nil
	local lastClick = 0
	local destroyed = false
	local connections = {}
	local boxes = {}
	local ticks = {}

	local controller = { frame = container, rows = data.rows }

	local gridLayer = UI.create("Frame", {
		Name = "Grid",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, container)

	local hit = UI.create("TextButton", {
		Name = "Hit",
		Text = "",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Active = true,
		InputSink = false,
	}, container)

	local ruler = nil

	if rulerHeight > 0 then
		ruler = UI.frame(container, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, rulerHeight), colors.panelRaised)
		ruler.Name = "Ruler"
		UI.separator(ruler, UDim2.new(0, 0, 1, -1), UDim2.new(1, 0, 0, 1), colors.border)
	end

	local emptyLabel = UI.label(
		container,
		options.emptyText or "No zones captured",
		UDim2.new(0, 0, 0.5, -10),
		UDim2.new(1, 0, 0, 20),
		UI.tokens.type.small,
		colors.muted
	)
	emptyLabel.TextXAlignment = Enum.TextXAlignment.Center

	local relayout

	local function setView(lo, hi)
		local span = math.clamp(hi - lo, MIN_SPAN, 1)

		lo = math.clamp(lo, 0, 1 - span)

		viewLo, viewHi = lo, lo + span

		relayout()

		if options.onViewChanged then
			options.onViewChanged(viewLo, viewHi)
		end
	end

	local function beginPan()
		panning = {
			loc = UserInputService:GetMouseLocation(),
			lo = viewLo,
			hi = viewHi,
		}
	end

	local function setHover(item)
		if options.onHover then
			options.onHover(item)
		end
	end

	local function newBox(index)
		local box = {}

		local button = UI.create("TextButton", {
			Text = "",
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Active = true,
			InputSink = true,
			ClipsDescendants = true,
		}, container)

		local label = UI.label(button, "", UDim2.fromOffset(3, 0), UDim2.new(1, -3, 1, 0), 11, Color3.new(1, 1, 1))
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Center

		box.button = button
		box.label = label

		button.MouseButton1Click:Connect(function()
			if box.zone then
				controller:SetSelected(selectedName ~= box.zone.name and box.zone.name or nil)
			end
		end)

		button.MouseButton2Down:Connect(function(x, y)
			lastMouse = Vector2.new(x, y)
			beginPan()
		end)

		button.MouseEnter:Connect(function(x, y)
			lastMouse = Vector2.new(x, y)

			if box.zone then
				setHover(box.zone)
			end
		end)

		button.MouseMoved:Connect(function(x, y)
			lastMouse = Vector2.new(x, y)
		end)

		button.MouseLeave:Connect(function()
			lastMouse = nil
			setHover(nil)
		end)

		boxes[index] = box
		return box
	end

	local function newTick(index)
		local grid = UI.frame(gridLayer, UDim2.fromOffset(0, 0), UDim2.new(0, 1, 1, 0), colors.border)
		grid.BackgroundTransparency = 0.7

		local label = nil

		if ruler then
			label =
				UI.label(ruler, "", UDim2.fromOffset(0, 1), UDim2.fromOffset(70, rulerHeight - 3), 10, colors.subtext)
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextYAlignment = Enum.TextYAlignment.Center
		end

		ticks[index] = { grid = grid, label = label }
		return ticks[index]
	end

	relayout = function()
		if destroyed then
			return
		end

		local sizeNow = container.AbsoluteSize
		local width, height = sizeNow.X, sizeNow.Y

		if width <= 0 or height <= 0 then
			return
		end

		local span = math.max(data.maxEnd, 1e-6)
		local lo, hi = viewLo * span, viewHi * span
		local scale = width / (hi - lo)

		local tickCount = math.clamp(math.floor(width / 90) + 1, 3, MAX_TICKS - 2)
		local step = niceStep(hi - lo, tickCount)
		local value = math.ceil(lo / step - 1e-9) * step
		local used = 0

		while value <= hi + step * 1e-6 and used < MAX_TICKS do
			used += 1

			local tick = ticks[used] or newTick(used)
			local px = math.floor((value - lo) * scale)

			tick.grid.Position = UDim2.fromOffset(px, 0)
			tick.grid.Visible = true

			if tick.label then
				tick.label.Position = UDim2.fromOffset(px + 3, 1)
				tick.label.Text = formatTick(value, step)
				tick.label.Visible = true
			end

			value += step
		end

		for i = used + 1, #ticks do
			ticks[i].grid.Visible = false

			if ticks[i].label then
				ticks[i].label.Visible = false
			end
		end

		local maxRows = math.max(math.floor((height - rulerHeight - 4) / rowHeight), 1)
		local boxesUsed = 0

		for _, it in ipairs(data.items) do
			if it.depth < maxRows and boxesUsed < maxBoxes then
				local x0 = (it.start - lo) * scale
				local x1 = x0 + it.ms * scale

				if x1 >= 0 and x0 <= width and x1 - x0 >= 1 then
					boxesUsed += 1

					local box = boxes[boxesUsed] or newBox(boxesUsed)
					local px = math.max(x0, 0)
					local pw = math.min(x1, width) - px
					local fill = colorFromRGB(it.color)

					box.zone = it
					box.button.Position = UDim2.fromOffset(px, rulerHeight + 2 + it.depth * rowHeight)
					box.button.Size = UDim2.fromOffset(math.max(pw, 1), rowHeight - 2)
					box.button.BackgroundColor3 = fill
					box.button.BackgroundTransparency = (selectedName and it.name ~= selectedName) and 0.65 or 0
					box.label.TextColor3 = textColorFor(fill)

					if pw > 150 then
						box.label.Text = string.format("%s  %.3f ms", it.name, it.ms)
					elseif pw > labelMinWidth then
						box.label.Text = it.name
					else
						box.label.Text = ""
					end

					box.button.Visible = true
				end
			end
		end

		for i = boxesUsed + 1, #boxes do
			boxes[i].button.Visible = false
			boxes[i].zone = nil
		end
	end

	hit.MouseButton1Down:Connect(function(x, y)
		lastMouse = Vector2.new(x, y)

		local now = os.clock()

		if now - lastClick < 0.3 then
			lastClick = 0
			panning = nil
			setView(0, 1)
			return
		end

		lastClick = now
		beginPan()
	end)

	hit.MouseButton2Down:Connect(function(x, y)
		lastMouse = Vector2.new(x, y)
		beginPan()
	end)

	hit.MouseEnter:Connect(function(x, y)
		lastMouse = Vector2.new(x, y)
	end)

	hit.MouseMoved:Connect(function(x, y)
		lastMouse = Vector2.new(x, y)
	end)

	hit.MouseLeave:Connect(function()
		lastMouse = nil
	end)

	table.insert(
		connections,
		UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseWheel then
				if not zoomEnabled or panning or not lastMouse or not UI.pointInside(container, lastMouse) then
					return
				end

				local steps = input.Position.Z

				if steps == 0 then
					return
				end

				local width = math.max(container.AbsoluteSize.X, 1)
				local fx = math.clamp((lastMouse.X - container.AbsolutePosition.X) / width, 0, 1)

				local span = viewHi - viewLo
				local anchor = viewLo + fx * span
				local newSpan = math.clamp(span * (options.zoomSpeed or 0.8) ^ steps, MIN_SPAN, 1)
				local newLo = anchor - fx * newSpan

				setView(newLo, newLo + newSpan)
			elseif input.UserInputType == Enum.UserInputType.MouseMovement then
				if not panning then
					return
				end

				local loc = UserInputService:GetMouseLocation()
				local dx = loc.X - panning.loc.X
				local width = math.max(container.AbsoluteSize.X, 1)
				local shift = dx / width * (panning.hi - panning.lo)

				setView(panning.lo - shift, panning.hi - shift)
			end
		end)
	)

	table.insert(
		connections,
		UserInputService.InputEnded:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.MouseButton2
			then
				panning = nil
			end
		end)
	)

	pcall(function()
		container:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			relayout()
		end)
	end)

	function controller:SetData(zones)
		local items, rows, maxEnd = analyze(zones or {})

		data = { items = items, rows = rows, maxEnd = maxEnd }
		self.rows = rows

		emptyLabel.Visible = #items == 0

		relayout()

		return rows, maxEnd
	end

	function controller:GetRows()
		return data.rows
	end

	function controller:GetItems()
		return data.items
	end

	function controller:SetSelected(name, silent)
		if selectedName == name then
			return
		end

		selectedName = name

		relayout()

		if not silent and options.onSelect then
			options.onSelect(name)
		end
	end

	function controller:GetSelected()
		return selectedName
	end

	function controller:SetView(lo, hi)
		setView(lo, hi)
	end

	function controller:GetView()
		return viewLo, viewHi
	end

	function controller:Fit()
		setView(0, 1)
	end

	function controller:Relayout()
		relayout()
	end

	function controller:Destroy()
		if destroyed then
			return
		end

		destroyed = true

		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end

		container:Destroy()
	end

	emptyLabel.Visible = true

	return container, controller
end

function UI.colorPicker(parent, position, size, initialColor, callback)
	local colors = UI.tokens.color
	local picker = UI.frame(parent, position, size or UDim2.fromOffset(226, 286), colors.panel, UI.tokens.radius.md)
	picker.Name = "ColorPicker"
	picker.ZIndex = 100000
	UI.stroke(picker, colors.borderStrong, 1, 0)

	local title =
		UI.label(picker, "Color", UDim2.fromOffset(10, 7), UDim2.new(1, -20, 0, 18), UI.tokens.type.small, colors.text)
	title.TextXAlignment = Enum.TextXAlignment.Left

	local color = initialColor or Color3.new(1, 1, 1)
	local hue, saturation, value = color:ToHSV()
	local draggingSquare, draggingHue = false, false
	local redraw

	local square = UI.frame(
		picker,
		UDim2.fromOffset(10, 30),
		UDim2.new(1, -20, 0, 142),
		Color3.fromHSV(hue, 1, 1),
		UI.tokens.radius.xs
	)
	square.ClipsDescendants = true
	UI.create("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1)),
		Transparency = NumberSequence.new(0, 1),
		Rotation = 0,
	}, square)
	UI.create("UIGradient", {
		Color = ColorSequence.new(Color3.new(0, 0, 0)),
		Transparency = NumberSequence.new(1, 0),
		Rotation = 90,
	}, square)
	local squareInput = UI.create("TextButton", {
		Text = "",
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Active = true,
		InputSink = true,
	}, square)
	local squareCursor = UI.frame(square, UDim2.fromOffset(0, 0), UDim2.fromOffset(12, 12), Color3.new(1, 1, 1), 6)
	UI.stroke(squareCursor, Color3.new(0, 0, 0), 1, 0)

	local hueBar =
		UI.frame(picker, UDim2.fromOffset(10, 180), UDim2.new(1, -20, 0, 14), colors.input, UI.tokens.radius.xs)
	for index = 0, 23 do
		local segment = UI.frame(
			hueBar,
			UDim2.new(index / 24, 0, 0, 0),
			UDim2.new(1 / 24, 1, 1, 0),
			Color3.fromHSV(index / 24, 1, 1),
			0
		)
		segment.BorderSizePixel = 0
	end
	UI.create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
			ColorSequenceKeypoint.new(1 / 6, Color3.fromRGB(255, 255, 0)),
			ColorSequenceKeypoint.new(2 / 6, Color3.fromRGB(0, 255, 0)),
			ColorSequenceKeypoint.new(3 / 6, Color3.fromRGB(0, 255, 255)),
			ColorSequenceKeypoint.new(4 / 6, Color3.fromRGB(0, 0, 255)),
			ColorSequenceKeypoint.new(5 / 6, Color3.fromRGB(255, 0, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
		}),
		Rotation = 0,
	}, hueBar)
	local hueInput = UI.create("TextButton", {
		Text = "",
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Active = true,
		InputSink = true,
	}, hueBar)
	local hueCursor = UI.frame(hueBar, UDim2.fromOffset(0, -2), UDim2.fromOffset(4, 18), colors.text, 2)

	local hexLabel = UI.label(picker, "HEX", UDim2.fromOffset(10, 208), UDim2.fromOffset(28, 20), 11, colors.subtext)
	hexLabel.TextXAlignment = Enum.TextXAlignment.Left
	local hexInput = UI.input(picker, "#FFFFFF", UDim2.fromOffset(42, 205), UDim2.new(1, -52, 0, 24), {
		text = string.format("#%02X%02X%02X", color.R * 255, color.G * 255, color.B * 255),
		maxLength = 7,
		textSize = 12,
	})
	local function applyHex()
		local raw = string.gsub(hexInput.Text, "#", "")
		if #raw == 6 then
			local red, green, blue =
				tonumber(string.sub(raw, 1, 2), 16),
				tonumber(string.sub(raw, 3, 4), 16),
				tonumber(string.sub(raw, 5, 6), 16)
			if red and green and blue then
				color = Color3.fromRGB(red, green, blue)
				hue, saturation, value = color:ToHSV()
				redraw()
				if callback then
					callback(color)
				end
			end
		end
	end
	hexInput.FocusLost:Connect(function()
		applyHex()
	end)
	local swatches = UI.frame(picker, UDim2.fromOffset(10, 240), UDim2.new(1, -20, 0, 34), colors.panel, 0)
	local presetColors = {
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(0, 0, 0),
		Color3.fromRGB(231, 76, 60),
		Color3.fromRGB(241, 196, 15),
		Color3.fromRGB(46, 204, 113),
		Color3.fromRGB(52, 152, 219),
		Color3.fromRGB(155, 89, 182),
		Color3.fromRGB(149, 165, 166),
	}

	redraw = function()
		square.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
		squareCursor.Position = UDim2.new(saturation, -6, 1 - value, -6)
		hueCursor.Position = UDim2.new(hue, -2, 0, -2)
		hexInput.Text = string.format("#%02X%02X%02X", color.R * 255, color.G * 255, color.B * 255)
	end

	local function updateColor(notify)
		color = Color3.fromHSV(hue, saturation, value)
		redraw()
		if notify and callback then
			callback(color)
		end
	end

	local function setSquareFromPoint(x, y)
		local p, s = square.AbsolutePosition, square.AbsoluteSize
		if not p or not s or s.X <= 0 or s.Y <= 0 then
			return
		end
		saturation = math.clamp((x - p.X) / s.X, 0, 1)
		value = 1 - math.clamp((y - p.Y) / s.Y, 0, 1)
		updateColor(true)
	end

	local function setHueFromPoint(x)
		local p, s = hueBar.AbsolutePosition, hueBar.AbsoluteSize
		if not p or not s or s.X <= 0 then
			return
		end
		hue = math.clamp((x - p.X) / s.X, 0, 1)
		updateColor(true)
	end

	squareInput.MouseButton1Down:Connect(function(x, y)
		draggingSquare = true
		setSquareFromPoint(x, y)
	end)
	squareInput.MouseMoved:Connect(function(x, y)
		if draggingSquare then
			setSquareFromPoint(x, y)
		end
	end)
	squareInput.MouseButton1Up:Connect(function()
		draggingSquare = false
	end)
	hueInput.MouseButton1Down:Connect(function(x)
		draggingHue = true
		setHueFromPoint(x)
	end)
	hueInput.MouseMoved:Connect(function(x)
		if draggingHue then
			setHueFromPoint(x)
		end
	end)
	hueInput.MouseButton1Up:Connect(function()
		draggingHue = false
	end)
	for index, preset in ipairs(presetColors) do
		local swatchButton = UI.create("TextButton", {
			Text = "",
			Position = UDim2.fromOffset((index - 1) * 25, 0),
			Size = UDim2.fromOffset(20, 20),
			BackgroundColor3 = preset,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Active = true,
			InputSink = true,
		}, swatches)
		UI.corner(swatchButton, 2)
		swatchButton.MouseButton1Click:Connect(function()
			color = preset
			hue, saturation, value = color:ToHSV()
			redraw()
			if callback then
				callback(color)
			end
		end)
	end

	local function setZIndex()
		for _, child in ipairs(picker:GetDescendants()) do
			if child:IsA("GuiObject") then
				child.ZIndex = 100001
			end
		end
	end
	setZIndex()
	redraw()

	local controller = { frame = picker }
	function controller:GetColor()
		return color
	end
	function controller:SetColor(nextColor, silent)
		color = nextColor or Color3.new(1, 1, 1)
		hue, saturation, value = color:ToHSV()
		redraw()
		if not silent and callback then
			callback(color)
		end
	end

	picker.Visible = false
	return picker, controller
end

function UI.separator(parent, position, size, color)
	return UI.frame(parent, position, size, color or UI.tokens.color.border)
end

function UI.group(parent, position, size, options)
	options = options or {}

	local group = UI.frame(
		parent,
		position,
		size,
		options.color or UI.tokens.color.surface,
		options.radius or UI.tokens.radius.md
	)

	group.ClipsDescendants = true

	return group
end

function UI.tab(parent, text, position, size, selected, callback)
	local colors = UI.tokens.color

	local button, label, record = UI.button(parent, text, position, size, callback, {

		color = selected and colors.surfaceAlt or colors.panel,

		hoverColor = colors.hover,

		textColor = selected and colors.text or colors.subtext,

		textSize = UI.tokens.type.small,

		radius = 0,

		border = false,

		paddingX = UI.tokens.space.md,
	})

	if selected then
		UI.frame(button, UDim2.new(0, 5, 1, -2), UDim2.new(1, -10, 0, 2), colors.accent, 1)
	end

	return button, label, record
end

function UI.tree(parent, position, size, data, options)
	options = options or {}

	local colors = UI.tokens.color

	local rowHeight = options.rowHeight or UI.metrics.treeRow
	local indent = options.indent or 14
	local iconSize = options.iconSize or 14
	local chevronSize = options.chevronSize or 10
	local textSize = options.textSize or UI.tokens.type.small
	local padding = options.padding or UI.tokens.space.sm
	local separator = options.separator or "/"

	local chevronIcon = options.chevronIcon or "builtin://global-icons/chevron-down.svg"
	local folderIcon = options.folderIcon or "builtin://global-icons/folder.svg"
	local fileIcon = options.fileIcon or "builtin://global-icons/file.svg"

	local rowColor = options.rowColor or colors.panel

	local container = UI.frame(
		parent,
		position or UDim2.fromOffset(0, 0),
		size or UDim2.fromOffset(240, 300),
		options.color or colors.panel,
		options.radius or 0
	)

	container.Name = options.name or "Tree"
	container.ClipsDescendants = true

	local list = UI.create("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(1, 0, 0, 0),
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = colors.subtext,
		ScrollBarImageTransparency = 0.4,
		ScrollBarAutoHide = true,
		ClipsDescendants = true,
	}, container)

	local state = {
		data = data or {},
		expanded = {},
		seen = {},
		selected = nil,
		lastClickKey = nil,
		lastClickTime = 0,
		destroyed = false,
	}

	local controller = { frame = container, list = list }
	local refresh

	local function keyOf(path)
		if type(path) == "string" then
			return path
		end

		local parts = {}

		for index, name in ipairs(path) do
			parts[index] = tostring(name)
		end

		return table.concat(parts, separator)
	end

	local function isBranch(value, name, path)
		if options.isBranch then
			return options.isBranch(value, name, path) == true
		end

		return type(value) == "table"
	end

	local function copyPath(path, name)
		local new = table.clone(path)

		table.insert(new, name)

		return new
	end

	local function flatten(tbl, path, depth, out)
		local entries = {}

		for name, value in pairs(tbl) do
			local entryPath = copyPath(path, name)

			table.insert(entries, {
				name = name,
				text = tostring(name),
				value = value,
				path = entryPath,
				key = keyOf(entryPath),
				branch = isBranch(value, name, entryPath),
				depth = depth,
			})
		end

		if options.sort ~= false then
			table.sort(entries, function(a, b)
				if a.branch ~= b.branch then
					return a.branch
				end

				return string.lower(a.text) < string.lower(b.text)
			end)
		end

		for _, entry in ipairs(entries) do
			table.insert(out, entry)

			if entry.branch then
				if not state.seen[entry.key] then
					state.seen[entry.key] = true
					state.expanded[entry.key] = options.startExpanded == true
				end

				if state.expanded[entry.key] and type(entry.value) == "table" then
					flatten(entry.value, entry.path, depth + 1, out)
				end
			end
		end
	end

	local function setExpanded(entry, expanded)
		if not entry.branch or state.expanded[entry.key] == expanded then
			return
		end

		state.expanded[entry.key] = expanded

		refresh()

		if options.onToggle then
			options.onToggle(entry.path, expanded, controller)
		end
	end

	local function select(entry)
		state.selected = entry.key

		refresh()

		if options.onSelect then
			options.onSelect(entry.path, entry.value, entry.branch, controller)
		end
	end

	local function onRowClick(entry)
		local now = os.clock()
		local doubleClick = state.lastClickKey == entry.key and now - state.lastClickTime < 0.3

		state.lastClickKey = entry.key
		state.lastClickTime = now

		if state.selected ~= entry.key then
			select(entry)
		end

		if doubleClick then
			state.lastClickKey = nil

			if entry.branch then
				setExpanded(entry, not state.expanded[entry.key])
			elseif options.onActivate then
				options.onActivate(entry.path, entry.value, controller)
			end
		end
	end

	refresh = function()
		if state.destroyed then
			return
		end

		UI.clear(list)

		local rows = {}

		flatten(state.data, {}, 0, rows)

		for index, entry in ipairs(rows) do
			local selected = state.selected == entry.key

			local color = selected and colors.selection or rowColor
			local hoverColor = selected and colors.selectionHover or colors.hover

			local button, label = UI.button(
				list,
				entry.text,
				UDim2.fromOffset(0, (index - 1) * rowHeight),
				UDim2.new(1, 0, 0, rowHeight),
				function()
					onRowClick(entry)
				end,
				{
					color = color,
					hoverColor = hoverColor,
					pressedColor = colors.pressed,
					textColor = selected and colors.text or colors.subtext,
					textSize = textSize,
					radius = 0,
					border = false,
					textY = 0,
					selected = selected,
				}
			)

			button.Name = entry.text
			button.BackgroundTransparency = (not selected and options.transparentRows) and 1 or 0

			local x = padding + entry.depth * indent

			if entry.branch then
				local expanded = state.expanded[entry.key] == true

				local _, _, chevron = UI.iconButton(
					button,
					chevronIcon,
					UDim2.fromOffset(x, math.floor((rowHeight - 16) / 2)),
					UDim2.fromOffset(16, 16),
					function()
						setExpanded(entry, not state.expanded[entry.key])
					end,
					{
						bgTransparency = 1,
						hoveringEnabled = false,
						border = false,
						iconSize = chevronSize,
					}
				)

				chevron.Rotation = expanded and 0 or -90
			end

			x += 16 + 2

			local icon = entry.branch and folderIcon or fileIcon

			if options.getIcon then
				icon = options.getIcon(entry.path, entry.value, entry.branch, state.expanded[entry.key] == true) or icon
			end

			if icon and icon ~= "" then
				UI.image(
					button,
					icon,
					UDim2.fromOffset(x, math.floor((rowHeight - iconSize) / 2)),
					UDim2.fromOffset(iconSize, iconSize)
				)

				x += iconSize + 5
			end

			label.Position = UDim2.fromOffset(x, 0)
			label.Size = UDim2.new(1, -(x + padding), 1, 0)
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextYAlignment = Enum.TextYAlignment.Center
		end

		list.CanvasSize = UDim2.new(1, 0, 0, #rows * rowHeight)
	end

	function controller:SetData(newData)
		state.data = newData or {}
		refresh()
	end

	function controller:GetData()
		return state.data
	end

	function controller:Refresh()
		refresh()
	end

	function controller:IsExpanded(path)
		return state.expanded[keyOf(path)] == true
	end

	function controller:Expand(path)
		if type(path) == "table" then
			for i = 1, #path do
				local key = keyOf({ table.unpack(path, 1, i) })
				state.seen[key] = true
				state.expanded[key] = true
			end
		else
			state.seen[path] = true
			state.expanded[path] = true
		end

		refresh()
	end

	function controller:Collapse(path)
		local key = keyOf(path)
		state.seen[key] = true
		state.expanded[key] = false
		refresh()
	end

	function controller:Toggle(path)
		local key = keyOf(path)
		state.seen[key] = true
		state.expanded[key] = not state.expanded[key]
		refresh()
	end

	local function setAll(value)
		local function walk(tbl, path)
			for name, child in pairs(tbl) do
				local childPath = copyPath(path, name)

				if isBranch(child, name, childPath) and type(child) == "table" then
					local key = keyOf(childPath)
					state.seen[key] = true
					state.expanded[key] = value
					walk(child, childPath)
				end
			end
		end

		walk(state.data, {})
		refresh()
	end

	function controller:ExpandAll()
		setAll(true)
	end

	function controller:CollapseAll()
		setAll(false)
	end

	function controller:GetSelected()
		return state.selected
	end

	function controller:SetSelected(path)
		state.selected = path ~= nil and keyOf(path) or nil
		refresh()
	end

	function controller:Destroy()
		if state.destroyed then
			return
		end

		state.destroyed = true

		UI.forgetButtons(container)
		container:Destroy()
	end

	refresh()

	return container, controller
end

function UI.window(name, position, size, title, options)
	options = options or {}

	local colors = UI.tokens.color
	local radius = options.radius or UI.tokens.radius.md
	local draggable = options.draggable ~= false
	local gripSize = 10
	local gripOffset = 6
	local titleX = draggable and (gripOffset + gripSize + 4) or 10

	local tabs = options.tabs or {}
	local hasTabs = #tabs > 0

	local headerHeight = options.headerHeight or 30
	local tabGap = options.tabGap or 2
	local tabTop = options.tabTop or 4
	local tabPaddingX = options.tabPaddingX or 12
	local tabRadius = options.tabRadius or UI.tokens.radius.sm
	local tabSpeed = options.tabSpeed or 18

	local headerColor = options.headerColor or colors.panelRaised
	local contentColor = options.contentColor or colors.panel

	local panel = UI.frame(UI.root(), position, size, colors.panel, radius)

	panel.Name = name
	panel.ClipsDescendants = true

	shared.windows[string.lower(name)] = panel

	if options.backdrop == true then
		UI.create("UIBackdrop", {
			Enabled = true,
			BlurRadius = options.backdropBlur or 16,
			TintColor3 = options.backdropColor or colors.panel,
			TintTransparency = options.backdropTransparency or 0.78,
		}, panel)

		panel.BackgroundTransparency = options.panelTransparency or 0.08
	end

	local border = UI.stroke(
		panel,
		options.borderColor or colors.borderStrong,
		options.borderThickness or 1,
		options.borderTransparency or 0.35
	)

	local header = UI.frame(panel, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, headerHeight), headerColor, 0)

	header.Name = "Header"
	header.ClipsDescendants = true

	UI.frame(header, UDim2.new(0, 0, 1, -radius), UDim2.new(1, 0, 0, radius), headerColor)

	UI.frame(header, UDim2.new(0, 8, 1, -1), UDim2.new(1, -16, 0, 1), colors.border)

	local tabHeight = headerHeight - tabTop
	local activeTabColor = options.activeTabColor or contentColor
	local inactiveTabColor = options.inactiveTabColor or headerColor
	local tabHoverColor = options.tabHoverColor or colors.hover

	local activeText = options.activeTabTextColor or colors.text
	local inactiveText = options.inactiveTabTextColor or colors.muted

	local titleTab = nil
	local titleText = tostring(title or name)

	local titleLabel

	local indicator = nil

	local function makeTabShape(parent, pos, sz, color)
		local shape = UI.frame(parent, pos, sz, color, tabRadius)

		local fill = UI.frame(shape, UDim2.new(0, 0, 1, -tabRadius), UDim2.new(1, 0, 0, tabRadius), color, 0)
		fill.Name = "BottomFill"

		if options.tabAccentColor then
			local accent = UI.frame(
				shape,
				UDim2.fromOffset(tabRadius + 2, 0),
				UDim2.new(1, -(tabRadius + 2) * 2, 0, 2),
				options.tabAccentColor,
				1
			)
			accent.Name = "ActiveAccent"
		end

		return shape
	end

	if not hasTabs then
		local function titleWidth(text)
			return options.titleTabWidth or (#text * 7 + tabPaddingX * 2)
		end

		titleTab = makeTabShape(
			header,
			UDim2.fromOffset(titleX, tabTop),
			UDim2.fromOffset(titleWidth(titleText), tabHeight),
			activeTabColor
		)

		titleTab.Name = "TitleTab"

		titleLabel = UI.label(
			titleTab,
			titleText,
			UDim2.fromOffset(0, 0),
			UDim2.fromScale(1, 1),
			options.titleSize or UI.tokens.type.small,
			options.titleColor or colors.text
		)

		titleLabel.TextXAlignment = Enum.TextXAlignment.Center
		titleLabel.TextYAlignment = Enum.TextYAlignment.Center

		titleLabel:GetPropertyChangedSignal("Text"):Connect(function()
			titleTab.Size = UDim2.fromOffset(titleWidth(titleLabel.Text), tabHeight)
		end)
	else
		titleLabel = UI.label(header, titleText, UDim2.fromOffset(titleX, 0), UDim2.fromOffset(0, 0), 12, colors.text)
		titleLabel.Visible = false

		indicator =
			makeTabShape(header, UDim2.fromOffset(titleX, tabTop), UDim2.fromOffset(0, tabHeight), activeTabColor)

		indicator.Name = "TabIndicator"
		indicator.Visible = false
	end

	titleLabel.Name = "Title"

	local closeButton = nil

	if options.closable then
		closeButton = UI.iconButton(
			header,
			options.closeIcon or "builtin://global-icons/x.svg",
			UDim2.new(1, -27, 0.5, -math.floor(19 / 2)),
			UDim2.fromOffset(22, 19),
			function()
				if options.onClose then
					options.onClose(panel)
				else
					panel.Visible = false
				end
			end,
			{
				color = headerColor,
				hoverColor = options.closeHoverColor or colors.hover,
				pressedColor = colors.pressed,
				iconSize = 11,
				radius = UI.tokens.radius.sm,
				border = false,
			}
		)
	end

	local dragHandle = nil

	if draggable then
		dragHandle = UI.iconButton(
			header,
			options.gripIcon or "builtin://global-icons/grip.svg",
			UDim2.new(0, gripOffset, 0.5, -math.floor(19 / 2)),
			UDim2.fromOffset(gripSize, 19),
			function() end,
			{
				color = headerColor,
				hoverColor = colors.hover,
				pressedColor = colors.pressed,
				iconSize = 11,
				radius = UI.tokens.radius.sm,
				border = false,
			}
		)

		dragHandle.Name = "DragHandle"

		local UserInputService = game:GetService("UserInputService")

		local dragging = false
		local dragStartX, dragStartY = 0, 0
		local startPos = nil

		local function isPointer(input)
			return input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
		end

		local connections = {}

		table.insert(
			connections,
			dragHandle.InputBegan:Connect(function(input)
				if not isPointer(input) then
					return
				end

				local mouse = UserInputService:GetMouseLocation()

				dragging = true
				dragStartX, dragStartY = mouse.X, mouse.Y
				startPos = panel.Position

				panel:SetAttribute("Dragging", true)
			end)
		)

		table.insert(
			connections,
			UserInputService.InputChanged:Connect(function(input)
				if not dragging or not startPos then
					return
				end

				if input.UserInputType ~= Enum.UserInputType.MouseMovement then
					return
				end

				local mouse = UserInputService:GetMouseLocation()

				local newX = startPos.X.Offset + (mouse.X - dragStartX)
				local newY = startPos.Y.Offset + (mouse.Y - dragStartY)

				local root = UI.root()
				local rootSize = root and root.AbsoluteSize
				local panelSize = panel.AbsoluteSize

				if rootSize and panelSize then
					newX = math.clamp(newX, 0, math.max(0, rootSize.X - panelSize.X))
					newY = math.clamp(newY, 0, math.max(0, rootSize.Y - headerHeight))
				end

				panel.Position = UDim2.new(startPos.X.Scale, newX, startPos.Y.Scale, newY)
			end)
		)

		table.insert(
			connections,
			UserInputService.InputEnded:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					dragging = false
					startPos = nil

					panel:SetAttribute("Dragging", false)
				end
			end)
		)

		panel.Destroying:Connect(function()
			for _, c in ipairs(connections) do
				c:Disconnect()
			end
		end)
	end

	local tabButtons = {}
	local pages = {}
	local selectedTab = nil

	local contentY = headerHeight

	local content = UI.frame(panel, UDim2.fromOffset(0, contentY), UDim2.new(1, 0, 1, -contentY), contentColor)

	content.Name = "Content"
	content.ClipsDescendants = true

	local controller = {}

	local function getTabName(tab)
		if type(tab) == "table" then
			return tab.name or tab.id or tab.text or "Tab"
		end

		return tostring(tab)
	end

	local function getTabText(tab)
		if type(tab) == "table" then
			return tab.text or tab.title or tab.name or tab.id or "Tab"
		end

		return tostring(tab)
	end

	local anim = {
		x = titleX,
		w = 0,
		running = false,
		snap = false,
	}

	local function wake()
		anim.running = true
	end

	local function step(dt)
		if not anim.running then
			return
		end

		local moving = false

		for tabName, data in pairs(tabButtons) do
			local active = tabName == selectedTab

			local activeTarget = active and 1 or 0
			local hoverTarget = (data.hovered and not active) and 1 or 0

			if anim.snap then
				data.activeAlpha = activeTarget
				data.hoverAlpha = hoverTarget
			else
				data.activeAlpha = tooltipSmoothTowards(data.activeAlpha, activeTarget, tabSpeed, dt)
				data.hoverAlpha = tooltipSmoothTowards(data.hoverAlpha, hoverTarget, tabSpeed, dt)
			end

			if math.abs(data.activeAlpha - activeTarget) < 0.005 then
				data.activeAlpha = activeTarget
			else
				moving = true
			end

			if math.abs(data.hoverAlpha - hoverTarget) < 0.005 then
				data.hoverAlpha = hoverTarget
			else
				moving = true
			end

			data.label.TextColor3 = inactiveText:Lerp(activeText, data.activeAlpha)
			data.button.BackgroundTransparency = 1 - data.hoverAlpha
		end

		local current = selectedTab and tabButtons[selectedTab]

		if current and indicator then
			indicator.Visible = true

			if anim.snap then
				anim.x, anim.w = current.x, current.width
			else
				anim.x = tooltipSmoothTowards(anim.x, current.x, tabSpeed, dt)
				anim.w = tooltipSmoothTowards(anim.w, current.width, tabSpeed, dt)
			end

			if math.abs(anim.x - current.x) < 0.25 and math.abs(anim.w - current.width) < 0.25 then
				anim.x, anim.w = current.x, current.width
			else
				moving = true
			end

			indicator.Position = UDim2.fromOffset(anim.x, tabTop)
			indicator.Size = UDim2.fromOffset(anim.w, tabHeight)
		end

		anim.snap = false
		anim.running = moving
	end

	local heartbeat = nil

	if hasTabs then
		heartbeat = RunService.Heartbeat:Connect(step)

		panel.Destroying:Connect(function()
			if heartbeat then
				heartbeat:Disconnect()
				heartbeat = nil
			end
		end)
	end

	function controller.selectTab(tabName)
		if not pages[tabName] then
			return
		end

		if selectedTab == tabName then
			return
		end

		local previousTab = selectedTab

		selectedTab = tabName

		for pageName, page in pairs(pages) do
			page.Visible = pageName == selectedTab
		end

		if previousTab == nil then
			anim.snap = true
		end

		wake()

		if options.onTabChanged then
			options.onTabChanged(tabName, previousTab, pages[tabName], panel)
		end
	end

	function controller.getSelectedTab()
		return selectedTab
	end

	function controller.getPage(tabName)
		return pages[tabName]
	end

	if hasTabs then
		local x = titleX

		for index, tab in ipairs(tabs) do
			local tabName = getTabName(tab)
			local tabText = getTabText(tab)

			local tabWidth = options.tabWidth
			if type(tab) == "table" and tab.width then
				tabWidth = tab.width
			end
			tabWidth = tabWidth or (#tabText * 7 + tabPaddingX * 2)

			local page = UI.frame(content, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 1, 0), contentColor)

			page.Name = tabName
			page.Visible = false
			page.ClipsDescendants = true

			pages[tabName] = page

			local button, label, record

			button, label, record = UI.button(
				header,
				tabText,
				UDim2.fromOffset(x, tabTop),
				UDim2.fromOffset(tabWidth, tabHeight),
				function()
					controller.selectTab(tabName)
				end,
				{
					color = inactiveTabColor,
					hoverColor = tabHoverColor,
					pressedColor = options.tabPressedColor or colors.pressed,
					textColor = inactiveText,
					textSize = options.tabTextSize or UI.tokens.type.small,
					textY = 0,
					radius = tabRadius,
					border = false,
					paddingX = tabPaddingX,
				}
			)

			button.Name = tabName .. "Tab"
			button.BackgroundTransparency = 1

			label.TextXAlignment = Enum.TextXAlignment.Center
			label.TextYAlignment = Enum.TextYAlignment.Center

			local data = {
				button = button,
				label = label,
				record = record,
				index = index,
				x = x,
				width = tabWidth,
				activeAlpha = 0,
				hoverAlpha = 0,
				hovered = false,
			}

			button.MouseEnter:Connect(function()
				data.hovered = true
				wake()
			end)

			button.MouseLeave:Connect(function()
				data.hovered = false
				wake()
			end)

			tabButtons[tabName] = data

			x += tabWidth + tabGap
		end

		local initialTab = options.selectedTab

		if not initialTab then
			initialTab = getTabName(tabs[1])
		end

		controller.selectTab(initialTab)

		step(0)
	end

	local clip = UI.frame(panel, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 1, 0), colors.panel, radius)

	clip.Name = "WindowClip"
	clip.BackgroundTransparency = 1
	clip.InputSink = false
	clip.Selectable = false

	return panel,
		content,
		header,
		{
			title = titleLabel,
			titleTab = titleTab,
			indicator = indicator,
			closeButton = closeButton,
			dragHandle = dragHandle,
			border = border,
			clip = clip,

			tabBar = nil,
			tabs = tabButtons,
			pages = pages,

			selectTab = controller.selectTab,
			getSelectedTab = controller.getSelectedTab,
			getPage = controller.getPage,
		}
end

function UI.toggleWindow(name)
	local window = shared.windows[string.lower(name)]

	if window then
		window.Visible = not window.Visible
	end
end

function UI.getWindow(name)
	return shared.windows[string.lower(name)]
end

function UI.input(parent, placeholder, position, size, options)
	options = options or {}

	local field = UI.create("TextBox", {

		Position = position or UDim2.fromOffset(0, 0),

		Size = size or UDim2.fromOffset(100, UI.metrics.inputHeight),

		BackgroundColor3 = options.color or UI.tokens.color.input,

		BorderSizePixel = 0,

		Text = options.text or "",

		PlaceholderText = tostring(placeholder or ""),

		TextSize = options.textSize or UI.tokens.type.small,

		TextColor3 = options.textColor or UI.tokens.color.text,

		PlaceholderColor3 = options.placeholderColor or UI.tokens.color.muted,

		TextTransparency = options.textTransparency or 0,

		TextEditable = options.textEditable ~= false,

		ClearTextOnFocus = options.clearTextOnFocus == true,

		SelectAllOnFocus = options.selectAllOnFocus == true,

		MaxLength = options.maxLength or -1,

		CaretColor3 = options.caretColor or UI.tokens.color.accent,

		SelectionColor3 = options.selectionColor or UI.tokens.color.selection,

		SelectionTransparency = options.selectionTransparency or 0.65,

		FocusColor3 = options.focusColor or UI.tokens.color.focus,

		Active = true,

		InputSink = true,
	}, parent)

	local squircle = Instance.new("UISquircle")
	squircle.Parent = field

	local stroke = UI.stroke(
		field,
		options.borderColor or UI.tokens.color.border,
		options.strokeThickness or 1,
		options.strokeTransparency or 0
	)

	local animate = options.animate ~= false
	local focusSpeed = options.focusSpeed or 16
	local focusTarget = 0
	local focusAlpha = 0
	local focusHeartbeat = nil
	local baseColor = stroke.Color
	local baseTransparency = stroke.Transparency

	local function focusColor()
		return options.focusColor or UI.tokens.color.focus
	end

	local function applyFocus()
		stroke.Color = baseColor:Lerp(focusColor(), focusAlpha)

		local targetTransparency = options.focusTransparency or 0

		stroke.Transparency = baseTransparency + (targetTransparency - baseTransparency) * focusAlpha
	end

	local function stopFocusAnimation()
		if focusHeartbeat then
			focusHeartbeat:Disconnect()
			focusHeartbeat = nil
		end
	end

	local function setFocus(target, snap)
		focusTarget = target

		if snap or not animate then
			stopFocusAnimation()

			focusAlpha = target

			applyFocus()

			return
		end

		if focusHeartbeat then
			return
		end

		focusHeartbeat = RunService.Heartbeat:Connect(function(dt)
			focusAlpha = tooltipSmoothTowards(focusAlpha, focusTarget, focusSpeed, dt)

			local finished = math.abs(focusAlpha - focusTarget) < 0.005

			if finished then
				focusAlpha = focusTarget
			end

			applyFocus()

			if finished then
				stopFocusAnimation()
			end
		end)
	end

	field.Focused:Connect(function()
		baseColor = stroke.Color
		baseTransparency = stroke.Transparency

		setFocus(1, false)
	end)

	field.FocusLost:Connect(function()
		setFocus(0, false)
	end)

	field.Destroying:Connect(stopFocusAnimation)

	return field, field, stroke
end

local function removeButtonRecords(gui)
	UI.forgetButtons(gui)
end

closeActiveDropdown = function(instant)
	local active = shared.activeDropdown

	if not active then
		return
	end

	shared.activeDropdown = nil

	if active.dismiss then
		active.dismiss(instant == true)
	elseif active.menu then
		removeButtonRecords(active.menu)

		active.menu:Destroy()
	end

	-- lets the trigger button animate its chevron / border back to closed
	if active.wake then
		active.wake()
	end
end

function UI.closeDropdown(instant)
	closeActiveDropdown(instant == true)
end

local function resolveDropdownItem(item)
	if type(item) == "table" then
		local itemValue = item.value

		if itemValue == nil then
			itemValue = item[1]
		end

		return itemValue, tostring(item.label or item.text or item.name or itemValue or ""), item.icon, item.shortcut
	end

	return item, tostring(item), nil, nil
end

local function createDropdownMenuAnimator(menu, config)
	local animate = config.animate ~= false
	local fadeSpeed = config.fadeSpeed or 22
	local sizeSpeed = config.sizeSpeed or 24
	local rowSpeed = config.rowSpeed or 22
	local rowHoverSpeed = config.rowHoverSpeed or 26
	local rowStagger = config.rowStagger or 0.025
	local maxStagger = config.maxStagger or 0.2
	local rowSlide = config.rowSlide or 8
	local slideDistance = config.slideDistance or 6
	local startScale = config.startScale or 0.6

	local anchorBottom = config.anchorBottom == true
	local dynamicRoot = config.dynamicRoot -- container whose children get rebuilt (search results)
	local x, y, width, height = config.x, config.y, config.width, config.height

	local state = {
		alpha = animate and 0 or 1,
		cur = animate and height * startScale or height,
		closing = false,
		started = false,
		destroyed = false,
		lastAlpha = nil,
	}

	local staticFades = {}
	local dynamicFades = {}
	local rows = {}
	local connection = nil
	local animator = {}

	menu.AnchorPoint = Vector2.new(0, anchorBottom and 1 or 0)

	local function addFades(list, obj)
		if obj:IsA("GuiObject") then
			table.insert(list, { obj = obj, prop = "BackgroundTransparency", base = obj.BackgroundTransparency })
		end

		if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
			table.insert(list, { obj = obj, prop = "TextTransparency", base = obj.TextTransparency })
		end

		if obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
			table.insert(list, { obj = obj, prop = "ImageTransparency", base = obj.ImageTransparency })
		end

		if obj:IsA("ScrollingFrame") then
			table.insert(
				list,
				{ obj = obj, prop = "ScrollBarImageTransparency", base = obj.ScrollBarImageTransparency }
			)
		end

		if obj:IsA("UIStroke") then
			table.insert(list, { obj = obj, prop = "Transparency", base = obj.Transparency })
		end

		if obj:IsA("UIBackdrop") then
			local okBlur, blur = pcall(function()
				return obj.BlurRadius
			end)

			local okTint, tint = pcall(function()
				return obj.TintTransparency
			end)

			if okBlur and type(blur) == "number" then
				table.insert(list, { obj = obj, prop = "BlurRadius", base = blur, blur = true })
			end

			if okTint and type(tint) == "number" then
				table.insert(list, { obj = obj, prop = "TintTransparency", base = tint })
			end
		end
	end

	local function applyList(list, a)
		for _, fade in ipairs(list) do
			if fade.blur then
				fade.obj[fade.prop] = fade.base * a
			else
				fade.obj[fade.prop] = 1 - (1 - fade.base) * a
			end
		end
	end

	local function applyFades(a)
		if a == state.lastAlpha then
			return
		end

		state.lastAlpha = a

		applyList(staticFades, a)
		applyList(dynamicFades, a)
	end

	local function place()
		local offsetY = (anchorBottom and 1 or -1) * slideDistance * (1 - state.alpha)

		menu.Position = UDim2.fromOffset(x, math.floor(y + offsetY + 0.5))
		menu.Size = UDim2.fromOffset(width, math.floor(state.cur + 0.5))
	end

	local function destroy()
		if state.destroyed then
			return
		end

		state.destroyed = true

		if connection then
			connection:Disconnect()
			connection = nil
		end

		UI.forgetButtons(menu)

		menu:Destroy()
	end

	local function updateRows(dt)
		for _, row in ipairs(rows) do
			local active = row.hovered or row.hover > 0 or row.appear < 1

			if row.appear < 1 then
				row.age += dt

				if row.age >= row.delay then
					row.appear = tooltipSmoothTowards(row.appear, 1, rowSpeed, dt)

					if row.appear > 0.995 then
						row.appear = 1
					end
				end
			end

			local hoverTarget = (row.hovered and row.record.enabled and not state.closing) and 1 or 0

			row.hover = tooltipSmoothTowards(row.hover, hoverTarget, rowHoverSpeed, dt)

			if math.abs(row.hover - hoverTarget) < 0.005 then
				row.hover = hoverTarget
			end

			if active then
				row.button.BackgroundColor3 = row.record.color:Lerp(row.record.hoverColor, row.hover)
				row.button.Position = UDim2.fromOffset(row.baseX - rowSlide * (1 - row.appear), row.baseY)
			end
		end
	end

	local function step(dt)
		if state.destroyed then
			return
		end

		if not UI.isAlive(menu) then
			destroy()

			return
		end

		local target = state.closing and 0 or 1

		if animate then
			state.alpha = tooltipSmoothTowards(state.alpha, target, fadeSpeed, dt)

			if math.abs(state.alpha - target) < 0.01 then
				state.alpha = target
			end

			state.cur = tooltipSmoothTowards(state.cur, height, sizeSpeed, dt)

			if math.abs(state.cur - height) < 0.5 then
				state.cur = height
			end
		else
			state.alpha, state.cur = target, height
		end

		updateRows(dt)
		applyFades(state.alpha)
		place()

		if state.closing and state.alpha <= 0.01 then
			destroy()
		end
	end

	-- Rows added before start() get the staggered slide-in; rows added later (search) appear instantly.
	function animator.addRow(rowButton, record, index)
		local row = {
			button = rowButton,
			record = record,
			baseX = rowButton.Position.X.Offset,
			baseY = rowButton.Position.Y.Offset,
			hover = 0,
			hovered = false,
			appear = (animate and not state.started) and 0 or 1,
			age = 0,
			delay = math.min((index or (#rows + 1)) * rowStagger, maxStagger),
		}

		table.insert(rows, row)

		rowButton.MouseEnter:Connect(function()
			row.hovered = true
		end)

		rowButton.MouseLeave:Connect(function()
			row.hovered = false
		end)
	end

	function animator.clearRows()
		rows = {}
	end

	-- call after rebuilding the contents of dynamicRoot
	function animator.refresh()
		if not state.started or not dynamicRoot then
			return
		end

		dynamicFades = {}

		for _, descendant in ipairs(dynamicRoot:GetDescendants()) do
			addFades(dynamicFades, descendant)
		end

		state.lastAlpha = nil
	end

	function animator.start()
		if state.started then
			return
		end

		state.started = true

		addFades(staticFades, menu)

		for _, descendant in ipairs(menu:GetDescendants()) do
			if dynamicRoot and descendant ~= dynamicRoot and descendant:IsDescendantOf(dynamicRoot) then
				addFades(dynamicFades, descendant)
			else
				addFades(staticFades, descendant)
			end
		end

		-- apply the starting state immediately so the menu never flashes at full opacity
		applyFades(state.alpha)
		place()

		connection = RunService.Heartbeat:Connect(step)
	end

	function animator.dismiss(instant)
		if state.destroyed or state.closing then
			return
		end

		if instant or not animate or not state.started then
			destroy()

			return
		end

		state.closing = true

		-- stop the fading menu from receiving clicks
		for _, descendant in ipairs(menu:GetDescendants()) do
			if descendant:IsA("TextButton") or descendant:IsA("ImageButton") or descendant:IsA("TextBox") then
				descendant.Active = false
			end
		end
	end

	return animator
end

function UI.dropdown(parent, value, position, size, chevronIcon, options)
	options = options or {}

	local colors = UI.tokens.color

	local currentValue = value

	local items = options.items or {}

	local animate = options.animate ~= false
	local speed = options.animationSpeed or 22
	local hoverEnabled = options.hoveringEnabled ~= false

	local button
	local label
	local record
	local chevron

	local controller = {}

	local function menuOverlay()
		local overlay = options.menuParent or UI.contextMenuOverlay()

		if overlay and overlay:IsA("ScreenGui") then
			pcall(function()
				overlay.Enabled = true
			end)
		end

		return overlay or UI.root()
	end

	local anim = {
		hover = 0,
		press = 0,
		open = 0,
		hovered = false,
		pressed = false,
		running = true,
		destroyed = false,
	}

	local function isOpen()
		local active = shared.activeDropdown

		return active ~= nil and active.controller == controller
	end

	local function wake()
		anim.running = true
	end

	local function choose(itemValue, itemText, item)
		currentValue = itemValue

		if not options.keepLabel then
			label.Text = itemText
		end

		closeActiveDropdown()

		if options.onChanged then
			options.onChanged(itemValue, item)
		end
	end

	local function newMenuAnimator(menu, extra)
		local config = {
			animate = animate,
			fadeSpeed = options.menuFadeSpeed,
			sizeSpeed = options.menuSizeSpeed,
			slideDistance = options.menuSlide,
			rowSlide = options.rowSlide,
			rowStagger = options.rowStagger,
		}

		for key, configValue in pairs(extra) do
			config[key] = configValue
		end

		return createDropdownMenuAnimator(menu, config)
	end

	local function buildRow(list, y, item, rowHeight, index, animator, highlight, suffix)
		local itemValue, itemText, icon = resolveDropdownItem(item)

		local selected = highlight and itemValue == currentValue

		local row, _, rowRecord = UI.button(
			list,
			itemText .. (suffix or ""),
			UDim2.fromOffset(0, y),
			UDim2.new(1, 0, 0, rowHeight),
			function()
				choose(itemValue, itemText, item)
			end,
			{
				color = selected and colors.selection or options.menuColor or colors.panelRaised,
				hoverColor = selected and colors.selectionHover or colors.hover,
				pressedColor = colors.pressed,
				textColor = selected and colors.text or colors.subtext,
				textSize = options.textSize or UI.tokens.type.small,
				radius = 0,
				border = false,
				paddingX = UI.tokens.space.md,
				icon = icon,
				iconSize = options.iconSize or 14,
				selected = selected,
				hoveringEnabled = false, -- the animator drives row hover
			}
		)

		row.BackgroundTransparency = options.itemBgTransparency or options.BackgroundTransparency or 0

		animator.addRow(row, rowRecord, index)

		return row
	end

	local function openMenu()
		local rowHeight = options.itemHeight or UI.metrics.inputHeight
		local maxVisibleItems = options.maxVisibleItems or 8
		local gap = options.menuGap or 2
		local margin = options.menuMargin or 4

		local desiredRows = math.max(1, math.min(#items, maxVisibleItems))
		local menuWidth = options.menuWidth or 140

		local menuPositionOption = options.menuPosition
		local fixedMenuPosition

		if type(menuPositionOption) == "function" then
			fixedMenuPosition = menuPositionOption()
		elseif typeof(menuPositionOption) == "UDim2" then
			fixedMenuPosition = menuPositionOption
		end

		---------------------------------------------------------------------
		-- Fixed position menu (with optional search / categories)
		---------------------------------------------------------------------
		if fixedMenuPosition then
			local overlay = menuOverlay()
			local screen = workspace:GetWindowDimensions()
			local edge = margin

			local showSearch = options.showSearch ~= false
			local searchHeight = showSearch and 34 or 0

			local totalHeight = desiredRows * rowHeight + searchHeight

			totalHeight = math.min(totalHeight, math.max(screen.Y - edge * 2, 1))

			local clampedWidth = math.min(menuWidth, math.max(screen.X - edge * 2, 1))

			local px = fixedMenuPosition.X.Scale * screen.X + fixedMenuPosition.X.Offset
			local py = fixedMenuPosition.Y.Scale * screen.Y + fixedMenuPosition.Y.Offset

			local flipped = false

			if px + clampedWidth > screen.X - edge then
				px = px - clampedWidth
			end

			if py + totalHeight > screen.Y - edge then
				py = py - totalHeight
				flipped = true
			end

			px = math.clamp(px, edge, math.max(edge, screen.X - clampedWidth - edge))
			py = math.clamp(py, edge, math.max(edge, screen.Y - totalHeight - edge))

			local menu = UI.frame(
				overlay,
				UDim2.fromOffset(px, py),
				UDim2.fromOffset(clampedWidth, totalHeight),
				options.menuColor or colors.panelRaised,
				options.radius or UI.tokens.radius.sm
			)

			if options.backdrop then
				UI.create("UIBackdrop", {
					Enabled = true,
					BlurRadius = options.backdropBlur or 18,
					TintColor3 = options.backdropColor or colors.panelRaised,
					TintTransparency = options.backdropTransparency or options.BackgroundTransparency or 0.85,
				}, menu)
			end

			menu.BackgroundTransparency = options.BackgroundTransparency or 0
			menu.Name = "DropdownMenu"
			menu.ZIndex = options.menuZIndex or 100000
			menu.ClipsDescendants = true

			UI.stroke(menu, options.borderColor or colors.borderStrong, 1, options.borderTransparency or 0)

			local search

			if showSearch then
				search = UI.input(
					menu,
					options.searchPlaceholder or "Search...",
					UDim2.fromOffset(5, 5),
					UDim2.new(1, -10, 0, 24),
					{ textSize = options.textSize or UI.tokens.type.small }
				)

				search.ZIndex = (options.menuZIndex or 100000) + 1
			end

			local list = UI.create("ScrollingFrame", {
				Position = UDim2.fromOffset(0, searchHeight),
				Size = UDim2.new(1, 0, 1, -searchHeight),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				CanvasPosition = Vector2.new(0, 0),
				CanvasSize = UDim2.new(1, 0, 0, 0),
				ScrollingEnabled = true,
				ScrollBarThickness = 5,
				ScrollBarImageColor3 = colors.subtext,
				ScrollBarImageTransparency = 0.4,
				ScrollBarAutoHide = true,
				ClipsDescendants = true,
			}, menu)

			list.ZIndex = (options.menuZIndex or 100000) + 1

			local animator = newMenuAnimator(menu, {
				x = px,
				y = flipped and (py + totalHeight) or py,
				width = clampedWidth,
				height = totalHeight,
				anchorBottom = flipped,
				dynamicRoot = list,
			})

			local function itemMatches(item, query)
				if query == "" then
					return true
				end

				local _, itemText = resolveDropdownItem(item)

				return string.find(string.lower(itemText), query, 1, true) ~= nil
			end

			local function renderItems()
				UI.clear(list)
				animator.clearRows()

				local query = search and string.lower(search.Text or "") or ""
				local y = 0
				local visible = 0

				local categories = options.categories

				if categories then
					for _, category in ipairs(categories) do
						local categoryItems = {}

						for _, item in ipairs(category.items or {}) do
							if itemMatches(item, query) then
								table.insert(categoryItems, item)
							end
						end

						if #categoryItems > 0 then
							UI.label(
								list,
								category.name,
								UDim2.fromOffset(10, y + 3),
								UDim2.new(1, -20, 0, rowHeight - 4),
								options.categoryTextSize or 10,
								colors.muted
							)

							y += rowHeight

							for _, item in ipairs(categoryItems) do
								local _, _, _, shortcut = resolveDropdownItem(item)

								visible += 1

								buildRow(
									list,
									y,
									item,
									rowHeight,
									visible,
									animator,
									false,
									shortcut and ("    " .. shortcut) or ""
								)

								y += rowHeight
							end
						end
					end
				else
					for _, item in ipairs(items) do
						if itemMatches(item, query) then
							visible += 1

							buildRow(list, y, item, rowHeight, visible, animator, false)

							y += rowHeight
						end
					end
				end

				list.CanvasSize = UDim2.new(1, 0, 0, math.max(y, rowHeight))

				animator.refresh()
			end

			if search then
				search.TextChanged:Connect(renderItems)
				search.FocusLost:Connect(renderItems)
			end

			renderItems()

			animator.start()

			shared.activeDropdown = {
				button = button,
				menu = menu,
				controller = controller,
				closeOnOutsideClick = options.closeOnOutsideClick ~= false,
				dismiss = animator.dismiss,
				wake = wake,
			}

			wake()

			return
		end

		---------------------------------------------------------------------
		-- Menu anchored to the button
		---------------------------------------------------------------------
		local absolutePosition = button.AbsolutePosition
		local absoluteSize = button.AbsoluteSize

		if not absolutePosition or not absoluteSize then
			return
		end

		local boundsSize = workspace:GetWindowDimensions()

		local boundsLeft = margin
		local boundsTop = margin
		local boundsRight = boundsSize.X - margin
		local boundsBottom = boundsSize.Y - margin

		menuWidth = math.min(menuWidth, math.max(1, boundsRight - boundsLeft))

		local menuX = absolutePosition.X

		if options.menuSide == "left" then
			menuX = absolutePosition.X - menuWidth - gap
		end

		if options.menuSide ~= "left" and menuX + menuWidth > boundsRight then
			menuX = boundsRight - menuWidth
		end

		if options.menuSide ~= "left" and menuX < boundsLeft then
			menuX = boundsLeft
		end

		local buttonTop = absolutePosition.Y
		local buttonBottom = absolutePosition.Y + absoluteSize.Y

		local spaceBelow = boundsBottom - buttonBottom - gap
		local spaceAbove = buttonTop - boundsTop - gap

		local desiredHeight = desiredRows * rowHeight

		local openAbove = desiredHeight > spaceBelow and spaceAbove > spaceBelow

		local availableSpace = openAbove and spaceAbove or spaceBelow

		local visibleRows = math.clamp(math.floor(availableSpace / rowHeight), 1, desiredRows)

		local menuHeight = visibleRows * rowHeight

		local menuY

		if openAbove then
			menuY = buttonTop - menuHeight - gap
		else
			menuY = buttonBottom + gap
		end

		menuY = math.clamp(menuY, boundsTop, math.max(boundsTop, boundsBottom - menuHeight))

		local menu = UI.create("ScrollingFrame", {
			Position = UDim2.fromOffset(menuX, menuY),
			Size = UDim2.fromOffset(menuWidth, menuHeight),
			BackgroundColor3 = options.menuColor or colors.panelRaised,
			BackgroundTransparency = options.BackgroundTransparency or 0,
			BorderSizePixel = 0,
			CanvasPosition = Vector2.new(0, 0),
			CanvasSize = UDim2.new(1, 0, 0, #items * rowHeight),
			ScrollingEnabled = #items > visibleRows,
			ScrollBarThickness = 5,
			ScrollBarImageColor3 = colors.subtext,
			ScrollBarImageTransparency = 0.4,
			ScrollBarAutoHide = true,
			ScrollBarFadeDelay = 0.45,
			ScrollBarFadeSpeed = 12,
			ClipsDescendants = true,
		}, menuOverlay())

		UI.corner(menu, options.radius or UI.tokens.radius.sm)

		if options.backdrop then
			UI.create("UIBackdrop", {
				Enabled = true,
				BlurRadius = options.backdropBlur or 18,
				TintColor3 = options.backdropColor or colors.panelRaised,
				TintTransparency = options.backdropTransparency or 0.85,
			}, menu)
		end

		menu.Name = "DropdownMenu"
		menu.ZIndex = options.menuZIndex or 100000
		menu.ClipsDescendants = true

		UI.stroke(menu, options.borderColor or colors.borderStrong, 1, options.borderTransparency or 0)

		local animator = newMenuAnimator(menu, {
			x = menuX,
			y = openAbove and (menuY + menuHeight) or menuY,
			width = menuWidth,
			height = menuHeight,
			anchorBottom = openAbove,
		})

		for index, item in ipairs(items) do
			buildRow(menu, (index - 1) * rowHeight, item, rowHeight, index, animator, true)
		end

		animator.start()

		shared.activeDropdown = {
			button = button,
			menu = menu,
			controller = controller,
			closeOnOutsideClick = options.closeOnOutsideClick ~= false,
			dismiss = animator.dismiss,
			wake = wake,
		}

		wake()
	end

	button, label, record = UI.button(
		parent,
		tostring(options.format and options.format(value) or value or ""),
		position,
		size or UDim2.fromOffset(140, UI.metrics.inputHeight),
		function()
			if isOpen() then
				closeActiveDropdown()

				return
			end

			closeActiveDropdown()

			openMenu()
		end,
		{
			color = options.color or colors.input,

			hoverColor = options.hoverColor or colors.hover,

			pressedColor = options.pressedColor or colors.pressed,

			textColor = options.textColor or colors.subtext,

			textSize = options.textSize or UI.tokens.type.small,

			radius = options.radius or UI.tokens.radius.sm,

			border = options.border ~= false,

			borderColor = options.borderColor or colors.border,

			paddingX = options.paddingX or UI.tokens.space.md,

			textY = options.textY,

			icon = options.icon,

			iconSize = options.iconSize or 14,

			hoveringEnabled = false, -- hover / press colours are driven by the animation below
		}
	)

	if chevronIcon then
		local iconSize = options.chevronSize or 12

		chevron = UI.image(
			button,
			chevronIcon,
			UDim2.new(1, -(iconSize + 6), 0.5, -math.floor(iconSize / 2)),
			UDim2.fromOffset(iconSize, iconSize)
		)

		chevron.Name = "Chevron"

		label.Size = UDim2.new(1, -(iconSize + 18), 1, 0)
	end

	---------------------------------------------------------------------
	-- Trigger button animation
	---------------------------------------------------------------------
	local stroke = button:FindFirstChildOfClass("UIStroke")

	local function renderButton()
		local focus = math.max(anim.hover, anim.open * 0.7)

		local color = record.color:Lerp(record.hoverColor, focus)

		color = color:Lerp(record.pressedColor, anim.press)

		button.BackgroundColor3 = color

		if stroke then
			stroke.Color = (options.borderColor or colors.border):Lerp(colors.borderStrong, anim.open)
		end

		if chevron then
			chevron.Rotation = 180 * anim.open
		end
	end

	button.MouseEnter:Connect(function()
		anim.hovered = true
		wake()
	end)

	button.MouseLeave:Connect(function()
		anim.hovered = false
		wake()
	end)

	button.MouseButton1Down:Connect(function()
		anim.pressed = true
		wake()
	end)

	-- MouseButton1Up only fires over the button, so release is tracked globally
	local inputEnded = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			anim.pressed = false
			wake()
		end
	end)

	local heartbeat
	local themeListener

	local function cleanup()
		if anim.destroyed then
			return
		end

		anim.destroyed = true

		if heartbeat then
			heartbeat:Disconnect()
			heartbeat = nil
		end

		if themeListener then
			themeListener.Disconnect()
			themeListener = nil
		end

		inputEnded:Disconnect()
	end

	-- repaint once after a theme change, even if the button is idle
	themeListener = UI.onThemeChanged(function()
		if not anim.destroyed then
			wake()
		end
	end)

	heartbeat = RunService.Heartbeat:Connect(function(dt)
		if anim.destroyed then
			return
		end

		if not UI.isAlive(button) then
			cleanup()

			return
		end

		if not anim.running then
			return
		end

		local hoverTarget = (hoverEnabled and anim.hovered and not anim.pressed) and 1 or 0
		local pressTarget = (hoverEnabled and anim.pressed) and 1 or 0
		local openTarget = isOpen() and 1 or 0

		local moving = false

		if animate then
			anim.hover = tooltipSmoothTowards(anim.hover, hoverTarget, speed, dt)
			anim.press = tooltipSmoothTowards(anim.press, pressTarget, speed * 1.6, dt)
			anim.open = tooltipSmoothTowards(anim.open, openTarget, speed * 0.8, dt)

			if math.abs(anim.hover - hoverTarget) < 0.005 then
				anim.hover = hoverTarget
			else
				moving = true
			end

			if math.abs(anim.press - pressTarget) < 0.005 then
				anim.press = pressTarget
			else
				moving = true
			end

			if math.abs(anim.open - openTarget) < 0.005 then
				anim.open = openTarget
			else
				moving = true
			end
		else
			anim.hover, anim.press, anim.open = hoverTarget, pressTarget, openTarget
		end

		renderButton()

		anim.running = moving
	end)

	button.Destroying:Connect(cleanup)

	---------------------------------------------------------------------
	-- Controller
	---------------------------------------------------------------------
	function controller:GetValue()
		return currentValue
	end

	function controller:SetValue(newValue, silent)
		currentValue = newValue

		if not options.keepLabel then
			label.Text = tostring(options.format and options.format(newValue) or newValue or "")
		end

		if not silent and options.onChanged then
			options.onChanged(newValue)
		end
	end

	function controller:SetItems(newItems)
		items = newItems or {}

		if isOpen() then
			closeActiveDropdown()
		end
	end

	function controller:IsOpen()
		return isOpen()
	end

	function controller:Open()
		if isOpen() or record == nil or record.destroyed or not UI.isAlive(record.gui) then
			return
		end

		record.callback()
	end

	function controller:Close(instant)
		if isOpen() then
			closeActiveDropdown(instant)
		end
	end

	function controller:Destroy()
		if isOpen() then
			closeActiveDropdown(true)
		end

		cleanup()

		UI.forgetButtons(button)

		button:Destroy()
	end

	controller.button = button

	controller.label = label

	controller.chevron = chevron

	controller.record = record

	button.BackgroundTransparency = options.BackgroundTransparency or 0

	renderButton()

	return button, label, controller
end

function UI.checkbox(parent, text, position, checked, callback, options)
	options = options or {}

	local colors = UI.tokens.color

	local value = checked == true

	local boxSize = options.boxSize or 18
	local markSize = options.markSize or 12
	local markIcon = options.markIcon or "builtin://global-icons/check.svg"

	local animate = options.animate ~= false
	local speed = options.animationSpeed or 22
	local pressShrink = options.pressShrink or 0.15 -- fraction the mark shrinks while pressed

	local container = UI.frame(
		parent,
		position or UDim2.fromOffset(0, 0),
		options.size or UDim2.fromOffset(180, UI.metrics.propertyRow),
		colors.panel
	)

	container.BackgroundTransparency = 1

	local box
	local mark
	local record
	local stroke

	local state = {
		alpha = value and 1 or 0, -- 0 = unchecked, 1 = checked
		hover = 0,
		press = 0,
		hovered = false,
		pressed = false,
		destroyed = false,
	}

	-- overshoot curve so the checkmark "pops" in
	local function easeOutBack(t)
		local c1 = 1.70158
		local c3 = c1 + 1
		return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
	end

	local function render()
		local uncheckedColor = options.color or colors.input
		local checkedColor = options.checkedColor or colors.accent

		-- box colour: unchecked -> checked
		local color = uncheckedColor:Lerp(checkedColor, state.alpha)

		-- hover: unchecked boxes move toward the hover colour, checked boxes lighten slightly
		color = color:Lerp(colors.hover, state.hover * (1 - state.alpha))
		color = color:Lerp(Color3.new(1, 1, 1), 0.08 * state.hover * state.alpha)

		-- press: darken
		color = color:Lerp(Color3.new(0, 0, 0), 0.1 * state.press)

		box.BackgroundColor3 = color

		-- border blends toward the accent as the box gets checked
		if stroke then
			stroke.Color = (options.borderColor or colors.border):Lerp(checkedColor, state.alpha)
		end

		-- checkmark: fade + scale in with overshoot, shrinks a little while pressed
		local a = math.clamp(state.alpha, 0, 1)
		local scale = value and easeOutBack(a) or a
		scale *= 1 - pressShrink * state.press

		local size = math.max(math.floor(markSize * scale + 0.5), 0)

		mark.Visible = a > 0.001
		mark.Size = UDim2.fromOffset(size, size)
		mark.ImageTransparency = 1 - math.clamp(a * 1.6, 0, 1)
	end

	box, _, record = UI.button(
		container,
		"",
		UDim2.fromOffset(0, math.floor((UI.metrics.propertyRow - boxSize) / 2)),
		UDim2.fromOffset(boxSize, boxSize),
		function()
			value = not value

			if not animate then
				state.alpha = value and 1 or 0
				render()
			end

			if callback then
				callback(value)
			end
		end,
		{
			color = colors.input,

			hoverColor = colors.hover,

			pressedColor = colors.pressed,

			radius = options.radius or UI.tokens.radius.xs,

			borderColor = colors.border,

			paddingX = 0,

			hoveringEnabled = false, -- hover/press colours are driven by the animation
		}
	)

	stroke = box:FindFirstChildOfClass("UIStroke")

	mark = UI.image(box, markIcon, UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(markSize, markSize))

	mark.Name = "Mark"
	mark.AnchorPoint = Vector2.new(0.5, 0.5)

	local textLabel = UI.label(
		container,
		text,
		UDim2.fromOffset(boxSize + 7, 1),
		UDim2.new(1, -(boxSize + 7), 1, -1),
		options.textSize or UI.tokens.type.small,
		options.textColor or colors.text
	)

	textLabel.TextYAlignment = Enum.TextYAlignment.Center
	textLabel.TextXAlignment = Enum.TextXAlignment.Left

	box.MouseEnter:Connect(function()
		state.hovered = true
	end)

	box.MouseLeave:Connect(function()
		state.hovered = false
	end)

	box.MouseButton1Down:Connect(function()
		state.pressed = true
	end)

	-- MouseButton1Up only fires over the button, so release is tracked globally
	local inputEnded = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			state.pressed = false
		end
	end)

	local heartbeat

	local function cleanup()
		if state.destroyed then
			return
		end

		state.destroyed = true

		if heartbeat then
			heartbeat:Disconnect()
			heartbeat = nil
		end

		inputEnded:Disconnect()
	end

	heartbeat = RunService.Heartbeat:Connect(function(dt)
		if state.destroyed then
			return
		end

		if not UI.isAlive(box) then
			cleanup()
			return
		end

		local alphaTarget = value and 1 or 0
		local hoverTarget = (state.hovered and not state.pressed) and 1 or 0
		local pressTarget = state.pressed and 1 or 0

		if animate then
			state.alpha = tooltipSmoothTowards(state.alpha, alphaTarget, speed, dt)
			state.hover = tooltipSmoothTowards(state.hover, hoverTarget, speed, dt)
			state.press = tooltipSmoothTowards(state.press, pressTarget, speed * 1.6, dt)

			if math.abs(state.alpha - alphaTarget) < 0.005 then
				state.alpha = alphaTarget
			end

			if math.abs(state.hover - hoverTarget) < 0.005 then
				state.hover = hoverTarget
			end

			if math.abs(state.press - pressTarget) < 0.005 then
				state.press = pressTarget
			end
		else
			state.alpha, state.hover, state.press = alphaTarget, hoverTarget, pressTarget
		end

		render()
	end)

	box.Destroying:Connect(cleanup)

	local controller = {}

	function controller:GetValue()
		return value
	end

	function controller:SetValue(newValue, silent, instant)
		value = newValue == true

		if instant or not animate then
			state.alpha = value and 1 or 0
			render()
		end

		if not silent and callback then
			callback(value)
		end
	end

	function controller:Destroy()
		cleanup()
		UI.forgetButtons(container)
		container:Destroy()
	end

	controller.frame = container

	controller.box = box

	controller.mark = mark

	controller.label = textLabel

	controller.record = record

	render()

	return container, controller
end

function UI.radio(parent, text, position, selected, callback, options)
	options = options or {}

	local colors = UI.tokens.color

	local value = selected == true
	local enabled = options.enabled ~= false

	local circleSize = options.circleSize or 18
	local dotSize = options.dotSize or 8

	local container = UI.frame(
		parent,
		position or UDim2.fromOffset(0, 0),
		options.size or UDim2.fromOffset(180, UI.metrics.propertyRow),
		colors.panel
	)

	container.BackgroundTransparency = 1

	local circle, record, dot, stroke, textLabel

	local function redraw()
		dot.Visible = value

		local base = options.color or colors.input

		record.color = base
		record.defaultColor = base

		circle.BackgroundColor3 = base

		if stroke then
			stroke.Color = value and (options.selectedBorderColor or colors.accent)
				or (options.borderColor or colors.border)
		end

		textLabel.TextColor3 = enabled and (options.textColor or colors.text) or colors.muted
	end

	local function select()
		if not enabled or value then
			return
		end

		value = true

		redraw()

		if callback then
			callback(true)
		end
	end

	circle, _, record = UI.button(
		container,
		"",
		UDim2.fromOffset(0, math.floor((UI.metrics.propertyRow - circleSize) / 2)),
		UDim2.fromOffset(circleSize, circleSize),
		select,
		{
			color = options.color or colors.input,
			hoverColor = colors.hover,
			pressedColor = colors.pressed,
			radius = math.floor(circleSize / 2),
			borderColor = colors.border,
			paddingX = 0,
			enabled = enabled,
		}
	)

	stroke = circle:FindFirstChildOfClass("UIStroke")

	dot = UI.frame(
		circle,
		UDim2.new(0.5, -math.floor(dotSize / 2), 0.5, -math.floor(dotSize / 2)),
		UDim2.fromOffset(dotSize, dotSize),
		options.dotColor or colors.accent,
		math.floor(dotSize / 2)
	)

	textLabel = UI.label(
		container,
		text,
		UDim2.fromOffset(circleSize + 7, 1),
		UDim2.new(1, -(circleSize + 7), 1, -1),
		options.textSize or UI.tokens.type.small,
		options.textColor or colors.text
	)

	textLabel.TextXAlignment = Enum.TextXAlignment.Left

	local textButton = UI.create("TextButton", {
		Text = "",
		Position = UDim2.fromOffset(circleSize + 4, 0),
		Size = UDim2.new(1, -(circleSize + 4), 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Active = true,
		InputSink = true,
	}, container)

	textButton.MouseButton1Click:Connect(select)

	local controller = {}

	function controller:GetValue()
		return value
	end

	function controller:SetValue(newValue, silent)
		newValue = newValue == true

		if value == newValue then
			return
		end

		value = newValue

		redraw()

		if not silent and callback then
			callback(value)
		end
	end

	function controller:SetText(newText)
		textLabel.Text = tostring(newText or "")
	end

	function controller:SetEnabled(newEnabled)
		enabled = newEnabled == true

		record.enabled = enabled
		circle.Active = enabled
		textButton.Active = enabled

		redraw()
	end

	controller.frame = container
	controller.circle = circle
	controller.dot = dot
	controller.label = textLabel
	controller.record = record

	redraw()

	return container, controller
end

function UI.radioGroup(parent, position, size, items, value, callback, options)
	options = options or {}

	items = items or {}

	local rowHeight = options.itemHeight or UI.metrics.propertyRow
	local gap = options.gap or 4
	local horizontal = options.direction == "horizontal"

	local container = UI.frame(parent, position or UDim2.fromOffset(0, 0), size, UI.tokens.color.panel)

	container.BackgroundTransparency = 1

	local currentValue = value
	local radios = {}

	local function normalize(item)
		if type(item) == "table" then
			local itemValue = item.value
			if itemValue == nil then
				itemValue = item[1]
			end

			return itemValue, tostring(item.text or item.label or item.name or itemValue or "")
		end

		return item, tostring(item)
	end

	local function setSelected(newValue)
		currentValue = newValue

		for radioValue, radio in pairs(radios) do
			radio:SetValue(radioValue == newValue, true)
		end
	end

	local offset = 0

	for _, item in ipairs(items) do
		local itemValue, itemText = normalize(item)

		local itemWidth = options.itemWidth or (#itemText * 7 + 32)

		local itemPosition = horizontal and UDim2.fromOffset(offset, 0) or UDim2.fromOffset(0, offset)

		local itemSize = horizontal and UDim2.fromOffset(itemWidth, rowHeight) or UDim2.new(1, 0, 0, rowHeight)

		local _, radio = UI.radio(container, itemText, itemPosition, itemValue == currentValue, function()
			if currentValue == itemValue then
				return
			end

			setSelected(itemValue)

			if callback then
				callback(itemValue, item)
			end
		end, {
			size = itemSize,
			textSize = options.textSize,
			textColor = options.textColor,
			enabled = options.enabled,
		})

		radios[itemValue] = radio

		offset += (horizontal and itemWidth or rowHeight) + gap
	end

	local controller = {}

	function controller:GetValue()
		return currentValue
	end

	function controller:SetValue(newValue, silent)
		if radios[newValue] == nil or currentValue == newValue then
			return
		end

		setSelected(newValue)

		if not silent and callback then
			callback(newValue)
		end
	end

	function controller:SetEnabled(enabled)
		for _, radio in pairs(radios) do
			radio:SetEnabled(enabled)
		end
	end

	controller.frame = container
	controller.radios = radios

	return container, controller
end

function UI.switch(parent, position, value, callback, options)
	options = options or {}

	local colors = UI.tokens.color

	local enabled = value == true

	local width = options.width or 34
	local height = options.height or 18
	local knobSize = height - 6
	local pad = 3

	local animate = options.animate ~= false
	local speed = options.animationSpeed or 22
	local pressStretch = options.pressStretch or 3

	local track
	local knob
	local record

	local state = {
		alpha = enabled and 1 or 0, -- 0 = off, 1 = on
		hover = 0,
		press = 0,
		hovered = false,
		pressed = false,
		destroyed = false,
	}

	local function render()
		local enabledColor = options.enabledColor or colors.accent
		local disabledColor = options.disabledColor or colors.input

		-- track colour: off -> on, with subtle hover lighten / press darken
		local color = disabledColor:Lerp(enabledColor, state.alpha)
		color = color:Lerp(Color3.new(1, 1, 1), 0.08 * state.hover)
		color = color:Lerp(Color3.new(0, 0, 0), 0.1 * state.press)

		track.BackgroundColor3 = color

		-- knob stretches slightly while pressed (iOS style), staying inside the track
		local knobWidth = knobSize + pressStretch * state.press
		local left = pad + (width - pad * 2 - knobWidth) * state.alpha

		knob.Size = UDim2.fromOffset(knobWidth, knobSize)
		knob.Position = UDim2.new(0, left, 0.5, -math.floor(knobSize / 2))
	end

	track, _, record = UI.button(parent, "", position, UDim2.fromOffset(width, height), function()
		enabled = not enabled

		if not animate then
			state.alpha = enabled and 1 or 0
			render()
		end

		if callback then
			callback(enabled)
		end
	end, {
		color = colors.input,
		hoverColor = colors.hover,
		pressedColor = colors.pressed,
		radius = math.floor(height / 2),
		borderColor = colors.border,
		paddingX = 0,
		hoveringEnabled = false, -- we drive hover/press colours ourselves
	})

	knob = UI.frame(
		track,
		UDim2.fromOffset(pad, pad),
		UDim2.fromOffset(knobSize, knobSize),
		options.knobColor or colors.text,
		math.floor(knobSize / 2)
	)

	track.MouseEnter:Connect(function()
		state.hovered = true
	end)

	track.MouseLeave:Connect(function()
		state.hovered = false
	end)

	track.MouseButton1Down:Connect(function()
		state.pressed = true
	end)

	-- MouseButton1Up only fires over the button, so release is tracked globally
	local inputEnded = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			state.pressed = false
		end
	end)

	local heartbeat

	local function cleanup()
		if state.destroyed then
			return
		end

		state.destroyed = true

		if heartbeat then
			heartbeat:Disconnect()
			heartbeat = nil
		end

		inputEnded:Disconnect()
	end

	heartbeat = RunService.Heartbeat:Connect(function(dt)
		if state.destroyed then
			return
		end

		if not UI.isAlive(track) then
			cleanup()
			return
		end

		local alphaTarget = enabled and 1 or 0
		local hoverTarget = (state.hovered and not state.pressed) and 1 or 0
		local pressTarget = state.pressed and 1 or 0

		if animate then
			state.alpha = tooltipSmoothTowards(state.alpha, alphaTarget, speed, dt)
			state.hover = tooltipSmoothTowards(state.hover, hoverTarget, speed, dt)
			state.press = tooltipSmoothTowards(state.press, pressTarget, speed * 1.6, dt)

			if math.abs(state.alpha - alphaTarget) < 0.005 then
				state.alpha = alphaTarget
			end

			if math.abs(state.hover - hoverTarget) < 0.005 then
				state.hover = hoverTarget
			end

			if math.abs(state.press - pressTarget) < 0.005 then
				state.press = pressTarget
			end
		else
			state.alpha, state.hover, state.press = alphaTarget, hoverTarget, pressTarget
		end

		render()
	end)

	track.Destroying:Connect(cleanup)

	local controller = {}

	function controller:GetValue()
		return enabled
	end

	function controller:SetValue(newValue, silent, instant)
		enabled = newValue == true

		if instant or not animate then
			state.alpha = enabled and 1 or 0
			render()
		end

		if not silent and callback then
			callback(enabled)
		end
	end

	function controller:Destroy()
		cleanup()
		UI.forgetButtons(track)
		track:Destroy()
	end

	controller.track = track
	controller.knob = knob
	controller.record = record

	render()

	return track, controller
end

function UI.slider(parent, position, size, minimum, maximum, value, callback, options)
	options = options or {}

	local colors = UI.tokens.color

	minimum = minimum or 0

	maximum = maximum or 1

	value = math.clamp(value or minimum, minimum, maximum)

	local step = options.step or 0

	local dragging = false

	local animate = options.animate ~= false
	local animationSpeed = options.animationSpeed or 20

	local displayValue = value
	local heartbeat = nil

	local container = UI.create("TextButton", {

		Text = "",

		Position = position or UDim2.fromOffset(0, 0),

		Size = size or UDim2.fromOffset(160, UI.metrics.inputHeight),

		BackgroundColor3 = colors.panel,

		BackgroundTransparency = 1,

		BorderSizePixel = 0,

		Active = true,

		InputSink = true,

		AutoButtonColor = false,
	}, parent)

	local trackHeight = options.trackHeight or 4

	local track = UI.frame(
		container,
		UDim2.new(0, 0, 0.5, -math.floor(trackHeight / 2)),
		UDim2.new(1, 0, 0, trackHeight),
		options.trackColor or colors.input,
		math.floor(trackHeight / 2)
	)

	local fill = UI.frame(
		track,
		UDim2.fromOffset(0, 0),
		UDim2.new(0, 0, 1, 0),
		options.fillColor or colors.accent,
		math.floor(trackHeight / 2)
	)

	local knobSize = options.knobSize or 12

	local knob = UI.frame(
		container,
		UDim2.fromOffset(0, 0),
		UDim2.fromOffset(knobSize, knobSize),
		options.knobColor or colors.text,
		math.floor(knobSize / 2)
	)

	UI.stroke(knob, options.knobBorderColor or colors.borderStrong, 1, options.knobBorderTransparency or 0)

	local function alphaFromValue(input)
		if maximum == minimum then
			return 0
		end

		return math.clamp((input - minimum) / (maximum - minimum), 0, 1)
	end

	local function redraw()
		local alpha = alphaFromValue(displayValue)

		fill.Size = UDim2.new(alpha, 0, 1, 0)

		knob.Position = UDim2.new(alpha, -math.floor(knobSize / 2), 0.5, -math.floor(knobSize / 2))
	end

	local function stopAnimation()
		if heartbeat then
			heartbeat:Disconnect()
			heartbeat = nil
		end
	end

	local function snapVisual()
		stopAnimation()

		displayValue = value

		redraw()
	end

	local function wake()
		if not animate or dragging then
			snapVisual()

			return
		end

		if heartbeat then
			return
		end

		heartbeat = RunService.Heartbeat:Connect(function(dt)
			displayValue = tooltipSmoothTowards(displayValue, value, animationSpeed, dt)

			local finished = math.abs(displayValue - value) < 0.0005

			if finished then
				displayValue = value
			end

			redraw()

			if finished then
				stopAnimation()
			end
		end)
	end

	container.Destroying:Connect(stopAnimation)

	local function setFromPoint(pointX, silent)
		local absolutePosition = track.AbsolutePosition

		local absoluteSize = track.AbsoluteSize

		if not absolutePosition or not absoluteSize or absoluteSize.X <= 0 then
			return
		end

		local alpha = math.clamp((pointX - absolutePosition.X) / absoluteSize.X, 0, 1)

		local newValue = minimum + (maximum - minimum) * alpha

		if step > 0 then
			newValue = math.floor((newValue - minimum) / step + 0.5) * step + minimum
		end

		newValue = math.clamp(newValue, minimum, maximum)

		if newValue == value then
			return
		end

		value = newValue
		displayValue = newValue

		redraw()

		if not silent and callback then
			callback(value)
		end
	end

	container.MouseButton1Down:Connect(function(x)
		stopAnimation()

		dragging = true

		setFromPoint(x)
	end)

	container.MouseMoved:Connect(function(x)
		if not dragging then
			return
		end

		setFromPoint(x)
	end)

	container.MouseButton1Up:Connect(function(x)
		if dragging then
			setFromPoint(x)
		end

		dragging = false
	end)

	local controller = {}

	function controller:GetValue()
		return value
	end

	function controller:SetValue(newValue, silent, instant)
		value = math.clamp(newValue, minimum, maximum)

		if step > 0 then
			value = math.floor((value - minimum) / step + 0.5) * step + minimum
		end

		if instant then
			snapVisual()
		else
			wake()
		end

		if not silent and callback then
			callback(value)
		end
	end

	function controller:SetRange(newMinimum, newMaximum)
		minimum = newMinimum

		maximum = newMaximum

		value = math.clamp(value, minimum, maximum)

		snapVisual()
	end

	controller.frame = container

	controller.track = track

	controller.fill = fill

	controller.knob = knob

	redraw()

	return container, controller
end

function UI.progressBar(parent, position, size, value, options)
	options = options or {}

	local colors = UI.tokens.color

	local progress = math.clamp(value or 0, 0, 1)

	local animate = options.animate ~= false
	local animationSpeed = options.animationSpeed or 18

	local displayProgress = progress
	local heartbeat = nil

	local background = UI.frame(
		parent,
		position,
		size or UDim2.fromOffset(160, 6),
		options.color or colors.input,
		options.radius or UI.tokens.radius.xs
	)

	background.ClipsDescendants = true

	local fill = UI.frame(
		background,
		UDim2.fromOffset(0, 0),
		UDim2.new(progress, 0, 1, 0),
		options.fillColor or colors.accent,
		options.radius or UI.tokens.radius.xs
	)

	local function stopAnimation()
		if heartbeat then
			heartbeat:Disconnect()
			heartbeat = nil
		end
	end

	local function redraw()
		fill.Size = UDim2.new(displayProgress, 0, 1, 0)
	end

	local function snapVisual()
		stopAnimation()

		displayProgress = progress

		redraw()
	end

	local function wake()
		if not animate then
			snapVisual()

			return
		end

		if heartbeat then
			return
		end

		heartbeat = RunService.Heartbeat:Connect(function(dt)
			displayProgress = tooltipSmoothTowards(displayProgress, progress, animationSpeed, dt)

			local finished = math.abs(displayProgress - progress) < 0.0005

			if finished then
				displayProgress = progress
			end

			redraw()

			if finished then
				stopAnimation()
			end
		end)
	end

	background.Destroying:Connect(stopAnimation)

	local controller = {}

	function controller:GetValue()
		return progress
	end

	function controller:SetValue(newValue, instant)
		progress = math.clamp(newValue, 0, 1)

		if instant then
			snapVisual()
		else
			wake()
		end
	end

	controller.frame = background

	controller.fill = fill

	return background, controller
end

function UI.sectionHeader(parent, text, position, size, options)
	options = options or {}

	local colors = UI.tokens.color

	local container = UI.frame(
		parent,
		position,
		size or UDim2.new(1, 0, 0, UI.metrics.sectionRow),
		options.headerColor or colors.panelRaised
	)

	container.BackgroundTransparency = options.transparent and 1 or 0

	local label = UI.label(
		container,
		text,
		UDim2.fromOffset(UI.tokens.space.md, 2),
		UDim2.new(1, -UI.tokens.space.md * 2, 1, -3),
		options.textSize or UI.tokens.type.small,
		options.textColor or colors.text
	)

	if options.separator ~= false then
		UI.separator(
			container,
			UDim2.new(0, UI.tokens.space.sm, 1, -1),
			UDim2.new(1, -UI.tokens.space.sm * 2, 0, 1),
			options.separatorColor or colors.border
		)
	end

	return container, label
end

function UI.badge(parent, text, position, options)
	options = options or {}

	local colors = UI.tokens.color

	local width = options.width or math.max(36, #tostring(text) * 7 + 12)

	local height = options.height or 18

	local frame = UI.frame(
		parent,
		position,
		UDim2.fromOffset(width, height),
		options.color or colors.accentSoft,
		options.radius or math.floor(height / 2)
	)

	local label = UI.label(
		frame,
		text,
		UDim2.fromOffset(4, 0),
		UDim2.new(1, -8, 1, 0),
		options.textSize or UI.tokens.type.caption,
		options.textColor or colors.text
	)

	return frame, label
end

function UI.card(parent, position, size, options)
	options = options or {}

	local colors = UI.tokens.color

	local card =
		
UI.frame(parent, position, size, options.color or colors.surface, options.radius or UI.tokens.radius.md)

	if options.border ~= false then
		UI.stroke(
			card,
			options.borderColor or colors.border,
			options.borderThickness or 1,
			options.borderTransparency or 0
		)
	end

	if options.shadow then
		UI.create("UIShadow", {

			BlurRadius = UDim.new(0, options.shadowBlur or 10),

			Offset = UDim2.fromOffset(0, options.shadowOffset or 3),

			Spread = UDim2.fromOffset(0, 0),

			Color3 = options.shadowColor or Color3.fromRGB(0, 0, 0),

			Transparency = options.shadowTransparency or 0.6,

			Enabled = true,
		}, card)
	end

	return card
end

function UI.root()
	if shared.root then
		return shared.root
	end

	local root = UI.create("ScreenGui", { Name = "Studio", DisplayOrder = 1000, IgnoreGuiInset = true }, game.CoreGui)

	shared.root = root

	shared.background = UI.create("TextButton", {

		Name = "EditorBackground",

		Text = "",

		Position = UDim2.fromOffset(0, 0),

		Size = UDim2.new(1, 0, 1, 0),

		BackgroundColor3 = UI.tokens.color.canvas,

		BorderSizePixel = 0,

		Active = true,

		InputSink = false,

		AutoButtonColor = false,

		ZIndex = -100000,
	}, root)

	shared.background.MouseButton1Click:Connect(function()
		local active = shared.activeDropdown

		if active and closeActiveDropdown and active.closeOnOutsideClick ~= false then
			closeActiveDropdown()
		end
	end)

	return root
end

function UI.contextMenu(parent, value, position, size, chevronIcon, options)
	if options == nil then
		options = parent
	end

	options = options or {}

	local colors = UI.tokens.color

	local rowHeight = options.itemHeight or UI.metrics.inputHeight
	local separatorHeight = options.separatorHeight or 9
	local padding = options.padding or 4
	local menuWidth = options.menuWidth or 200
	local maxVisibleItems = options.maxVisibleItems or 12
	local edge = options.menuMargin or 4
	local baseZ = options.menuZIndex or 100050
	local textSize = options.textSize or UI.tokens.type.small
	local textColor = options.textColor or colors.text
	local iconSize = options.iconSize or 14
	local showSearch = options.showSearch == true
	local preferLeft = options.menuSide == "left"
	local itemBgTransparency = options.itemBgTransparency or 1
	local hoverTransparency = options.hoverTransparency or 0.1
	local animationSpeed = options.animationSpeed or 24
	local animate = options.animate ~= false
	local baseColor = options.itemColor or options.menuColor or colors.panelRaised
	local hoverColor = options.hoverColor or colors.accent
	local chevronIcon = options.chevronIcon or "builtin://global-icons/chevron-down.svg"

	local fadeSpeed = options.fadeSpeed or 22
	local rowSpeed = options.rowSpeed or 22
	local rowStagger = options.rowStagger or 0.02
	local maxStagger = options.maxStagger or 0.18
	local slideDistance = options.slideDistance or 8
	local rowSlide = options.rowSlide or 10
	local hoverNudge = options.hoverNudge or 2
	local pressDarken = options.pressDarken or 0.08
	local panelTransparency = options.BackgroundTransparency or 0.5

	local items = options.items
	local categories = options.categories

	local controller = {}
	local stack = {}
	local dying = {}
	local connections = {}
	local heartbeat = nil
	local catcher = nil
	local open = false
	local context = nil

	local function evaluate(value, ...)
		if type(value) == "function" then
			return value(...)
		end

		return value
	end

	local function normalize(raw)
		if type(raw) ~= "table" then
			return { text = tostring(raw), value = raw, enabled = true }
		end

		if raw.separator == true or raw.type == "separator" then
			return { separator = true }
		end

		local value = raw.value

		if value == nil then
			value = raw[1]
		end

		return {
			text = tostring(raw.label or raw.text or raw.name or value or ""),
			value = value,
			icon = raw.icon,
			shortcut = raw.shortcut,
			enabled = evaluate(raw.enabled, context) ~= false,
			check = evaluate(raw.check, context) == true,
			callback = raw.callback or raw.onClick,
			children = raw.submenu or raw.children or raw.items,
			raw = raw,
		}
	end

	local function matches(entry, query)
		if query == "" then
			return true
		end

		if entry.separator then
			return false
		end

		return string.find(string.lower(entry.text or ""), query, 1, true) ~= nil
	end

	local function topEntries(query)
		local out = {}
		local cats = evaluate(categories, context)

		if cats then
			for _, category in ipairs(cats) do
				local matched = {}

				for _, raw in ipairs(category.items or {}) do
					local entry = normalize(raw)

					if matches(entry, query) then
						table.insert(matched, entry)
					end
				end

				if #matched > 0 then
					table.insert(out, { header = category.name })

					for _, entry in ipairs(matched) do
						table.insert(out, entry)
					end
				end
			end
		else
			for _, raw in ipairs(evaluate(items, context) or {}) do
				local entry = normalize(raw)

				if matches(entry, query) then
					table.insert(out, entry)
				end
			end
		end

		return out
	end

	local function childEntries(list)
		local out = {}

		for _, raw in ipairs(evaluate(list, context) or {}) do
			table.insert(out, normalize(raw))
		end

		return out
	end

	local function track(list, obj, prop)
		table.insert(list, { obj = obj, prop = prop, base = obj[prop] })
	end

	local function applyFades(list, a)
		for _, f in ipairs(list) do
			f.obj[f.prop] = 1 - (1 - f.base) * a
		end
	end

	local function closeFrom(level, instant)
		for i = #stack, level, -1 do
			local menu = stack[i]
			stack[i] = nil

			if menu.shell then
				if instant or not animate then
					menu.shell:Destroy()
				else
					menu.closing = true
					menu.alphaTarget = 0
					table.insert(dying, menu)
				end
			end
		end
	end

	local function flushDying()
		for i = #dying, 1, -1 do
			local menu = dying[i]

			if menu.shell then
				menu.shell:Destroy()
			end

			dying[i] = nil
		end
	end

	local function place(menu)
		local screen = workspace:GetWindowDimensions()
		local anchor = menu.anchor
		local x, y

		if anchor.rowRect then
			local rect = anchor.rowRect

			if preferLeft then
				x = rect.left - menuWidth + 2

				if x < edge then
					x = rect.right - 2
				end
			else
				x = rect.right - 2

				if x + menuWidth > screen.X - edge then
					x = rect.left - menuWidth + 2
				end
			end

			y = rect.top - padding
		else
			local point = anchor.point

			x = preferLeft and (point.X - menuWidth) or point.X

			if x + menuWidth > screen.X - edge then
				x = point.X - menuWidth
			end

			if x < edge then
				x = point.X
			end

			y = point.Y

			if y + menu.height > screen.Y - edge then
				y = point.Y - menu.height
			end
		end

		x = math.clamp(x, edge, math.max(edge, screen.X - menuWidth - edge))
		y = math.clamp(y, edge, math.max(edge, screen.Y - menu.height - edge))

		menu.baseX = math.floor(x + 0.5)
		menu.baseY = math.floor(y + 0.5)

		if anchor.rowRect then
			menu.slideX = (menu.baseX >= anchor.rowRect.right - 4) and -1 or 1
			menu.slideY = 0
		else
			menu.slideX = 0
			menu.slideY = (anchor.point.Y + menu.height > screen.Y - edge) and 1 or -1
		end

		menu.shell.Position = UDim2.fromOffset(menu.baseX, menu.baseY)
	end

	local renderRows
	local openLevel

	local function choose(entry)
		controller:Close("select")

		if entry.callback then
			entry.callback(entry.value, entry.raw, context)
		end

		if options.onChanged then
			options.onChanged(entry.value, entry.raw, context)
		end
	end

	renderRows = function(menu, stagger)
		local query = menu.search and string.lower(menu.search.Text or "") or ""
		local entries = menu.source(query)

		UI.clear(menu.list)

		menu.rows = {}
		menu.statics = {}

		local z = menu.z + 3
		local rowWidth = menuWidth - padding * 2
		local y = 0
		local index = 0

		for _, entry in ipairs(entries) do
			index += 1

			if entry.header then
				local header = UI.label(
					menu.list,
					entry.header,
					UDim2.fromOffset(10, y + 3),
					UDim2.new(1, -20, 0, rowHeight - 4),
					options.categoryTextSize or 10,
					colors.muted
				)

				header.TextXAlignment = Enum.TextXAlignment.Left
				header.ZIndex = z + 1

				track(menu.statics, header, "TextTransparency")

				y += rowHeight
			elseif entry.separator then
				local line = UI.separator(
					menu.list,
					UDim2.fromOffset(padding + 6, y + math.floor(separatorHeight / 2)),
					UDim2.fromOffset(menuWidth - (padding + 6) * 2, 1),
					colors.border
				)

				line.ZIndex = z

				track(menu.statics, line, "BackgroundTransparency")

				y += separatorHeight
			else
				local enabled = entry.enabled ~= false

				local row = UI.create("TextButton", {
					Text = "",
					Position = UDim2.fromOffset(padding, y),
					Size = UDim2.fromOffset(rowWidth, rowHeight),
					BackgroundColor3 = baseColor,
					BackgroundTransparency = itemBgTransparency,
					BorderSizePixel = 0,
					AutoButtonColor = false,
					Active = true,
					InputSink = true,
					ZIndex = z,
				}, menu.list)

				UI.corner(row, options.itemRadius or UI.tokens.radius.sm)

				local record = {
					button = row,
					hover = 0,
					hovered = false,
					pressed = 0,
					isPressed = false,
					enabled = enabled,
					baseY = y,
					fades = {},
					appear = (animate and stagger) and 0 or 1,
					age = 0,
					delay = math.min(index * rowStagger, maxStagger),
					labelX = 24,
					lastA = -1,
				}

				local labelX = 24

				if entry.icon then
					local icon = UI.image(
						row,
						entry.icon,
						UDim2.fromOffset(7, math.floor((rowHeight - iconSize) / 2)),
						UDim2.fromOffset(iconSize, iconSize)
					)

					icon.ZIndex = z + 1

					track(record.fades, icon, "ImageTransparency")

					labelX = 7 + iconSize + 7
				elseif entry.check then
					local dot = UI.frame(
						row,
						UDim2.fromOffset(10, math.floor(rowHeight / 2) - 3),
						UDim2.fromOffset(6, 6),
						colors.accent,
						3
					)

					dot.ZIndex = z + 1

					track(record.fades, dot, "BackgroundTransparency")
				end

				record.labelX = labelX

				local label = UI.label(
					row,
					entry.text,
					UDim2.fromOffset(labelX, 0),
					UDim2.new(1, -(labelX + (entry.shortcut and 84 or 22)), 1, 0),
					textSize,
					enabled and textColor or colors.muted
				)

				label.TextXAlignment = Enum.TextXAlignment.Left
				label.TextYAlignment = Enum.TextYAlignment.Center
				label.ZIndex = z + 1

				record.label = label
				track(record.fades, label, "TextTransparency")

				if entry.shortcut then
					local hint = UI.label(
						row,
						entry.shortcut,
						UDim2.new(1, -90, 0, 0),
						UDim2.fromOffset(82, rowHeight),
						UI.tokens.type.caption,
						colors.muted
					)

					hint.TextXAlignment = Enum.TextXAlignment.Right
					hint.TextYAlignment = Enum.TextYAlignment.Center
					hint.ZIndex = z + 1

					track(record.fades, hint, "TextTransparency")
				end

				if entry.children then
					local arrow = UI.image(row, chevronIcon, UDim2.new(1, -18, 0.5, -5), UDim2.fromOffset(10, 10))

					arrow.Rotation = -90
					arrow.ZIndex = z + 1

					record.arrow = arrow
					track(record.fades, arrow, "ImageTransparency")
				end

				table.insert(menu.rows, record)

				local function openChild()
					local position = row.AbsolutePosition

					record.childOpen = true

					openLevel(menu.level + 1, function()
						return childEntries(entry.children)
					end, {
						rowRect = {
							left = position.X,
							right = position.X + row.AbsoluteSize.X + padding,
							top = position.Y,
						},
					})
				end

				row.MouseEnter:Connect(function()
					record.hovered = true

					if not enabled then
						return
					end

					for _, other in ipairs(menu.rows) do
						other.childOpen = false
					end

					if entry.children then
						openChild()
					else
						closeFrom(menu.level + 1)
					end
				end)

				row.MouseLeave:Connect(function()
					record.hovered = false
					record.isPressed = false
				end)

				row.MouseButton1Down:Connect(function()
					if enabled then
						record.isPressed = true
					end
				end)

				row.MouseButton1Up:Connect(function()
					record.isPressed = false
				end)

				row.MouseButton1Click:Connect(function()
					if entry.children then
						openChild()
					else
						choose(entry)
					end
				end)

				y += rowHeight
			end
		end

		menu.contentHeight = math.max(y, rowHeight)

		local screen = workspace:GetWindowDimensions()
		local available = math.max(screen.Y - edge * 2 - padding * 2 - menu.searchHeight, rowHeight)
		local visible = math.min(menu.contentHeight, maxVisibleItems * rowHeight, available)

		menu.list.CanvasSize = UDim2.new(1, 0, 0, menu.contentHeight)
		menu.list.Size = UDim2.new(1, 0, 0, visible)
		menu.list.ScrollingEnabled = menu.contentHeight > visible

		menu.height = menu.searchHeight + visible + padding * 2
		menu.inner.Size = UDim2.fromOffset(menuWidth, menu.height)
	end

	local function updateMenu(menu, dt)
		if animate then
			menu.alpha = tooltipSmoothTowards(menu.alpha, menu.alphaTarget, fadeSpeed, dt)

			if math.abs(menu.alpha - menu.alphaTarget) < 0.01 then
				menu.alpha = menu.alphaTarget
			end
		else
			menu.alpha = menu.alphaTarget
		end

		local a = menu.alpha

		if not menu.closing then
			if animate then
				menu.cur = tooltipSmoothTowards(menu.cur, menu.height, animationSpeed, dt)

				if math.abs(menu.cur - menu.height) < 0.5 then
					menu.cur = menu.height
				end
			else
				menu.cur = menu.height
			end
		end

		menu.shell.Size = UDim2.fromOffset(menuWidth, math.floor(menu.cur + 0.5))

		if menu.baseX then
			local inv = 1 - a

			menu.shell.Position = UDim2.fromOffset(
				math.floor(menu.baseX + menu.slideX * slideDistance * inv + 0.5),
				math.floor(menu.baseY + menu.slideY * slideDistance * inv + 0.5)
			)
		end

		menu.inner.BackgroundTransparency = 1 - (1 - panelTransparency) * a

		applyFades(menu.statics, a)

		for _, st in ipairs(menu.strokes) do
			st.obj.Transparency = 1 - (1 - st.base) * a
		end

		for _, b in ipairs(menu.backdrops) do
			if b.blur ~= nil then
				b.obj.BlurRadius = b.blur * a
			end

			if b.tint ~= nil then
				b.obj.TintTransparency = 1 - (1 - b.tint) * a
			end
		end

		for _, row in ipairs(menu.rows) do
			if row.appear < 1 then
				row.age += dt

				if row.age >= row.delay then
					row.appear = tooltipSmoothTowards(row.appear, 1, rowSpeed, dt)

					if row.appear > 0.995 then
						row.appear = 1
					end
				end
			end

			local hoverTarget = (row.hovered and row.enabled) and 1 or 0
			local pressTarget = row.isPressed and 1 or 0

			row.hover = tooltipSmoothTowards(row.hover, hoverTarget, 26, dt)
			row.pressed = tooltipSmoothTowards(row.pressed, pressTarget, 40, dt)

			row.button.BackgroundColor3 = baseColor:Lerp(hoverColor, row.hover)
			row.button.BackgroundTransparency = math.clamp(
				itemBgTransparency + (hoverTransparency - itemBgTransparency) * row.hover - pressDarken * row.pressed,
				0,
				1
			)

			local slide = (1 - row.appear) * -rowSlide
			row.button.Position = UDim2.fromOffset(padding + slide, row.baseY)

			if row.label then
				row.label.Position = UDim2.fromOffset(row.labelX + hoverNudge * row.hover, 0)
			end

			if row.arrow then
				local lit = math.max(row.hover, row.childOpen and 1 or 0)

				row.arrow.Position = UDim2.new(1, -18 + 3 * lit, 0.5, -5)
			end

			local fa = row.appear * a

			if fa ~= row.lastA then
				row.lastA = fa
				applyFades(row.fades, fa)
			end
		end
	end

	local function step(dt)
		for _, menu in ipairs(stack) do
			updateMenu(menu, dt)
		end

		for i = #dying, 1, -1 do
			local menu = dying[i]

			updateMenu(menu, dt)

			if menu.alpha <= 0.02 then
				if menu.shell then
					menu.shell:Destroy()
				end

				table.remove(dying, i)
			end
		end

		if not open and #dying == 0 and heartbeat then
			heartbeat:Disconnect()
			heartbeat = nil
		end
	end

	openLevel = function(level, source, anchor)
		closeFrom(level)

		local overlay = UI.contextMenuOverlay()
		local z = baseZ + level * 10

		local shell = UI.create("Frame", {
			Name = "ContextMenu" .. level,
			Size = UDim2.fromOffset(menuWidth, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			ZIndex = z,
		}, overlay)

		local inner = UI.frame(
			shell,
			UDim2.fromOffset(0, 0),
			UDim2.fromOffset(menuWidth, 10),
			options.menuColor or colors.panelRaised,
			options.radius or UI.tokens.radius.md
		)

		inner.Name = "Panel"
		inner.BackgroundTransparency = animate and 1 or panelTransparency
		inner.ZIndex = z + 1

		local backdrops = {}

		local function trackBackdrop(obj)
			if obj == nil or type(obj) == "number" then
				return
			end

			local okBlur, blur = pcall(function()
				return obj.BlurRadius
			end)

			local okTint, tint = pcall(function()
				return obj.TintTransparency
			end)

			if okBlur or okTint then
				table.insert(backdrops, {
					obj = obj,
					blur = okBlur and blur or nil,
					tint = okTint and tint or nil,
				})
			end
		end

		local strokes = {}

		local function trackStroke(obj)
			if obj == nil or type(obj) == "number" then
				return
			end

			local ok, base = pcall(function()
				return obj.Transparency
			end)

			if ok and type(base) == "number" then
				table.insert(strokes, { obj = obj, base = base })
			end
		end

		trackBackdrop(UI.backdrop(inner, 15, Color3.new(0, 0, 0)))
		trackStroke(UI.stroke(inner, options.borderColor or colors.borderStrong, 1, options.borderTransparency or 0))

		if options.backdrop then
			trackBackdrop(UI.create("UIBackdrop", {
				Enabled = true,
				BlurRadius = options.backdropBlur or 18,
				TintColor3 = options.backdropColor or colors.panelRaised,
				TintTransparency = options.backdropTransparency or options.BackgroundTransparency or 0.85,
			}, inner))
		end

		local menu = {
			level = level,
			z = z,
			shell = shell,
			inner = inner,
			source = source,
			anchor = anchor,
			rows = {},
			statics = {},
			backdrops = backdrops,
			strokes = strokes,
			height = 0,
			cur = 0,
			alpha = animate and 0 or 1,
			alphaTarget = 1,
			closing = false,
			slideX = 0,
			slideY = 0,
			searchHeight = (level == 1 and showSearch) and 34 or 0,
		}

		if menu.searchHeight > 0 then
			menu.search = UI.input(
				inner,
				options.searchPlaceholder or "Search...",
				UDim2.fromOffset(5, 5),
				UDim2.new(1, -10, 0, 24),
				{ textSize = textSize }
			)

			menu.search.ZIndex = z + 2
		end

		menu.list = UI.create("ScrollingFrame", {
			Position = UDim2.fromOffset(0, menu.searchHeight + padding),
			Size = UDim2.new(1, 0, 0, 10),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasPosition = Vector2.new(0, 0),
			CanvasSize = UDim2.new(1, 0, 0, 0),
			ScrollBarThickness = 5,
			ScrollBarImageColor3 = colors.subtext,
			ScrollBarImageTransparency = 0.4,
			ScrollBarAutoHide = true,
			ClipsDescendants = true,
			ZIndex = z + 2,
		}, inner)

		table.insert(stack, menu)

		renderRows(menu, true)
		place(menu)

		menu.cur = animate and 0 or menu.height
		shell.Size = UDim2.fromOffset(menuWidth, math.floor(menu.cur + 0.5))

		if menu.search then
			menu.search.TextChanged:Connect(function()
				renderRows(menu, false)
				place(menu)
			end)
		end

		return menu
	end

	local function toPoint(position)
		local screen = workspace:GetWindowDimensions()

		local ok, scaleX = pcall(function()
			return position.X.Scale
		end)

		if ok and scaleX ~= nil then
			return Vector2.new(
				position.X.Scale * screen.X + position.X.Offset,
				position.Y.Scale * screen.Y + position.Y.Offset
			)
		end

		return position
	end

	function controller:Open(position, newContext)
		if open then
			controller:Close("reopen")
		end

		if shared.activeContextMenu and shared.activeContextMenu ~= controller then
			shared.activeContextMenu:Close("replaced")
		end

		if closeActiveDropdown then
			closeActiveDropdown()
		end

		context = newContext
		controller.context = newContext

		local point

		if position ~= nil then
			point = toPoint(position)
		elseif options.menuPosition then
			local menuPosition = options.menuPosition

			if type(menuPosition) == "function" then
				menuPosition = menuPosition()
			end

			point = toPoint(menuPosition)
		else
			point = UserInputService:GetMouseLocation()
		end

		table.insert(
			connections,
			UserInputService.InputBegan:Connect(function(input)
				if input.KeyCode == Enum.KeyCode.Escape then
					controller:Close("escape")
				end
			end)
		)

		if not heartbeat then
			heartbeat = RunService.Heartbeat:Connect(step)
		end

		open = true
		shared.activeContextMenu = controller

		openLevel(1, topEntries, { point = point })

		if options.onOpen then
			options.onOpen(context)
		end

		return true
	end

	function controller:Close(reason)
		if not open then
			return false
		end

		open = false

		local instant = reason == "destroy" or reason == "reopen"

		closeFrom(1, instant)

		if instant then
			flushDying()
		end

		if catcher then
			catcher:Destroy()
			catcher = nil
		end

		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end

		connections = {}

		if (instant or not animate) and heartbeat then
			heartbeat:Disconnect()
			heartbeat = nil
		end

		if shared.activeContextMenu == controller then
			shared.activeContextMenu = nil
		end

		if options.onClose then
			options.onClose(reason or "closed", context)
		end

		return true
	end

	function controller:Toggle(position, newContext)
		if open then
			return controller:Close("toggle")
		end

		return controller:Open(position, newContext)
	end

	function controller:IsOpen()
		return open
	end

	function controller:ContainsPoint(x, y)
		for _, menu in ipairs(stack) do
			local shell = menu.shell

			if shell and UI.isAlive(shell) then
				local position = shell.AbsolutePosition

				if
					x >= position.X
					and x <= position.X + menuWidth
					and y >= position.Y
					and y <= position.Y + menu.height
				then
					return true
				end
			end
		end

		return false
	end

	function controller:SetItems(newItems)
		items = newItems
		categories = nil

		if open then
			controller:Close("items")
		end
	end

	function controller:SetCategories(newCategories)
		categories = newCategories

		if open then
			controller:Close("items")
		end
	end

	function controller:Destroy()
		controller:Close("destroy")
		flushDying()

		if heartbeat then
			heartbeat:Disconnect()
			heartbeat = nil
		end
	end

	return controller
end

function UI.widgetOverlay()
	if shared.widgetOverlay then
		return shared.widgetOverlay
	end

	local root = UI.create(
		"ScreenGui",
		{ Name = "Widgets", DisplayOrder = 1001, IgnoreGuiInset = true, RenderOnTop = true, Enabled = true },
		game.CoreGui
	)

	shared.widgetOverlay = root

	return root
end

function UI.contextMenuOverlay()
	if shared.contextMenuOverlay then
		return shared.contextMenuOverlay
	end

	local root = UI.create(
		"ScreenGui",
		{ Name = "Menus", DisplayOrder = 4000, IgnoreGuiInset = true, RenderOnTop = true, Enabled = true },
		game.CoreGui
	)

	shared.contextMenuOverlay = root

	return root
end

function UI.RootOverlay()
	if shared.overlayRoot then
		return shared.overlayRoot
	end

	local root = UI.create("ScreenGui", {

		Name = "Overlay",

		DisplayOrder = 1000,

		IgnoreGuiInset = true,
	}, game.CoreGui)

	root.RenderOnTop = true

	shared.overlayRoot = root

	return root
end

function UI.TopbarButton(parent, definition, options)
	options = options or {}

	local tokens = UI.tokens

	local radius = options.radius or tokens.radius.sm
	local size = options.size or UDim2.fromOffset(52, 58)
	local position = options.position or UDim2.fromOffset(0, 0)
	local onClick = options.onClick

	local iconSize = options.iconSize or 22
	local iconTop = 7

	local animate = options.animate ~= false
	local speed = options.animationSpeed or 22
	local hoverLift = options.hoverLift or 2 -- px the icon rises on hover
	local hoverScale = options.hoverScale or 0.08 -- icon grows by this fraction on hover
	local pressScale = options.pressScale or 0.12 -- icon shrinks by this fraction on press
	local hoverEnabled = options.hoveringEnabled ~= false

	-- Colours are read live every frame so theme changes apply automatically.
	-- options.colors still overrides individual keys, as before.
	local function pick(key, fallback)
		local override = options.colors and options.colors[key]
		return override or fallback
	end

	local function palette()
		local c = UI.tokens.color

		return {
			surface = pick("surface", c.surface),
			raised = pick("raised", c.panelRaised),
			input = pick("input", c.input),
			subtext = pick("subtext", c.subtext),
			text = pick("text", c.text),
			accent = pick("accent", c.accent),
		}
	end

	local initial = palette()

	local item, _, record = UI.button(parent, "", position, size, function() end, {
		color = initial.surface,
		hoverColor = initial.raised,
		pressedColor = initial.input,
		radius = radius,
		hoveringEnabled = false, -- hover/press colours are driven by the animation
		border = false,
	})

	item.Name = definition.name .. "Tool"

	local icon = nil

	if definition.icon then
		icon = UI.image(
			item,
			"builtin://icons/" .. definition.icon,
			UDim2.new(0.5, 0, 0, iconTop + math.floor(iconSize / 2)),
			UDim2.fromOffset(iconSize, iconSize)
		)

		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Name = "Icon"
	end

	local label = UI.label(
		item,
		definition.name,
		UDim2.fromOffset(4, 35),
		UDim2.new(1, -8, 0, 16),
		tokens.type.caption,
		initial.subtext
	)

	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Top

	-- accent indicator that grows in when the button is selected
	local indicator = UI.frame(item, UDim2.new(0.5, 0, 1, -3), UDim2.new(0, 0, 0, 2), initial.accent, 1)

	indicator.AnchorPoint = Vector2.new(0.5, 1)
	indicator.Name = "Indicator"
	indicator.Visible = false

	local state = {
		hover = 0,
		press = 0,
		select = 0,
		hovered = false,
		pressed = false,
		selected = options.selected == true,
		running = true,
		destroyed = false,
	}

	state.select = state.selected and 1 or 0

	local function render()
		local p = palette()

		-- background: surface -> raised on hover/selected, -> input on press
		local color = p.surface:Lerp(p.raised, math.max(state.hover, state.select * 0.6))
		color = color:Lerp(p.input, state.press)

		item.BackgroundColor3 = color

		-- label brightens with hover / selection
		label.TextColor3 = p.subtext:Lerp(p.text, math.max(state.hover, state.select))

		if icon then
			local scale = 1 + hoverScale * state.hover - pressScale * state.press
			local px = math.max(math.floor(iconSize * scale + 0.5), 1)
			local lift = hoverLift * state.hover * (1 - state.press)

			icon.Size = UDim2.fromOffset(px, px)
			icon.Position = UDim2.new(0.5, 0, 0, iconTop + math.floor(iconSize / 2) - lift)
		end

		indicator.BackgroundColor3 = p.accent
		indicator.Visible = state.select > 0.001
		indicator.Size = UDim2.new(0.6 * state.select, 0, 0, 2)
	end

	local function wake()
		state.running = true
	end

	item.MouseEnter:Connect(function()
		state.hovered = true
		wake()
	end)

	item.MouseLeave:Connect(function()
		state.hovered = false
		wake()
	end)

	item.MouseButton1Down:Connect(function()
		state.pressed = true
		wake()
	end)

	-- MouseButton1Up only fires over the button, so release is tracked globally
	local inputEnded = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			state.pressed = false
			wake()
		end
	end)

	if onClick then
		item.MouseButton1Click:Connect(function()
			onClick(item, definition)
		end)
	end

	local heartbeat
	local themeListener

	local function cleanup()
		if state.destroyed then
			return
		end

		state.destroyed = true

		if heartbeat then
			heartbeat:Disconnect()
			heartbeat = nil
		end

		if themeListener then
			themeListener.Disconnect()
			themeListener = nil
		end

		inputEnded:Disconnect()
	end

	-- repaint once when the theme changes, even if the button is idle
	themeListener = UI.onThemeChanged(function()
		if not state.destroyed then
			wake()
		end
	end)

	heartbeat = RunService.Heartbeat:Connect(function(dt)
		if state.destroyed then
			return
		end

		if not UI.isAlive(item) then
			cleanup()
			return
		end

		-- idle: nothing to animate
		if not state.running then
			return
		end

		local hoverTarget = (hoverEnabled and state.hovered and not state.pressed) and 1 or 0
		local pressTarget = (hoverEnabled and state.pressed) and 1 or 0
		local selectTarget = state.selected and 1 or 0

		local moving = false

		if animate then
			state.hover = tooltipSmoothTowards(state.hover, hoverTarget, speed, dt)
			state.press = tooltipSmoothTowards(state.press, pressTarget, speed * 1.6, dt)
			state.select = tooltipSmoothTowards(state.select, selectTarget, speed, dt)

			if math.abs(state.hover - hoverTarget) < 0.005 then
				state.hover = hoverTarget
			else
				moving = true
			end

			if math.abs(state.press - pressTarget) < 0.005 then
				state.press = pressTarget
			else
				moving = true
			end

			if math.abs(state.select - selectTarget) < 0.005 then
				state.select = selectTarget
			else
				moving = true
			end
		else
			state.hover, state.press, state.select = hoverTarget, pressTarget, selectTarget
		end

		render()

		state.running = moving
	end)

	item.Destroying:Connect(cleanup)

	local controller = {}

	function controller:SetSelected(selected, instant)
		state.selected = selected == true

		if instant or not animate then
			state.select = state.selected and 1 or 0
			render()
		end

		wake()
	end

	function controller:IsSelected()
		return state.selected
	end

	function controller:SetText(text)
		label.Text = tostring(text or "")
	end

	function controller:Destroy()
		cleanup()
		UI.forgetButtons(item)
		item:Destroy()
	end

	controller.button = item
	controller.label = label
	controller.icon = icon
	controller.indicator = indicator
	controller.record = record

	render()

	return item, label, controller
end

function UI.buttonList(parent, position, size, buttons, options)
	options = options or {}

	local colors = UI.tokens.color
	local horizontal = options.direction == "horizontal"
	local iconPrefix = options.iconPrefix or "builtin://global-icons/"

	local BASE =
		{ rowHeight = 22, gap = 0, iconSize = 14, textSize = 12, paddingX = 6, iconGap = 6, separatorSpace = 7 }

	local scale = options.scale or 1
	local rowHeight, gap, iconSize, textSize, paddingX, iconGap, separatorSpace, charWidth

	local function applyScale(newScale)
		scale = math.max(newScale or 1, 0.1)

		local function s(value)
			return math.max(1, math.floor(value * scale + 0.5))
		end

		rowHeight = options.rowHeight or s(BASE.rowHeight)
		gap = options.gap or math.floor(BASE.gap * scale + 0.5)
		iconSize = options.iconSize or s(BASE.iconSize)
		textSize = options.textSize or math.clamp(s(BASE.textSize), 6, 100)
		paddingX = options.paddingX or s(BASE.paddingX)
		iconGap = options.iconGap or s(BASE.iconGap)
		separatorSpace = options.separatorSpace or s(BASE.separatorSpace)
		charWidth = options.charWidth or (textSize * 0.58)
	end

	applyScale(scale)
	local hoverColor = options.hoverColor or colors.hover
	local selectedColor = options.selectedColor or colors.selection
	local textColor = options.textColor or colors.text

	local function iconPath(icon)
		if not icon or icon == "" then
			return nil
		end
		if string.find(icon, "://", 1, true) then
			return icon
		end
		return iconPrefix .. icon
	end

	local function rowWidth(config)
		if config.width then
			return config.width
		end
		local text = tostring(config.text or config.label or config.name or "")
		local width = math.ceil(#text * charWidth) + paddingX * 2
		if config.icon then
			width += iconSize + iconGap
		end
		return width
	end

	local function computeAutoWidth(list)
		local widest = 0
		for _, config in ipairs(list or {}) do
			if (config.type or "button") == "button" then
				widest = math.max(widest, rowWidth(config))
			end
		end
		return options.width or widest
	end

	local autoWidth = computeAutoWidth(buttons)

	local autoSize = size == nil

	local container = UI.frame(
		parent,
		position or UDim2.fromOffset(0, 0),
		size or (horizontal and UDim2.fromOffset(0, rowHeight) or UDim2.fromOffset(autoWidth, 0)),
		options.color or colors.panel
	)
	container.Name = options.name or "ButtonList"
	container.BackgroundTransparency = options.color and 0 or 1

	if autoSize then
		container.AutomaticSize = horizontal and Enum.AutomaticSize.X or Enum.AutomaticSize.Y
	end

	local layout = UI.create("UIListLayout", {
		FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, gap),
		VerticalAlignment = Enum.VerticalAlignment.Top,
	}, container)

	local controller = { frame = container, layout = layout, items = {}, selected = options.selected }

	local function paint(item, hovered)
		if not item.enabled then
			item.button.BackgroundTransparency = 1
			item.label.TextColor3 = colors.muted
			return
		end

		local isSelected = options.selectable and controller.selected == item.id

		item.label.TextColor3 = textColor

		if isSelected then
			item.button.BackgroundColor3 = hovered and colors.selectionHover or selectedColor
			item.button.BackgroundTransparency = 0
		elseif hovered then
			item.button.BackgroundColor3 = hoverColor
			item.button.BackgroundTransparency = 0
		else
			item.button.BackgroundTransparency = 1
		end
	end

	local function repaintAll()
		for _, item in pairs(controller.items) do
			if item.button then
				paint(item, item.hovered)
			end
		end
	end

	local function build()
		UI.clear(container, { [layout] = true })
		controller.items = {}

		for index, config in ipairs(controller.buttonConfigs) do
			local kind = config.type or "button"

			if kind == "separator" then
				local holder = UI.create("Frame", {
					Name = "Separator",
					Size = horizontal and UDim2.new(0, separatorSpace, 1, 0) or UDim2.new(1, 0, 0, separatorSpace),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					LayoutOrder = index,
				}, container)

				UI.separator(
					holder,
					horizontal and UDim2.new(0.5, 0, 0, 3) or UDim2.new(0, 4, 0.5, 0),
					horizontal and UDim2.new(0, 1, 1, -6) or UDim2.new(1, -8, 0, 1),
					colors.border
				)
			elseif kind == "custom" then
				local holder = UI.create("Frame", {
					Name = tostring(config.name or ("Custom" .. index)),
					Size = horizontal and UDim2.new(0, config.width or 100, 1, 0)
						or UDim2.new(1, 0, 0, config.height or rowHeight),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					LayoutOrder = index,
				}, container)

				if config.create then
					config.create(holder, colors, UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1))
				end
			else
				local id = config.name or config.id or tostring(index)
				local text = tostring(config.text or config.label or config.name or "")
				local icon = iconPath(config.icon)
				local enabled = config.enabled ~= false

				local button, label, record
				button, label, record = UI.button(
					container,
					text,
					UDim2.fromOffset(0, 0),
					horizontal and UDim2.fromOffset(rowWidth(config), rowHeight) or UDim2.new(1, 0, 0, rowHeight),
					function()
						if options.selectable then
							controller.selected = id
							repaintAll()
							if options.onSelected then
								options.onSelected(id, config)
							end
						end
						if config.callback then
							config.callback(controller, config)
						end
					end,
					{
						color = colors.panel,
						hoverColor = hoverColor,
						pressedColor = colors.pressed,
						textColor = textColor,
						textSize = textSize,
						radius = options.radius or UI.tokens.radius.xs,
						border = false,
						paddingX = paddingX,
						textY = 0,
						enabled = enabled,
					}
				)

				button.Name = tostring(id)
				button.LayoutOrder = index
				button.BackgroundTransparency = 1

				local labelX = paddingX
				if icon then
					UI.image(
						button,
						icon,
						UDim2.new(0, paddingX, 0.5, -math.floor(iconSize / 2)),
						UDim2.fromOffset(iconSize, iconSize)
					)
					labelX = paddingX + iconSize + iconGap
				end

				label.Position = UDim2.fromOffset(labelX, 0)
				label.Size = UDim2.new(1, -(labelX + paddingX), 1, 0)
				label.TextXAlignment = Enum.TextXAlignment.Left
				label.TextYAlignment = Enum.TextYAlignment.Center

				local item = {
					id = id,
					button = button,
					label = label,
					record = record,
					config = config,
					enabled = enabled,
					hovered = false,
				}
				controller.items[id] = item

				button.MouseEnter:Connect(function()
					item.hovered = true
					paint(item, true)
				end)
				button.MouseLeave:Connect(function()
					item.hovered = false
					paint(item, false)
				end)
				button.MouseButton1Down:Connect(function()
					if item.enabled then
						button.BackgroundColor3 = colors.pressed
						button.BackgroundTransparency = 0
					end
				end)
				button.MouseButton1Up:Connect(function()
					paint(item, item.hovered)
				end)

				if config.tooltip then
					UI.tooltip(button, config.tooltip, config.tooltipOptions)
				end

				paint(item, false)
			end
		end
	end

	function controller:GetButton(name)
		local item = self.items[name]
		return item and item.button or nil
	end

	function controller:GetSelected()
		return self.selected
	end

	function controller:SetSelected(name, silent)
		self.selected = name
		repaintAll()
		if not silent and name ~= nil and options.onSelected and self.items[name] then
			options.onSelected(name, self.items[name].config)
		end
	end

	function controller:SetEnabled(name, enabled)
		local item = self.items[name]
		if not item then
			return false
		end
		item.enabled = enabled == true
		item.record.enabled = item.enabled
		item.button.Active = item.enabled
		paint(item, false)
		return true
	end

	function controller:SetScale(newScale)
		applyScale(newScale)

		layout.Padding = UDim.new(0, gap)

		if autoSize then
			if horizontal then
				container.Size = UDim2.fromOffset(0, rowHeight)
			else
				container.Size = UDim2.fromOffset(computeAutoWidth(self.buttonConfigs), 0)
			end
		end

		build()
	end

	function controller:GetScale()
		return scale
	end

	function controller:SetText(name, text)
		local item = self.items[name]
		if item then
			item.label.Text = tostring(text or "")
		end
	end

	function controller:SetButtons(newButtons)
		self.buttonConfigs = newButtons or {}

		if autoSize and not horizontal then
			container.Size = UDim2.fromOffset(computeAutoWidth(self.buttonConfigs), 0)
		end

		build()
	end

	function controller:Destroy()
		UI.forgetButtons(container)
		container:Destroy()
	end

	controller.buttonConfigs = buttons or {}
	build()

	return container, controller
end

function UI.tooltip(target, text, options)
	options = options or {}

	local colors = UI.tokens.color

	shared.tooltips = shared.tooltips or {}

	local existing = shared.tooltips[target]
	if existing then
		existing:SetText(text)
		return existing
	end

	if not shared.tooltipJanitor then
		shared.tooltipJanitor = RunService.Heartbeat:Connect(function()
			local registry = shared.tooltips
			if registry == nil then
				return
			end

			for tooltipTarget, tooltipController in pairs(registry) do
				if not UI.isAlive(tooltipTarget) then
					tooltipController:Destroy()
					registry[tooltipTarget] = nil
				end
			end
		end)
	end

	local hoverDelay = options.hoverDelay or 0.4

	local fadeSpeed = options.fadeSpeed or 14

	local riseDistance = options.riseDistance or 6

	local padding = options.padding or 6

	local gap = options.gap or 8

	local screenMargin = options.screenMargin or 4

	local placement = options.placement or "cursor"

	local offset = options.offset or Vector2.new(12, 20)

	local textSize = options.textSize or 12

	local maxWidth = options.maxWidth

	local backgroundTransparency = options.backgroundTransparency or 0

	local borderTransparency = options.borderTransparency or 0

	local textTransparency = options.textTransparency or 0

	local root = UI.RootOverlay()

	local tooltip = UI.create("Frame", {

		Name = "Tooltip",

		Position = UDim2.fromOffset(0, 0),

		Size = UDim2.fromOffset(1, 1),

		BackgroundColor3 = options.backgroundColor or colors.surface,

		BackgroundTransparency = 1,

		BorderSizePixel = 0,

		Active = false,

		InputSink = false,

		Selectable = false,

		Visible = false,

		ZIndex = options.zIndex or 100000,
	}, root)

	UI.corner(tooltip, options.cornerRadius or UI.tokens.radius.sm)

	local stroke = UI.stroke(tooltip, options.borderColor or colors.borderStrong, options.borderThickness or 1, 1)

	local label = UI.create("TextLabel", {

		Name = "Text",

		Text = tostring(text or ""),

		Position = UDim2.fromOffset(padding, padding),

		Size = UDim2.fromOffset(1, 1),

		BackgroundTransparency = 1,

		BorderSizePixel = 0,

		TextSize = textSize,

		TextColor3 = options.textColor or colors.text,

		TextTransparency = 1,

		TextWrapped = maxWidth ~= nil,

		ZIndex = (options.zIndex or 100000) + 1,
	}, tooltip)

	local state = {

		hovered = false,

		hoverTime = 0,

		alpha = 0,

		anchorMouse = Vector2.new(0, 0),

		mouse = Vector2.new(0, 0),

		destroyed = false,
	}

	local controller = {}

	local function updateSize()
		local bounds = label.TextBounds

		if not bounds then
			return tooltip.AbsoluteSize.X, tooltip.AbsoluteSize.Y
		end

		local contentWidth = math.max(bounds.X, 1)

		local contentHeight = math.max(bounds.Y, textSize)

		if maxWidth then
			contentWidth = math.min(contentWidth, maxWidth)

			label.Size = UDim2.fromOffset(maxWidth, math.max(contentHeight, textSize))

			contentWidth = maxWidth
		else
			label.Size = UDim2.fromOffset(contentWidth, contentHeight)
		end

		local width = contentWidth + padding * 2

		local height = contentHeight + padding * 2

		tooltip.Size = UDim2.fromOffset(width, height)

		return width, height
	end

	local function calculatePosition(width, height)
		local targetPosition = target.AbsolutePosition

		local targetSize = target.AbsoluteSize

		local x
		local y

		if placement == "cursor" then
			local anchor = options.followCursor and state.mouse or state.anchorMouse

			x = anchor.X + offset.X

			y = anchor.Y + offset.Y
		elseif placement == "above" then
			x = targetPosition.X + (targetSize.X - width) / 2

			y = targetPosition.Y - height - gap
		elseif placement == "below" then
			x = targetPosition.X + (targetSize.X - width) / 2

			y = targetPosition.Y + targetSize.Y + gap
		elseif placement == "left" then
			x = targetPosition.X - width - gap

			y = targetPosition.Y + (targetSize.Y - height) / 2
		else
			x = targetPosition.X + targetSize.X + gap

			y = targetPosition.Y + (targetSize.Y - height) / 2
		end

		local rise = (1 - state.alpha) * riseDistance

		if placement == "left" then
			x -= rise
		elseif placement == "right" then
			x += rise
		else
			y -= rise
		end

		local screenSize = root.AbsoluteSize

		if screenSize then
			x = math.clamp(x, screenMargin, math.max(screenMargin, screenSize.X - width - screenMargin))

			y = math.clamp(y, screenMargin, math.max(screenMargin, screenSize.Y - height - screenMargin))
		end

		return x, y
	end

	local function updateTransparency()
		tooltip.BackgroundTransparency = 1 - state.alpha * (1 - backgroundTransparency)

		stroke.Transparency = 1 - state.alpha * (1 - borderTransparency)

		label.TextTransparency = 1 - state.alpha * (1 - textTransparency)
	end

	local enterConnection = target.MouseEnter:Connect(function(x, y)
		state.hovered = true

		state.hoverTime = 0

		state.anchorMouse = Vector2.new(x, y)

		state.mouse = state.anchorMouse
	end)

	local leaveConnection = target.MouseLeave:Connect(function()
		state.hovered = false

		state.hoverTime = 0
	end)

	local moveConnection = target.MouseMoved:Connect(function(x, y)
		state.mouse = Vector2.new(x, y)
	end)

	local heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		if state.destroyed then
			return
		end

		if state.hovered then
			state.hoverTime += dt
		else
			state.hoverTime = 0
		end

		local targetAlpha = state.hovered and state.hoverTime >= hoverDelay and 1 or 0

		state.alpha = tooltipSmoothTowards(state.alpha, targetAlpha, fadeSpeed, dt)

		if math.abs(state.alpha - targetAlpha) < 0.01 then
			state.alpha = targetAlpha
		end

		if state.alpha <= 0.001 then
			tooltip.Visible = false

			return
		end

		tooltip.Visible = true

		local width, height = updateSize()

		local x, y = calculatePosition(width, height)

		tooltip.Position = UDim2.fromOffset(x, y)

		updateTransparency()
	end)

	function controller:SetText(newText)
		label.Text = tostring(newText or "")
	end

	function controller:SetPlacement(newPlacement)
		placement = newPlacement or "cursor"
	end

	function controller:Show()
		state.hovered = true

		state.hoverTime = hoverDelay
	end

	function controller:Hide()
		state.hovered = false

		state.hoverTime = 0
	end

	function controller:Destroy()
		if state.destroyed then
			return
		end

		state.destroyed = true

		if shared.tooltips and shared.tooltips[target] == controller then
			shared.tooltips[target] = nil
		end

		enterConnection:Disconnect()

		leaveConnection:Disconnect()

		moveConnection:Disconnect()

		heartbeatConnection:Disconnect()

		tooltip:Destroy()
	end

	controller.frame = tooltip
	controller.label = label
	controller.target = target

	shared.tooltips[target] = controller

	return controller
end

function UI.shared()
	return shared
end

return UI

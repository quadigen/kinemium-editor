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
	reduceMotion = false,

	themeObjects = setmetatable({}, { __mode = "k" }),
	themeBindings = setmetatable({}, { __mode = "k" }),
	themeFontFaces = setmetatable({}, { __mode = "k" }),
	themes = {},
	themeOrder = {},
	themeListeners = {},
	themeName = "Dark",
	trackedRoots = setmetatable({}, { __mode = "k" }),
	focusInputs = setmetatable({}, { __mode = "k" }),
	focusInputConnection = nil,
}
local THEME_ANIMATION_DURATION = 0.24
local EMPTY_MAP = {}

local function tooltipLerp(a, b, t)
	return a + (b - a) * t
end

local function tooltipSmoothTowards(current, target, speed, dt)
	if shared.reduceMotion then
		return target
	end
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

		local animate = THEME_ANIMATION_DURATION > 0 and not shared.reduceMotion and mapsHaveChanges(maps) and next(shared.themeObjects) ~= nil

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

local componentModules = {
	require("./Components/corner"),
	require("./Components/backdrop"),
	require("./Components/stroke"),
	require("./Components/frame"),
	require("./Components/prompt"),
	require("./Components/range_slider"),
	require("./Components/point2d"),
	require("./Components/label"),
	require("./Components/image"),
	require("./Components/property"),
	require("./Components/toast"),
	require("./Components/menu_bar"),
	require("./Components/button"),
	require("./Components/icon_button"),
	require("./Components/graph"),
	require("./Components/flamegraph"),
	require("./Components/color_picker"),
	require("./Components/separator"),
	require("./Components/group"),
	require("./Components/tab"),
	require("./Components/tree"),
	require("./Components/window"),
	require("./Components/input"),
	require("./Components/dropdown"),
	require("./Components/checkbox"),
	require("./Components/radio"),
	require("./Components/radio_group"),
	require("./Components/switch"),
	require("./Components/slider"),
	require("./Components/progress_bar"),
	require("./Components/section_header"),
	require("./Components/badge"),
	require("./Components/card"),
	require("./Components/root"),
	require("./Components/context_menu"),
	require("./Components/widget_overlay"),
	require("./Components/context_menu_overlay"),
	require("./Components/root_overlay"),
	require("./Components/topbar_button"),
	require("./Components/button_list"),
	require("./Components/tooltip"),
	require("./Components/collapsible"),
	require("./Components/tabs"),
}

local components = {
	UI = UI,
	shared = shared,
	tooltipSmoothTowards = tooltipSmoothTowards,
}

for _, install in ipairs(componentModules) do
	install(components)
end

function UI.shared()
	return shared
end

return UI

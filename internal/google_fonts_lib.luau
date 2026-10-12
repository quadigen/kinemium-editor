local UI = require("@internal/editor_ui")
local colors = UI.tokens.color
local HttpService = game:GetService("HttpService")

local CATALOG_URL = "https://fonts.google.com/metadata/fonts"
local CSS_URL = "https://fonts.googleapis.com/css2?family="

local CSS_USER_AGENT =
	"Mozilla/5.0 (Linux; U; Android 2.2; en-us) AppleWebKit/533.1 (KHTML, like Gecko) Version/4.0 Mobile Safari/533.1"
local CATALOG_USER_AGENT = "Mozilla/5.0"

local ROW_HEIGHT = 28
local MAX_ROWS = 100
local PAD = 8
local PREVIEW_HEIGHT = 100

--------------------------------------------------------------------------------
-- Networking
--------------------------------------------------------------------------------

local function Get(url, userAgent)
	local response = HttpService:RequestAsync({
		Url = url,
		Method = "GET",
		Headers = {
			["User-Agent"] = userAgent,
		},
	})

	if not response.Success then
		error(`HTTP {response.StatusCode} for {url}`)
	end

	return response.Body
end

local function GetAllFonts()
	local body = Get(CATALOG_URL, CATALOG_USER_AGENT)

	-- The endpoint prefixes the JSON with an anti-XSSI line: )]}'
	body = body:gsub("^%s*%)%]%}'[^\n]*\n", "")
	local catalog = HttpService:JSONDecode(body)

	local fonts = {}
	local seen = {}

	for _, font in ipairs(catalog.familyMetadataList or {}) do
		local family = font.family

		if family and not seen[family] then
			seen[family] = true
			table.insert(fonts, {
				family = family,
				category = font.category or "",
			})
		end
	end

	table.sort(fonts, function(a, b)
		return a.family < b.family
	end)

	return fonts
end

local function UrlEncode(text)
	text = text:gsub("[^%w%s%-_%.~]", function(char)
		return string.format("%%%02X", string.byte(char))
	end)
	return (text:gsub("%s", "+"))
end

local function ResolveFontUrl(family)
	local css = Get(CSS_URL .. UrlEncode(family), CSS_USER_AGENT)
	local url = css:match("url%((https://[^%)]+)%)")

	if not url then
		error(`no font file found for {family}`)
	end

	return url
end

local faces = {} -- family -> Font
local pending = {} -- family -> true while a download is running

local function LoadFace(family)
	if faces[family] then
		return faces[family]
	end

	local url = ResolveFontUrl(family)
	local bytes = Get(url, CSS_USER_AGENT)

	if #bytes == 0 then
		error(`empty font download for {family}`)
	end

	local face = Font.fromMemory(bytes)
	faces[family] = face
	return face
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "Fonts"
gui.RenderOnTop = true
gui.Parent = game.CoreGui

local panel, content =
	UI.window("Fonts", UDim2.fromOffset(120, 120), UDim2.fromOffset(320, 480), "Fonts Library (Google)", {
		closable = true,
	})

content.BackgroundTransparency = 1
panel.Visible = true
panel.BackgroundTransparency = 0.5
panel.ClipsDescendants = true
panel.Parent = gui

UI.backdrop(panel, 15, Color3.new(0, 0, 0))

local inputHeight = UI.metrics.inputHeight
local listTop = PAD + inputHeight + 6

local search = UI.input(
	content,
	"Search fonts or category...",
	UDim2.fromOffset(PAD, PAD),
	UDim2.new(1, -PAD * 2, 0, inputHeight),
	{ textSize = UI.tokens.type.body }
)

local scroller = UI.create("ScrollingFrame", {
	Name = "FontList",
	Position = UDim2.fromOffset(PAD, listTop),
	Size = UDim2.new(1, -PAD * 2, 1, -(listTop + 6 + PREVIEW_HEIGHT + PAD)),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.new(1, 0, 0, 0),
	ScrollBarThickness = 5,
	ScrollBarImageColor3 = colors.subtext,
	ScrollBarImageTransparency = 0.4,
	ScrollBarAutoHide = true,
	ClipsDescendants = true,
}, content)

local previewCard = UI.card(
	content,
	UDim2.new(0, PAD, 1, -(PREVIEW_HEIGHT + PAD)),
	UDim2.new(1, -PAD * 2, 0, PREVIEW_HEIGHT),
	{ color = colors.surface }
)
previewCard.BackgroundTransparency = 0.5

local preview = UI.label(
	previewCard,
	"The quick brown fox jumps over the lazy dog 0123456789",
	UDim2.fromOffset(8, 6),
	UDim2.new(1, -16, 1, -30),
	22,
	colors.text
)
preview.TextWrapped = true
preview.TextXAlignment = Enum.TextXAlignment.Left
preview.TextYAlignment = Enum.TextYAlignment.Top

local status = UI.label(
	previewCard,
	"Loading catalog...",
	UDim2.new(0, 8, 1, -22),
	UDim2.new(1, -16, 0, 18),
	UI.tokens.type.small,
	colors.muted
)
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Center

--------------------------------------------------------------------------------
-- List
--------------------------------------------------------------------------------

local allFonts = {}
local rows = {} -- family -> { family, button, label, record, hovered }
local selected = nil

local function SetStatus(text)
	status.Text = text
end

local function PaintRow(row)
	local isSelected = selected == row.family

	UI.setButtonState(row.record, isSelected and "selected" or "default")

	row.button.BackgroundTransparency = (isSelected or row.hovered) and 0 or 1

	if row.hovered then
		row.button.BackgroundColor3 = row.record.hoverColor
	end

	row.label.TextColor3 = isSelected and colors.text or colors.subtext
end

local function ApplyFace(family, face)
	local row = rows[family]

	if row then
		row.label.FontFace = face
	end
end

local function Select(family)
	selected = family

	for _, row in pairs(rows) do
		PaintRow(row)
	end

	if faces[family] then
		preview.FontFace = faces[family]
		SetStatus(family)
		return
	end

	if pending[family] then
		SetStatus(`Downloading {family}...`)
		return
	end

	pending[family] = true
	SetStatus(`Downloading {family}...`)

	task.spawn(function()
		local ok, result = pcall(LoadFace, family)
		pending[family] = nil

		if ok then
			ApplyFace(family, result)
		end

		-- The user may have clicked something else while this was in flight.
		if selected ~= family then
			return
		end

		if ok then
			preview.FontFace = result
			SetStatus(family)
		else
			warn(`Font {family} failed: {result}`)
			SetStatus(`Could not load {family}`)
		end
	end)
end

local function MakeFontItem(entry, order)
	local family = entry.family

	local button, label, record = UI.button(
		scroller,
		family,
		UDim2.fromOffset(0, (order - 1) * ROW_HEIGHT),
		UDim2.new(1, 0, 0, ROW_HEIGHT),
		function()
			Select(family)
		end,
		{
			color = colors.panel,
			hoverColor = colors.hover,
			pressedColor = colors.pressed,
			textColor = colors.subtext,
			textSize = UI.tokens.type.title,
			radius = 0,
			border = false,
			textY = 0,
			hoveringEnabled = false,
		}
	)

	button.Name = family
	button.BackgroundTransparency = 1

	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center

	local row = {
		family = family,
		button = button,
		label = label,
		record = record,
		hovered = false,
	}

	rows[family] = row

	-- Rows whose font is already downloaded show up in their own face.
	if faces[family] then
		label.FontFace = faces[family]
	end

	button.MouseEnter:Connect(function()
		row.hovered = true
		PaintRow(row)
	end)

	button.MouseLeave:Connect(function()
		row.hovered = false
		PaintRow(row)
	end)

	PaintRow(row)
end

local function Rebuild()
	UI.clear(scroller)
	table.clear(rows)

	local query = string.lower(search.Text)
	local matches = 0
	local shown = 0

	for _, entry in ipairs(allFonts) do
		local hit = query == ""
			or string.find(string.lower(entry.family), query, 1, true) ~= nil
			or string.find(string.lower(entry.category), query, 1, true) ~= nil

		if hit then
			matches += 1

			if shown < MAX_ROWS then
				shown += 1
				MakeFontItem(entry, shown)
			end
		end
	end

	scroller.CanvasSize = UDim2.new(1, 0, 0, shown * ROW_HEIGHT)
	scroller.CanvasPosition = Vector2.new(0, 0)

	if matches == 0 then
		SetStatus("No fonts match")
	elseif matches > shown then
		SetStatus(`Showing {shown} of {matches} fonts, search to narrow`)
	elseif selected == nil then
		SetStatus(`{matches} fonts`)
	end
end

search.TextChanged:Connect(Rebuild)

--------------------------------------------------------------------------------
-- Startup
--------------------------------------------------------------------------------

task.spawn(function()
	local success, result = pcall(GetAllFonts)

	if not success then
		warn(result)
		SetStatus("Could not load the font catalog")
		return
	end

	print(`Loaded {#result} font families`)
	allFonts = result
	Rebuild()
end)

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
local TEXT_COLOR = colors.text or Color3.new(1, 1, 1)
local MUTED_COLOR = colors.textMuted or Color3.fromRGB(170, 170, 170)

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

local gui = Instance.new("ScreenGui")
gui.Name = "Fonts"
gui.RenderOnTop = true
gui.Parent = game.CoreGui

local panel, content = UI.window(
	"Fonts Library (Google)",
	UDim2.fromOffset(120, 120),
	UDim2.fromOffset(320, 480),
	"Fonts Library (Google)",
	{
		closable = true,
	}
)

content.BackgroundTransparency = 1
panel.Visible = true
panel.BackgroundTransparency = 0.5
panel.ClipsDescendants = true
panel.Parent = gui

UI.backdrop(panel, 15, Color3.new(0, 0, 0))

local search = Instance.new("TextBox")
search.Position = UDim2.fromOffset(8, 8)
search.Size = UDim2.new(1, -16, 0, 28)
search.BackgroundTransparency = 0.8
search.TextColor3 = TEXT_COLOR
search.PlaceholderText = "Search fonts..."
search.Text = ""
search.TextSize = 14
search.ClearTextOnFocus = false
search.Parent = content

local scroller = Instance.new("ScrollingFrame")
scroller.BackgroundTransparency = 1
scroller.Position = UDim2.fromOffset(8, 44)
scroller.Size = UDim2.new(1, -16, 1, -44 - 120)
scroller.Parent = content

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Vertical
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Wraps = true
layout.Parent = scroller

local previewBox = Instance.new("Frame")
previewBox.BackgroundTransparency = 0.85
previewBox.Position = UDim2.new(0, 8, 1, -112)
previewBox.Size = UDim2.new(1, -16, 0, 104)
previewBox.Parent = content

local preview = Instance.new("TextLabel")
preview.BackgroundTransparency = 1
preview.Size = UDim2.new(1, -8, 1, -20)
preview.Position = UDim2.fromOffset(4, 2)
preview.TextColor3 = TEXT_COLOR
preview.TextSize = 22
preview.TextWrapped = true
preview.TextXAlignment = Enum.TextXAlignment.Left
preview.TextYAlignment = Enum.TextYAlignment.Top
preview.Text = "The quick brown fox jumps over the lazy dog 0123456789"
preview.Parent = previewBox

local status = Instance.new("TextLabel")
status.BackgroundTransparency = 1
status.Position = UDim2.new(0, 4, 1, -18)
status.Size = UDim2.new(1, -8, 0, 16)
status.TextColor3 = MUTED_COLOR
status.TextSize = 12
status.TextXAlignment = Enum.TextXAlignment.Left
status.Text = "Loading catalog..."
status.Parent = previewBox

local allFonts = {}
local rows = {}
local selected = nil

local function SetStatus(text)
	status.Text = text
end

local function Select(family)
	selected = family

	for name, row in pairs(rows) do
		row.BackgroundTransparency = if name == family then 0.6 else 0.95
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
	local row = Instance.new("TextButton")
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.LayoutOrder = order
	row.BackgroundTransparency = 0.95
	row.Text = entry.family
	row.TextColor3 = TEXT_COLOR
	row.TextSize = 14
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.Parent = scroller

	row.MouseButton1Click:Connect(function()
		Select(entry.family)
	end)

	rows[entry.family] = row
end

local function Rebuild()
	for _, row in pairs(rows) do
		row:Destroy()
	end
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

	scroller.CanvasSize = UDim2.fromOffset(0, shown * ROW_HEIGHT)
	scroller.CanvasPosition = Vector2.new(0, 0)

	if selected and rows[selected] then
		rows[selected].BackgroundTransparency = 0.6
	end

	if matches > shown then
		SetStatus(`Showing {shown} of {matches} fonts, search to narrow`)
	elseif selected == nil then
		SetStatus(`{matches} fonts`)
	end
end

search:GetPropertyChangedSignal("Text"):Connect(Rebuild)

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

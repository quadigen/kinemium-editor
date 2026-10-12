local UI = require("@internal/editor_ui")
local colors = UI.tokens.color
local HttpService = game:GetService("HttpService")

local API = "https://api.iconify.design"

local COLUMNS = 6
local TILE = 52
local GAP = 6
local ICON_SIZE = 28
local ICON_RES = 64 -- height requested from the SVG endpoint
local PAGE = 64 -- Iconify's default and a valid search limit (min 32, max 999)
local MAX_LIMIT = 384
local DEBOUNCE = 0.35
local PAD = 8
local CARD_HEIGHT = 112
local SET_WIDTH = 130

--------------------------------------------------------------------------------
-- Iconify API
--------------------------------------------------------------------------------

local function ColorToHex(color)
	return string.format(
		"%02x%02x%02x",
		math.floor(color.R * 255 + 0.5),
		math.floor(color.G * 255 + 0.5),
		math.floor(color.B * 255 + 0.5)
	)
end

local iconColor = ColorToHex(colors.text)
local sets = {} -- prefix -> icon set info (name, author, license, ...)

local function GetJSON(url)
	local response = HttpService:RequestAsync({
		Url = url,
		Method = "GET",
	})

	if not response.Success then
		error(`HTTP {response.StatusCode} for {url}`)
	end

	return HttpService:JSONDecode(response.Body)
end

local function SearchIcons(query, prefix, limit)
	local url = `{API}/search?query={HttpService:UrlEncode(query)}&limit={math.floor(limit)}`

	if prefix ~= "" then
		url ..= `&prefix={HttpService:UrlEncode(prefix)}`
	end

	return GetJSON(url)
end

local function SplitName(name)
	return string.match(name, "^([^:]+):(.+)$")
end

-- Icons are rendered by the API itself: /{prefix}/{icon}.svg
local function IconUrl(name, height)
	local prefix, icon = SplitName(name)

	return `{API}/{prefix}/{icon}.svg?color=%23{iconColor}&height={height}`
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "Icons"
gui.RenderOnTop = true
gui.Parent = game.CoreGui

local panel, content =
	UI.window("Icons", UDim2.fromOffset(120, 120), UDim2.fromOffset(380, 540), "Icon Library (Iconify)", {
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
	"Search icons...",
	UDim2.fromOffset(PAD, PAD),
	UDim2.new(1, -(PAD * 2 + SET_WIDTH + 6), 0, inputHeight),
	{ textSize = UI.tokens.type.body }
)

-- Icon set filter. The menu is anchored under the button, with its own search box.
local setButton
local setLabel
local setController
local Search -- assigned further down; the dropdown callback needs it in scope

setButton, setLabel, setController = UI.dropdown(
	content,
	"",
	UDim2.new(1, -(PAD + SET_WIDTH), 0, PAD),
	UDim2.fromOffset(SET_WIDTH, inputHeight),
	"builtin://global-icons/chevron-down.svg",
	{
		items = { { label = "All icon sets", value = "" } },
		menuWidth = 240,
		maxVisibleItems = 10,
		textSize = UI.tokens.type.small,
		searchPlaceholder = "Filter icon sets...",
		format = function(value)
			if value == "" then
				return "All icon sets"
			end

			return sets[value] and sets[value].name or value
		end,
		menuPosition = function()
			local position, size = setButton.AbsolutePosition, setButton.AbsoluteSize

			return UDim2.fromOffset(math.max(position.X + size.X - 240, 4), position.Y + size.Y + 2)
		end,
		onChanged = function(value)
			Search(false, value)
		end,
	}
)

local scroller = UI.create("ScrollingFrame", {
	Name = "IconList",
	Position = UDim2.fromOffset(PAD, listTop),
	Size = UDim2.new(1, -PAD * 2, 1, -(listTop + 20 + CARD_HEIGHT + PAD)),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.new(1, 0, 0, 0),
	ScrollBarThickness = 5,
	ScrollBarImageColor3 = colors.subtext,
	ScrollBarImageTransparency = 0.4,
	ScrollBarAutoHide = true,
	ClipsDescendants = true,
}, content)

local status = UI.label(
	content,
	"Type to search icons from 200+ icon sets",
	UDim2.new(0, PAD, 1, -(CARD_HEIGHT + PAD + 18)),
	UDim2.new(1, -PAD * 2, 0, 16),
	UI.tokens.type.small,
	colors.muted
)
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Center

-- Detail card: large preview, name, set/license, URL and colour.
local card = UI.card(
	content,
	UDim2.new(0, PAD, 1, -(CARD_HEIGHT + PAD)),
	UDim2.new(1, -PAD * 2, 0, CARD_HEIGHT),
	{ color = colors.surface }
)
card.BackgroundTransparency = 0.5

local previewFrame =
	UI.frame(card, UDim2.fromOffset(8, 8), UDim2.fromOffset(80, 80), colors.surfaceAlt, UI.tokens.radius.md)

local previewImage = UI.image(previewFrame, "", UDim2.fromOffset(8, 8), UDim2.fromOffset(64, 64))

local nameLabel =
	UI.label(card, "", UDim2.fromOffset(96, 8), UDim2.new(1, -104, 0, 18), UI.tokens.type.title, colors.text)
nameLabel.TextXAlignment = Enum.TextXAlignment.Left

local metaLabel =
	UI.label(card, "", UDim2.fromOffset(96, 28), UDim2.new(1, -104, 0, 16), UI.tokens.type.caption, colors.muted)
metaLabel.TextXAlignment = Enum.TextXAlignment.Left

local urlInput = UI.input(
	card,
	"Select an icon to get its SVG URL",
	UDim2.fromOffset(96, 50),
	UDim2.new(1, -104, 0, 22),
	{ textSize = UI.tokens.type.caption, selectAllOnFocus = true }
)

local colorLabel =
	UI.label(card, "Color", UDim2.fromOffset(96, 80), UDim2.fromOffset(40, 22), UI.tokens.type.small, colors.subtext)
colorLabel.TextXAlignment = Enum.TextXAlignment.Left

local colorInput = UI.input(card, "#RRGGBB", UDim2.fromOffset(138, 80), UDim2.fromOffset(84, 22), {
	text = "#" .. iconColor,
	maxLength = 7,
	textSize = UI.tokens.type.small,
	selectAllOnFocus = true,
})

--------------------------------------------------------------------------------
-- Results
--------------------------------------------------------------------------------

local icons = {} -- "prefix:name" strings from the last search
local tiles = {} -- name -> { button, record, image }
local built = 0 -- how many entries of `icons` already have a tile
local hasMore = false
local moreButton = nil
local selected = nil

local currentSet = ""
local limit = PAGE
local debounceId = 0
local requestId = 0

local function SetStatus(text)
	status.Text = text
end

local function PaintTile(name, tile)
	local isSelected = name == selected

	UI.setButtonState(tile.record, isSelected and "selected" or "default")
	tile.button.BackgroundTransparency = isSelected and 0 or 0.5
end

local function Select(name)
	selected = name

	for tileName, tile in pairs(tiles) do
		PaintTile(tileName, tile)
	end

	local url = IconUrl(name, ICON_RES)
	local prefix = SplitName(name)
	local info = sets[prefix]
	local parts = {}

	if info then
		table.insert(parts, info.name or prefix)

		if info.license and info.license.title then
			table.insert(parts, info.license.title)
		end

		if info.author and info.author.name then
			table.insert(parts, info.author.name)
		end
	else
		table.insert(parts, prefix)
	end

	previewImage.Image = url
	nameLabel.Text = name
	metaLabel.Text = table.concat(parts, "  •  ")
	urlInput.Text = url
end

local function MakeTile(name, index)
	local column = (index - 1) % COLUMNS
	local line = math.floor((index - 1) / COLUMNS)

	local button, _, record = UI.button(
		scroller,
		"",
		UDim2.fromOffset(column * (TILE + GAP), line * (TILE + GAP)),
		UDim2.fromOffset(TILE, TILE),
		function()
			Select(name)
		end,
		{
			color = colors.surface,
			hoverColor = colors.hover,
			pressedColor = colors.pressed,
			radius = UI.tokens.radius.md,
			border = false,
			bgTransparency = 0.5,
		}
	)

	button.Name = name

	local offset = math.floor(ICON_SIZE / 2)
	local image = UI.image(
		button,
		IconUrl(name, ICON_RES),
		UDim2.new(0.5, -offset, 0.5, -offset),
		UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
	)

	local tile = { button = button, record = record, image = image }
	tiles[name] = tile

	-- Hovering shows the name without changing the selection.
	button.MouseEnter:Connect(function()
		nameLabel.Text = name
	end)

	button.MouseLeave:Connect(function()
		nameLabel.Text = selected or ""
	end)

	PaintTile(name, tile)
end

local function ClearTiles()
	UI.clear(scroller)
	table.clear(tiles)

	built = 0
	moreButton = nil

	scroller.CanvasSize = UDim2.new(1, 0, 0, 0)
	scroller.CanvasPosition = Vector2.new(0, 0)
end

local function LayoutTiles()
	for index = built + 1, #icons do
		MakeTile(icons[index], index)
	end

	built = #icons

	if moreButton then
		UI.forgetButtons(moreButton)
		moreButton:Destroy()
		moreButton = nil
	end

	local height = math.ceil(built / COLUMNS) * (TILE + GAP)

	if hasMore then
		moreButton = UI.button(
			scroller,
			"Load more",
			UDim2.fromOffset(0, height),
			UDim2.fromOffset(COLUMNS * (TILE + GAP) - GAP, 26),
			function()
				limit = math.min(limit + PAGE, MAX_LIMIT)
				SetStatus("Loading more...")
				Search(true, currentSet)
			end,
			{
				color = colors.panelRaised,
				hoverColor = colors.hover,
				pressedColor = colors.pressed,
				textColor = colors.subtext,
				textSize = UI.tokens.type.small,
				radius = UI.tokens.radius.sm,
				border = false,
			}
		)

		height += 32
	end

	scroller.CanvasSize = UDim2.new(1, 0, 0, height)
end

-- append = true keeps the tiles already built and only adds the new ones.
Search = function(append, prefix)
	currentSet = prefix or currentSet

	if not append then
		limit = PAGE
	end

	local query = string.match(search.Text, "^%s*(.-)%s*$")

	requestId += 1
	local thisRequest = requestId

	if query == "" then
		icons = {}
		hasMore = false
		ClearTiles()
		SetStatus("Type to search icons from 200+ icon sets")
		return
	end

	SetStatus("Searching...")

	task.spawn(function()
		local ok, result = pcall(SearchIcons, query, currentSet, limit)

		-- A newer search has started since this one was sent.
		if thisRequest ~= requestId then
			return
		end

		if not ok then
			warn(`Icon search failed: {result}`)
			SetStatus("Search failed")
			return
		end

		for prefixName, info in pairs(result.collections or {}) do
			sets[prefixName] = info
		end

		icons = result.icons or {}
		hasMore = #icons >= limit and limit < MAX_LIMIT

		if not append then
			ClearTiles()
		end

		LayoutTiles()

		if selected and tiles[selected] then
			PaintTile(selected, tiles[selected])
		end

		if #icons == 0 then
			SetStatus("No icons found")
		else
			SetStatus(`{#icons} icons{hasMore and "+" or ""}`)
		end
	end)
end

-- Changing the colour only re-points the images; no new search is needed.
local function RefreshImages()
	for name, tile in pairs(tiles) do
		tile.image.Image = IconUrl(name, ICON_RES)
	end

	if selected then
		local url = IconUrl(selected, ICON_RES)
		previewImage.Image = url
		urlInput.Text = url
	end
end

colorInput.FocusLost:Connect(function()
	local raw = string.gsub(colorInput.Text, "#", "")

	if #raw == 6 and string.match(raw, "^%x+$") then
		iconColor = string.lower(raw)
		colorInput.Text = "#" .. iconColor
		RefreshImages()
	else
		colorInput.Text = "#" .. iconColor
	end
end)

-- Wait for typing to pause, so a search isn't sent for every keystroke.
search.TextChanged:Connect(function()
	debounceId += 1
	local thisDebounce = debounceId

	task.delay(DEBOUNCE, function()
		if thisDebounce == debounceId then
			Search(false, currentSet)
		end
	end)
end)

--------------------------------------------------------------------------------
-- Startup: load the icon set list for the filter dropdown
--------------------------------------------------------------------------------

task.spawn(function()
	local ok, result = pcall(GetJSON, `{API}/collections`)

	if not ok then
		warn(`Could not load icon sets: {result}`)
		return
	end

	local items = {}

	for prefix, info in pairs(result) do
		sets[prefix] = info
		table.insert(items, { label = info.name or prefix, value = prefix })
	end

	table.sort(items, function(a, b)
		return string.lower(a.label) < string.lower(b.label)
	end)

	table.insert(items, 1, { label = "All icon sets", value = "" })
	setController:SetItems(items)

	print(`Loaded {#items - 1} icon sets`)
end)

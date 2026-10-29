if IsPlaytest then
	return
end

local UI = require("@internal/editor_ui")
local colors = UI.tokens.color
local HttpService = game:GetService("HttpService")

local API = "https://api.iconify.design"
local PREFIX = "lucide"

local SVG_PREFIX = "data:image/svg+xml;utf8,"

local COLUMNS = 6
local TILE = 52
local GAP = 6
local ICON_SIZE = 28
local ICON_RES = 64
local PREVIEW_RES = 128
local PAGE = 64
local MAX_LIMIT = 384
local FETCH_CHUNK = 48
local DEBOUNCE = 0.35
local PAD = 8
local CARD_HEIGHT = 112

local function ColorToHex(color)
	return string.format(
		"%02x%02x%02x",
		math.floor(color.R * 255 + 0.5),
		math.floor(color.G * 255 + 0.5),
		math.floor(color.B * 255 + 0.5)
	)
end

local iconColor = ColorToHex(colors.text)
local setInfo = { name = "Lucide", license = "ISC", author = "Lucide Contributors" }

local entries = {}

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

local function SearchIcons(query, limit)
	local url = `{API}/search?query={HttpService:UrlEncode(query)}&limit={math.floor(limit)}&prefix={PREFIX}`

	return GetJSON(url)
end

local function LoadEntries(names)
	local missing = {}

	for _, name in ipairs(names) do
		if not entries[name] then
			table.insert(missing, name)
		end
	end

	for start = 1, #missing, FETCH_CHUNK do
		local chunk = table.move(missing, start, math.min(start + FETCH_CHUNK - 1, #missing), 1, {})
		local data = GetJSON(`{API}/{PREFIX}.json?icons={table.concat(chunk, ",")}`)

		local defaultWidth = data.width or 24
		local defaultHeight = data.height or 24

		for _, name in ipairs(chunk) do
			local icon = data.icons and data.icons[name]

			if not icon and data.aliases and data.aliases[name] then
				icon = data.icons and data.icons[data.aliases[name].parent]
			end

			if icon and icon.body then
				entries[name] = {
					body = icon.body,
					width = icon.width or defaultWidth,
					height = icon.height or defaultHeight,
				}
			end
		end
	end
end

local function SvgFor(name, size)
	local entry = entries[name]
	local body = string.gsub(entry.body, "currentColor", "#" .. iconColor)

	return string.format(
		'<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">%s</svg>',
		size,
		size,
		entry.width,
		entry.height,
		body
	)
end

local function ImageFor(name, size)
	return SVG_PREFIX .. SvgFor(name, size)
end

local gui = UI.widgetOverlay()

local panel, content =
	UI.window("Lucide", UDim2.fromOffset(120, 120), UDim2.fromOffset(380, 540), "Icon Library (Lucide)", {
		closable = true,
	})

content.BackgroundTransparency = 1
panel.Visible = false
panel.BackgroundTransparency = 0.5
panel.ClipsDescendants = true
panel.Parent = gui

UI.backdrop(panel, 15, Color3.new(0, 0, 0))

local inputHeight = UI.metrics.inputHeight
local listTop = PAD + inputHeight + 6

local search = UI.input(
	content,
	"Search Lucide icons...",
	UDim2.fromOffset(PAD, PAD),
	UDim2.new(1, -PAD * 2, 0, inputHeight),
	{ textSize = UI.tokens.type.body }
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
	"Type to search Lucide icons",
	UDim2.new(0, PAD, 1, -(CARD_HEIGHT + PAD + 18)),
	UDim2.new(1, -PAD * 2, 0, 16),
	UI.tokens.type.small,
	colors.muted
)
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Center

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

local svgInput = UI.input(
	card,
	"Select an icon to get its SVG",
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

local icons = {}
local tiles = {}
local built = 0
local hasMore = false
local moreButton = nil
local selected = nil

local limit = PAGE
local debounceId = 0
local requestId = 0

local function SetStatus(text)
	status.Text = text
end

local function MetaText()
	local parts = { setInfo.name }

	if setInfo.license then
		table.insert(parts, setInfo.license)
	end

	if setInfo.author then
		table.insert(parts, setInfo.author)
	end

	return table.concat(parts, "    ")
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

	previewImage.Image = ImageFor(name, PREVIEW_RES)
	nameLabel.Text = name
	metaLabel.Text = MetaText()
	svgInput.Text = SvgFor(name, 24)
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

	local tooltip = UI.tooltip(button, name, {
		placement = "below",
		hoverDelay = 0.35,
	})

	button.Name = name

	local offset = math.floor(ICON_SIZE / 2)
	local image = UI.image(
		button,
		ImageFor(name, ICON_RES),
		UDim2.new(0.5, -offset, 0.5, -offset),
		UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
	)

	local tile = { button = button, record = record, image = image }
	tiles[name] = tile

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

local Search

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
				Search(true)
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

Search = function(append)
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
		SetStatus("Type to search Lucide icons")
		return
	end

	SetStatus("Searching...")

	task.spawn(function()
		local ok, result = pcall(function()
			local response = SearchIcons(query, limit)

			local names = {}

			for _, full in ipairs(response.icons or {}) do
				local name = string.match(full, "^[^:]+:(.+)$")

				if name then
					table.insert(names, name)
				end
			end

			LoadEntries(names)

			return { names = names, collections = response.collections }
		end)

		if thisRequest ~= requestId then
			return
		end

		if not ok then
			warn(`Icon search failed: {result}`)
			SetStatus("Search failed")
			return
		end

		local info = result.collections and result.collections[PREFIX]

		if info then
			setInfo.name = info.name or setInfo.name
			setInfo.license = info.license and info.license.title or setInfo.license
			setInfo.author = info.author and info.author.name or setInfo.author
		end

		icons = {}

		for _, name in ipairs(result.names) do
			if entries[name] then
				table.insert(icons, name)
			end
		end

		hasMore = #result.names >= limit and limit < MAX_LIMIT

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

local function RefreshImages()
	for name, tile in pairs(tiles) do
		tile.image.Image = ImageFor(name, ICON_RES)
	end

	if selected then
		previewImage.Image = ImageFor(selected, PREVIEW_RES)
		svgInput.Text = SvgFor(selected, 24)
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

search.TextChanged:Connect(function()
	debounceId += 1
	local thisDebounce = debounceId

	task.delay(DEBOUNCE, function()
		if thisDebounce == debounceId then
			Search(false)
		end
	end)
end)

return {
	Enable = function()
		panel.Visible = true
	end,

	Disable = function()
		panel.Visible = false
	end,

	Toggle = function()
		panel.Visible = not panel.Visible
	end,

	Refresh = function()
		UI.refreshWindow("Lucide")
		RefreshImages()
	end,

	IsVisible = function()
		return panel.Visible
	end,
}

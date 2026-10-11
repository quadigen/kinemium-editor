local UI = require("@internal/editor_ui")
local colors = UI.tokens.color

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

local HttpService = game:GetService("HttpService")

local URL = "https://fonts.google.com/metadata/fonts"

local function GetAllFonts()
	local response = HttpService:RequestAsync({
		Url = URL,
		Method = "GET",
		Headers = {
			["User-Agent"] = "Mozilla/5.0",
		},
	})

	if not response.Success then
		error(`Failed to fetch fonts: HTTP {response.StatusCode}`)
	end

	local body = response.Body:gsub("^%s*%)%]%}'[^\n]*\n", "")
	local catalog = HttpService:JSONDecode(body)

	local fonts = {}
	local seen = {}

	for _, font in ipairs(catalog.familyMetadataList or {}) do
		local family = font.family

		if family and not seen[family] then
			seen[family] = true
			table.insert(fonts, family)
		end
	end

	table.sort(fonts)

	return fonts
end

local success, result = pcall(GetAllFonts)

local scroller = Instance.new("ScrollingFrame")
scroller.BackgroundTransparency = 1
scroller.Size = UDim2.new(1, 0, 1, 0)
scroller.Parent = content

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.Parent = scroller

local function MakeFontItem(font)
	local frame = Instance.new("TextButton")
	frame.Size = UDim2.new(1, 0, 0, 30)
	frame.Text = font
	frame.BackgroundTransparency = 1
	frame.Parent = scroller
end

local i = 0

if success then
	print(`Loaded {#result} font families`)

	for _, family in pairs(result) do
		if i == 100 then
			break
		end
		i += 1
		MakeFontItem(family)
	end
else
	warn(result)
end

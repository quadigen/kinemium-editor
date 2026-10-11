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
panel.Visible = false
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

if success then
	print(`Loaded {#result} font families`)

	local json = HttpService:JSONEncode(result)
	print(json)
else
	warn(result)
end

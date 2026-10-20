if (IsServer or IsClient) or IsPlaytest then
	return nil
end
local UI = require("@internal/editor_ui")

local Packages = game:GetService("Packages")
local HttpService = game:GetService("HttpService")
local tokens = UI.tokens
local marketplaceLayoutMode = "List"

return function(page, windowControls, gui)
	local BUTTON_SIZE = 28
	local CONTROL_GAP = 6
	local marketplacePlugins = {}
	local marketplacePage = windowControls.pages.Marketplace

	local MARKETPLACE_MARGIN = tokens.space.lg
	local MARKETPLACE_CONTROLS_HEIGHT = 30
	local MARKETPLACE_SERVER_GAP = 8
	local MARKETPLACE_CONTROLS_TOTAL_HEIGHT = MARKETPLACE_CONTROLS_HEIGHT * 2 + MARKETPLACE_SERVER_GAP
	local MARKETPLACE_GAP = 10

	local marketplaceControlsY = MARKETPLACE_MARGIN
	local marketplaceControls = UI.frame(
		marketplacePage,
		UDim2.new(0, MARKETPLACE_MARGIN, 0, marketplaceControlsY),
		UDim2.new(1, -(MARKETPLACE_MARGIN * 2), 0, MARKETPLACE_CONTROLS_TOTAL_HEIGHT),
		tokens.color.surfaceAlt,
		0
	)

	marketplaceControls.BackgroundTransparency = 1
	marketplaceControls.Parent = marketplacePage

	local marketplaceSearch = UI.input(
		marketplaceControls,
		"Search packages...",
		UDim2.new(0, 0, 0, 0),
		UDim2.new(1, -(BUTTON_SIZE * 2 + CONTROL_GAP * 2), 0, BUTTON_SIZE),
		{
			text = "",
			maxLength = 64,
			selectAllOnFocus = true,
			focusColor = tokens.color.accent,
		}
	)

	local refreshMarketplace = UI.iconButton(
		marketplaceControls,
		"builtin://global-icons/refresh.svg",
		UDim2.new(1, -30, 0, 0),
		UDim2.fromOffset(30, 30),
		function() end,
		{
			bgTransparency = 0,
		}
	)

	local marketplaceServer = UI.input(
		marketplaceControls,
		"Marketplace server (e.g. https://opus.quadigen.com)",
		UDim2.new(0, 0, 0, MARKETPLACE_CONTROLS_HEIGHT + MARKETPLACE_SERVER_GAP),
		UDim2.new(1, 0, 0, MARKETPLACE_CONTROLS_HEIGHT),
		{
			text = Packages.MarketplaceServer,
			maxLength = 256,
			selectAllOnFocus = true,
			focusColor = tokens.color.accent,
		}
	)

	local marketplaceListY = marketplaceControlsY + MARKETPLACE_CONTROLS_TOTAL_HEIGHT + MARKETPLACE_GAP

	local marketplaceList = UI.frame(
		marketplacePage,
		UDim2.new(0, MARKETPLACE_MARGIN, 0, marketplaceListY),
		UDim2.new(1, -(MARKETPLACE_MARGIN * 2), 1, -(marketplaceListY + MARKETPLACE_MARGIN)),
		tokens.color.surfaceAlt,
		15
	)

	marketplaceList.ClipsDescendants = true
	marketplaceList.Parent = marketplacePage

	local marketplaceLayout = Instance.new("UIListLayout")
	marketplaceLayout.FillDirection = Enum.FillDirection.Horizontal
	marketplaceLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	marketplaceLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	marketplaceLayout.Wraps = true
	marketplaceLayout.MaxItemsPerLine = 4
	marketplaceLayout.Padding = UDim.new(0, 10)
	marketplaceLayout.LinePadding = UDim.new(0, 10)
	marketplaceLayout.PaddingLeft = UDim.new(0, 10)
	marketplaceLayout.PaddingRight = UDim.new(0, 10)
	marketplaceLayout.PaddingTop = UDim.new(0, 10)
	marketplaceLayout.PaddingBottom = UDim.new(0, 10)
	marketplaceLayout.SortOrder = Enum.SortOrder.LayoutOrder
	marketplaceLayout.Parent = marketplaceList

	local function updateMarketplaceLayout()
		if marketplaceLayoutMode == "Grid" then
			marketplaceLayout.FillDirection = Enum.FillDirection.Horizontal
			marketplaceLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
			marketplaceLayout.VerticalAlignment = Enum.VerticalAlignment.Top

			marketplaceLayout.Wraps = true
			marketplaceLayout.MaxItemsPerLine = 4
			marketplaceLayout.Padding = UDim.new(0, 10)
			marketplaceLayout.LinePadding = UDim.new(0, 10)
		else
			marketplaceLayout.FillDirection = Enum.FillDirection.Vertical
			marketplaceLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
			marketplaceLayout.VerticalAlignment = Enum.VerticalAlignment.Top

			marketplaceLayout.Wraps = false
			marketplaceLayout.MaxItemsPerLine = 1
			marketplaceLayout.Padding = UDim.new(0, 8)
			marketplaceLayout.LinePadding = UDim.new(0, 0)
		end
	end

	local marketplaceImageCache = {}

	local function firstValue(...)
		for _, value in ipairs({ ... }) do
			if value ~= nil and value ~= "" then
				return value
			end
		end

		return nil
	end

	local function stringList(value)
		local result = {}

		if type(value) ~= "table" then
			return result
		end

		for _, entry in ipairs(value) do
			if type(entry) == "string" then
				table.insert(result, entry)
			end
		end

		return result
	end

	local function packageEntries(response)
		if type(response) ~= "table" then
			return {}
		end

		if response[1] ~= nil then
			return response
		end

		for _, key in ipairs({ "packages", "results", "items", "entries", "data" }) do
			if type(response[key]) == "table" then
				return response[key]
			end
		end

		return {}
	end

	local function normalizePackage(entry)
		if type(entry) ~= "table" then
			return nil
		end

		if type(entry.package) == "table" then
			entry = entry.package
		elseif type(entry.Package) == "table" then
			entry = entry.Package
		end

		local manifest = entry.manifest or entry.Manifest or {}
		local assets = entry.assets or entry.Assets or {}

		local namespace = firstValue(
			entry.namespace,
			entry.Namespace,
			manifest.namespace,
			manifest.Namespace,
			entry.owner,
			entry.Owner
		)
		local name = firstValue(entry.name, entry.Name, manifest.name, manifest.Name, "Unknown Package")
		local version = firstValue(entry.version, entry.Version, manifest.version, manifest.Version, "?")
		local description = firstValue(
			entry.description,
			entry.Description,
			manifest.description,
			manifest.Description,
			"No description provided."
		)
		local packageType = firstValue(entry.type, entry.Type, manifest.type, manifest.Type, "package")
		local tags = stringList(firstValue(entry.tags, entry.Tags, manifest.tags, manifest.Tags))
		local icon = firstValue(
			entry.iconUrl,
			entry.icon_url,
			assets.iconUrl,
			assets.IconUrl,
			assets.icon_url,
			entry.icon,
			manifest.icon,
			manifest.Icon
		)
		local thumbnail = firstValue(
			entry.thumbnailUrl,
			entry.thumbnail_url,
			assets.thumbnailUrl,
			assets.ThumbnailUrl,
			assets.thumbnail_url,
			entry.thumbnail,
			manifest.thumbnail,
			manifest.Thumbnail
		)

		return {
			Slug = namespace and (namespace .. "/" .. name) or name,
			Namespace = namespace,
			Downloads = firstValue(entry.downloads, entry.DownloadCount, entry.download_count, 0),
			UpdatedAt = firstValue(
				entry.updatedAt,
				entry.updated_at,
				entry.publishedAt,
				entry.published_at,
				entry.createdAt,
				entry.created_at,
				""
			),
			Manifest = {
				Name = name,
				Version = version,
				Description = description,
				Author = namespace,
				Type = packageType,
				Keywords = tags,
			},
			Assets = {
				IconUrl = icon or "",
				ThumbnailUrl = thumbnail or "",
			},
		}
	end

	local function resolveAssetUrl(url)
		if type(url) ~= "string" or url == "" then
			return ""
		end

		if url:match("^https?://") then
			return url
		end

		if url:sub(1, 2) == "//" then
			return "https:" .. url
		end

		local server = Packages.MarketplaceServer

		if type(server) ~= "string" or server == "" then
			return url
		end

		return string.gsub(server, "/+$", "") .. "/" .. string.gsub(url, "^/+", "")
	end

	local function setCardImage(image, url)
		url = resolveAssetUrl(url)

		if url == "" then
			return
		end

		local cached = marketplaceImageCache[url]

		if cached then
			image.Image = cached

			return
		end

		local ok, content = pcall(function()
			return HttpService:GetImageBytes(url)
		end)

		if ok and content then
			marketplaceImageCache[url] = content
			image.Image = content
		end
	end

	local function marketplaceListCard(plugin)
		local manifest = plugin.Manifest
		local assets = plugin.Assets
		local imageSource = assets.ThumbnailUrl ~= "" and assets.ThumbnailUrl or assets.IconUrl

		local card = UI.button(marketplaceList, "", UDim2.new(0, 0, 0, 0), UDim2.new(1, -20, 0, 124), function()
			print("Selected package:", plugin.Slug or manifest.Name)
		end, {
			color = tokens.color.surface,
			radius = 18,
			hoverColor = tokens.color.surface,
			pressedColor = tokens.color.surface,
		})

		card.Parent = marketplaceList
		card.ClipsDescendants = true

		local iconFrame = UI.frame(card, UDim2.new(0, 14, 0, 14), UDim2.fromOffset(92, 96), tokens.color.surfaceAlt, 12)

		iconFrame.ClipsDescendants = true
		iconFrame.Parent = card

		local icon = UI.image(iconFrame, "", UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 1, 0))

		icon.Parent = iconFrame
		setCardImage(icon, imageSource)

		local contentX = 118

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.BackgroundTransparency = 1
		title.Position = UDim2.new(0, contentX, 0, 14)
		title.Size = UDim2.new(1, -(contentX + 170), 0, 24)
		title.Text = manifest.Name or "Unknown Package"
		title.TextColor3 = tokens.color.text
		title.TextSize = 18
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextYAlignment = Enum.TextYAlignment.Center
		title.Parent = card

		local function pill(text, rightOffset, width)
			local tag = Instance.new("TextLabel")
			tag.Name = text
			tag.BackgroundColor3 = tokens.color.surfaceAlt
			tag.Position = UDim2.new(1, -rightOffset - width, 0, 12)
			tag.Size = UDim2.fromOffset(width, 22)
			tag.Text = text
			tag.TextColor3 = tokens.color.text
			tag.TextSize = 11
			tag.TextXAlignment = Enum.TextXAlignment.Center
			tag.TextYAlignment = Enum.TextYAlignment.Center
			tag.Parent = card

			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 7)
			corner.Parent = tag
		end

		local right = 14

		local typeLabel = string.upper(tostring(manifest.Type or "package"))
		pill(typeLabel, right, math.max(58, #typeLabel * 7 + 16))

		right = right + math.max(58, #typeLabel * 7 + 16) + 6

		local versionLabel = "V" .. tostring(manifest.Version or "?")
		pill(versionLabel, right, math.max(44, #versionLabel * 7 + 16))

		right = right + math.max(44, #versionLabel * 7 + 16) + 6

		local keyword = "PACKAGE"

		if manifest.Keywords and #manifest.Keywords > 0 then
			keyword = string.upper(manifest.Keywords[1])
		end

		pill(keyword, right, math.max(58, #keyword * 7 + 16))

		local description = Instance.new("TextLabel")
		description.Name = "Description"
		description.BackgroundTransparency = 1
		description.Position = UDim2.new(0, contentX, 0, 42)
		description.Size = UDim2.new(1, -(contentX + 16), 0, 38)
		description.Text = manifest.Description or "No description provided."
		description.TextColor3 = tokens.color.text
		description.TextTransparency = 0.12
		description.TextSize = 14
		description.TextWrapped = true
		description.TextXAlignment = Enum.TextXAlignment.Left
		description.TextYAlignment = Enum.TextYAlignment.Top
		description.Parent = card

		local divider = Instance.new("Frame")
		divider.BorderSizePixel = 0
		divider.BackgroundColor3 = tokens.color.surfaceAlt
		divider.BackgroundTransparency = 0.35
		divider.Position = UDim2.new(0, contentX, 1, -36)
		divider.Size = UDim2.new(1, -(contentX + 16), 0, 1)
		divider.Parent = card

		local author = Instance.new("TextLabel")
		author.Name = "Author"
		author.BackgroundTransparency = 1
		author.Position = UDim2.new(0, contentX, 1, -28)
		author.Size = UDim2.new(0, 140, 0, 18)
		author.Text = "by " .. (manifest.Author or "unknown")
		author.TextColor3 = tokens.color.accent
		author.TextSize = 13
		author.TextXAlignment = Enum.TextXAlignment.Left
		author.TextYAlignment = Enum.TextYAlignment.Center
		author.Parent = card

		local stats = Instance.new("TextLabel")
		stats.Name = "Stats"
		stats.BackgroundTransparency = 1
		stats.AnchorPoint = Vector2.new(1, 0)
		stats.Position = UDim2.new(1, -14, 1, -28)
		stats.Size = UDim2.new(0, 220, 0, 18)

		stats.Text = string.format(
			"%s downloads   %s",
			tostring(plugin.Downloads or 0),
			string.sub(tostring(plugin.UpdatedAt or ""), 1, 10)
		)

		stats.TextColor3 = tokens.color.subtext
		stats.TextSize = 12
		stats.TextXAlignment = Enum.TextXAlignment.Right
		stats.TextYAlignment = Enum.TextYAlignment.Center
		stats.Parent = card

		local shadow = Instance.new("UIShadow")
		shadow.BlurRadius = UDim.new(0, 8)
		shadow.Enabled = false
		shadow.Parent = card

		card.MouseEnter:Connect(function()
			shadow.Enabled = true
		end)

		card.MouseLeave:Connect(function()
			shadow.Enabled = false
		end)

		return card
	end

	local function marketplaceGridCard(plugin)
		local manifest = plugin.Manifest
		local assets = plugin.Assets

		local imageSource = assets.ThumbnailUrl ~= "" and assets.ThumbnailUrl or assets.IconUrl

		local CARD_WIDTH = 300
		local CARD_HEIGHT = 236
		local THUMBNAIL_HEIGHT = 154

		local card = UI.button(
			marketplaceList,
			"",
			UDim2.new(0, 0, 0, 0),
			UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT),
			function()
				print("Selected package:", plugin.Slug or manifest.Name)
			end,
			{
				color = tokens.color.surface,
				radius = 14,
				hoverColor = tokens.color.surface,
				pressedColor = tokens.color.surface,
			}
		)

		card.Parent = marketplaceList
		card.ClipsDescendants = true

		-- Thumbnail

		local thumbnailFrame =
			UI.frame(card, UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0, THUMBNAIL_HEIGHT), tokens.color.surfaceAlt, 0)

		thumbnailFrame.ClipsDescendants = true
		thumbnailFrame.Parent = card

		local thumbnail = UI.image(thumbnailFrame, "", UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 1, 0))

		thumbnail.Parent = thumbnailFrame
		setCardImage(thumbnail, imageSource)

		-- Title

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.BackgroundTransparency = 1
		title.Position = UDim2.new(0, 10, 0, THUMBNAIL_HEIGHT + 9)
		title.Size = UDim2.new(1, -20, 0, 24)
		title.Text = manifest.Name or "Unknown Package"
		title.TextColor3 = tokens.color.text
		title.TextSize = 16
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextYAlignment = Enum.TextYAlignment.Center
		title.Parent = card

		-- Author/version

		local metadata = Instance.new("TextLabel")
		metadata.Name = "Metadata"
		metadata.BackgroundTransparency = 1
		metadata.Position = UDim2.new(0, 10, 0, THUMBNAIL_HEIGHT + 34)
		metadata.Size = UDim2.new(1, -20, 0, 18)
		metadata.Text = "by " .. (manifest.Author or "unknown") .. "    v" .. (manifest.Version or "?")
		metadata.TextColor3 = tokens.color.subtext
		metadata.TextSize = 12
		metadata.TextXAlignment = Enum.TextXAlignment.Left
		metadata.TextYAlignment = Enum.TextYAlignment.Center
		metadata.Parent = card

		-- Bottom metadata

		local stats = Instance.new("TextLabel")
		stats.Name = "Stats"
		stats.BackgroundTransparency = 1
		stats.Position = UDim2.new(0, 10, 1, -27)
		stats.Size = UDim2.new(1, -20, 0, 18)
		stats.Text = string.format(
			"%s downloads   %s",
			tostring(plugin.Downloads or 0),
			string.sub(tostring(plugin.UpdatedAt or ""), 1, 10)
		)

		stats.TextColor3 = tokens.color.subtext
		stats.TextSize = 12
		stats.TextXAlignment = Enum.TextXAlignment.Left
		stats.TextYAlignment = Enum.TextYAlignment.Center
		stats.Parent = card

		local shadow = Instance.new("UIShadow")
		shadow.BlurRadius = UDim.new(0, 8)
		shadow.Enabled = false
		shadow.Parent = card

		card.MouseEnter:Connect(function()
			shadow.Enabled = true
		end)

		card.MouseLeave:Connect(function()
			shadow.Enabled = false
		end)

		return card
	end

	local function clearMarketplace()
		for _, child in pairs(marketplaceList:GetChildren()) do
			if child ~= marketplaceLayout then
				-- The cards own UI.button records; drop them before the
				-- Instances are destroyed so no rebuild touches a dead Instance.
				UI.forgetButtons(child)

				child:Destroy()
			end
		end
	end

	local function renderMarketplace()
		clearMarketplace()

		updateMarketplaceLayout()

		for _, plugin in pairs(marketplacePlugins) do
			if marketplaceLayoutMode == "Grid" then
				marketplaceGridCard(plugin)
			else
				marketplaceListCard(plugin)
			end
		end
	end

	local function loadMarketplace()
		local params = { sort = "recent", limit = 24 }
		local query = marketplaceSearch.Text

		if query and query ~= "" then
			params.q = query
		end

		local ok, data, meta = Packages:BrowseMarketplace(params)

		marketplacePlugins = {}

		if ok then
			for _, entry in ipairs(packageEntries(data)) do
				local package = normalizePackage(entry)

				if package then
					table.insert(marketplacePlugins, package)
				end
			end
		else
			print("Marketplace load failed:", tostring(data), tostring(meta and meta.status))
		end

		renderMarketplace()
	end

	local layoutButton

	layoutButton = UI.iconButton(
		marketplaceControls,
		"builtin://global-icons/grid.svg",
		UDim2.new(1, -(BUTTON_SIZE * 2 + CONTROL_GAP), 0, 0),
		UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE),
		function()
			if marketplaceLayoutMode == "List" then
				marketplaceLayoutMode = "Grid"
			else
				marketplaceLayoutMode = "List"
			end

			renderMarketplace()
		end,
		{
			bgTransparency = 0,
		}
	)

	refreshMarketplace.MouseButton1Click:Connect(function()
		loadMarketplace()
	end)

	marketplaceSearch.FocusLost:Connect(function()
		loadMarketplace()
	end)

	marketplaceServer.FocusLost:Connect(function()
		Packages.MarketplaceServer = marketplaceServer.Text
		marketplaceServer.Text = Packages.MarketplaceServer

		loadMarketplace()
	end)

	loadMarketplace()
end

if (IsServer or IsClient) or IsPlaytest then
	return nil
end
local UI = require("@internal/editor_ui")

local Packages = game:GetService("Packages")
local MatrixService = game:GetService("MatrixService")
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
			Name = name,
			PackageId = firstValue(entry.packageId, entry.PackageId, entry.package_id, ""),
			License = firstValue(entry.license, entry.License, ""),
			Visibility = firstValue(entry.visibility, entry.Visibility, ""),
			ReviewStatus = firstValue(entry.reviewStatus, entry.review_status, ""),
			Rating = entry.rating or entry.Rating,
			AcquisitionCount = firstValue(
				entry.acquisitionCount,
				entry.acquisition_count,
				entry.downloads,
				entry.DownloadCount,
				entry.download_count,
				0
			),
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
			Raw = entry,
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

	local function resolveImageSource(url)
		if type(url) ~= "string" or url == "" then
			return nil, nil
		end

		if string.sub(url, 1, 6) == "mxc://" then
			local session = MatrixService.Session

			if
				type(session) ~= "table"
				or type(session.homeserver) ~= "string"
				or type(session.accessToken) ~= "string"
			then
				return nil, nil
			end

			local resolved = MatrixService:MxcToHttp(session.homeserver, url, {
				authenticated = true,
			})

			if not resolved then
				return nil, nil
			end

			return resolved, {
				Authorization = "Bearer " .. session.accessToken,
			}
		end

		return resolveAssetUrl(url), nil
	end

	local function setCardImage(image, url)
		local headers
		url, headers = resolveImageSource(url)

		if not url or url == "" then
			return
		end

		local cached = marketplaceImageCache[url]

		if cached then
			image.Image = cached

			return
		end

		local ok, content = pcall(function()
			if headers then
				return HttpService:GetImageBytes(url, headers)
			end

			return HttpService:GetImageBytes(url)
		end)

		if ok and content then
			marketplaceImageCache[url] = content
			image.Image = content
		end
	end

	local detailPage = UI.frame(
		marketplacePage,
		UDim2.fromOffset(0, 0),
		UDim2.new(1, 0, 1, 0),
		tokens.color.panel,
		0
	)

	detailPage.Name = "PackageDetails"
	detailPage.Visible = false
	detailPage.ClipsDescendants = true

	local detailBack = UI.button(
		detailPage,
		"Back",
		UDim2.new(0, MARKETPLACE_MARGIN, 0, 8),
		UDim2.fromOffset(74, 28),
		function() end,
		{
			color = tokens.color.surface,
			hoverColor = tokens.color.surfaceAlt,
			pressedColor = tokens.color.input,
			textColor = tokens.color.text,
		}
	)

	local detailCrumb = UI.label(
		detailPage,
		"MARKETPLACE",
		UDim2.new(0, MARKETPLACE_MARGIN + 84, 0, 8),
		UDim2.new(1, -(MARKETPLACE_MARGIN * 2 + 84), 0, 28),
		12,
		tokens.color.subtext
	)

	local detailScroll = UI.create("ScrollingFrame", {
		Name = "DetailScroll",
		Position = UDim2.new(0, MARKETPLACE_MARGIN, 0, 46),
		Size = UDim2.new(1, -(MARKETPLACE_MARGIN * 2), 1, -(46 + MARKETPLACE_MARGIN)),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = tokens.color.subtext,
		CanvasSize = UDim2.fromOffset(0, 0),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ClipsDescendants = true,
	}, detailPage)

	local function formatDetailDate(value)
		if type(value) == "number" then
			local seconds = value > 100000000000 and math.floor(value / 1000) or value
			local ok, formatted = pcall(os.date, "%Y-%m-%d", seconds)

			if ok and formatted then
				return formatted
			end
		end

		local text = tostring(value or "")

		if text == "" then
			return "unknown"
		end

		return string.sub(text, 1, 10)
	end

	local function formatDetailCount(value)
		local number = tonumber(value)

		if number ~= nil then
			return tostring(number)
		end

		return tostring(value or 0)
	end

	local function detailTextHeight(text, charsPerLine, lineHeight)
		local length = math.max(1, #tostring(text or ""))
		return math.max(lineHeight, math.ceil(length / math.max(1, charsPerLine)) * lineHeight)
	end

	local function detailPill(parent, text, x, y, options)
		options = options or {}

		local label = tostring(text or "")

		if label == "" then
			return x
		end

		local width = math.max(options.minWidth or 50, #label * 7 + 20)
		local pill = UI.frame(parent, UDim2.fromOffset(x, y), UDim2.fromOffset(width, 22), options.color or tokens.color.surfaceAlt, 7)
		local textLabel = UI.label(pill, label, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 1, 0), 11, options.textColor or tokens.color.text)

		textLabel.TextXAlignment = Enum.TextXAlignment.Center

		return x + width + 6
	end

	local function clearPackageDetail()
		for _, child in ipairs(detailScroll:GetChildren()) do
			child:Destroy()
		end
	end

	local function renderPackageDetail(plugin, data)
		clearPackageDetail()

		if type(data) == "table" and type(data.package) == "table" then
			data = data.package
		end

		data = type(data) == "table" and data or {}

		local manifest = plugin.Manifest or {}
		local assets = plugin.Assets or {}
		local name = firstValue(data.name, data.Name, manifest.Name, plugin.Name, "Unknown Package")
		local namespace = firstValue(data.namespace, data.Namespace, plugin.Namespace, "unknown")
		local description = firstValue(data.description, data.Description, manifest.Description, "No description provided.")
		local itemType = firstValue(data.itemType, data.type, data.Type, manifest.Type, "package")
		local version = firstValue(data.latestVersion, data.version, data.Version, manifest.Version, "?")
		local tags = stringList(firstValue(data.tags, data.Tags, manifest.Keywords))
		local license = firstValue(data.license, data.License, plugin.License, "Not specified")
		local visibility = firstValue(data.visibility, data.Visibility, plugin.Visibility, "public")
		local reviewStatus = firstValue(data.reviewStatus, data.review_status, plugin.ReviewStatus, "approved")
		local engineConstraint = firstValue(data.engineConstraint, data.engine_constraint, "Any")
		local packageId = firstValue(data.packageId, data.package_id, plugin.PackageId, "unknown")
		local updatedAt = firstValue(data.updatedAt, data.updated_at, data.publishedAt, data.published_at, plugin.UpdatedAt, "")
		local acquisitionCount = firstValue(
			data.acquisitionCount,
			data.acquisition_count,
			data.downloads,
			plugin.AcquisitionCount,
			plugin.Downloads,
			0
		)
		local rating = data.rating or plugin.Rating or {}
		local ratingAverage = tonumber(rating.average or rating.Average)
		local ratingCount = tonumber(rating.count or rating.Count) or 0
		local iconUrl = firstValue(data.iconUrl, data.icon_url, assets.IconUrl)
		local bannerUrl = firstValue(data.bannerUrl, data.banner_url, data.thumbnailUrl, assets.ThumbnailUrl)
		local versions = type(data.versions) == "table" and data.versions or {}
		local latest = nil

		for _, item in ipairs(versions) do
			if type(item) == "table" and not item.yanked then
				latest = item
				break
			end
		end

		local dependencies = latest and type(latest.dependencies) == "table" and latest.dependencies or {}
		local contentWidth = math.max(360, detailScroll.AbsoluteSize.X - 12)
		local charsPerLine = math.max(36, math.floor(contentWidth / 7.5))

		local hero = UI.frame(detailScroll, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 170), tokens.color.surfaceAlt, 14)

		hero.ClipsDescendants = true

		local banner = UI.image(hero, "", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1))

		banner.ScaleType = Enum.ScaleType.Crop
		banner.Parent = hero
		setCardImage(banner, bannerUrl)

		if not bannerUrl or bannerUrl == "" then
			local empty = UI.label(hero, "NO BANNER", UDim2.fromOffset(18, 14), UDim2.new(1, -36, 0, 18), 11, tokens.color.muted)

			empty.TextXAlignment = Enum.TextXAlignment.Right
		end

		local info = UI.card(detailScroll, UDim2.fromOffset(0, 156), UDim2.new(1, 0, 0, 138), {
			color = tokens.color.surface,
			radius = 14,
		})

		local iconFrame = UI.frame(info, UDim2.fromOffset(16, -24), UDim2.fromOffset(86, 86), tokens.color.surfaceAlt, 13)

		iconFrame.ClipsDescendants = true
		UI.stroke(iconFrame, tokens.color.border, 1, 0)

		local icon = UI.image(iconFrame, "", UDim2.fromOffset(0, 0), UDim2.new(1, 0, 1, 0))

		icon.ScaleType = Enum.ScaleType.Fit
		icon.Parent = iconFrame
		setCardImage(icon, iconUrl)

		local title = UI.label(
			info,
			tostring(name),
			UDim2.fromOffset(120, 10),
			UDim2.new(1, -136, 0, 30),
			23,
			tokens.color.text
		)

		title.TextYAlignment = Enum.TextYAlignment.Center

		local author = UI.label(
			info,
			"by " .. tostring(namespace),
			UDim2.fromOffset(120, 40),
			UDim2.new(1, -136, 0, 20),
			13,
			tokens.color.accent
		)

		local pillX = detailPill(info, string.upper(tostring(itemType)), 120, 66, {
			color = tokens.color.accentSoft,
		})

		pillX = detailPill(info, "v" .. tostring(version), pillX, 66, {
			minWidth = 44,
		})

		detailPill(info, string.upper(tostring(reviewStatus)), pillX, 66, {
			minWidth = 62,
			textColor = reviewStatus == "approved" and tokens.color.text or tokens.color.muted,
		})

		if #tags > 0 then
			local tagText = UI.label(
				info,
				table.concat(tags, "   "),
				UDim2.fromOffset(120, 98),
				UDim2.new(1, -136, 0, 18),
				12,
				tokens.color.subtext
			)

			tagText.TextWrapped = false
		end

		local statY = 306
		local statCards = {
			{
				label = "DOWNLOADS",
				value = formatDetailCount(acquisitionCount),
			},
			{
				label = "RATING",
				value = ratingAverage and string.format("%.1f (%d)", ratingAverage, ratingCount) or "No ratings",
			},
			{
				label = "VERSION",
				value = "v" .. tostring(version),
			},
			{
				label = "UPDATED",
				value = formatDetailDate(updatedAt),
			},
		}

		for index, stat in ipairs(statCards) do
			local card = UI.card(
				detailScroll,
				UDim2.new((index - 1) * 0.25, 0, 0, statY),
				UDim2.new(0.25, -8, 0, 64),
				{
					color = tokens.color.surface,
					radius = 12,
				}
			)

			UI.label(
				card,
				stat.label,
				UDim2.fromOffset(12, 10),
				UDim2.new(1, -24, 0, 16),
				10,
				tokens.color.muted
			)

			UI.label(
				card,
				stat.value,
				UDim2.fromOffset(12, 28),
				UDim2.new(1, -24, 0, 24),
				17,
				tokens.color.text
			)
		end

		local bodyY = statY + 78
		local descriptionHeight = math.clamp(62 + detailTextHeight(description, charsPerLine, 18), 92, 240)
		local descriptionCard = UI.card(detailScroll, UDim2.fromOffset(0, bodyY), UDim2.new(1, 0, 0, descriptionHeight), {
			color = tokens.color.surface,
			radius = 12,
		})

		UI.label(
			descriptionCard,
			"ABOUT",
			UDim2.fromOffset(16, 12),
			UDim2.new(1, -32, 0, 16),
			10,
			tokens.color.muted
		)

		local descriptionLabel = UI.label(
			descriptionCard,
			tostring(description),
			UDim2.fromOffset(16, 34),
			UDim2.new(1, -32, 1, -46),
			14,
			tokens.color.text
		)

		descriptionLabel.TextWrapped = true
		descriptionLabel.TextYAlignment = Enum.TextYAlignment.Top

		local detailsY = bodyY + descriptionHeight + 12
		local detailsHeight = 122
		local detailsCard = UI.card(detailScroll, UDim2.fromOffset(0, detailsY), UDim2.new(1, 0, 0, detailsHeight), {
			color = tokens.color.surface,
			radius = 12,
		})

		UI.label(
			detailsCard,
			"DETAILS",
			UDim2.fromOffset(16, 12),
			UDim2.new(1, -32, 0, 16),
			10,
			tokens.color.muted
		)

		local function detailField(labelText, valueText, x, y, width)
			UI.label(
				detailsCard,
				labelText,
				UDim2.fromOffset(x, y),
				UDim2.new(0, width, 0, 14),
				9,
				tokens.color.muted
			)

			local value = UI.label(
				detailsCard,
				tostring(valueText),
				UDim2.fromOffset(x, y + 15),
				UDim2.new(0, width, 0, 18),
				12,
				tokens.color.text
			)

			value.TextWrapped = false
		end

		local halfWidth = math.max(120, math.floor((contentWidth - 48) / 2))

		detailField("LICENSE", license, 16, 38, halfWidth)
		detailField("ENGINE", engineConstraint, 32 + halfWidth, 38, halfWidth)
		detailField("VISIBILITY", visibility, 16, 76, halfWidth)
		detailField("REVIEW", reviewStatus, 32 + halfWidth, 76, halfWidth)

		local packageIdLabel = UI.label(
			detailsCard,
			tostring(packageId),
			UDim2.fromOffset(16, 105),
			UDim2.new(1, -32, 0, 14),
			10,
			tokens.color.subtext
		)

		packageIdLabel.TextWrapped = false

		local dependenciesY = detailsY + detailsHeight + 12
		local dependencyCount = math.min(#dependencies, 8)
		local dependenciesHeight = 48 + math.max(1, dependencyCount) * 22
		local dependenciesCard = UI.card(
			detailScroll,
			UDim2.fromOffset(0, dependenciesY),
			UDim2.new(1, 0, 0, dependenciesHeight),
			{
				color = tokens.color.surface,
				radius = 12,
			}
		)

		UI.label(
			dependenciesCard,
			"DEPENDENCIES",
			UDim2.fromOffset(16, 12),
			UDim2.new(1, -32, 0, 16),
			10,
			tokens.color.muted
		)

		if dependencyCount == 0 then
			UI.label(
				dependenciesCard,
				"No dependencies.",
				UDim2.fromOffset(16, 34),
				UDim2.new(1, -32, 0, 18),
				12,
				tokens.color.subtext
			)
		else
			for index = 1, dependencyCount do
				local dependency = dependencies[index]
				local dependencyName = tostring(dependency.name or dependency.Name or "unknown")
				local dependencyNamespace = tostring(dependency.namespace or dependency.Namespace or "unknown")
				local constraint = tostring(dependency.constraint or dependency.Constraint or "*")
				local y = 32 + (index - 1) * 22

				UI.label(
					dependenciesCard,
					dependencyNamespace .. "/" .. dependencyName,
					UDim2.fromOffset(16, y),
					UDim2.new(1, -140, 0, 18),
					12,
					tokens.color.text
				)

				local constraintLabel = UI.label(
					dependenciesCard,
					constraint,
					UDim2.new(1, -124, 0, y),
					UDim2.fromOffset(108, 18),
					11,
					tokens.color.subtext
				)

				constraintLabel.TextXAlignment = Enum.TextXAlignment.Right
			end
		end

		local versionsY = dependenciesY + dependenciesHeight + 12
		local versionCount = math.min(#versions, 6)
		local versionsHeight = 48 + math.max(1, versionCount) * 26
		local versionsCard = UI.card(
			detailScroll,
			UDim2.fromOffset(0, versionsY),
			UDim2.new(1, 0, 0, versionsHeight),
			{
				color = tokens.color.surface,
				radius = 12,
			}
		)

		UI.label(
			versionsCard,
			string.format("VERSIONS (%d)", #versions),
			UDim2.fromOffset(16, 12),
			UDim2.new(1, -32, 0, 16),
			10,
			tokens.color.muted
		)

		if versionCount == 0 then
			UI.label(
				versionsCard,
				"No published versions.",
				UDim2.fromOffset(16, 34),
				UDim2.new(1, -32, 0, 18),
				12,
				tokens.color.subtext
			)
		else
			for index = 1, versionCount do
				local item = versions[index]
				local y = 32 + (index - 1) * 26
				local versionText = "v" .. tostring(item.version or item.Version or "?")
				local dateText = formatDetailDate(item.publishedAt or item.published_at)
				local sizeText = ""

				if type(item.size) == "number" then
					sizeText = string.format("%.1f KB", item.size / 1024)
				end

				UI.label(
					versionsCard,
					versionText,
					UDim2.fromOffset(16, y),
					UDim2.fromOffset(140, 20),
					12,
					item.yanked and tokens.color.muted or tokens.color.text
				)

				UI.label(
					versionsCard,
					dateText .. (sizeText ~= "" and ("   " .. sizeText) or ""),
					UDim2.new(1, -236, 0, y),
					UDim2.fromOffset(220, 20),
					11,
					tokens.color.subtext
				).TextXAlignment = Enum.TextXAlignment.Right

				if item.yanked then
					local yanked = UI.label(
						versionsCard,
						"YANKED",
						UDim2.new(1, -70, 0, y),
						UDim2.fromOffset(54, 20),
						9,
						tokens.color.warning
					)

					yanked.TextXAlignment = Enum.TextXAlignment.Right
				end
			end
		end

		detailScroll.CanvasSize = UDim2.fromOffset(0, versionsY + versionsHeight + 12)
		detailScroll.CanvasPosition = Vector2.new(0, 0)
	end

	local function openPackagePage(plugin)
		marketplaceControls.Visible = false
		marketplaceList.Visible = false
		detailPage.Visible = true
		detailCrumb.Text = string.upper("MARKETPLACE   /   " .. tostring(plugin.Slug or plugin.Manifest.Name))

		renderPackageDetail(plugin, plugin.Raw)

		local ok, data = Packages:GetMarketplacePackage(plugin.Namespace, plugin.Name)

		if ok then
			renderPackageDetail(plugin, data)
		else
			UI.toast("Could not load package details.", {
				type = "error",
			})
		end
	end

	detailBack.MouseButton1Click:Connect(function()
		detailPage.Visible = false
		marketplaceControls.Visible = true
		marketplaceList.Visible = true
	end)

	local function marketplaceListCard(plugin)
		local manifest = plugin.Manifest
		local assets = plugin.Assets
		local imageSource = assets.ThumbnailUrl ~= "" and assets.ThumbnailUrl or assets.IconUrl

		local card = UI.button(marketplaceList, "", UDim2.new(0, 0, 0, 0), UDim2.new(1, -20, 0, 124), function()
			openPackagePage(plugin)
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
				openPackagePage(plugin)
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

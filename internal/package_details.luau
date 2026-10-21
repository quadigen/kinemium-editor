if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local UI = require("@internal/editor_ui")
local Packages = game:GetService("Packages")

local tokens = UI.tokens
local colors = tokens.color

local PAGE_PADDING = 20
local SECTION_GAP = 14
local CARD_PADDING = 18
local CARD_GAP = 10
local CARD_RADIUS = 12

local TOPBAR_HEIGHT = 48
local BANNER_HEIGHT = 150
local FADE_HEIGHT = 80
local ICON_SIZE = 88
local ICON_OVERLAP = 44
local IDENTITY_HEIGHT = 64
local INSTALL_WIDTH = 100

local STAT_HEIGHT = 68
local STAT_GAP = 8
local ROW_HEIGHT = 32
local VERSION_ROW_HEIGHT = 44
local DOWNLOAD_WIDTH = 96
local DOWNLOAD_HEIGHT = 26
local PILL_HEIGHT = 22
local PILL_PADDING = 10
local PILL_ICON_SPACE = 16
local CHAR_WIDTH = 8

local MAX_TAGS = 6
local MAX_DEPENDENCIES = 12
local MAX_VERSIONS = 8

local ICONS = {
	download = "builtin://global-icons/download.svg",
	package = "builtin://global-icons/package.svg",
	tag = "builtin://global-icons/tag.svg",
	calendar = "builtin://global-icons/calendar.svg",
	clock = "builtin://global-icons/clock.svg",
	user = "builtin://global-icons/user.svg",
	star = "builtin://global-icons/star.svg",
	like = "builtin://global-icons/thumbs-up.svg",
	dislike = "builtin://global-icons/thumbs-down.svg",
	shield = "builtin://global-icons/shield-check.svg",
	license = "builtin://global-icons/scale.svg",
	engine = "builtin://global-icons/cpu.svg",
	eye = "builtin://global-icons/eye.svg",
	hash = "builtin://global-icons/hash.svg",
	id = "builtin://global-icons/fingerprint.svg",
	namespace = "builtin://global-icons/at-sign.svg",
	install = "builtin://global-icons/hard-drive-download.svg",
	about = "builtin://global-icons/info.svg",
	details = "builtin://global-icons/file.svg",
	dependencies = "builtin://global-icons/folder.svg",
	versions = "builtin://global-icons/tag.svg",
	warning = "builtin://global-icons/warning.svg",
	check = "builtin://global-icons/check.svg",
}

local function firstValue(...)
	for index = 1, select("#", ...) do
		local value = select(index, ...)

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
		if type(entry) == "string" and entry ~= "" then
			table.insert(result, entry)
		end
	end

	return result
end

local function tableList(value)
	local result = {}

	if type(value) ~= "table" then
		return result
	end

	for _, entry in ipairs(value) do
		if type(entry) == "table" then
			table.insert(result, entry)
		end
	end

	return result
end

local function formatDate(value)
	if type(value) == "userdata" then
		return DateTime.fromIsoDate(value) or "Unknown"
	end

	if type(value) == "string" then
		if value == "" then
			return "Unknown"
		end

		if not value:match("^%d+$") then
			return string.sub(value, 1, 10)
		end

		value = tonumber(value)
	end

	if type(value) ~= "number" then
		return "Unknown"
	end

	local ok, dateTime = pcall(function()
		if value > 100000000000 then
			return DateTime.fromUnixTimestampMillis(value)
		end

		return DateTime.fromUnixTimestamp(value)
	end)

	return ok and DateTime.fromIsoDate(dateTime) or "Unknown"
end

local function pickDate(...)
	for index = 1, select("#", ...) do
		local value = select(index, ...)
		local kind = type(value)

		if kind == "number" or kind == "userdata" or (kind == "string" and value ~= "") then
			return value
		end
	end

	return nil
end

local function formatCount(value)
	local number = tonumber(value)

	if number == nil then
		return tostring(value or 0)
	end

	local text = tostring(math.floor(number))
	local sign, digits = text:match("^(-?)(%d+)$")

	if not digits then
		return text
	end

	digits = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	digits = digits:gsub("^,", "")

	return sign .. digits
end

local function formatSize(bytes)
	if type(bytes) ~= "number" then
		return ""
	end

	if bytes >= 1024 * 1024 then
		return string.format("%.1f MB", bytes / (1024 * 1024))
	end

	if bytes >= 1024 then
		return string.format("%.1f KB", bytes / 1024)
	end

	return string.format("%d B", math.floor(bytes))
end

local function trySet(object, property, value)
	pcall(function()
		object[property] = value
	end)
end

local function truncate(label)
	trySet(label, "TextTruncate", Enum.TextTruncate.AtEnd)

	return label
end

local function addIcon(iconParent, name, x, y, size, color)
	local path = ICONS[name]

	if not path or path == "" then
		return nil
	end

	local image = UI.image(iconParent, path, UDim2.fromOffset(x, y), UDim2.fromOffset(size, size))

	image.Name = "Icon_" .. name
	trySet(image, "ImageColor3", color or colors.muted)

	return image
end

return function(parent, options)
	options = options or {}

	local state = {
		plugin = nil,
		serial = 0,
		open = false,
	}

	local controller = {}

	local page = UI.frame(parent, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 1, 0), colors.panel, 0)

	page.Name = "PackageDetails"
	page.Visible = false
	page.ClipsDescendants = true

	controller.frame = page

	local topbar = UI.frame(page, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, TOPBAR_HEIGHT), colors.panelRaised, 0)

	topbar.Name = "TopBar"
	topbar.ZIndex = 10

	UI.separator(topbar, UDim2.new(0, 0, 1, -1), UDim2.new(1, 0, 0, 1), colors.border)

	local backButton = UI.button(
		topbar,
		"Back",
		UDim2.fromOffset(PAGE_PADDING, (TOPBAR_HEIGHT - 28) / 2),
		UDim2.fromOffset(78, 28),
		function()
			controller:Close()
		end,
		{
			color = colors.surface,
			hoverColor = colors.hover,
			pressedColor = colors.pressed,
			textColor = colors.text,
			radius = tokens.radius.md,
			textY = 0,
		}
	)

	backButton.Name = "Back"

	local crumbX = PAGE_PADDING + 78 + 14

	local crumb = UI.label(
		topbar,
		"MARKETPLACE",
		UDim2.fromOffset(crumbX, 0),
		UDim2.new(1, -(crumbX + PAGE_PADDING), 1, 0),
		tokens.type.caption,
		colors.subtext
	)

	crumb.Name = "Breadcrumb"
	truncate(crumb)

	local function setCrumb(plugin, suffix)
		local slug = tostring(plugin.Slug or (plugin.Manifest and plugin.Manifest.Name) or "")
		local text = "MARKETPLACE   /   " .. slug

		if suffix then
			text ..= "   ·   " .. suffix
		end

		crumb.Text = string.upper(text)
	end

	local scroll = UI.create("ScrollingFrame", {
		Name = "Scroll",
		Position = UDim2.fromOffset(0, TOPBAR_HEIGHT),
		Size = UDim2.new(1, 0, 1, -TOPBAR_HEIGHT),
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = colors.subtext,
		ScrollBarImageTransparency = 0.4,
		CanvasSize = UDim2.fromOffset(0, 0),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ClipsDescendants = true,
	}, page)

	local scrollPadding = UI.create("UIPadding", {
		PaddingLeft = UDim.new(0, PAGE_PADDING),
		PaddingRight = UDim.new(0, PAGE_PADDING + 4),
		PaddingTop = UDim.new(0, PAGE_PADDING),
		PaddingBottom = UDim.new(0, PAGE_PADDING),
	}, scroll)

	local scrollLayout = UI.create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, SECTION_GAP),
	}, scroll)

	local keep = { [scrollPadding] = true, [scrollLayout] = true }

	local function syncCanvas()
		local total, count = 0, 0

		for _, child in ipairs(scroll:GetChildren()) do
			if child:IsA("GuiObject") then
				total += child.Size.Y.Offset
				count += 1
			end
		end

		total += math.max(count - 1, 0) * SECTION_GAP

		scroll.CanvasSize = UDim2.fromOffset(0, total + PAGE_PADDING * 2)
	end

	local function pill(pillParent, text, order, config)
		config = config or {}

		local label = tostring(text or "")

		if label == "" then
			return nil
		end

		local hasIcon = config.icon ~= nil and ICONS[config.icon] ~= nil
		local iconSpace = hasIcon and PILL_ICON_SPACE or 0

		local frame = UI.frame(
			pillParent,
			UDim2.fromOffset(0, 0),
			UDim2.fromOffset(#label * 7 + PILL_PADDING * 2 + iconSpace, PILL_HEIGHT),
			config.color or colors.surfaceAlt,
			7
		)

		frame.LayoutOrder = order

		if config.stroke then
			UI.stroke(frame, config.stroke, 1, 0.3)
		end

		if hasIcon then
			addIcon(
				frame,
				config.icon,
				PILL_PADDING - 2,
				(PILL_HEIGHT - 12) / 2,
				12,
				config.iconColor or config.textColor or colors.subtext
			)
		end

		local textLabel = UI.label(
			frame,
			label,
			UDim2.fromOffset(iconSpace, 0),
			UDim2.new(1, -iconSpace, 1, 0),
			tokens.type.caption,
			config.textColor or colors.text
		)

		textLabel.TextWrapped = false
		textLabel.TextXAlignment = Enum.TextXAlignment.Center

		local function fit()
			local width = textLabel.TextBounds.X

			if width and width > 0 then
				frame.Size = UDim2.fromOffset(math.ceil(width) + PILL_PADDING * 2 + iconSpace, PILL_HEIGHT)
			end
		end

		pcall(function()
			textLabel:GetPropertyChangedSignal("TextBounds"):Connect(fit)
		end)

		fit()

		return frame
	end

	local HEADER_HEIGHT = 16

	local function setBody(card, bodyHeight)
		card.Size = UDim2.new(1, 0, 0, CARD_PADDING * 2 + HEADER_HEIGHT + CARD_GAP + bodyHeight)

		syncCanvas()
	end

	local function section(title, order, rightText, icon)
		local card = UI.card(scroll, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 0), {
			color = colors.surface,
			radius = CARD_RADIUS,
		})

		card.Name = title
		card.LayoutOrder = order

		UI.create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, CARD_GAP),
		}, card)

		setBody(card, 20)

		local header = UI.create("Frame", {
			Name = "Header",
			Size = UDim2.new(1, 0, 0, HEADER_HEIGHT),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			LayoutOrder = 0,
		}, card)

		local titleX = 0

		if icon and addIcon(header, icon, 0, 1, 14, colors.muted) then
			titleX = 20
		end

		UI.label(
			header,
			title,
			UDim2.fromOffset(titleX, 0),
			UDim2.new(0.6, -titleX, 1, 0),
			tokens.type.caption,
			colors.muted
		)

		if rightText and rightText ~= "" then
			local right = UI.label(
				header,
				rightText,
				UDim2.new(0.6, 0, 0, 0),
				UDim2.new(0.4, 0, 1, 0),
				tokens.type.caption,
				colors.muted
			)

			right.TextXAlignment = Enum.TextXAlignment.Right
		end

		return card
	end

	local function row(rowParent, order, height)
		local frame = UI.frame(rowParent, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, height), colors.surfaceAlt, 8)

		frame.BackgroundTransparency = 0.55
		frame.LayoutOrder = order

		return frame
	end

	local function rightLabel(rowParent, text, width, rightOffset, height, size, color, y)
		local label = UI.label(
			rowParent,
			text,
			UDim2.new(1, -(rightOffset + width), 0, y or 0),
			UDim2.fromOffset(width, height),
			size,
			color
		)

		label.TextXAlignment = Enum.TextXAlignment.Right

		return label
	end

	local function emptyNote(noteParent, text)
		local label = UI.label(
			noteParent,
			text,
			UDim2.fromOffset(0, 0),
			UDim2.new(1, 0, 0, 18),
			tokens.type.small,
			colors.subtext
		)

		label.LayoutOrder = 1

		return label
	end

	local function overflowNote(noteParent, text, order)
		local label = UI.label(
			noteParent,
			text,
			UDim2.fromOffset(0, 0),
			UDim2.new(1, 0, 0, 18),
			tokens.type.caption,
			colors.muted
		)

		label.LayoutOrder = order
		label.TextXAlignment = Enum.TextXAlignment.Center

		return label
	end

	local function roundImage(image, radius)
		UI.create("UICorner", { CornerRadius = UDim.new(0, radius) }, image)
	end

	function controller:Render(plugin, data)
		UI.clear(scroll, keep)

		if type(data) == "table" and type(data.package) == "table" then
			data = data.package
		end

		data = type(data) == "table" and data or {}

		local manifest = plugin.Manifest or {}
		local assets = plugin.Assets or {}

		local name = firstValue(data.name, data.Name, manifest.Name, plugin.Name, "Unknown Package")
		local namespace = firstValue(data.namespace, data.Namespace, plugin.Namespace, "unknown")
		local description =
			firstValue(data.description, data.Description, manifest.Description, "No description provided.")
		local itemType = firstValue(data.itemType, data.type, data.Type, manifest.Type, "package")
		local version = firstValue(data.latestVersion, data.version, data.Version, manifest.Version, "?")
		local tags = stringList(firstValue(data.tags, data.Tags, manifest.Keywords))
		local license = firstValue(data.license, data.License, plugin.License, "Not specified")
		local visibility = firstValue(data.visibility, data.Visibility, plugin.Visibility, "public")
		local reviewStatus = firstValue(data.reviewStatus, data.review_status, plugin.ReviewStatus, "approved")
		local engineConstraint = firstValue(data.engineConstraint, data.engine_constraint, "Any")
		local packageId = firstValue(data.packageId, data.package_id, plugin.PackageId, "unknown")

		local downloads = firstValue(
			data.downloadCount,
			data.download_count,
			data.acquisitionCount,
			data.acquisition_count,
			data.downloads,
			plugin.AcquisitionCount,
			plugin.Downloads,
			0
		)
		local installs = firstValue(data.installCount, data.install_count, 0)

		local rating = data.rating or plugin.Rating or {}
		local ratingAverage = type(rating) == "table" and tonumber(rating.average or rating.Average) or nil
		local ratingCount = type(rating) == "table" and tonumber(rating.count or rating.Count) or 0

		local reactions = type(data.reactions) == "table" and data.reactions or {}
		local likes = tonumber(reactions.likes) or 0
		local dislikes = tonumber(reactions.dislikes) or 0

		local creator = type(data.creator) == "table" and data.creator or {}
		local owner = firstValue(data.owner, creator.userId, manifest.Author, namespace, "Unknown")
		local reviewedBy = firstValue(data.reviewedBy, data.reviewed_by, "None")
		local reviewNote = firstValue(data.reviewNote, data.review_note)
		local deprecated = data.deprecated == true

		local iconUrl = firstValue(data.iconUrl, data.icon_url, assets.IconUrl)
		local bannerUrl = firstValue(data.bannerUrl, data.banner_url, data.thumbnailUrl, assets.ThumbnailUrl)

		local versions = tableList(data.versions)

		local latest = nil

		for _, item in ipairs(versions) do
			if not item.yanked then
				latest = item
				break
			end
		end

		local dependencies = latest and tableList(latest.dependencies) or {}

		local updatedAt = pickDate(
			data.updatedAt,
			data.updated_at,
			data.publishedAt,
			data.published_at,
			plugin.UpdatedAt,
			latest and latest.publishedAt,
			latest and latest.published_at
		)
		local createdAt = pickDate(data.createdAt, data.created_at)
		local publishedAt = pickDate(data.publishedAt, data.published_at)
		local reviewedAt = pickDate(data.reviewedAt, data.reviewed_at)
		local submittedAt = pickDate(data.submittedAt, data.submitted_at)

		local pillsTop = BANNER_HEIGHT + IDENTITY_HEIGHT

		local hero =
			UI.card(scroll, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, pillsTop + PILL_HEIGHT + CARD_PADDING), {
				color = colors.surface,
				radius = 14,
			})

		hero.Name = "Hero"
		hero.LayoutOrder = 1
		hero.ClipsDescendants = true

		local banner = UI.frame(hero, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, BANNER_HEIGHT), colors.surfaceAlt, 14)

		banner.Name = "Banner"
		banner.ClipsDescendants = true

		local bannerImage = UI.image(banner, "", UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1))

		bannerImage.ScaleType = Enum.ScaleType.Crop
		bannerImage.ZIndex = 1

		roundImage(bannerImage, 14)

		if bannerUrl and bannerUrl ~= "" then
			if options.setImage then
				options.setImage(bannerImage, bannerUrl)
			end
		else
			local empty = UI.label(
				banner,
				"NO BANNER",
				UDim2.fromOffset(0, 0),
				UDim2.new(1, 0, 1, -FADE_HEIGHT / 2),
				tokens.type.caption,
				colors.muted
			)

			empty.TextXAlignment = Enum.TextXAlignment.Center
		end

		local fade =
			UI.frame(banner, UDim2.new(0, 0, 1, -FADE_HEIGHT), UDim2.new(1, 0, 0, FADE_HEIGHT), colors.surface, 0)

		fade.Name = "Fade"
		fade.ZIndex = 2

		UI.create("UIGradient", {
			Transparency = NumberSequence.new(1, 0),
			Rotation = 90,
		}, fade)

		local identity = UI.create("Frame", {
			Name = "Identity",
			Position = UDim2.fromOffset(0, BANNER_HEIGHT),
			Size = UDim2.new(1, 0, 0, IDENTITY_HEIGHT),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, hero)

		local actionWidth = options.onInstall and (INSTALL_WIDTH + CARD_PADDING) or 0
		local textX = CARD_PADDING + ICON_SIZE + 16
		local textRight = textX + CARD_PADDING + actionWidth

		local title = UI.label(
			identity,
			tostring(name),
			UDim2.fromOffset(textX, 8),
			UDim2.new(1, -textRight, 0, 28),
			22,
			colors.text
		)

		title.Name = "Title"
		truncate(title)

		local authorX = textX

		if addIcon(identity, "user", textX, 40, 13, colors.accent) then
			authorX = textX + 18
		end

		local author = UI.label(
			identity,
			"by " .. tostring(namespace),
			UDim2.fromOffset(authorX, 38),
			UDim2.new(1, -(textRight + (authorX - textX)), 0, 18),
			13,
			colors.accent
		)

		author.Name = "Author"
		truncate(author)

		if options.onInstall then
			local _, installLabel = UI.button(
				identity,
				options.installText or "Install",
				UDim2.new(1, -(INSTALL_WIDTH + CARD_PADDING), 0, 12),
				UDim2.fromOffset(INSTALL_WIDTH, 34),
				function()
					options.onInstall(plugin, data)
				end,
				{
					color = colors.accent,
					hoverColor = colors.selectionHover,
					pressedColor = colors.pressed,
					textColor = colors.text,
					textSize = tokens.type.body,
					radius = tokens.radius.md,
					border = false,
					textY = 0,
				}
			)

			installLabel.TextXAlignment = Enum.TextXAlignment.Center
		end

		local pills = UI.create("Frame", {
			Name = "Pills",
			Position = UDim2.fromOffset(CARD_PADDING, pillsTop),
			Size = UDim2.new(1, -CARD_PADDING * 2, 0, PILL_HEIGHT),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, hero)

		local pillsLayout = UI.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Wraps = true,
			Padding = UDim.new(0, 6),
			LinePadding = UDim.new(0, 6),
		}, pills)

		local function fitHero()
			local height = math.max(pillsLayout.AbsoluteContentSize.Y, PILL_HEIGHT)

			pills.Size = UDim2.new(1, -CARD_PADDING * 2, 0, height)
			hero.Size = UDim2.new(1, 0, 0, pillsTop + height + CARD_PADDING)

			syncCanvas()
		end

		pillsLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fitHero)

		local approved = tostring(reviewStatus):lower() == "approved"
		local order = 0

		local function addPill(text, config)
			order += 1
			pill(pills, text, order, config)
		end

		addPill(string.upper(tostring(itemType)), { color = colors.accent, textColor = colors.text, icon = "package" })
		addPill("v" .. tostring(version), { icon = "tag", textColor = colors.text, iconColor = colors.subtext })
		addPill(string.upper(tostring(reviewStatus)), {
			textColor = approved and colors.success or colors.warning,
			icon = approved and "shield" or "warning",
		})
		addPill(string.upper(tostring(visibility)), { icon = "eye", textColor = colors.subtext })

		if deprecated then
			addPill("DEPRECATED", { textColor = colors.warning, icon = "warning" })
		end

		for index, tag in ipairs(tags) do
			if index > MAX_TAGS then
				break
			end

			addPill(tag, { color = colors.surface, stroke = colors.border, textColor = colors.subtext, icon = "hash" })
		end

		fitHero()

		local iconFrame = UI.frame(
			hero,
			UDim2.fromOffset(CARD_PADDING, BANNER_HEIGHT - ICON_OVERLAP),
			UDim2.fromOffset(ICON_SIZE, ICON_SIZE),
			colors.surfaceAlt,
			16
		)

		iconFrame.Name = "Icon"
		iconFrame.ClipsDescendants = true
		iconFrame.ZIndex = 5

		UI.stroke(iconFrame, colors.surface, 3, 0)

		local iconImage = UI.image(iconFrame, "", UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1))

		iconImage.ScaleType = Enum.ScaleType.Fit
		iconImage.ZIndex = 6

		roundImage(iconImage, 16)

		if iconUrl and iconUrl ~= "" then
			if options.setImage then
				options.setImage(iconImage, iconUrl)
			end
		else
			local initial = UI.label(
				iconFrame,
				string.upper(string.sub(tostring(name), 1, 1)),
				UDim2.fromOffset(0, 0),
				UDim2.fromScale(1, 1),
				34,
				colors.muted
			)

			initial.TextXAlignment = Enum.TextXAlignment.Center
			initial.ZIndex = 6
		end

		local ratingText = "No ratings"

		if ratingAverage then
			ratingText = string.format("%.1f  (%d)", ratingAverage, math.floor(ratingCount or 0))
		end

		local statCards = {
			{ label = "DOWNLOADS", value = formatCount(downloads), icon = "download" },
			{ label = "RATING", value = ratingText, icon = "star" },
			{ label = "VERSION", value = "v" .. tostring(version), icon = "tag" },
			{ label = "UPDATED", value = formatDate(updatedAt), icon = "clock" },
			{ label = "INSTALLS", value = formatCount(installs), icon = "install" },
			{ label = "REACTIONS", value = formatCount(likes) .. "  /  " .. formatCount(dislikes), icon = "like" },
			{ label = "CREATED", value = formatDate(createdAt), icon = "calendar" },
			{ label = "PUBLISHED", value = formatDate(publishedAt), icon = "calendar" },
		}

		local statColumns = 4
		local statRows = math.ceil(#statCards / statColumns)

		local stats = UI.create("Frame", {
			Name = "Stats",
			Size = UDim2.new(1, 0, 0, statRows * STAT_HEIGHT + (statRows - 1) * STAT_GAP),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			LayoutOrder = 2,
		}, scroll)

		for index, stat in ipairs(statCards) do
			local column = (index - 1) % statColumns
			local statRow = math.floor((index - 1) / statColumns)

			local card = UI.card(
				stats,
				UDim2.new(column * 0.25, column * 2, 0, statRow * (STAT_HEIGHT + STAT_GAP)),
				UDim2.new(0.25, -6, 0, STAT_HEIGHT),
				{
					color = colors.surface,
					radius = CARD_RADIUS,
				}
			)

			card.Name = stat.label

			UI.label(
				card,
				stat.label,
				UDim2.fromOffset(14, 12),
				UDim2.new(1, -46, 0, 14),
				tokens.type.caption,
				colors.muted
			)

			addIcon(card, stat.icon, 0, 0, 14, colors.muted, nil)

			local statIcon = card:FindFirstChild("Icon_" .. stat.icon)

			if statIcon then
				statIcon.Position = UDim2.new(1, -28, 0, 12)
			end

			truncate(UI.label(card, stat.value, UDim2.fromOffset(14, 32), UDim2.new(1, -28, 0, 24), 17, colors.text))
		end

		local about = section("ABOUT", 3, nil, "about")

		local descriptionLabel =
			UI.label(about, tostring(description), UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 20), 14, colors.text)

		descriptionLabel.LayoutOrder = 1
		descriptionLabel.TextWrapped = true
		descriptionLabel.TextYAlignment = Enum.TextYAlignment.Top
		trySet(descriptionLabel, "LineHeight", 1.2)

		local function fitDescription()
			local height = descriptionLabel.TextBounds.Y

			if height and height > 0 then
				local bodyHeight = math.ceil(height) + 2

				descriptionLabel.Size = UDim2.new(1, 0, 0, bodyHeight)
				setBody(about, bodyHeight)
			end
		end

		pcall(function()
			descriptionLabel:GetPropertyChangedSignal("TextBounds"):Connect(fitDescription)
		end)

		fitDescription()

		local details = section("DETAILS", 4, nil, "details")

		local FIELD_HEIGHT, FIELD_GAP = 40, 12
		local FIELD_ICON_X = 22

		local fields = {
			{ "LICENSE", license, "license" },
			{ "ENGINE", engineConstraint, "engine" },
			{ "VISIBILITY", visibility, "eye" },
			{ "REVIEW", reviewStatus, "shield" },
			{ "NAMESPACE", namespace, "namespace" },
			{ "PACKAGE ID", packageId, "id" },
			{ "OWNER", owner, "user" },
			{ "REVIEWED BY", reviewedBy, "user" },
			{ "REVIEWED", formatDate(reviewedAt), "clock" },
			{ "SUBMITTED", formatDate(submittedAt), "calendar" },
			{ "DEPRECATED", deprecated and "Yes" or "No", deprecated and "warning" or "check" },
			{ "TYPE", string.upper(tostring(itemType)), "package" },
		}

		if reviewNote then
			table.insert(fields, { "REVIEW NOTE", reviewNote, "about" })
		end

		local fieldRows = math.ceil(#fields / 2)

		local grid = UI.create("Frame", {
			Name = "Fields",
			Size = UDim2.new(1, 0, 0, fieldRows * FIELD_HEIGHT + (fieldRows - 1) * FIELD_GAP),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			LayoutOrder = 1,
		}, details)

		setBody(details, fieldRows * FIELD_HEIGHT + (fieldRows - 1) * FIELD_GAP)

		for index, field in ipairs(fields) do
			local column = (index - 1) % 2
			local fieldRow = math.floor((index - 1) / 2)

			local cell = UI.create("Frame", {
				Name = field[1],
				Position = UDim2.new(column * 0.5, column * 10, 0, fieldRow * (FIELD_HEIGHT + FIELD_GAP)),
				Size = UDim2.new(0.5, -10, 0, FIELD_HEIGHT),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
			}, grid)

			local textX = 0

			if field[3] and addIcon(cell, field[3], 0, 13, 14, colors.muted) then
				textX = FIELD_ICON_X
			end

			UI.label(
				cell,
				field[1],
				UDim2.fromOffset(textX, 0),
				UDim2.new(1, -textX, 0, 14),
				tokens.type.caption,
				colors.muted
			)

			truncate(
				UI.label(
					cell,
					tostring(field[2]),
					UDim2.fromOffset(textX, 18),
					UDim2.new(1, -textX, 0, 20),
					tokens.type.small,
					colors.text
				)
			)
		end

		local depsCard =
			section("DEPENDENCIES", 5, #dependencies > 0 and tostring(#dependencies) or nil, "dependencies")

		if #dependencies == 0 then
			emptyNote(depsCard, "No dependencies.")
			setBody(depsCard, 18)
		else
			local shown = math.min(#dependencies, MAX_DEPENDENCIES)

			for index = 1, shown do
				local dependency = dependencies[index]
				local depName = tostring(dependency.name or dependency.Name or "unknown")
				local depNamespace = tostring(dependency.namespace or dependency.Namespace or "unknown")
				local constraint = tostring(dependency.constraint or dependency.Constraint or "*")

				local item = row(depsCard, index, ROW_HEIGHT)

				addIcon(item, "package", 12, (ROW_HEIGHT - 14) / 2, 14, colors.subtext)

				truncate(
					UI.label(
						item,
						depNamespace .. "/" .. depName,
						UDim2.fromOffset(34, 0),
						UDim2.new(1, -172, 1, 0),
						tokens.type.small,
						colors.text
					)
				)

				rightLabel(item, constraint, 110, 12, ROW_HEIGHT, tokens.type.caption, colors.subtext)
			end

			local extra = #dependencies > shown

			if extra then
				overflowNote(depsCard, string.format("+ %d more", #dependencies - shown), shown + 1)
			end

			setBody(depsCard, shown * ROW_HEIGHT + (shown - 1) * CARD_GAP + (extra and (CARD_GAP + 18) or 0))
		end

		local versionsCard = section("VERSIONS", 6, #versions > 0 and tostring(#versions) or nil, "versions")

		if #versions == 0 then
			emptyNote(versionsCard, "No published versions.")
			setBody(versionsCard, 18)
		else
			local shown = math.min(#versions, MAX_VERSIONS)

			for index = 1, shown do
				local item = versions[index]
				local yanked = item.yanked == true
				local versionText = "v" .. tostring(item.version or item.Version or "?")
				local dateText = formatDate(item.publishedAt or item.published_at)
				local sizeText = formatSize(item.size)
				local meta = tostring(dateText) .. (sizeText ~= "" and ("   " .. tostring(sizeText)) or "")

				local line = row(versionsCard, index, VERSION_ROW_HEIGHT)
				line.Name = versionText

				local iconColor = yanked and colors.muted or colors.subtext

				addIcon(line, "tag", 12, 8, 14, iconColor)

				local versionX = 12 + 14 + 8
				local versionWidth = #versionText * CHAR_WIDTH + 4

				UI.label(
					line,
					versionText,
					UDim2.fromOffset(versionX, 4),
					UDim2.fromOffset(versionWidth, 20),
					tokens.type.small,
					yanked and colors.muted or colors.text
				)

				if item == latest then
					UI.badge(line, "LATEST", UDim2.fromOffset(versionX + versionWidth + 8, 5), {
						color = colors.accent,
						textColor = colors.text,
						height = 18,
					})
				end

				local rightOffset = 12 + DOWNLOAD_WIDTH + 10

				if yanked then
					rightLabel(line, "YANKED", 54, rightOffset, 20, tokens.type.caption, colors.warning, 4)

					rightOffset += 62
				end

				rightLabel(line, meta, 170, rightOffset, 20, tokens.type.caption, colors.subtext, 4)

				local summary = firstValue(item.changelog, item.notes, item.releaseNotes, item.release_notes)

				if type(summary) ~= "string" then
					local parts = {}

					local versionEngine = firstValue(item.engineConstraint, item.engine_constraint)

					if versionEngine then
						table.insert(parts, "Engine " .. tostring(versionEngine))
					end

					table.insert(parts, #tableList(item.dependencies) .. " dependencies")

					local versionDownloads = firstValue(item.downloadCount, item.download_count, item.downloads)

					if versionDownloads then
						table.insert(parts, formatCount(versionDownloads) .. " downloads")
					end

					local checksum = firstValue(item.checksum, item.sha256, item.hash)

					if type(checksum) == "string" then
						table.insert(parts, "sha " .. string.sub(checksum, 1, 8))
					end

					summary = table.concat(parts, "   ·   ")
				end

				truncate(
					UI.label(
						line,
						summary,
						UDim2.fromOffset(versionX, 24),
						UDim2.new(1, -(versionX + 12 + DOWNLOAD_WIDTH + 10), 0, 14),
						tokens.type.caption,
						colors.muted
					)
				)

				local downloadButton, downloadLabel = UI.button(
					line,
					"Download",
					UDim2.new(1, -(12 + DOWNLOAD_WIDTH), 0.5, -DOWNLOAD_HEIGHT / 2),
					UDim2.fromOffset(DOWNLOAD_WIDTH, DOWNLOAD_HEIGHT),
					function()
						if options.onDownload then
							options.onDownload(plugin, data, item)
						end
					end,
					{
						color = yanked and colors.surface or colors.accent,
						hoverColor = colors.selectionHover,
						pressedColor = colors.pressed,
						textColor = yanked and colors.muted or colors.text,
						textSize = tokens.type.caption,
						radius = tokens.radius.sm,
						border = false,
						icon = ICONS.download,
						iconSize = 12,
						paddingX = 6,
						textY = 0,
						enabled = not yanked,
					}
				)

				downloadButton.Name = "Download"
				downloadLabel.Size = UDim2.new(1, -(12 + 12 + 6), 1, 0)
				downloadLabel.TextXAlignment = Enum.TextXAlignment.Center
			end

			local extra = #versions > shown

			if extra then
				overflowNote(versionsCard, string.format("+ %d older versions", #versions - shown), shown + 1)
			end

			setBody(
				versionsCard,
				shown * VERSION_ROW_HEIGHT + (shown - 1) * CARD_GAP + (extra and (CARD_GAP + 18) or 0)
			)
		end

		syncCanvas()
		scroll.CanvasPosition = Vector2.new(0, 0)
	end

	function controller:IsOpen()
		return state.open
	end

	function controller:Open(plugin)
		state.open = true
		state.plugin = plugin
		state.serial += 1

		local serial = state.serial

		setCrumb(plugin)

		if options.onOpen then
			options.onOpen(plugin)
		end

		page.Visible = true

		controller:Render(plugin, plugin.Raw)

		if not options.fetch then
			return
		end

		setCrumb(plugin, "LOADING")

		local called, ok, data = pcall(options.fetch, plugin)

		if serial ~= state.serial or not state.open then
			return
		end

		setCrumb(plugin)

		if called and ok then
			controller:Render(plugin, data)
		else
			UI.toast("Could not load package details.", { type = "error" })
		end
	end

	function controller:Close()
		if not state.open then
			return
		end

		state.open = false
		state.serial += 1

		page.Visible = false

		if options.onClose then
			options.onClose()
		end
	end

	function controller:Destroy()
		state.open = false
		state.serial += 1

		UI.forgetButtons(page)
		page:Destroy()
	end

	return controller
end

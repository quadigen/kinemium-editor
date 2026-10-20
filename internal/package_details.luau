if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local UI = require("@internal/editor_ui")

local tokens = UI.tokens
local colors = tokens.color

-- Layout constants -----------------------------------------------------------

local PAGE_PADDING = 20 -- space around the scrolling content
local SECTION_GAP = 14 -- vertical gap between cards
local CARD_PADDING = 18 -- inner padding of cards
local CARD_GAP = 10 -- gap between items inside a card
local CARD_RADIUS = 12

local TOPBAR_HEIGHT = 48
local BANNER_HEIGHT = 150
local FADE_HEIGHT = 80
local ICON_SIZE = 88
local ICON_OVERLAP = 44 -- how far the icon hangs over the banner
local IDENTITY_HEIGHT = 64
local INSTALL_WIDTH = 100

local STAT_HEIGHT = 68
local ROW_HEIGHT = 32
local PILL_HEIGHT = 22
local PILL_PADDING = 10
local CHAR_WIDTH = 8 -- rough monospace-ish estimate, only used for the LATEST badge offset

local MAX_TAGS = 6
local MAX_DEPENDENCIES = 12
local MAX_VERSIONS = 8

-- Helpers --------------------------------------------------------------------

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
	if type(value) == "number" then
		-- Treat very large numbers as milliseconds.
		local seconds = value > 100000000000 and math.floor(value / 1000) or value
		local ok, formatted = pcall(os.date, "%Y-%m-%d", seconds)

		if ok and formatted then
			return formatted
		end
	end

	local text = tostring(value or "")

	if text == "" then
		return "Unknown"
	end

	return string.sub(text, 1, 10)
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

-- Cosmetic-only properties: never let an unsupported one break the page.
local function trySet(object, property, value)
	pcall(function()
		object[property] = value
	end)
end

local function truncate(label)
	trySet(label, "TextTruncate", Enum.TextTruncate.AtEnd)

	return label
end

-- options:
--   setImage(imageLabel, url)   loads an image into an ImageLabel
--   fetch(plugin) -> ok, data   fetches full package details (may yield)
--   onOpen(plugin)              called when the page opens
--   onClose()                   called when the page closes (Back)
--   onInstall(plugin, data)     if given, an install button is shown
--   installText                 label for the install button
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

	-- Top bar -----------------------------------------------------------------

	local topbar = UI.frame(page, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, TOPBAR_HEIGHT), colors.panelRaised, 0)

	topbar.Name = "TopBar"
	topbar.ZIndex = 10

	UI.separator(topbar, UDim2.new(0, 0, 1, -1), UDim2.new(1, 0, 0, 1), colors.border)

	local backButton = UI.button(
		topbar,
		"←  Back",
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

	-- Scrolling body ----------------------------------------------------------

	local scroll = UI.create("ScrollingFrame", {
		Name = "Scroll",
		Position = UDim2.fromOffset(0, TOPBAR_HEIGHT),
		Size = UDim2.new(1, 0, 1, -TOPBAR_HEIGHT),
		BackgroundTransparency = 1,
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
		PaddingRight = UDim.new(0, PAGE_PADDING + 4), -- extra room for the scrollbar
		PaddingTop = UDim.new(0, PAGE_PADDING),
		PaddingBottom = UDim.new(0, PAGE_PADDING),
	}, scroll)

	local scrollLayout = UI.create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, SECTION_GAP),
	}, scroll)

	local keep = { [scrollPadding] = true, [scrollLayout] = true }

	local function syncCanvas()
		scroll.CanvasSize = UDim2.fromOffset(0, scrollLayout.AbsoluteContentSize.Y + PAGE_PADDING * 2)
	end

	scrollLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(syncCanvas)

	-- Builders ----------------------------------------------------------------

	local function pill(pillParent, text, order, config)
		config = config or {}

		local label = tostring(text or "")

		if label == "" then
			return nil
		end

		-- The pill sizes itself to its text so long tags never clip.
		local frame = UI.frame(
			pillParent,
			UDim2.fromOffset(0, 0),
			UDim2.fromOffset(0, PILL_HEIGHT),
			config.color or colors.surfaceAlt,
			7
		)

		frame.LayoutOrder = order
		frame.AutomaticSize = Enum.AutomaticSize.X

		UI.create("UIPadding", {
			PaddingLeft = UDim.new(0, PILL_PADDING),
			PaddingRight = UDim.new(0, PILL_PADDING),
		}, frame)

		if config.stroke then
			UI.stroke(frame, config.stroke, 1, 0.3)
		end

		local textLabel = UI.label(
			frame,
			label,
			UDim2.fromOffset(0, 0),
			UDim2.fromOffset(0, PILL_HEIGHT),
			tokens.type.caption,
			config.textColor or colors.text
		)

		textLabel.TextWrapped = false
		textLabel.AutomaticSize = Enum.AutomaticSize.X
		textLabel.TextXAlignment = Enum.TextXAlignment.Center

		return frame
	end

	local function section(title, order, rightText)
		local card = UI.card(scroll, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 0), {
			color = colors.surface,
			radius = CARD_RADIUS,
		})

		card.Name = title
		card.LayoutOrder = order
		card.AutomaticSize = Enum.AutomaticSize.Y

		UI.create("UIPadding", {
			PaddingLeft = UDim.new(0, CARD_PADDING),
			PaddingRight = UDim.new(0, CARD_PADDING),
			PaddingTop = UDim.new(0, CARD_PADDING),
			PaddingBottom = UDim.new(0, CARD_PADDING),
		}, card)

		UI.create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, CARD_GAP),
		}, card)

		local header = UI.create("Frame", {
			Name = "Header",
			Size = UDim2.new(1, 0, 0, 16),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			LayoutOrder = 0,
		}, card)

		UI.label(header, title, UDim2.fromOffset(0, 0), UDim2.new(0.6, 0, 1, 0), tokens.type.caption, colors.muted)

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

	local function rightLabel(rowParent, text, width, rightOffset, height, size, color)
		local label = UI.label(
			rowParent,
			text,
			UDim2.new(1, -(rightOffset + width), 0, 0),
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
		-- ClipsDescendants does not follow rounded corners, so images need their own.
		UI.create("UICorner", { CornerRadius = UDim.new(0, radius) }, image)
	end

	-- Rendering ---------------------------------------------------------------

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
		local updatedAt =
			firstValue(data.updatedAt, data.updated_at, data.publishedAt, data.published_at, plugin.UpdatedAt, "")
		local downloads = firstValue(
			data.acquisitionCount,
			data.acquisition_count,
			data.downloads,
			plugin.AcquisitionCount,
			plugin.Downloads,
			0
		)
		local rating = data.rating or plugin.Rating or {}
		local ratingAverage = type(rating) == "table" and tonumber(rating.average or rating.Average) or nil
		local ratingCount = type(rating) == "table" and tonumber(rating.count or rating.Count) or 0
		local iconUrl = firstValue(data.iconUrl, data.icon_url, assets.IconUrl)
		local bannerUrl = firstValue(data.bannerUrl, data.banner_url, data.thumbnailUrl, assets.ThumbnailUrl)

		-- Only keep well-formed entries so a bad record can't error the whole page.
		local versions = tableList(data.versions)

		local latest = nil

		for _, item in ipairs(versions) do
			if not item.yanked then
				latest = item
				break
			end
		end

		local dependencies = latest and tableList(latest.dependencies) or {}

		-- Hero ------------------------------------------------------------------

		local hero = UI.card(scroll, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 0), {
			color = colors.surface,
			radius = 14,
		})

		hero.Name = "Hero"
		hero.LayoutOrder = 1
		hero.AutomaticSize = Enum.AutomaticSize.Y
		hero.ClipsDescendants = true

		local stack = UI.create("Frame", {
			Name = "Stack",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, hero)

		UI.create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, stack)

		local banner = UI.frame(stack, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, BANNER_HEIGHT), colors.surfaceAlt, 14)

		banner.Name = "Banner"
		banner.LayoutOrder = 1
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
			Size = UDim2.new(1, 0, 0, IDENTITY_HEIGHT),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			LayoutOrder = 2,
		}, stack)

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

		local author = UI.label(
			identity,
			"by " .. tostring(namespace),
			UDim2.fromOffset(textX, 38),
			UDim2.new(1, -textRight, 0, 18),
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
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			LayoutOrder = 3,
		}, stack)

		UI.create("UIPadding", {
			PaddingLeft = UDim.new(0, CARD_PADDING),
			PaddingRight = UDim.new(0, CARD_PADDING),
			PaddingBottom = UDim.new(0, CARD_PADDING),
		}, pills)

		UI.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Wraps = true,
			Padding = UDim.new(0, 6),
			LinePadding = UDim.new(0, 6),
		}, pills)

		local approved = tostring(reviewStatus):lower() == "approved"
		local order = 0

		local function addPill(text, config)
			order += 1
			pill(pills, text, order, config)
		end

		addPill(string.upper(tostring(itemType)), { color = colors.accent, textColor = colors.text })
		addPill("v" .. tostring(version))
		addPill(string.upper(tostring(reviewStatus)), {
			textColor = approved and colors.success or colors.warning,
		})

		for index, tag in ipairs(tags) do
			if index > MAX_TAGS then
				break
			end

			addPill(tag, { color = colors.surface, stroke = colors.border, textColor = colors.subtext })
		end

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

		-- Stats -----------------------------------------------------------------

		local stats = UI.create("Frame", {
			Name = "Stats",
			Size = UDim2.new(1, 0, 0, STAT_HEIGHT),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			LayoutOrder = 2,
		}, scroll)

		-- 4 cells + 3 gaps of 10px: each cell is a quarter of the width minus its share of the gaps.
		UI.create("UIGridLayout", {
			CellSize = UDim2.new(0.25, -8, 0, STAT_HEIGHT),
			CellPadding = UDim2.fromOffset(10, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, stats)

		local ratingText = "No ratings"

		if ratingAverage then
			ratingText = string.format("%.1f  (%d)", ratingAverage, math.floor(ratingCount or 0))
		end

		local statCards = {
			{ label = "DOWNLOADS", value = formatCount(downloads) },
			{ label = "RATING", value = ratingText },
			{ label = "VERSION", value = "v" .. tostring(version) },
			{ label = "UPDATED", value = formatDate(updatedAt) },
		}

		for index, stat in ipairs(statCards) do
			local card = UI.card(stats, UDim2.fromOffset(0, 0), UDim2.fromOffset(100, STAT_HEIGHT), {
				color = colors.surface,
				radius = CARD_RADIUS,
			})

			card.Name = stat.label
			card.LayoutOrder = index

			UI.label(
				card,
				stat.label,
				UDim2.fromOffset(14, 12),
				UDim2.new(1, -28, 0, 14),
				tokens.type.caption,
				colors.muted
			)

			truncate(UI.label(card, stat.value, UDim2.fromOffset(14, 32), UDim2.new(1, -28, 0, 24), 17, colors.text))
		end

		-- About -----------------------------------------------------------------

		local about = section("ABOUT", 3)

		local descriptionLabel =
			UI.label(about, tostring(description), UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 0), 14, colors.text)

		descriptionLabel.LayoutOrder = 1
		descriptionLabel.TextWrapped = true
		descriptionLabel.AutomaticSize = Enum.AutomaticSize.Y
		descriptionLabel.TextYAlignment = Enum.TextYAlignment.Top
		trySet(descriptionLabel, "LineHeight", 1.2)

		-- Details ---------------------------------------------------------------

		local details = section("DETAILS", 4)

		local grid = UI.create("Frame", {
			Name = "Fields",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			LayoutOrder = 1,
		}, details)

		-- 2 columns with a 20px gutter.
		UI.create("UIGridLayout", {
			CellSize = UDim2.new(0.5, -10, 0, 40),
			CellPadding = UDim2.fromOffset(20, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, grid)

		local fields = {
			{ "LICENSE", license },
			{ "ENGINE", engineConstraint },
			{ "VISIBILITY", visibility },
			{ "REVIEW", reviewStatus },
			{ "NAMESPACE", namespace },
			{ "PACKAGE ID", packageId },
		}

		for index, field in ipairs(fields) do
			local cell = UI.create("Frame", {
				Name = field[1],
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				LayoutOrder = index,
			}, grid)

			UI.label(cell, field[1], UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 14), tokens.type.caption, colors.muted)

			truncate(
				UI.label(
					cell,
					tostring(field[2]),
					UDim2.fromOffset(0, 18),
					UDim2.new(1, 0, 0, 20),
					tokens.type.small,
					colors.text
				)
			)
		end

		-- Dependencies ----------------------------------------------------------

		local depsCard = section("DEPENDENCIES", 5, #dependencies > 0 and tostring(#dependencies) or nil)

		if #dependencies == 0 then
			emptyNote(depsCard, "No dependencies.")
		else
			local shown = math.min(#dependencies, MAX_DEPENDENCIES)

			for index = 1, shown do
				local dependency = dependencies[index]
				local depName = tostring(dependency.name or dependency.Name or "unknown")
				local depNamespace = tostring(dependency.namespace or dependency.Namespace or "unknown")
				local constraint = tostring(dependency.constraint or dependency.Constraint or "*")

				local item = row(depsCard, index, ROW_HEIGHT)

				truncate(
					UI.label(
						item,
						depNamespace .. "/" .. depName,
						UDim2.fromOffset(12, 0),
						UDim2.new(1, -150, 1, 0),
						tokens.type.small,
						colors.text
					)
				)

				rightLabel(item, constraint, 110, 12, ROW_HEIGHT, tokens.type.caption, colors.subtext)
			end

			if #dependencies > shown then
				overflowNote(depsCard, string.format("+ %d more", #dependencies - shown), shown + 1)
			end
		end

		-- Versions --------------------------------------------------------------

		local versionsCard = section("VERSIONS", 6, #versions > 0 and tostring(#versions) or nil)

		if #versions == 0 then
			emptyNote(versionsCard, "No published versions.")
		else
			local shown = math.min(#versions, MAX_VERSIONS)

			for index = 1, shown do
				local item = versions[index]
				local yanked = item.yanked == true
				local versionText = "v" .. tostring(item.version or item.Version or "?")
				local dateText = formatDate(item.publishedAt or item.published_at)
				local sizeText = formatSize(item.size)
				local meta = dateText .. (sizeText ~= "" and ("   " .. sizeText) or "")

				local line = row(versionsCard, index, ROW_HEIGHT)
				local versionWidth = #versionText * CHAR_WIDTH + 4

				UI.label(
					line,
					versionText,
					UDim2.fromOffset(12, 0),
					UDim2.fromOffset(versionWidth, ROW_HEIGHT),
					tokens.type.small,
					yanked and colors.muted or colors.text
				)

				if item == latest then
					UI.badge(line, "LATEST", UDim2.fromOffset(12 + versionWidth + 8, (ROW_HEIGHT - 18) / 2), {
						color = colors.accent,
						textColor = colors.text,
						height = 18,
					})
				end

				local rightOffset = 12

				if yanked then
					rightLabel(line, "YANKED", 54, rightOffset, ROW_HEIGHT, tokens.type.caption, colors.warning)

					rightOffset += 62
				end

				rightLabel(line, meta, 190, rightOffset, ROW_HEIGHT, tokens.type.caption, colors.subtext)
			end

			if #versions > shown then
				overflowNote(versionsCard, string.format("+ %d older versions", #versions - shown), shown + 1)
			end
		end

		syncCanvas()
		scroll.CanvasPosition = Vector2.new(0, 0)
	end

	-- Lifecycle ---------------------------------------------------------------

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

		-- Show what we already know straight away, then upgrade with the full record.
		controller:Render(plugin, plugin.Raw)

		if not options.fetch then
			return
		end

		setCrumb(plugin, "LOADING")

		local called, ok, data = pcall(options.fetch, plugin)

		-- The user may have gone back or opened something else while we were yielding.
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

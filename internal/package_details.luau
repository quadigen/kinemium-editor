if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local UI = require("@internal/editor_ui")

local tokens = UI.tokens
local colors = tokens.color

local BANNER_HEIGHT = 150
local FADE_HEIGHT = 80
local ICON_SIZE = 88

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

local function formatDate(value)
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

local function formatCount(value)
	local number = tonumber(value)

	if number == nil then
		return tostring(value or 0)
	end

	local text = tostring(math.floor(number))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()

	return (formatted:gsub("^,", ""))
end

local function formatSize(bytes)
	if type(bytes) ~= "number" then
		return ""
	end

	if bytes >= 1024 * 1024 then
		return string.format("%.1f MB", bytes / (1024 * 1024))
	end

	return string.format("%.1f KB", bytes / 1024)
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

	local MARGIN = tokens.space.lg
	local TOPBAR = 44

	local topbar = UI.frame(page, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, TOPBAR), colors.panelRaised, 0)

	topbar.Name = "TopBar"

	UI.separator(topbar, UDim2.new(0, 0, 1, -1), UDim2.new(1, 0, 0, 1), colors.border)

	local backButton = UI.button(topbar, "Back", UDim2.fromOffset(MARGIN, 8), UDim2.fromOffset(78, 28), function()
		controller:Close()
	end, {
		color = colors.surface,
		hoverColor = colors.hover,
		pressedColor = colors.pressed,
		textColor = colors.text,
		icon = "builtin://global-icons/chevron-down.svg",
		iconSize = 12,
		radius = tokens.radius.md,
	})

	backButton.Name = "Back"

	local crumb = UI.label(
		topbar,
		"MARKETPLACE",
		UDim2.fromOffset(MARGIN + 90, 0),
		UDim2.new(1, -(MARGIN * 2 + 90), 1, 0),
		tokens.type.caption,
		colors.subtext
	)

	crumb.Name = "Breadcrumb"

	-- Scrolling body ----------------------------------------------------------

	local scroll = UI.create("ScrollingFrame", {
		Name = "Scroll",
		Position = UDim2.fromOffset(0, TOPBAR),
		Size = UDim2.new(1, 0, 1, -TOPBAR),
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
		PaddingLeft = UDim.new(0, MARGIN),
		PaddingRight = UDim.new(0, MARGIN + 4),
		PaddingTop = UDim.new(0, MARGIN),
		PaddingBottom = UDim.new(0, MARGIN),
	}, scroll)

	local scrollLayout = UI.create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 12),
	}, scroll)

	local keep = { [scrollPadding] = true, [scrollLayout] = true }

	local function syncCanvas()
		scroll.CanvasSize = UDim2.fromOffset(0, scrollLayout.AbsoluteContentSize.Y + MARGIN * 2)
	end

	scrollLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(syncCanvas)

	-- Builders ----------------------------------------------------------------

	local function pill(pillParent, text, order, config)
		config = config or {}

		local label = tostring(text or "")

		if label == "" then
			return nil
		end

		local width = math.max(config.minWidth or 44, #label * 7 + 18)
		local frame = UI.frame(
			pillParent,
			UDim2.fromOffset(0, 0),
			UDim2.fromOffset(width, 22),
			config.color or colors.surfaceAlt,
			7
		)

		frame.LayoutOrder = order

		if config.stroke then
			UI.stroke(frame, config.stroke, 1, 0.3)
		end

		local text = UI.label(
			frame,
			label,
			UDim2.fromOffset(0, 0),
			UDim2.fromScale(1, 1),
			tokens.type.caption,
			config.textColor or colors.text
		)

		text.TextXAlignment = Enum.TextXAlignment.Center

		return frame
	end

	local function section(title, order, rightText)
		local card = UI.card(scroll, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 0), {
			color = colors.surface,
			radius = 12,
		})

		card.Name = title
		card.LayoutOrder = order
		card.AutomaticSize = Enum.AutomaticSize.Y

		UI.create("UIPadding", {
			PaddingLeft = UDim.new(0, 16),
			PaddingRight = UDim.new(0, 16),
			PaddingTop = UDim.new(0, 14),
			PaddingBottom = UDim.new(0, 14),
		}, card)

		UI.create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 8),
		}, card)

		local header = UI.create("Frame", {
			Name = "Header",
			Size = UDim2.new(1, 0, 0, 16),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			LayoutOrder = 0,
		}, card)

		UI.label(header, title, UDim2.fromOffset(0, 0), UDim2.new(0.6, 0, 1, 0), 10, colors.muted)

		if rightText and rightText ~= "" then
			local right =
				UI.label(header, rightText, UDim2.new(0.6, 0, 0, 0), UDim2.new(0.4, 0, 1, 0), 10, colors.muted)

			right.TextXAlignment = Enum.TextXAlignment.Right
		end

		return card
	end

	local function row(rowParent, order, height)
		local frame = UI.frame(rowParent, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, height), colors.surfaceAlt, 6)

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

	local function overflowNote(parent, text, order)
		local label = UI.label(parent, text, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 16), 11, colors.muted)

		label.LayoutOrder = order
		label.TextXAlignment = Enum.TextXAlignment.Center

		return label
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
		local versions = type(data.versions) == "table" and data.versions or {}

		local latest = nil

		for _, item in ipairs(versions) do
			if type(item) == "table" and not item.yanked then
				latest = item
				break
			end
		end

		local dependencies = latest and type(latest.dependencies) == "table" and latest.dependencies or {}

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
			Size = UDim2.new(1, 0, 0, 60),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			LayoutOrder = 2,
		}, stack)

		local actionWidth = options.onInstall and 108 or 0
		local textX = 16 + ICON_SIZE + 14

		local title = UI.label(
			identity,
			tostring(name),
			UDim2.fromOffset(textX, 6),
			UDim2.new(1, -(textX + 16 + actionWidth), 0, 28),
			22,
			colors.text
		)

		title.Name = "Title"

		local author = UI.label(
			identity,
			"by " .. tostring(namespace),
			UDim2.fromOffset(textX, 36),
			UDim2.new(1, -(textX + 16 + actionWidth), 0, 18),
			13,
			colors.accent
		)

		author.Name = "Author"

		if options.onInstall then
			local _, installLabel = UI.button(
				identity,
				options.installText or "Install",
				UDim2.new(1, -(actionWidth + 8), 0, 10),
				UDim2.fromOffset(actionWidth - 8, 32),
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
			PaddingLeft = UDim.new(0, 16),
			PaddingRight = UDim.new(0, 16),
			PaddingBottom = UDim.new(0, 16),
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
		addPill("v" .. tostring(version), { minWidth = 44 })
		addPill(string.upper(tostring(reviewStatus)), {
			minWidth = 62,
			textColor = approved and colors.success or colors.warning,
		})

		for index, tag in ipairs(tags) do
			if index > 6 then
				break
			end

			addPill(tostring(tag), { color = colors.surface, stroke = colors.border, textColor = colors.subtext })
		end

		local iconFrame = UI.frame(
			hero,
			UDim2.fromOffset(16, BANNER_HEIGHT - 44),
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
			Size = UDim2.new(1, 0, 0, 64),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			LayoutOrder = 2,
		}, scroll)

		UI.create("UIGridLayout", {
			CellSize = UDim2.new(0.25, -6, 0, 64),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, stats)

		local statCards = {
			{ label = "DOWNLOADS", value = formatCount(downloads) },
			{
				label = "RATING",
				value = ratingAverage and string.format("%.1f  (%d)", ratingAverage, ratingCount) or "No ratings",
			},
			{ label = "VERSION", value = "v" .. tostring(version) },
			{ label = "UPDATED", value = formatDate(updatedAt) },
		}

		for index, stat in ipairs(statCards) do
			local card = UI.card(stats, UDim2.fromOffset(0, 0), UDim2.fromOffset(100, 64), {
				color = colors.surface,
				radius = 12,
			})

			card.LayoutOrder = index

			UI.label(card, stat.label, UDim2.fromOffset(14, 11), UDim2.new(1, -28, 0, 14), 10, colors.muted)

			local value =
				UI.label(card, stat.value, UDim2.fromOffset(14, 29), UDim2.new(1, -28, 0, 24), 17, colors.text)
		end

		-- About -----------------------------------------------------------------

		local about = section("ABOUT", 3)

		local descriptionLabel =
			UI.label(about, tostring(description), UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 0), 14, colors.text)

		descriptionLabel.LayoutOrder = 1
		descriptionLabel.TextWrapped = true
		descriptionLabel.AutomaticSize = Enum.AutomaticSize.Y
		descriptionLabel.TextYAlignment = Enum.TextYAlignment.Top

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

		UI.create("UIGridLayout", {
			CellSize = UDim2.new(0.5, -8, 0, 36),
			CellPadding = UDim2.fromOffset(16, 8),
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

			UI.label(cell, field[1], UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 14), 9, colors.muted)

			local value = UI.label(
				cell,
				tostring(field[2]),
				UDim2.fromOffset(0, 15),
				UDim2.new(1, 0, 0, 18),
				tokens.type.small,
				colors.text
			)
		end

		-- Dependencies ----------------------------------------------------------

		local depsCard = section("DEPENDENCIES", 5, #dependencies > 0 and tostring(#dependencies) or nil)

		if #dependencies == 0 then
			local none = UI.label(
				depsCard,
				"No dependencies.",
				UDim2.fromOffset(0, 0),
				UDim2.new(1, 0, 0, 18),
				tokens.type.small,
				colors.subtext
			)

			none.LayoutOrder = 1
		else
			local shown = math.min(#dependencies, 12)

			for index = 1, shown do
				local dependency = dependencies[index]
				local depName = tostring(dependency.name or dependency.Name or "unknown")
				local depNamespace = tostring(dependency.namespace or dependency.Namespace or "unknown")
				local constraint = tostring(dependency.constraint or dependency.Constraint or "*")

				local item = row(depsCard, index, 28)

				local depLabel = UI.label(
					item,
					depNamespace .. "/" .. depName,
					UDim2.fromOffset(10, 0),
					UDim2.new(1, -140, 1, 0),
					tokens.type.small,
					colors.text
				)

				rightLabel(item, constraint, 110, 10, 28, tokens.type.caption, colors.subtext)
			end

			if #dependencies > shown then
				overflowNote(depsCard, string.format("+ %d more", #dependencies - shown), shown + 1)
			end
		end

		-- Versions --------------------------------------------------------------

		local versionsCard = section("VERSIONS", 6, #versions > 0 and tostring(#versions) or nil)

		if #versions == 0 then
			local none = UI.label(
				versionsCard,
				"No published versions.",
				UDim2.fromOffset(0, 0),
				UDim2.new(1, 0, 0, 18),
				tokens.type.small,
				colors.subtext
			)

			none.LayoutOrder = 1
		else
			local shown = math.min(#versions, 8)

			for index = 1, shown do
				local item = versions[index]
				local yanked = item.yanked == true
				local versionText = "v" .. tostring(item.version or item.Version or "?")
				local dateText = formatDate(item.publishedAt or item.published_at)
				local sizeText = formatSize(item.size)
				local meta = dateText .. (sizeText ~= "" and ("   " .. sizeText) or "")

				local line = row(versionsCard, index, 30)

				UI.label(
					line,
					versionText,
					UDim2.fromOffset(10, 0),
					UDim2.fromOffset(#versionText * 8 + 4, 30),
					tokens.type.small,
					yanked and colors.muted or colors.text
				)

				if item == latest then
					UI.badge(line, "LATEST", UDim2.fromOffset(10 + #versionText * 8 + 10, 6), {
						color = colors.accent,
						textColor = colors.text,
						height = 18,
					})
				end

				local rightOffset = 10

				if yanked then
					rightLabel(line, "YANKED", 54, rightOffset, 30, 9, colors.warning)

					rightOffset += 60
				end

				rightLabel(line, meta, 190, rightOffset, 30, tokens.type.caption, colors.subtext)
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

		crumb.Text = string.upper(
			"MARKETPLACE   /   " .. tostring(plugin.Slug or (plugin.Manifest and plugin.Manifest.Name) or "")
		)

		if options.onOpen then
			options.onOpen(plugin)
		end

		page.Visible = true

		-- Show what we already know straight away, then upgrade with the full record.
		controller:Render(plugin, plugin.Raw)

		if not options.fetch then
			return
		end

		local ok, data = options.fetch(plugin)

		if serial ~= state.serial or not state.open then
			return
		end

		if ok then
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

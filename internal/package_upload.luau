if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local UI = require("@internal/editor_ui")

local Packages = game:GetService("Packages")
local MatrixService = game:GetService("MatrixService")
local Project = game:GetService("Project")
local DialogService = game:GetService("DialogService")
local Filesystem = game:GetService("Filesystem")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local TYPES = { "package", "model", "plugin", "template", "tool" }
local VISIBILITIES = { "public", "unlisted", "private" }

local MIME_TYPES = {
	png = "image/png",
	jpg = "image/jpeg",
	jpeg = "image/jpeg",
	webp = "image/webp",
	gif = "image/gif",
}

local CHEVRON = "builtin://global-icons/chevron-down.svg"

local LABEL_HEIGHT = 15
local INPUT_OFFSET = LABEL_HEIGHT + 3
local INPUT_HEIGHT = 30
local COLUMN_GAP = 12
local CARD_PAD = 12
local ROW_HEIGHT = INPUT_OFFSET + INPUT_HEIGHT
local SECTION_GAP = 6
local HEADER_H = 30
local TOGGLE_H = 22
local BANNER_HEIGHT = 104
local ICON_SIZE = 104
local ANIM_SPEED = 14

local PackageUpload = {}

local function smooth(current, target, speed, dt)
	return current + (target - current) * (1 - math.exp(-speed * dt))
end

local function trim(text)
	return (string.gsub(tostring(text or ""), "^%s*(.-)%s*$", "%1"))
end

local function splitCSV(text)
	local result = {}
	local seen = {}

	for item in string.gmatch(tostring(text or "") .. ",", "([^,]*),") do
		item = trim(item)

		if item ~= "" and not seen[item] then
			seen[item] = true
			table.insert(result, item)
		end
	end

	return result
end

local function sanitizeName(text)
	local value = string.lower(trim(text))

	if value == "" then
		value = "package"
	end

	value = string.gsub(value, "[^%w%-%._]+", "-")
	value = string.gsub(value, "%-+", "-")
	value = string.gsub(value, "^%-+", "")
	value = string.gsub(value, "%-+$", "")

	if value == "" then
		value = "package"
	end

	return value
end

local function sessionNamespace()
	local session = MatrixService.Session

	if type(session) ~= "table" then
		return nil
	end

	local userId = session.userId

	if type(userId) ~= "string" then
		return nil
	end

	local localpart = string.match(userId, "^@([^:]+):")

	if localpart == nil or localpart == "" then
		return nil
	end

	return string.lower(localpart)
end

local function choiceLabel(value)
	return string.upper(string.sub(value, 1, 1)) .. string.sub(value, 2)
end

local function fileName(path)
	return (string.match(tostring(path or ""), "[^/\\]+$") or tostring(path or ""))
end

local function mimeType(path)
	local extension = string.lower(string.match(tostring(path or ""), "%.([%w]+)$") or "")
	return MIME_TYPES[extension] or "application/octet-stream"
end

local function responseError(response)
	local decodeOk, decoded = pcall(function()
		return HttpService:JSONDecode(response.Body)
	end)

	if decodeOk and type(decoded) == "table" then
		return tostring(decoded.error or decoded.message or decoded.detail or "HTTP " .. tostring(response.StatusCode))
	end

	return "HTTP " .. tostring(response.StatusCode)
end

local function uploadPackageImage(session, namespace, name, asset, path)
	if path == nil then
		return
	end

	local contentsOk, contents = pcall(function()
		return Filesystem:ReadFile(path)
	end)

	if not contentsOk or type(contents) ~= "string" or contents == "" then
		error("Could not read " .. fileName(path) .. ".", 0)
	end

	local url = string.format(
		"%s/_kinemium/v1/packages/%s/%s/%s",
		string.gsub(session.homeserver, "/+$", ""),
		namespace,
		name,
		asset
	)

	local requestOk, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "POST",
			Headers = {
				["Authorization"] = "Bearer " .. session.accessToken,
				["Content-Type"] = mimeType(path),
			},
			Body = contents,
		})
	end)

	if not requestOk or type(response) ~= "table" then
		error("Could not upload " .. asset .. " " .. fileName(path) .. ".", 0)
	end

	if not response.Success then
		error("Could not upload " .. asset .. " " .. fileName(path) .. ": " .. responseError(response), 0)
	end
end

local function notify(kind, title, message)
	UI.toast("package", {
		type = kind,
		title = title,
		message = message,
		duration = 7,
		backgroundTransparency = 0.4,
		blur = true,
	})
end

function PackageUpload.open(target)
	if target == nil then
		return
	end

	local tokens = UI.tokens
	local namespace = sessionNamespace()
	local project = Project:GetActiveProject()
	local projectName = nil

	if type(project) == "table" then
		projectName = project.Name
	end

	local defaultName = sanitizeName(target.Name or projectName or "package")

	local state = {
		packageType = "package",
		visibility = "public",
		banner = nil,
		icon = nil,
	}

	local fields = {}
	local sections = {}
	local sectionByName = {}
	local prompt
	local entrypointTouched = false

	local function isEnabled(name)
		local section = sectionByName[name]
		return section ~= nil and section.enabled
	end

	-- Dim and lock a text box when its section is disabled.
	local function setBoxEnabled(box, on)
		pcall(function()
			box.TextEditable = on
			box.TextTransparency = on and 0 or 0.5
		end)
	end

	----------------------------------------------------------------------
	-- Field helpers
	----------------------------------------------------------------------

	local function addTextBox(parent, labelText, value, placeholder, position, size, maxLength)
		UI.label(
			parent,
			labelText,
			position,
			UDim2.new(size.X.Scale, size.X.Offset, 0, LABEL_HEIGHT),
			tokens.type.caption,
			tokens.color.muted
		)

		return UI.input(
			parent,
			placeholder,
			UDim2.new(position.X.Scale, position.X.Offset, 0, position.Y.Offset + INPUT_OFFSET),
			size,
			{
				text = value,
				maxLength = maxLength,
			}
		)
	end

	local function addChoices(parent, labelText, initialValue, position, size, choices, onChanged)
		local colors = tokens.color

		UI.label(
			parent,
			labelText,
			position,
			UDim2.new(size.X.Scale, size.X.Offset, 0, LABEL_HEIGHT),
			tokens.type.caption,
			colors.muted
		)

		local row = UI.frame(
			parent,
			UDim2.new(position.X.Scale, position.X.Offset, 0, position.Y.Offset + INPUT_OFFSET),
			size,
			Color3.new(0, 0, 0)
		)
		row.BackgroundTransparency = 1

		local value = initialValue
		local entries = {}
		local count = #choices
		local gap = 4

		local function refresh()
			for choiceValue, entry in pairs(entries) do
				local selected = choiceValue == value

				entry.button.BackgroundColor3 = selected and colors.accent or colors.input
				entry.label.TextColor3 = selected and colors.text or colors.subtext
			end
		end

		for index, choiceValue in ipairs(choices) do
			local button, label = UI.button(
				row,
				choiceLabel(choiceValue),
				UDim2.new((index - 1) / count, (index - 1) * gap / count, 0, 0),
				UDim2.new(1 / count, -(count - 1) * gap / count, 0, INPUT_HEIGHT),
				function()
					value = choiceValue
					refresh()

					if onChanged then
						onChanged(choiceValue)
					end
				end,
				{
					color = colors.input,
					hoverColor = colors.hover,
					pressedColor = colors.pressed,
					textColor = colors.subtext,
					textSize = tokens.type.small,
					radius = tokens.radius.sm,
					border = true,
					borderColor = colors.border,
					borderTransparency = 0.15,
					paddingX = 4,
				}
			)

			entries[choiceValue] = { button = button, label = label }
		end

		refresh()
	end

	local function smallButton(parent, text, position, size, callback)
		return UI.button(parent, text, position, size, callback, {
			color = tokens.color.panelRaised,
			hoverColor = tokens.color.hover,
			pressedColor = tokens.color.pressed,
			textColor = tokens.color.text,
			textSize = tokens.type.small,
			radius = tokens.radius.sm,
			border = true,
			borderColor = tokens.color.border,
			borderTransparency = 0.2,
			paddingX = 4,
		})
	end

	local function addMediaPreview(parent, position, size, placeholderText, fit)
		local colors = tokens.color
		local frame = UI.frame(parent, position, size, colors.input, tokens.radius.sm)
		UI.stroke(frame, colors.border, 1, 0.2)

		local image = UI.image(frame, "", UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1))
		image.ZIndex = 1
		image.ScaleType = fit and Enum.ScaleType.Fit or Enum.ScaleType.Crop
		image.Visible = false

		local placeholder = UI.label(
			frame,
			placeholderText,
			UDim2.fromOffset(0, 0),
			UDim2.fromScale(1, 1),
			tokens.type.caption,
			colors.muted
		)
		placeholder.ZIndex = 2
		placeholder.TextXAlignment = Enum.TextXAlignment.Center
		placeholder.TextYAlignment = Enum.TextYAlignment.Center

		local click = UI.create("TextButton", {
			Name = "PickImage",
			Text = "",
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			ZIndex = 3,
		}, frame)

		return image, placeholder, click, frame
	end

	local refreshAll -- forward declaration (summaries depend on field state)

	local function chooseImage(preview, placeholder, nameLabel, key)
		if not isEnabled("Media") then
			return
		end

		local ok, path = pcall(function()
			return DialogService:PickFile()
		end)

		if not ok or type(path) ~= "string" or path == "" then
			return
		end

		state[key] = path
		preview.Image = path
		preview.Visible = true
		placeholder.Visible = false
		nameLabel.Text = fileName(path)
		nameLabel.TextColor3 = tokens.color.subtext
		refreshAll()
	end

	local function clearImage(preview, placeholder, nameLabel, key)
		if not isEnabled("Media") then
			return
		end

		state[key] = nil
		preview.Image = ""
		preview.Visible = false
		placeholder.Visible = true
		nameLabel.Text = "No file selected"
		nameLabel.TextColor3 = tokens.color.muted
		refreshAll()
	end

	----------------------------------------------------------------------
	-- Prompt (dialog shell + upload logic)
	----------------------------------------------------------------------

	local _, content, controller = UI.prompt({
		title = "Upload as Package",
		description = "Package the selected instance and publish it to the Kinemium marketplace.",
		size = UDim2.fromOffset(720, 700),
		padding = 16,
		scrollable = true,
		destroyOnClose = true,
		buttons = {
			{
				id = "cancel",
				text = "Cancel",
				role = "secondary",
			},
			{
				id = "upload",
				text = "Upload",
				role = "primary",
				callback = function(controller)
					local useMedia = isEnabled("Media")
					local useAbout = isEnabled("About")
					local useCompat = isEnabled("Compatibility")
					local useDeps = isEnabled("Dependencies")

					local name = trim(fields.name.Text)
					local version = trim(fields.version.Text)

					if name == "" then
						notify("error", "Missing package name", "Enter a name for the package.")
						return false
					end

					if not string.match(name, "^[%w%.%-_]+$") then
						notify(
							"error",
							"Invalid package name",
							"Use only letters, numbers, dots, dashes, and underscores."
						)
						return false
					end

					if version == "" or not string.match(version, "^[%w%.%+%-]+$") then
						notify("error", "Invalid version", "Use a version such as 1.0.0.")
						return false
					end

					-- Compatibility (falls back to defaults when disabled)
					local entrypoint = name .. ".kine"
					local engineConstraint = "*"

					if useCompat then
						local typedEntry = trim(fields.entrypoint.Text)
						local typedEngine = trim(fields.engineConstraint.Text)

						if entrypointTouched and typedEntry ~= "" then
							entrypoint = typedEntry
						end

						if typedEngine ~= "" then
							engineConstraint = typedEngine
						end

						if string.sub(entrypoint, 1, 1) == "/" or string.match(entrypoint, "%.%.%./") then
							notify("error", "Invalid entry point", "The entry point must be a relative path.")
							return false
						end
					end

					-- About
					local description = useAbout and trim(fields.description.Text) or ""
					local tags = useAbout and splitCSV(fields.tags.Text) or {}

					if #tags > 20 then
						notify("error", "Too many tags", "Use no more than 20 tags.")
						return false
					end

					-- Dependencies
					local dependencies = {}

					if useDeps then
						for _, entry in ipairs(splitCSV(fields.dependencies.Text)) do
							local dependencyNamespace, dependencyName, constraint =
								string.match(entry, "^([%w%.%-_]+)/([%w%.%-_]+)@(.+)$")

							if dependencyNamespace == nil then
								dependencyNamespace, dependencyName = string.match(entry, "^([%w%.%-_]+)/([%w%.%-_]+)$")
							end

							if dependencyNamespace == nil then
								notify(
									"error",
									"Invalid dependency",
									"Use namespace/name or namespace/name@constraint, separated by commas."
								)
								return false
							end

							dependencies[dependencyNamespace .. "/" .. dependencyName] = constraint or "*"
						end
					end

					local manifest = {
						name = name,
						version = version,
						entrypoint = entrypoint,
						engineConstraint = engineConstraint,
						type = state.packageType,
						visibility = state.visibility,
					}

					if description ~= "" then
						manifest.description = description
					end

					if #tags > 0 then
						manifest.tags = tags
					end

					if next(dependencies) ~= nil then
						manifest.dependencies = dependencies
					end

					local iconPath = useMedia and state.icon or nil
					local bannerPath = useMedia and state.banner or nil

					local session = MatrixService.Session

					if
						(iconPath ~= nil or bannerPath ~= nil)
						and (
							type(session) ~= "table"
							or type(session.homeserver) ~= "string"
							or type(session.accessToken) ~= "string"
						)
					then
						notify("error", "Not signed in", "Sign in before uploading package media.")
						return false
					end

					controller:SetBusy(true, "upload", "Uploading...")

					local callOk, ok, data, meta = pcall(function()
						return Packages:PublishInstance(target, manifest, {
							filename = name .. "-" .. version .. ".zip",
							contentType = "application/zip",
						})
					end)

					if not callOk then
						controller:SetBusy(false, "upload")
						notify("error", "Package upload failed", tostring(ok))
						return false
					end

					if not ok then
						controller:SetBusy(false, "upload")

						local detail = "The package could not be uploaded."

						if type(data) == "string" and data ~= "" then
							detail = data
						elseif type(data) == "table" then
							detail = tostring(data.message or data.error or data.detail or detail)
						end

						local status = meta and meta.status

						if status then
							detail = detail .. " (HTTP " .. tostring(status) .. ")"
						end

						notify("error", "Package upload failed", detail)
						return false
					end

					local package = type(data) == "table" and (data.package or data.Package) or nil
					local packageNamespace = package and (package.namespace or package.Namespace) or sessionNamespace()
					local packageName = package and (package.name or package.Name) or name
					local mediaWarnings = {}

					if packageNamespace then
						for _, entry in ipairs({
							{ asset = "icon", path = iconPath },
							{ asset = "banner", path = bannerPath },
						}) do
							if entry.path ~= nil then
								local uploadOk, uploadErr = pcall(
									uploadPackageImage,
									session,
									packageNamespace,
									packageName,
									entry.asset,
									entry.path
								)

								if not uploadOk then
									table.insert(mediaWarnings, tostring(uploadErr))
								end
							end
						end
					elseif iconPath ~= nil or bannerPath ~= nil then
						table.insert(mediaWarnings, "The package namespace was not returned by the server.")
					end

					local status = meta and meta.status
					local reviewStatus = package and (package.reviewStatus or package.ReviewStatus)

					local message = "Your package was submitted and is pending review."

					if reviewStatus then
						message = "Your package was submitted with status: " .. tostring(reviewStatus) .. "."
					elseif status then
						message = "Your package was submitted (HTTP " .. tostring(status) .. ")."
					end

					if #mediaWarnings > 0 then
						notify("error", "Package uploaded, media not applied", table.concat(mediaWarnings, " "))
					else
						notify("success", "Package uploaded", message)
					end

					return true
				end,
			},
		},
	})

	prompt = controller

	----------------------------------------------------------------------
	-- Accordion sections
	----------------------------------------------------------------------

	local cardWidth = 682
	local innerWidth = cardWidth - CARD_PAD * 2
	local leftWidth = math.floor((innerWidth - COLUMN_GAP) * 0.56)
	local rightWidth = innerWidth - COLUMN_GAP - leftWidth
	local rightX = CARD_PAD + leftWidth + COLUMN_GAP
	local fullWidth = UDim2.new(1, -CARD_PAD * 2, 0, INPUT_HEIGHT)
	local bannerWidth = cardWidth - CARD_PAD * 2 - ICON_SIZE - COLUMN_GAP

	-- Y origin of field content inside an optional section's body (below the toggle row).
	local OPTIONAL_ORIGIN = CARD_PAD + TOGGLE_H + 10

	local function createSection(def)
		local frame = UI.frame(
			content,
			UDim2.fromOffset(0, 0),
			UDim2.new(1, -6, 0, HEADER_H),
			tokens.color.panelRaised,
			tokens.radius.md
		)
		frame.Name = def.name
		frame.ClipsDescendants = true
		UI.stroke(frame, tokens.color.borderStrong, 1, 0.5)

		local section = {
			def = def,
			frame = frame,
			enabled = true,
			expanded = def.expanded == true,
			current = def.expanded and (HEADER_H + def.bodyHeight) or HEADER_H,
			lastHeight = -1,
			bodyHeight = def.bodyHeight,
			onEnabled = nil,
		}

		sections[#sections + 1] = section
		sectionByName[def.name] = section

		local header, headerLabel = UI.button(
			frame,
			def.name,
			UDim2.fromOffset(0, 0),
			UDim2.new(1, 0, 0, HEADER_H),
			function()
				section.expanded = not section.expanded
			end,
			{
				color = tokens.color.panelRaised,
				radius = tokens.radius.md,
				border = false,
				textColor = tokens.color.text,
			}
		)
		header.Name = def.name .. "Header"
		headerLabel.Position = UDim2.fromOffset(12, 0)
		headerLabel.Size = UDim2.new(0, 140, 1, 0)
		headerLabel.TextXAlignment = Enum.TextXAlignment.Left
		headerLabel.TextYAlignment = Enum.TextYAlignment.Center
		section.headerLabel = headerLabel

		local summary = UI.label(
			header,
			"",
			UDim2.new(0, 150, 0, 0),
			UDim2.new(1, -150 - 34, 0, HEADER_H),
			tokens.type.caption,
			tokens.color.muted
		)
		summary.TextXAlignment = Enum.TextXAlignment.Right
		summary.TextYAlignment = Enum.TextYAlignment.Center
		section.summary = summary

		section.chevron = UI.image(header, CHEVRON, UDim2.new(1, -22, 0.5, -6), UDim2.fromOffset(12, 12))
		section.chevron.Rotation = section.expanded and 0 or -90

		local body =
			UI.frame(frame, UDim2.fromOffset(0, HEADER_H), UDim2.new(1, 0, 0, def.bodyHeight), tokens.color.panel)
		body.Name = "Body"
		body.BackgroundTransparency = 1
		body.Visible = section.expanded
		section.body = body

		UI.separator(body, UDim2.fromOffset(6, 0), UDim2.new(1, -12, 0, 1), tokens.color.surface)

		if def.optional then
			local _, checkbox = UI.checkbox(
				body,
				"Include in upload",
				UDim2.fromOffset(CARD_PAD, CARD_PAD),
				true,
				function(value)
					section.enabled = value
					if section.onEnabled then
						section.onEnabled(value)
					end
					refreshAll()
				end,
				{ size = UDim2.new(1, -CARD_PAD * 2, 0, TOGGLE_H) }
			)
			section.checkbox = checkbox
		end

		return section, body
	end

	-- Identity ----------------------------------------------------------
	do
		local section, body = createSection({
			name = "Identity",
			bodyHeight = CARD_PAD * 2 + ROW_HEIGHT,
			expanded = true,
		})

		fields.name = addTextBox(
			body,
			"Name",
			defaultName,
			"my-package",
			UDim2.fromOffset(CARD_PAD, CARD_PAD),
			UDim2.fromOffset(leftWidth, INPUT_HEIGHT),
			64
		)
		fields.version = addTextBox(
			body,
			"Version",
			"1.0.0",
			"1.0.0",
			UDim2.fromOffset(rightX, CARD_PAD),
			UDim2.fromOffset(rightWidth, INPUT_HEIGHT),
			32
		)

		section.summaryFn = function()
			return string.format("%s  v%s", trim(fields.name.Text), trim(fields.version.Text))
		end
	end

	-- Listing -----------------------------------------------------------
	do
		local section, body = createSection({
			name = "Listing",
			bodyHeight = CARD_PAD * 2 + ROW_HEIGHT,
			expanded = true,
		})

		addChoices(
			body,
			"Type",
			state.packageType,
			UDim2.fromOffset(CARD_PAD, CARD_PAD),
			UDim2.fromOffset(leftWidth, INPUT_HEIGHT),
			TYPES,
			function(value)
				state.packageType = value
				refreshAll()
			end
		)
		addChoices(
			body,
			"Visibility",
			state.visibility,
			UDim2.fromOffset(rightX, CARD_PAD),
			UDim2.fromOffset(rightWidth, INPUT_HEIGHT),
			VISIBILITIES,
			function(value)
				state.visibility = value
				refreshAll()
			end
		)

		section.summaryFn = function()
			return choiceLabel(state.packageType) .. " | " .. choiceLabel(state.visibility)
		end
	end

	-- Media -------------------------------------------------------------
	do
		local oy = OPTIONAL_ORIGIN
		local section, body = createSection({
			name = "Media",
			optional = true,
			bodyHeight = oy + 168,
		})

		local bannerImage, bannerPlaceholder, bannerClick, bannerFrame = addMediaPreview(
			body,
			UDim2.fromOffset(CARD_PAD, oy),
			UDim2.fromOffset(bannerWidth, BANNER_HEIGHT),
			"Banner",
			false
		)
		local iconImage, iconPlaceholder, iconClick, iconFrame = addMediaPreview(
			body,
			UDim2.fromOffset(cardWidth - CARD_PAD - ICON_SIZE, oy),
			UDim2.fromOffset(ICON_SIZE, ICON_SIZE),
			"Icon",
			true
		)

		local bannerName = UI.label(
			body,
			"No file selected",
			UDim2.fromOffset(CARD_PAD, oy + BANNER_HEIGHT + 34),
			UDim2.fromOffset(bannerWidth, LABEL_HEIGHT),
			tokens.type.caption,
			tokens.color.muted
		)
		bannerName.TextXAlignment = Enum.TextXAlignment.Left

		local iconName = UI.label(
			body,
			"No file selected",
			UDim2.fromOffset(cardWidth - CARD_PAD - ICON_SIZE, oy + BANNER_HEIGHT + 34),
			UDim2.fromOffset(ICON_SIZE, LABEL_HEIGHT),
			tokens.type.caption,
			tokens.color.muted
		)
		iconName.TextXAlignment = Enum.TextXAlignment.Left

		smallButton(
			body,
			"Choose banner",
			UDim2.fromOffset(CARD_PAD, oy + BANNER_HEIGHT + 4),
			UDim2.fromOffset(120, 26),
			function()
				chooseImage(bannerImage, bannerPlaceholder, bannerName, "banner")
			end
		)
		smallButton(
			body,
			"Clear",
			UDim2.fromOffset(CARD_PAD + 126, oy + BANNER_HEIGHT + 4),
			UDim2.fromOffset(54, 26),
			function()
				clearImage(bannerImage, bannerPlaceholder, bannerName, "banner")
			end
		)

		local iconButtonX = cardWidth - CARD_PAD - ICON_SIZE

		smallButton(
			body,
			"Choose",
			UDim2.fromOffset(iconButtonX, oy + BANNER_HEIGHT + 4),
			UDim2.fromOffset(60, 26),
			function()
				chooseImage(iconImage, iconPlaceholder, iconName, "icon")
			end
		)
		smallButton(
			body,
			"Clear",
			UDim2.fromOffset(iconButtonX + 64, oy + BANNER_HEIGHT + 4),
			UDim2.fromOffset(40, 26),
			function()
				clearImage(iconImage, iconPlaceholder, iconName, "icon")
			end
		)

		bannerClick.MouseButton1Click:Connect(function()
			chooseImage(bannerImage, bannerPlaceholder, bannerName, "banner")
		end)
		iconClick.MouseButton1Click:Connect(function()
			chooseImage(iconImage, iconPlaceholder, iconName, "icon")
		end)

		section.onEnabled = function(on)
			local transparency = on and 0 or 0.6
			pcall(function()
				bannerImage.ImageTransparency = transparency
				iconImage.ImageTransparency = transparency
				bannerPlaceholder.TextTransparency = on and 0 or 0.5
				iconPlaceholder.TextTransparency = on and 0 or 0.5
				bannerFrame.BackgroundTransparency = on and 0 or 0.5
				iconFrame.BackgroundTransparency = on and 0 or 0.5
				bannerName.TextTransparency = on and 0 or 0.5
				iconName.TextTransparency = on and 0 or 0.5
			end)
		end

		section.summaryFn = function()
			local parts = {}
			if state.banner then
				table.insert(parts, "Banner")
			end
			if state.icon then
				table.insert(parts, "Icon")
			end
			return #parts > 0 and table.concat(parts, " + ") or "None selected"
		end
	end

	-- About -------------------------------------------------------------
	do
		local oy = OPTIONAL_ORIGIN
		local section, body = createSection({
			name = "About",
			optional = true,
			bodyHeight = oy + ROW_HEIGHT * 2 + 10 + CARD_PAD,
		})

		fields.description = addTextBox(
			body,
			"Description",
			"",
			"What does this package do?",
			UDim2.fromOffset(CARD_PAD, oy),
			fullWidth,
			512
		)
		fields.tags = addTextBox(
			body,
			"Tags",
			"",
			"tool, utility, ui",
			UDim2.fromOffset(CARD_PAD, oy + ROW_HEIGHT + 10),
			fullWidth,
			256
		)

		section.onEnabled = function(on)
			setBoxEnabled(fields.description, on)
			setBoxEnabled(fields.tags, on)
		end

		section.summaryFn = function()
			local parts = {}
			if trim(fields.description.Text) ~= "" then
				table.insert(parts, "Description")
			end
			local tagCount = #splitCSV(fields.tags.Text)
			if tagCount > 0 then
				table.insert(parts, tagCount .. (tagCount == 1 and " tag" or " tags"))
			end
			return #parts > 0 and table.concat(parts, ", ") or "Empty"
		end
	end

	-- Compatibility -----------------------------------------------------
	do
		local oy = OPTIONAL_ORIGIN
		local section, body = createSection({
			name = "Compatibility",
			optional = true,
			bodyHeight = oy + ROW_HEIGHT + CARD_PAD,
		})

		fields.entrypoint = addTextBox(
			body,
			"Entry point",
			defaultName .. ".kine",
			"my-package.kine",
			UDim2.fromOffset(CARD_PAD, oy),
			UDim2.fromOffset(leftWidth, INPUT_HEIGHT),
			128
		)
		fields.engineConstraint = addTextBox(
			body,
			"Engine constraint",
			"*",
			"*",
			UDim2.fromOffset(rightX, oy),
			UDim2.fromOffset(rightWidth, INPUT_HEIGHT),
			64
		)
		fields.entrypoint.TextChanged:Connect(function()
			entrypointTouched = true
		end)

		section.onEnabled = function(on)
			setBoxEnabled(fields.entrypoint, on)
			setBoxEnabled(fields.engineConstraint, on)
		end

		section.summaryFn = function()
			local entry = entrypointTouched and trim(fields.entrypoint.Text) or ""
			if entry == "" then
				entry = trim(fields.name.Text) .. ".kine"
			end
			return entry
		end
	end

	-- Dependencies ------------------------------------------------------
	do
		local oy = OPTIONAL_ORIGIN
		local section, body = createSection({
			name = "Dependencies",
			optional = true,
			bodyHeight = oy + ROW_HEIGHT + CARD_PAD,
		})

		fields.dependencies = addTextBox(
			body,
			"Dependencies",
			"",
			"namespace/package@1.0.0, namespace/other",
			UDim2.fromOffset(CARD_PAD, oy),
			fullWidth,
			512
		)

		section.onEnabled = function(on)
			setBoxEnabled(fields.dependencies, on)
		end

		section.summaryFn = function()
			local count = #splitCSV(fields.dependencies.Text)
			if count == 0 then
				return "None"
			end
			return count .. (count == 1 and " dependency" or " dependencies")
		end
	end

	----------------------------------------------------------------------
	-- Summaries / state refresh
	----------------------------------------------------------------------

	refreshAll = function()
		for _, section in ipairs(sections) do
			local on = section.enabled

			if on then
				local ok, text = pcall(section.summaryFn)
				section.summary.Text = ok and text or ""
			else
				section.summary.Text = "Disabled"
			end

			section.headerLabel.TextColor3 = on and tokens.color.text or tokens.color.muted
			section.summary.TextColor3 = on and tokens.color.muted or tokens.color.warning
		end
	end

	for _, box in pairs(fields) do
		box.TextChanged:Connect(function()
			refreshAll()
		end)
	end

	refreshAll()

	----------------------------------------------------------------------
	-- Footer labels (positioned after the last section)
	----------------------------------------------------------------------

	local sourceLabel = UI.label(
		content,
		"Source: " .. tostring(target.Name) .. " (" .. tostring(target.ClassName) .. ")",
		UDim2.fromOffset(2, 0),
		UDim2.new(1, -6, 0, LABEL_HEIGHT),
		tokens.type.caption,
		tokens.color.muted
	)
	sourceLabel.TextXAlignment = Enum.TextXAlignment.Left

	local namespaceLabel = UI.label(
		content,
		namespace and ("Publishing as namespace: " .. namespace) or "Namespace: taken from your Kinemium session",
		UDim2.fromOffset(2, 0),
		UDim2.new(1, -6, 0, LABEL_HEIGHT),
		tokens.type.caption,
		tokens.color.muted
	)
	namespaceLabel.TextXAlignment = Enum.TextXAlignment.Left

	----------------------------------------------------------------------
	-- Layout + animation
	----------------------------------------------------------------------

	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		if not UI.isAlive(content) then
			connection:Disconnect()
			return
		end

		local y = 0

		for _, section in ipairs(sections) do
			local target = section.expanded and (HEADER_H + section.bodyHeight) or HEADER_H

			section.current = smooth(section.current, target, ANIM_SPEED, dt)

			if math.abs(section.current - target) < 0.5 then
				section.current = target
			end

			local height = math.floor(section.current + 0.5)

			if height ~= section.lastHeight then
				section.lastHeight = height
				section.frame.Size = UDim2.new(1, -6, 0, height)

				local alpha = math.clamp((section.current - HEADER_H) / section.bodyHeight, 0, 1)
				section.chevron.Rotation = -90 * (1 - alpha)
				section.body.Visible = section.current > HEADER_H + 1
			end

			section.frame.Position = UDim2.fromOffset(0, y)
			y += section.current + SECTION_GAP
		end

		y += 6
		sourceLabel.Position = UDim2.fromOffset(2, y)
		namespaceLabel.Position = UDim2.fromOffset(2, y + LABEL_HEIGHT + 3)

		content.CanvasSize = UDim2.fromOffset(0, y + LABEL_HEIGHT * 2 + 20)
	end)

	content.Destroying:Connect(function()
		if connection then
			connection:Disconnect()
		end
	end)

	return prompt
end

return PackageUpload

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

local TYPES = { "package", "model", "plugin", "template", "tool" }
local VISIBILITIES = { "public", "unlisted", "private" }

local MIME_TYPES = {
	png = "image/png",
	jpg = "image/jpeg",
	jpeg = "image/jpeg",
	webp = "image/webp",
	gif = "image/gif",
	bmp = "image/bmp",
	svg = "image/svg+xml",
}

local LABEL_HEIGHT = 15
local INPUT_OFFSET = LABEL_HEIGHT + 3
local INPUT_HEIGHT = 30
local COLUMN_GAP = 12
local CARD_PAD = 12
local ROW_HEIGHT = INPUT_OFFSET + INPUT_HEIGHT
local SECTION_GAP = 14
local SECTION_TITLE_HEIGHT = 16
local SECTION_TOP = SECTION_TITLE_HEIGHT + 6
local BANNER_HEIGHT = 104
local ICON_SIZE = 104

local PackageUpload = {}

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

local function uploadImage(path)
	if path == nil then
		return nil
	end

	local contentsOk, contents = pcall(function()
		return Filesystem:ReadFile(path)
	end)

	if not contentsOk or type(contents) ~= "string" or contents == "" then
		error("Could not read " .. fileName(path) .. ".", 0)
	end

	local session = MatrixService.Session

	if
		type(session) ~= "table"
		or type(session.homeserver) ~= "string"
		or type(session.accessToken) ~= "string"
	then
		error("Sign in before uploading media.", 0)
	end

	local requestOk, response = pcall(function()
		return HttpService:RequestAsync({
			Url = string.gsub(session.homeserver, "/+$", "") .. "/_matrix/media/v3/upload",
			Method = "POST",
			Headers = {
				["Authorization"] = "Bearer " .. session.accessToken,
				["Content-Type"] = mimeType(path),
			},
			Body = contents,
		})
	end)

	if not requestOk or type(response) ~= "table" then
		error("Could not upload " .. fileName(path) .. ".", 0)
	end

	if not response.Success then
		error("Could not upload " .. fileName(path) .. " (HTTP " .. tostring(response.StatusCode) .. ").", 0)
	end

	local decodeOk, decoded = pcall(function()
		return HttpService:JSONDecode(response.Body)
	end)

	local mxc = decodeOk and type(decoded) == "table" and decoded.content_uri

	if type(mxc) ~= "string" or mxc == "" then
		error("The media upload returned no content URI.", 0)
	end

	return MatrixService:MxcToHttp(session.homeserver, mxc)
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
	local prompt
	local entrypointTouched = false

	local function addTextBox(parent, labelText, value, placeholder, position, size, maxLength)
		UI.label(
			parent,
			labelText,
			position,
			UDim2.new(size.X.Scale, size.X.Offset, 0, LABEL_HEIGHT),
			UI.tokens.type.caption,
			UI.tokens.color.muted
		)

		return UI.input(parent, placeholder, UDim2.new(position.X.Scale, position.X.Offset, 0, position.Y.Offset + INPUT_OFFSET), size, {
			text = value,
			maxLength = maxLength,
		})
	end

	local function addChoices(parent, labelText, initialValue, position, size, choices, onChanged)
		local colors = UI.tokens.color

		UI.label(
			parent,
			labelText,
			position,
			UDim2.new(size.X.Scale, size.X.Offset, 0, LABEL_HEIGHT),
			UI.tokens.type.caption,
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
					textSize = UI.tokens.type.small,
					radius = UI.tokens.radius.sm,
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

	local function addSection(parent, y, title, height)
		local colors = UI.tokens.color

		local heading = UI.label(
			parent,
			title,
			UDim2.fromOffset(2, y),
			UDim2.new(1, -4, 0, SECTION_TITLE_HEIGHT),
			UI.tokens.type.caption,
			colors.muted
		)
		heading.TextXAlignment = Enum.TextXAlignment.Left

		local card = UI.card(parent, UDim2.fromOffset(0, y + SECTION_TOP), UDim2.new(1, -6, 0, height), {
			color = colors.surface,
			radius = UI.tokens.radius.md,
			border = true,
			borderColor = colors.border,
			borderTransparency = 0.25,
			shadow = true,
			shadowBlur = 8,
			shadowOffset = 2,
			shadowTransparency = 0.8,
		})

		return card, y + SECTION_TOP + height + SECTION_GAP
	end

	local function smallButton(parent, text, position, size, callback)
		return UI.button(parent, text, position, size, callback, {
			color = UI.tokens.color.panelRaised,
			hoverColor = UI.tokens.color.hover,
			pressedColor = UI.tokens.color.pressed,
			textColor = UI.tokens.color.text,
			textSize = UI.tokens.type.small,
			radius = UI.tokens.radius.sm,
			border = true,
			borderColor = UI.tokens.color.border,
			borderTransparency = 0.2,
			paddingX = 4,
		})
	end

	local function addMediaPreview(parent, position, size, placeholderText, fit)
		local colors = UI.tokens.color
		local frame = UI.frame(parent, position, size, colors.input, UI.tokens.radius.sm)
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
			UI.tokens.type.caption,
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

		return image, placeholder, click
	end

	local function chooseImage(preview, placeholder, nameLabel, key)
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
		nameLabel.TextColor3 = UI.tokens.color.subtext
	end

	local function clearImage(preview, placeholder, nameLabel, key)
		state[key] = nil
		preview.Image = ""
		preview.Visible = false
		placeholder.Visible = true
		nameLabel.Text = "No file selected"
		nameLabel.TextColor3 = UI.tokens.color.muted
	end

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
					local name = trim(fields.name.Text)
					local version = trim(fields.version.Text)
					local description = trim(fields.description.Text)
					local entrypoint = trim(fields.entrypoint.Text)
					local engineConstraint = trim(fields.engineConstraint.Text)

					if name == "" then
						notify("error", "Missing package name", "Enter a name for the package.")
						return false
					end

					if not string.match(name, "^[%w%.%-_]+$") then
						notify("error", "Invalid package name", "Use only letters, numbers, dots, dashes, and underscores.")
						return false
					end

					if version == "" or not string.match(version, "^[%w%.%+%-]+$") then
						notify("error", "Invalid version", "Use a version such as 1.0.0.")
						return false
					end

					if not entrypointTouched or entrypoint == "" then
						entrypoint = name .. ".kine"
					end

					if string.sub(entrypoint, 1, 1) == "/" or string.match(entrypoint, "%.%.%./") then
						notify("error", "Invalid entry point", "The entry point must be a relative path.")
						return false
					end

					local tags = splitCSV(fields.tags.Text)

					if #tags > 20 then
						notify("error", "Too many tags", "Use no more than 20 tags.")
						return false
					end

					local dependencies = {}

					for _, entry in ipairs(splitCSV(fields.dependencies.Text)) do
						local dependencyNamespace, dependencyName, constraint =
							string.match(entry, "^([%w%.%-_]+)/([%w%.%-_]+)@(.+)$")

						if dependencyNamespace == nil then
							dependencyNamespace, dependencyName =
								string.match(entry, "^([%w%.%-_]+)/([%w%.%-_]+)$")
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

					local manifest = {
						name = name,
						version = version,
						entrypoint = entrypoint,
						engineConstraint = engineConstraint ~= "" and engineConstraint or "*",
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

					controller:SetBusy(true, "upload", "Uploading...")

					local iconUrl = nil
					local bannerUrl = nil

					if state.icon ~= nil then
						local uploadOk, result = pcall(uploadImage, state.icon)

						if not uploadOk then
							controller:SetBusy(false, "upload")
							notify("error", "Icon upload failed", tostring(result))
							return false
						end

						iconUrl = result
					end

					if state.banner ~= nil then
						local uploadOk, result = pcall(uploadImage, state.banner)

						if not uploadOk then
							controller:SetBusy(false, "upload")
							notify("error", "Banner upload failed", tostring(result))
							return false
						end

						bannerUrl = result
					end

					if iconUrl ~= nil then
						manifest.icon = iconUrl
					end

					if bannerUrl ~= nil then
						manifest.thumbnail = bannerUrl
					end

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

					local status = meta and meta.status
					local reviewStatus = nil

					if type(data) == "table" then
						reviewStatus = data.reviewStatus or data.ReviewStatus or data.status or data.Status
					end

					local message = "Your package was submitted and is pending review."

					if reviewStatus then
						message = "Your package was submitted with status: " .. tostring(reviewStatus) .. "."
					elseif status then
						message = "Your package was submitted (HTTP " .. tostring(status) .. ")."
					end

					notify("success", "Package uploaded", message)
					return true
				end,
			},
		},
	})

	prompt = controller

	local cardWidth = 682
	local innerWidth = cardWidth - CARD_PAD * 2
	local leftWidth = math.floor((innerWidth - COLUMN_GAP) * 0.56)
	local rightWidth = innerWidth - COLUMN_GAP - leftWidth
	local rightX = CARD_PAD + leftWidth + COLUMN_GAP
	local fullWidth = UDim2.new(1, -CARD_PAD * 2, 0, INPUT_HEIGHT)
	local bannerWidth = cardWidth - CARD_PAD * 2 - ICON_SIZE - COLUMN_GAP

	local card
	local y = 0

	card, y = addSection(content, y, "Identity", CARD_PAD * 2 + ROW_HEIGHT)
	fields.name = addTextBox(card, "Name", defaultName, "my-package", UDim2.fromOffset(CARD_PAD, CARD_PAD), UDim2.fromOffset(leftWidth, INPUT_HEIGHT), 64)
	fields.version = addTextBox(card, "Version", "1.0.0", "1.0.0", UDim2.fromOffset(rightX, CARD_PAD), UDim2.fromOffset(rightWidth, INPUT_HEIGHT), 32)

	card, y = addSection(content, y, "Listing", CARD_PAD * 2 + ROW_HEIGHT)
	addChoices(card, "Type", state.packageType, UDim2.fromOffset(CARD_PAD, CARD_PAD), UDim2.fromOffset(leftWidth, INPUT_HEIGHT), TYPES, function(value)
		state.packageType = value
	end)
	addChoices(card, "Visibility", state.visibility, UDim2.fromOffset(rightX, CARD_PAD), UDim2.fromOffset(rightWidth, INPUT_HEIGHT), VISIBILITIES, function(value)
		state.visibility = value
	end)

	card, y = addSection(content, y, "Media", 180)

	local bannerImage, bannerPlaceholder, bannerClick = addMediaPreview(
		card,
		UDim2.fromOffset(CARD_PAD, CARD_PAD),
		UDim2.fromOffset(bannerWidth, BANNER_HEIGHT),
		"Banner",
		false
	)
	local iconImage, iconPlaceholder, iconClick = addMediaPreview(
		card,
		UDim2.fromOffset(cardWidth - CARD_PAD - ICON_SIZE, CARD_PAD),
		UDim2.fromOffset(ICON_SIZE, ICON_SIZE),
		"Icon",
		true
	)

	local bannerName = UI.label(
		card,
		"No file selected",
		UDim2.fromOffset(CARD_PAD, CARD_PAD + BANNER_HEIGHT + 34),
		UDim2.fromOffset(bannerWidth, LABEL_HEIGHT),
		UI.tokens.type.caption,
		UI.tokens.color.muted
	)
	bannerName.TextXAlignment = Enum.TextXAlignment.Left
	bannerName.TextTruncate = Enum.TextTruncate.AtEnd

	local iconName = UI.label(
		card,
		"No file selected",
		UDim2.fromOffset(cardWidth - CARD_PAD - ICON_SIZE, CARD_PAD + BANNER_HEIGHT + 34),
		UDim2.fromOffset(ICON_SIZE, LABEL_HEIGHT),
		UI.tokens.type.caption,
		UI.tokens.color.muted
	)
	iconName.TextXAlignment = Enum.TextXAlignment.Left
	iconName.TextTruncate = Enum.TextTruncate.AtEnd

	smallButton(card, "Choose banner", UDim2.fromOffset(CARD_PAD, CARD_PAD + BANNER_HEIGHT + 4), UDim2.fromOffset(120, 26), function()
		chooseImage(bannerImage, bannerPlaceholder, bannerName, "banner")
	end)
	smallButton(card, "Clear", UDim2.fromOffset(CARD_PAD + 126, CARD_PAD + BANNER_HEIGHT + 4), UDim2.fromOffset(54, 26), function()
		clearImage(bannerImage, bannerPlaceholder, bannerName, "banner")
	end)

	local iconButtonX = cardWidth - CARD_PAD - ICON_SIZE

	smallButton(card, "Choose", UDim2.fromOffset(iconButtonX, CARD_PAD + BANNER_HEIGHT + 4), UDim2.fromOffset(60, 26), function()
		chooseImage(iconImage, iconPlaceholder, iconName, "icon")
	end)
	smallButton(card, "Clear", UDim2.fromOffset(iconButtonX + 64, CARD_PAD + BANNER_HEIGHT + 4), UDim2.fromOffset(40, 26), function()
		clearImage(iconImage, iconPlaceholder, iconName, "icon")
	end)

	bannerClick.MouseButton1Click:Connect(function()
		chooseImage(bannerImage, bannerPlaceholder, bannerName, "banner")
	end)
	iconClick.MouseButton1Click:Connect(function()
		chooseImage(iconImage, iconPlaceholder, iconName, "icon")
	end)

	card, y = addSection(content, y, "About", CARD_PAD * 2 + ROW_HEIGHT * 2 + 10)
	fields.description = addTextBox(card, "Description", "", "What does this package do?", UDim2.fromOffset(CARD_PAD, CARD_PAD), fullWidth, 512)
	fields.tags = addTextBox(card, "Tags", "", "tool, utility, ui", UDim2.fromOffset(CARD_PAD, CARD_PAD + ROW_HEIGHT + 10), fullWidth, 256)

	card, y = addSection(content, y, "Compatibility", CARD_PAD * 2 + ROW_HEIGHT)
	fields.entrypoint = addTextBox(card, "Entry point", defaultName .. ".kine", "my-package.kine", UDim2.fromOffset(CARD_PAD, CARD_PAD), UDim2.fromOffset(leftWidth, INPUT_HEIGHT), 128)
	fields.engineConstraint = addTextBox(card, "Engine constraint", "*", "*", UDim2.fromOffset(rightX, CARD_PAD), UDim2.fromOffset(rightWidth, INPUT_HEIGHT), 64)
	fields.entrypoint.TextChanged:Connect(function()
		entrypointTouched = true
	end)

	card, y = addSection(content, y, "Dependencies", CARD_PAD * 2 + ROW_HEIGHT)
	fields.dependencies = addTextBox(
		card,
		"Dependencies",
		"",
		"namespace/package@1.0.0, namespace/other",
		UDim2.fromOffset(CARD_PAD, CARD_PAD),
		fullWidth,
		512
	)

	local sourceLabel = UI.label(
		content,
		"Source: " .. tostring(target.Name) .. " (" .. tostring(target.ClassName) .. ")",
		UDim2.fromOffset(2, y),
		UDim2.new(1, -6, 0, LABEL_HEIGHT),
		UI.tokens.type.caption,
		UI.tokens.color.muted
	)
	sourceLabel.TextXAlignment = Enum.TextXAlignment.Left
	sourceLabel.TextTruncate = Enum.TextTruncate.AtEnd

	local namespaceLabel = UI.label(
		content,
		namespace and ("Publishing as namespace: " .. namespace)
			or "Namespace: taken from your Kinemium session",
		UDim2.fromOffset(2, y + LABEL_HEIGHT + 3),
		UDim2.new(1, -6, 0, LABEL_HEIGHT),
		UI.tokens.type.caption,
		UI.tokens.color.muted
	)
	namespaceLabel.TextXAlignment = Enum.TextXAlignment.Left
	namespaceLabel.TextTruncate = Enum.TextTruncate.AtEnd

	content.CanvasSize = UDim2.fromOffset(0, y + LABEL_HEIGHT * 2 + 20)

	fields.name.Focused:Connect(function()
		content.CanvasPosition = Vector2.new(0, 0)
	end)

	return prompt
end

return PackageUpload

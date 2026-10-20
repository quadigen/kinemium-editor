if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local UI = require("@internal/editor_ui")

local Packages = game:GetService("Packages")
local MatrixService = game:GetService("MatrixService")
local Project = game:GetService("Project")

local TYPES = { "package", "model", "plugin", "template", "tool" }
local VISIBILITIES = { "public", "unlisted", "private" }

local ROW_GAP = 10
local LABEL_HEIGHT = 15
local INPUT_OFFSET = LABEL_HEIGHT + 3
local INPUT_HEIGHT = 30
local ROW_HEIGHT = INPUT_OFFSET + INPUT_HEIGHT + ROW_GAP
local COLUMN_GAP = 12

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
	}

	local fields = {}
	local prompt
	local entrypointTouched = false

	local function addTextBox(parent, labelText, value, placeholder, position, size, maxLength)
		UI.label(
			parent,
			labelText,
			position,
			UDim2.new(1, 0, 0, LABEL_HEIGHT),
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
			UDim2.new(1, 0, 0, LABEL_HEIGHT),
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

	local leftWidth = UDim2.new(0.6, -COLUMN_GAP / 2, 0, INPUT_HEIGHT)
	local rightWidth = UDim2.new(0.4, -COLUMN_GAP / 2, 0, INPUT_HEIGHT)
	local rightX = UDim2.new(0.6, COLUMN_GAP / 2, 0, 0)

	local _, content, controller = UI.prompt({
		title = "Upload as Package",
		description = "Export the selected instance and submit it to the Kinemium marketplace.",
		size = UDim2.fromOffset(580, 640),
		padding = 14,
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
					local icon = trim(fields.icon.Text)
					local thumbnail = trim(fields.thumbnail.Text)

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

					if icon ~= "" then
						manifest.icon = icon
					end

					if thumbnail ~= "" then
						manifest.thumbnail = thumbnail
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

	local promptHandle = prompt

	fields.name = addTextBox(content, "Package name", defaultName, "my-package", UDim2.fromOffset(0, 0), leftWidth, 64)
	fields.version = addTextBox(content, "Version", "1.0.0", "1.0.0", rightX, rightWidth, 32)

	addChoices(
		content,
		"Type",
		state.packageType,
		UDim2.fromOffset(0, ROW_HEIGHT),
		leftWidth,
		TYPES,
		function(value)
			state.packageType = value
		end
	)

	addChoices(
		content,
		"Visibility",
		state.visibility,
		UDim2.new(rightX.X.Scale, rightX.X.Offset, 0, ROW_HEIGHT),
		rightWidth,
		VISIBILITIES,
		function(value)
			state.visibility = value
		end
	)

	fields.entrypoint = addTextBox(
		content,
		"Entry point",
		defaultName .. ".kine",
		"my-package.kine",
		UDim2.fromOffset(0, ROW_HEIGHT * 2),
		leftWidth,
		128
	)

	fields.entrypoint.TextChanged:Connect(function()
		entrypointTouched = true
	end)

	fields.engineConstraint = addTextBox(
		content,
		"Engine constraint",
		"*",
		"*",
		UDim2.new(rightX.X.Scale, rightX.X.Offset, 0, ROW_HEIGHT * 2),
		rightWidth,
		64
	)

	fields.description = addTextBox(
		content,
		"Description",
		"",
		"What does this package do?",
		UDim2.fromOffset(0, ROW_HEIGHT * 3),
		UDim2.new(1, -10, 0, INPUT_HEIGHT),
		512
	)

	fields.tags = addTextBox(
		content,
		"Tags",
		"",
		"tool, utility, ui",
		UDim2.fromOffset(0, ROW_HEIGHT * 4),
		UDim2.new(1, -10, 0, INPUT_HEIGHT),
		256
	)

	fields.dependencies = addTextBox(
		content,
		"Dependencies",
		"",
		"namespace/package@1.0.0, namespace/other",
		UDim2.fromOffset(0, ROW_HEIGHT * 5),
		UDim2.new(1, -10, 0, INPUT_HEIGHT),
		512
	)

	fields.icon = addTextBox(
		content,
		"Icon URL",
		"",
		"https://example.com/icon.png",
		UDim2.fromOffset(0, ROW_HEIGHT * 6),
		leftWidth,
		512
	)

	fields.thumbnail = addTextBox(
		content,
		"Thumbnail URL",
		"",
		"https://example.com/thumbnail.png",
		UDim2.new(rightX.X.Scale, rightX.X.Offset, 0, ROW_HEIGHT * 6),
		rightWidth,
		512
	)

	content.CanvasSize = UDim2.fromOffset(0, ROW_HEIGHT * 7 + 12)

	local sourceLabel = UI.label(
		content,
		"Source: " .. tostring(target.Name) .. " (" .. tostring(target.ClassName) .. ")",
		UDim2.fromOffset(0, ROW_HEIGHT * 7 + 4),
		UDim2.new(1, -10, 0, LABEL_HEIGHT),
		UI.tokens.type.caption,
		UI.tokens.color.muted
	)
	sourceLabel.TextTruncate = Enum.TextTruncate.AtEnd

	local namespaceLabel = UI.label(
		content,
		namespace and ("Publishing as namespace: " .. namespace)
			or "Namespace: taken from your Kinemium session",
		UDim2.fromOffset(0, ROW_HEIGHT * 7 + 4 + LABEL_HEIGHT + 3),
		UDim2.new(1, -10, 0, LABEL_HEIGHT),
		UI.tokens.type.caption,
		UI.tokens.color.muted
	)
	namespaceLabel.TextTruncate = Enum.TextTruncate.AtEnd

	content.CanvasSize = UDim2.fromOffset(0, ROW_HEIGHT * 7 + 4 + LABEL_HEIGHT * 2 + 16)

	fields.name.Focused:Connect(function()
		content.CanvasPosition = Vector2.new(0, 0)
	end)

	return promptHandle
end

return PackageUpload

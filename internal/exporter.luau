local UI = require("@internal/editor_ui")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ExportService = game:GetService("ExportService")
local Project = game:GetService("Project")
local Filesystem = game:GetService("Filesystem")
local ExporterService = game:GetService("ExporterService")

local tokens = UI.tokens

local gui = UI.widgetOverlay()

local HEADER_H = 30
local ROW_H = 24
local ROW_GAP = 4
local BODY_PAD = 8
local LIST_PAD = 10
local LIST_GAP = 5
local FOOTER_H = 84
local SCROLLBAR = 6
local SECTION_INSET = LIST_PAD * 2 + SCROLLBAR
local ANIM_SPEED = 14
local CHEVRON = "builtin://global-icons/chevron-down.svg"

local function smooth(current, target, speed, dt)
	return current + (target - current) * (1 - math.exp(-speed * dt))
end

local function sleep(seconds)
	local elapsed = 0
	while elapsed < seconds do
		local dt = RunService.Heartbeat:Wait()
		elapsed += (type(dt) == "number" and dt or 1 / 60)
	end
end

local function trim(text)
	return (string.gsub(text, "^%s*(.-)%s*$", "%1"))
end

local function notEmpty(label)
	return function(raw)
		local text = trim(raw)
		if text == "" then
			return false, label .. " can't be empty."
		end
		return true, text
	end
end

local function fileName(label)
	return function(raw)
		local text = trim(raw)
		if text == "" then
			return false, label .. " can't be empty."
		end
		if string.find(text, '[/\\:*?"<>|]') then
			return false, label .. " contains invalid characters."
		end
		return true, text
	end
end

local function reverseDomain(label)
	return function(raw)
		local text = trim(raw)
		local count = 0
		local bad = string.find(text, "^%.") or string.find(text, "%.$") or string.find(text, "%.%.")

		for part in string.gmatch(text, "[^%.]+") do
			if not string.find(part, "^[%a][%w_]*$") then
				bad = true
			end
			count += 1
		end

		if bad or count < 2 then
			return false, label .. " must look like com.example.game."
		end

		return true, text
	end
end

local function semver(raw)
	local text = trim(raw)
	if not string.find(text, "^%d+%.%d+%.%d+$") then
		return false, "Version must look like 1.0.0."
	end
	return true, text
end

local values = {}
local sections = {}
local sectionByName = {}
local selected = nil
local exporting = false

local statusLabel, exportSelectedLabel, exportAllLabel
local progress
local progressTarget, progressShown = 0, 0
local setAllEnabled

local panel, content, _, windowControls =
	UI.window("Export Game", UDim2.new(0.5, 0, 0.5, 0), UDim2.new(0.4, 0, 0.6, 0), "Export Game", { closable = true })
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Visible = false
panel.Parent = gui

local scroll = Instance.new("ScrollingFrame")
scroll.Name = "Targets"
scroll.Size = UDim2.new(1, 0, 1, -FOOTER_H)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 5
scroll.ScrollBarImageColor3 = tokens.color.subtext
scroll.ScrollBarImageTransparency = 0.4
scroll.CanvasSize = UDim2.new(1, 0, 0, 0)
scroll.Parent = content

local scrollLayout = Instance.new("UIListLayout")
scrollLayout.FillDirection = Enum.FillDirection.Vertical
scrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
scrollLayout.Padding = UDim.new(0, LIST_GAP)
scrollLayout.PaddingTop = UDim.new(0, LIST_PAD)
scrollLayout.PaddingLeft = UDim.new(0, LIST_PAD)
scrollLayout.Parent = scroll

local function selectedPlatform()
	if selected and sectionByName[selected] and not sectionByName[selected].page.Global and not sectionByName[selected].page.Unavailable then
		return selected
	end
	return nil
end

local function enabledPlatforms()
	local list, total = {}, 0
	for _, section in ipairs(sections) do
		if not section.page.Global and not section.page.Unavailable then
			total += 1
			if values[section.page.Name].enabled ~= false then
				table.insert(list, section.page.Name)
			end
		end
	end
	return list, total
end

local function resolveOutput(name)
	local store = values[name]
	if store.output then
		local nameWithExtension = trim(store.output)
		if name == "Windows" and not string.match(string.lower(nameWithExtension), "%.exe$") then
			return nameWithExtension .. ".exe"
		end
		return nameWithExtension
	end
	return values.General.projectName .. (store.format == "AAB" and ".aab" or ".apk")
end

local function updateStatus()
	local list, total = enabledPlatforms()
	local name = selectedPlatform()

	if exportSelectedLabel then
		exportSelectedLabel.Text = name and ("Export " .. name) or "Export Selected"
		exportAllLabel.Text = string.format("Export All (%d)", #list)
	end

	if statusLabel and not exporting then
		statusLabel.TextColor3 = tokens.color.muted

		if #list == 0 then
			statusLabel.Text = "No platforms enabled."
		else
			statusLabel.Text = string.format("%d of %d platforms enabled.", #list, total)
		end
	end
end

local SUMMARY_KEYS = { "format", "arch", "mode" }

local function refreshHeader(section)
	local page = section.page
	local store = values[page.Name]

	if page.Global then
		section.summary.Text = string.format("%s  v%s", store.projectName, store.version)
		return
	end

	if page.Unavailable then
		section.summary.Text = "Unavailable"
		return
	end

	if store.enabled == false then
		section.summary.Text = "Disabled"
		return
	end

	local parts = {}
	for _, key in ipairs(SUMMARY_KEYS) do
		if store[key] ~= nil then
			table.insert(parts, tostring(store[key]))
		end
	end
	section.summary.Text = table.concat(parts, " | ")
end

local function platformOutputFolder(root, name, gameType)
	local folder = root .. "/" .. string.lower(name)
	return gameType == "Single Player" and (folder .. "/singleplayer") or folder
end

local function refreshPreview(section)
	if not section.preview then
		return
	end

	local name = section.page.Name
	section.preview.Text =
		string.format("Output: %s/%s", platformOutputFolder(values.General.outputDir, name, values.General.gameType), resolveOutput(name))
end

local function applyEnabled(section)
	local page = section.page
	local store = values[page.Name]
	local on = store.enabled ~= false and not page.Unavailable

	for _, field in ipairs(page.Fields) do
		if field.key ~= "enabled" or page.Unavailable then
			local row = section.rows[field.key]

			if row then
				local active = on and not page.Unavailable and not field.unavailable

				if active and field.dependsOn then
					active = store[field.dependsOn] == true
				end

				row:SetEnabled(active)
			end
		end
	end

	section.headerLabel.TextColor3 = on and tokens.color.text or tokens.color.muted
	section.summary.TextColor3 = on and tokens.color.muted or tokens.color.warning
end

local function refreshSection(section)
	applyEnabled(section)
	refreshHeader(section)

	if section.page.Global then
		for _, other in ipairs(sections) do
			refreshPreview(other)
		end
	else
		refreshPreview(section)
	end

	updateStatus()
end

local function resetSection(section)
	local store = values[section.page.Name]

	for _, field in ipairs(section.page.Fields) do
		if field.type ~= "actions" then
			store[field.key] = field.default
			section.rows[field.key]:SetValue(field.default, true)
		end
	end

	refreshSection(section)
end

local function setSelected(name)
	for _, section in ipairs(sections) do
		section.control:SetExpanded(section.page.Name == name)
	end
	selected = name
	updateStatus()
end

local MODES = { "Release", "Debug" }
local COMPRESS = { "None", "Fast", "Best" }
local WEB_COMPRESS = { "None", "Gzip", "Brotli" }
local DESKTOP_ARCH = { "x86_64", "arm64" }

local OS_TAG = { Windows = "windows", Linux = "linux", MacOS = "macos" }
local ARCH_TAG = { x86_64 = "x86_64", arm64 = "arm64" }

local ENABLED_FIELD = {
	key = "enabled",
	label = "Enabled",
	type = "checkbox",
	default = true,
	tooltip = "Include this platform when using Export All.",
}

local pages = {
	{
		Name = "General",
		Global = true,
		Icon = "builtin://global-icons/settings.svg",
		Fields = {
			{
				key = "projectName",
				label = "Project Name",
				type = "text",
				default = "MyGame",
				validate = notEmpty("Project name"),
			},
			{
				key = "version",
				label = "Version",
				type = "text",
				default = "1.0.0",
				validate = semver,
				tooltip = "Format: major.minor.patch",
			},
			{
				key = "outputDir",
				label = "Output Folder",
				type = "text",
				default = "build",
				validate = notEmpty("Output folder"),
			},
			{
				key = "gameType",
				label = "Game Type",
				type = "dropdown",
				options = { "Client + Server", "Single Player" },
				default = "Client + Server",
				tooltip = "Single Player exports one game executable and its runtime dependencies.",
			},
			{
				key = "clean",
				label = "Clean Previous Exports",
				type = "checkbox",
				default = true,
				tooltip = "Remove old generated executables after a successful export.",
			},
			{ key = "openFolder", label = "Open Folder After", type = "checkbox", default = true },
			{
				key = "platforms",
				label = "Platforms",
				type = "actions",
				actions = {
					{
						text = "Enable All",
						callback = function()
							setAllEnabled(true)
						end,
					},
					{
						text = "Disable All",
						callback = function()
							setAllEnabled(false)
						end,
					},
				},
			},
		},
	},

	{
		Name = "Windows",
		Icon = "builtin://global-icons/windows.png",
		OpenCallback = function() end,
		CloseCallback = function() end,
		Fields = {
			ENABLED_FIELD,
			{ key = "arch", label = "Architecture", type = "dropdown", options = { "x86_64" }, default = "x86_64" },
			{ key = "mode", label = "Build Mode", type = "dropdown", options = MODES, default = "Release", unavailable = "Export uses prebuilt release templates." },
			{
				key = "output",
				label = "Output Name",
				type = "text",
				default = "Game.exe",
				validate = fileName("Output name"),
			},
			{ key = "icon", label = "Icon", type = "text", default = "", placeholder = "path/to/icon.ico", tooltip = "Optional .ico path, absolute or relative to your project. Requires the Windows editor." },
			{ key = "compression", label = "Compression", type = "dropdown", options = COMPRESS, default = "Fast" },
			{
				key = "embedAssets",
				label = "Embed Assets",
				type = "checkbox",
				default = true,
				unavailable = "Game assets are embedded in desktop exports.",
			},
			{ key = "console", label = "Console Window", type = "checkbox", default = false },
		},
	},

	{
		Name = "Linux",
		Icon = "builtin://global-icons/linux.png",
		OpenCallback = function() end,
		CloseCallback = function() end,
		Fields = {
			ENABLED_FIELD,
			{ key = "arch", label = "Architecture", type = "dropdown", options = DESKTOP_ARCH, default = "x86_64" },
			{ key = "mode", label = "Build Mode", type = "dropdown", options = MODES, default = "Release", unavailable = "Export uses prebuilt release templates." },
			{
				key = "output",
				label = "Output Name",
				type = "text",
				default = "Game.x86_64",
				validate = fileName("Output name"),
			},
			{ key = "icon", label = "Icon", type = "text", default = "", placeholder = "path/to/icon.png", unavailable = "Linux executable templates do not provide a desktop icon." },
			{ key = "compression", label = "Compression", type = "dropdown", options = COMPRESS, default = "Fast" },
			{ key = "embedAssets", label = "Embed Assets", type = "checkbox", default = true, unavailable = "Game assets are embedded in desktop exports." },
			{ key = "strip", label = "Strip Symbols", type = "checkbox", default = true, unavailable = "Linux release templates are already stripped." },
		},
	},

	{
		Name = "MacOS",
		Icon = "builtin://global-icons/apple.png",
		OpenCallback = function() end,
		CloseCallback = function() end,
		Fields = {
			ENABLED_FIELD,
			{
				key = "arch",
				label = "Architecture",
				type = "dropdown",
				options = DESKTOP_ARCH,
				default = "arm64",
			},
			{ key = "mode", label = "Build Mode", type = "dropdown", options = MODES, default = "Release", unavailable = "Export uses prebuilt release templates." },
			{
				key = "output",
				label = "Output Name",
				type = "text",
				default = "Game",
				validate = fileName("Output name"),
			},
			{
				key = "bundleId",
				label = "Bundle Identifier",
				type = "text",
				default = "com.example.game",
				validate = reverseDomain("Bundle identifier"),
				unavailable = "Requires a macOS app bundle.",
			},
			{ key = "icon", label = "Icon", type = "text", default = "", placeholder = "path/to/icon.icns", unavailable = "Requires a macOS app bundle." },
			{ key = "compression", label = "Compression", type = "dropdown", options = COMPRESS, default = "Fast" },
			{ key = "codesign", label = "Code Sign", type = "checkbox", default = false, unavailable = "Signing requires a macOS packaging toolchain." },
			{
				key = "notarize",
				label = "Notarize",
				type = "checkbox",
				default = false,
				dependsOn = "codesign",
				unavailable = "Notarization requires a signed macOS app bundle.",
			},
		},
	},

	{
		Name = "Android",
		Unavailable = true,
		Icon = "builtin://global-icons/android.png",
		OpenCallback = function() end,
		CloseCallback = function() end,
		Fields = {
			ENABLED_FIELD,
			{
				key = "format",
				label = "Package Format",
				type = "dropdown",
				options = { "APK", "AAB" },
				default = "APK",
			},
			{
				key = "arch",
				label = "Architecture",
				type = "dropdown",
				options = { "arm64-v8a", "armeabi-v7a", "x86_64" },
				default = "arm64-v8a",
			},
			{ key = "mode", label = "Build Mode", type = "dropdown", options = MODES, default = "Release", unavailable = "Export uses prebuilt release templates." },
			{
				key = "package",
				label = "Package Name",
				type = "text",
				default = "com.example.game",
				validate = reverseDomain("Package name"),
			},
			{ key = "versionCode", label = "Version Code", type = "number", default = 1, min = 1, decimals = 0 },
			{ key = "minSdk", label = "Min SDK", type = "number", default = 24, min = 1, max = 99, decimals = 0 },
			{ key = "icon", label = "Icon", type = "text", default = "", placeholder = "path/to/icon.png" },
			{ key = "sign", label = "Sign Package", type = "checkbox", default = false },
			{
				key = "keystore",
				label = "Keystore",
				type = "text",
				default = "",
				placeholder = "path/to/release.keystore",
				dependsOn = "sign",
				required = true,
			},
		},
	},

	{
		Name = "Emscripten",
		Unavailable = true,
		Icon = "builtin://global-icons/emscripten.png",
		OpenCallback = function() end,
		CloseCallback = function() end,
		Fields = {
			ENABLED_FIELD,
			{ key = "mode", label = "Build Mode", type = "dropdown", options = MODES, default = "Release", unavailable = "Export uses prebuilt release templates." },
			{
				key = "output",
				label = "Output Name",
				type = "text",
				default = "index.html",
				validate = fileName("Output name"),
			},
			{
				key = "memory",
				label = "Memory (MB)",
				type = "number",
				default = 256,
				min = 16,
				max = 4096,
				decimals = 0,
			},
			{ key = "compression", label = "Compression", type = "dropdown", options = WEB_COMPRESS, default = "Gzip" },
			{
				key = "threads",
				label = "Threads",
				type = "checkbox",
				default = false,
				tooltip = "Needs cross-origin isolation headers on your host.",
			},
		},
	},
}

local function buildRow(section, page, field, y)
	local store = values[page.Name]

	if field.type ~= "actions" then
		store[field.key] = field.default
	end

	local function onChange(newValue)
		store[field.key] = newValue
		refreshSection(section)
	end

	local opts = {
		name = field.key,
		labelWidth = 120,
		transparent = true,
		placeholder = field.placeholder,
		selectAllOnFocus = true,
	}

	if field.type == "dropdown" then
		opts.custom = function(holder, controller)
			local items = {}
			for _, option in ipairs(field.options) do
				table.insert(items, { value = option, text = option })
			end

			local button, ddLabel, dd
			button, ddLabel, dd =
				UI.dropdown(holder, field.default, UDim2.new(0, 0, 0.5, -11), UDim2.new(1, 0, 0, 22), CHEVRON, {
					items = items,
					menuWidth = 170,
					showSearch = false,
					menuPosition = function()
						local p, s = button.AbsolutePosition, button.AbsoluteSize
						return UDim2.fromOffset(p.X, p.Y + s.Y + 2)
					end,
					onChanged = function(newValue)
						controller:Fire(newValue)
					end,
				})

			return {
				dd = dd,
				GetValue = function()
					return dd:GetValue()
				end,
				SetValue = function(_, v, silent)
					dd:SetValue(v, silent)
				end,
				SetEnabled = function(_, v)
					dd.record.enabled = v
					button.Active = v
					button.BackgroundTransparency = v and 0 or 0.5
					ddLabel.TextColor3 = v and tokens.color.subtext or tokens.color.muted

					if not v then
						dd:Close()
					end
				end,
				Destroy = function() end,
			}
		end
	elseif field.type == "checkbox" then
		opts.custom = function(holder, controller)
			local _, checkbox = UI.checkbox(
				holder,
				"",
				UDim2.new(0, 0, 0.5, -11),
				field.default == true,
				function(newValue)
					controller:Fire(newValue)
				end,
				{ size = UDim2.new(1, 0, 0, 22) }
			)

			return {
				GetValue = function()
					return checkbox:GetValue()
				end,
				SetValue = function(_, v, silent)
					checkbox:SetValue(v, silent)
				end,
				SetEnabled = function(_, v)
					checkbox.record.enabled = v
					checkbox.box.Active = v
					checkbox.box.BackgroundTransparency = v and 0 or 0.5
					checkbox.mark.ImageTransparency = v and 0 or 0.6
				end,
				Destroy = function() end,
			}
		end
	elseif field.type == "actions" then
		opts.custom = function(holder)
			local x = 0

			for _, action in ipairs(field.actions) do
				local width = action.width or 90

				UI.button(
					holder,
					action.text,
					UDim2.fromOffset(x, 1),
					UDim2.fromOffset(width, 22),
					action.callback,
					{ textSize = tokens.type.small }
				)

				x += width + 6
			end

			return {
				SetEnabled = function() end,
				Destroy = function() end,
			}
		end
	elseif field.type == "number" then
		opts.numeric = true
		opts.min = field.min
		opts.max = field.max
		opts.decimals = field.decimals
	elseif field.type == "text" and field.validate then
		opts.validate = function(raw)
			local ok, result = field.validate(raw)

			if not ok then
				UI.toast(result, {
					type = "warning",
					title = "Invalid value",
					message = result,
					duration = 4,
				})
				return false
			end

			return true, result
		end
	end

	local _, controller = UI.property(
		section.body,
		field.label,
		UDim2.fromOffset(0, y),
		UDim2.new(1, 0, 0, ROW_H),
		field.default,
		onChange,
		opts
	)

	section.rows[field.key] = controller

	if field.type == "dropdown" then
		table.insert(section.dropdowns, controller.custom.dd)
	end

	if field.unavailable or field.tooltip then
		pcall(UI.tooltip, controller.label, field.unavailable or field.tooltip, { placement = "above", maxWidth = 240 })
	end
end

local function updateCanvas()
	local total = 0

	for _, section in ipairs(sections) do
		total += section.control:GetHeight()
	end

	scroll.CanvasSize = UDim2.new(1, 0, 0, LIST_PAD * 2 + total + LIST_GAP * (#sections - 1))
end

for index, page in ipairs(pages) do
	values[page.Name] = {}

	local section = {
		page = page,
		dropdowns = {},
		rows = {},
	}

	local frame, control = UI.collapsible(scroll, page.Name, UDim2.new(), UDim2.new(1, -SECTION_INSET, 0, HEADER_H), {
		name = page.Name,
		layoutOrder = index,
		icon = page.Icon,
		chevron = CHEVRON,
		headerHeight = HEADER_H,
		animSpeed = ANIM_SPEED,
		color = tokens.color.panelRaised,
		radius = tokens.radius.sm,
		controlled = true,
		onToggle = function(wantExpanded)
			setSelected(wantExpanded and page.Name or nil)
		end,
		onOpen = function()
			if page.OpenCallback then
				page.OpenCallback()
			end
		end,
		onClose = function()
			for _, dd in ipairs(section.dropdowns) do
				dd:Close()
			end

			if page.CloseCallback then
				page.CloseCallback()
			end
		end,
		onHeightChanged = updateCanvas,
	})

	section.frame = frame
	section.control = control
	section.body = control.body
	section.headerLabel = control.headerLabel
	section.summary = control.summary

	sectionByName[page.Name] = section

	local y = BODY_PAD + 2

	for _, field in ipairs(page.Fields) do
		buildRow(section, page, field, y)
		y += ROW_H + ROW_GAP
	end

	local resetW = 120

	if not page.Global then
		local preview = UI.label(
			section.body,
			"",
			UDim2.fromOffset(BODY_PAD, y),
			UDim2.new(1, -(resetW + BODY_PAD * 2 + 4), 0, 22),
			tokens.type.caption,
			tokens.color.muted
		)
		preview.TextXAlignment = Enum.TextXAlignment.Left
		preview.TextYAlignment = Enum.TextYAlignment.Center
		section.preview = preview
	end

	UI.button(
		section.body,
		"Reset to Defaults",
		UDim2.new(1, -(resetW + BODY_PAD), 0, y),
		UDim2.fromOffset(resetW, 22),
		function()
			resetSection(section)
		end,
		{ color = tokens.color.input, textSize = tokens.type.small }
	)

	y += 22 + BODY_PAD

	control:SetBodyHeight(y)

	table.insert(sections, section)
	refreshSection(section)
end

updateCanvas()

setAllEnabled = function(on)
	for _, section in ipairs(sections) do
		if not section.page.Global and not section.page.Unavailable then
			values[section.page.Name].enabled = on
			section.rows.enabled:SetValue(on, true)
			refreshSection(section)
		end
	end
end

local function validateSection(name)
	local section = sectionByName[name]
	local store = values[name]

	for _, field in ipairs(section.page.Fields) do
		local value = store[field.key]
		local relevant = value ~= nil and not field.unavailable and not (field.dependsOn and store[field.dependsOn] ~= true)

		if relevant and type(value) == "string" then
			if field.required and trim(value) == "" then
				return false, name .. ": " .. field.label .. " is required."
			end

			if field.validate then
				local ok, message = field.validate(value)
				if not ok then
					return false, name .. ": " .. message
				end
			end
		end
	end

	return true
end

local function buildConfig(name)
	local config = {}

	for key, value in pairs(values[name]) do
		config[key] = value
	end

	config.platform = name
	config.output = resolveOutput(name)
	config.os_name = OS_TAG[name]
	config.arch_name = ARCH_TAG[values[name].arch] or values[name].arch
	config.general = table.clone(values.General)

	return config
end

local function projectPath(project, value)
	local normalized = string.gsub(trim(value), "\\", "/")
	if string.sub(normalized, 1, 1) == "/" or string.match(normalized, "^%a:/") then
		return normalized
	end
	return project .. "/" .. normalized
end

local function openOutputFolder(folder)
	local normalized = string.gsub(folder, "\\", "/")
	local encoded = string.gsub(normalized, "[^%w%-%._~/:]", function(character)
		return string.format("%%%02X", string.byte(character))
	end)
	local prefix = "file:///"
	if string.sub(encoded, 1, 2) == "//" then
		prefix = "file:"
	elseif string.sub(encoded, 1, 1) == "/" then
		prefix = "file://"
	end
	HttpService:OpenURL(prefix .. encoded)
end

local function exportPlatform(name, config, project, buildFolder, gameFile)
	local platformFolder = platformOutputFolder(buildFolder, name, config.general.gameType)
	local singleplayer = config.general.gameType == "Single Player"
	local icon = config.icon and trim(config.icon) or ""
	ExporterService:ExportExecutable(
		singleplayer and "Singleplayer" or "Both",
		platformFolder,
		singleplayer and "" or "127.0.0.1",
		singleplayer and 0 or 8080,
		gameFile,
		config.os_name,
		config.arch_name,
		{
			outputName = config.output,
			title = trim(config.general.projectName) .. " v" .. trim(config.general.version),
			console = config.console,
			clean = config.general.clean,
			compression = config.compression,
			icon = name == "Windows" and icon ~= "" and projectPath(project, icon) or "",
		}
	)
	print("Exported " .. name .. " to " .. platformFolder)
end

local function setProgress(value, instant)
	progressTarget = value

	if instant then
		progressShown = value
		if progress then
			progress:SetValue(value)
		end
	end
end

local exportSelectedRecord, exportAllRecord

local function setBusy(busy)
	for _, pair in ipairs({
		{ exportSelectedRecord, exportSelectedLabel },
		{ exportAllRecord, exportAllLabel },
	}) do
		pair[1].enabled = not busy
		pair[1].gui.Active = not busy
		pair[2].TextColor3 = busy and tokens.color.muted or tokens.color.text
	end
end

local function runExport(names)
	if exporting then
		return
	end

	if #names == 0 then
		UI.toast("Nothing to export", {
			type = "warning",
			title = "Export",
			message = "Enable at least one platform first.",
			duration = 4,
		})
		return
	end

	local ok, message = validateSection("General")
	if not ok then
		UI.toast(message, { type = "error", title = "Can't export", message = message, duration = 5 })
		return
	end

	for _, name in ipairs(names) do
		ok, message = validateSection(name)
		if not ok then
			UI.toast(message, { type = "error", title = "Can't export", message = message, duration = 5 })
			return
		end
	end

	local configs = {}
	for i, name in ipairs(names) do
		configs[i] = buildConfig(name)
	end

	exporting = true
	setBusy(true)
	setProgress(0, true)

	local failures = {}

	local project, buildFolder, gameFile
	local prepared, prepareError = pcall(function()
		local active = Project:GetActiveProject()
		assert(active and active.Path and active.Path ~= "", "Open a project before exporting.")
		project = active.Path
		buildFolder = projectPath(project, configs[1].general.outputDir)
		local snapshotFolder = project .. "/build"
		if not Filesystem:IsDirectory(snapshotFolder) then
			assert(Filesystem:CreateFolder(project, "build") ~= "", "Could not create " .. snapshotFolder)
		end
		gameFile = snapshotFolder .. "/game.kine"
		assert(ExportService:ExportToFile(gameFile, buildFolder), "Could not save the game map for export.")
	end)
	if not prepared then
		exporting = false
		setBusy(false)
		setProgress(0, true)
		statusLabel.TextColor3 = tokens.color.error
		statusLabel.Text = "Export failed."
		UI.toast("Export failed", { type = "error", message = tostring(prepareError), duration = 0 })
		return
	end

	for i, name in ipairs(names) do
		statusLabel.TextColor3 = tokens.color.subtext
		statusLabel.Text = string.format("Exporting %s (%d/%d)...", name, i, #names)
		setProgress((i - 1) / #names)

		local success, err = pcall(exportPlatform, name, configs[i], project, buildFolder, gameFile)

		if not success then
			table.insert(failures, name .. ": " .. tostring(err))
		end

		setProgress(i / #names)
	end

	exporting = false
	setBusy(false)

	if #failures == 0 then
		statusLabel.TextColor3 = tokens.color.success
		statusLabel.Text = string.format("Exported %d platform%s.", #names, #names == 1 and "" or "s")

		UI.toast("Export finished", {
			type = "success",
			title = "Export",
			message = string.format("Exported %d platform%s.", #names, #names == 1 and "" or "s"),
			duration = 5,
		})

		if configs[1].general.openFolder then
			local output = #names == 1 and platformOutputFolder(buildFolder, names[1], configs[1].general.gameType) or buildFolder
			local opened, openError = pcall(openOutputFolder, output)
			if not opened then
				UI.toast("Could not open output folder", { type = "warning", message = tostring(openError) })
			end
		end
	else
		statusLabel.TextColor3 = tokens.color.error
		statusLabel.Text = string.format("%d of %d exports failed.", #failures, #names)

		UI.toast("Export failed", {
			type = "error",
			title = "Export",
			message = string.format("%d of %d exports failed.", #failures, #names),
			details = table.concat(failures, "\n"),
			duration = 0,
		})
	end

	sleep(2.5)

	if not exporting then
		setProgress(0)
		updateStatus()
	end
end

local function exportSelected()
	local name = selectedPlatform()

	if not name then
		UI.toast("Select a platform first", {
			type = "warning",
			title = "Export",
			message = "Open a platform to export it, or use Export All.",
			duration = 4,
		})
		return
	end

	if values[name].enabled == false then
		UI.toast("Platform disabled", {
			type = "warning",
			title = "Export",
			message = name .. " is disabled. Turn on Enabled to export.",
			duration = 4,
		})
		return
	end

	runExport({ name })
end

local function exportAll()
	runExport((enabledPlatforms()))
end

local footer = UI.frame(content, UDim2.new(0, 0, 1, -FOOTER_H), UDim2.new(1, 0, 0, FOOTER_H), tokens.color.panelRaised)
footer.Name = "Footer"
UI.separator(footer, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 1), tokens.color.surface)

statusLabel = UI.label(
	footer,
	"",
	UDim2.fromOffset(LIST_PAD, 8),
	UDim2.new(1, -LIST_PAD * 2, 0, 16),
	tokens.type.caption,
	tokens.color.muted
)
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextYAlignment = Enum.TextYAlignment.Center

local _, progressController =
	UI.progressBar(footer, UDim2.fromOffset(LIST_PAD, 28), UDim2.new(1, -LIST_PAD * 2, 0, 4), 0)
progress = progressController

local _, selectedLabel, selectedRecord
_, selectedLabel, selectedRecord = UI.button(
	footer,
	"Export Selected",
	UDim2.fromOffset(LIST_PAD, 42),
	UDim2.new(0.5, -(LIST_PAD + 4), 0, 30),
	exportSelected,
	{
		color = tokens.color.accent,
		hoverColor = tokens.color.selectionHover,
		pressedColor = tokens.color.pressed,
		textColor = tokens.color.text,
		textSize = tokens.type.body,
		border = false,
	}
)
exportSelectedLabel, exportSelectedRecord = selectedLabel, selectedRecord

local _, allLabel, allRecord
_, allLabel, allRecord =
	UI.button(footer, "Export All", UDim2.new(0.5, 4, 0, 42), UDim2.new(0.5, -(LIST_PAD + 4), 0, 30), exportAll, {
		color = tokens.color.input,
		hoverColor = tokens.color.hover,
		pressedColor = tokens.color.pressed,
		textColor = tokens.color.text,
		textSize = tokens.type.body,
		border = false,
	})
exportAllLabel, exportAllRecord = allLabel, allRecord

updateStatus()

local heartbeat = RunService.Heartbeat:Connect(function(dt)
	if progress then
		progressShown = smooth(progressShown, progressTarget, 10, dt)

		if math.abs(progressShown - progressTarget) < 0.002 then
			progressShown = progressTarget
		end

		progress:SetValue(progressShown)
	end
end)

panel.Destroying:Connect(function()
	heartbeat:Disconnect()
end)

return {
	Enable = function()
		panel.Visible = true
	end,

	Disable = function()
		panel.Visible = false
	end,

	Toggle = function()
		panel.Visible = not panel.Visible
	end,

	Refresh = function()
		UI.refreshWindow("Export Game")
	end,

	IsVisible = function()
		return panel.Visible
	end,
}

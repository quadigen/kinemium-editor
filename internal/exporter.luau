local UI = require("@internal/editor_ui")
local RunService = game:GetService("RunService")

local colors = UI.colors
local tokens = UI.tokens

local gui = UI.widgetOverlay()

local HEADER_H = 30
local ROW_H = 24
local ROW_GAP = 4
local BODY_PAD = 8
local LIST_PAD = 10
local LIST_GAP = 5
local FOOTER_H = 46
local ANIM_SPEED = 14
local CHEVRON = "builtin://global-icons/chevron-down.svg"

local function smooth(current, target, speed, dt)
	return current + (target - current) * (1 - math.exp(-speed * dt))
end

local panel, content, _, windowControls =
	UI.window("Export Game", UDim2.new(0.5, 0, 0.5, 0), UDim2.new(0.4, 0, 0.5, 0), "Export Game", {})
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

local MODES = { "Release", "Debug" }

local pages = {
	{
		Name = "Windows",
		Icon = "builtin://global-icons/windows.png",
		OpenCallback = function() end,
		CloseCallback = function() end,
		Fields = {
			{
				key = "arch",
				label = "Architecture",
				type = "dropdown",
				options = { "x86_64", "arm64" },
				default = "x86_64",
			},
			{ key = "mode", label = "Build Mode", type = "dropdown", options = MODES, default = "Release" },
			{ key = "output", label = "Output Name", type = "text", default = "Game.exe" },
			{ key = "embedAssets", label = "Embed Assets", type = "checkbox", default = true },
			{ key = "console", label = "Console Window", type = "checkbox", default = false },
		},
	},

	{
		Name = "Linux",
		Icon = "builtin://global-icons/linux.png",
		OpenCallback = function() end,
		CloseCallback = function() end,
		Fields = {
			{
				key = "arch",
				label = "Architecture",
				type = "dropdown",
				options = { "x86_64", "arm64" },
				default = "x86_64",
			},
			{ key = "mode", label = "Build Mode", type = "dropdown", options = MODES, default = "Release" },
			{ key = "output", label = "Output Name", type = "text", default = "Game.x86_64" },
			{ key = "embedAssets", label = "Embed Assets", type = "checkbox", default = true },
			{ key = "strip", label = "Strip Symbols", type = "checkbox", default = true },
		},
	},

	{
		Name = "MacOS",
		Icon = "builtin://global-icons/apple.png",
		OpenCallback = function() end,
		CloseCallback = function() end,
		Fields = {
			{
				key = "arch",
				label = "Architecture",
				type = "dropdown",
				options = { "Universal", "arm64", "x86_64" },
				default = "Universal",
			},
			{ key = "mode", label = "Build Mode", type = "dropdown", options = MODES, default = "Release" },
			{ key = "output", label = "Output Name", type = "text", default = "Game.app" },
			{ key = "bundleId", label = "Bundle Identifier", type = "text", default = "com.example.game" },
			{ key = "codesign", label = "Code Sign", type = "checkbox", default = false },
		},
	},

	{
		Name = "Android",
		Icon = "builtin://global-icons/android.png",
		OpenCallback = function() end,
		CloseCallback = function() end,
		Fields = {
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
			{ key = "mode", label = "Build Mode", type = "dropdown", options = MODES, default = "Release" },
			{ key = "package", label = "Package Name", type = "text", default = "com.example.game" },
			{ key = "versionCode", label = "Version Code", type = "number", default = 1, min = 1, decimals = 0 },
			{ key = "minSdk", label = "Min SDK", type = "number", default = 24, min = 1, max = 99, decimals = 0 },
		},
	},

	{
		Name = "Emscripten",
		Icon = "builtin://global-icons/emscripten.png",
		OpenCallback = function() end,
		CloseCallback = function() end,
		Fields = {
			{ key = "mode", label = "Build Mode", type = "dropdown", options = MODES, default = "Release" },
			{ key = "output", label = "Output Name", type = "text", default = "index.html" },
			{
				key = "memory",
				label = "Memory (MB)",
				type = "number",
				default = 256,
				min = 16,
				max = 4096,
				decimals = 0,
			},
			{ key = "threads", label = "Threads", type = "checkbox", default = false },
			{ key = "compress", label = "Gzip Compress", type = "checkbox", default = true },
		},
	},
}

local values = {}
local sections = {}
local selected = nil
local exportLabel = nil

local function buildRow(section, page, field, y)
	local store = values[page.Name]
	store[field.key] = field.default

	local function onChange(newValue)
		store[field.key] = newValue
	end

	local opts = {
		name = field.key,
		labelWidth = 120,
		transparent = true,
	}

	if field.type == "dropdown" then
		opts.custom = function(holder, controller)
			local items = {}
			for _, option in ipairs(field.options) do
				table.insert(items, { value = option, text = option })
			end

			local button, dd
			button, _, dd =
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

			return dd
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
				end
			)

			return checkbox
		end
	elseif field.type == "number" then
		opts.numeric = true
		opts.min = field.min
		opts.max = field.max
		opts.decimals = field.decimals
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

	if field.type == "dropdown" then
		table.insert(section.dropdowns, controller.custom)
	end
end

local function updateExportLabel()
	if exportLabel then
		exportLabel.Text = selected and ("Export for " .. selected) or "Export"
	end
end

local function setSelected(name)
	for _, section in ipairs(sections) do
		local open = section.page.Name == name

		if section.expanded ~= open then
			section.expanded = open

			if open then
				section.page.OpenCallback()
			else
				for _, dd in ipairs(section.dropdowns) do
					dd:Close()
				end

				section.page.CloseCallback()
			end
		end
	end

	selected = name
	updateExportLabel()
end

for index, page in ipairs(pages) do
	values[page.Name] = {}

	local bodyHeight = BODY_PAD * 2 + #page.Fields * ROW_H + (#page.Fields - 1) * ROW_GAP + 1

	local frame = UI.frame(
		scroll,
		UDim2.new(),
		UDim2.new(1, -(LIST_PAD * 2 + 6), 0, HEADER_H),
		tokens.color.panelRaised,
		tokens.radius.sm
	)
	frame.Name = page.Name
	frame.LayoutOrder = index
	frame.ClipsDescendants = true
	UI.stroke(frame, tokens.color.border, 1, 0)

	local section = {
		page = page,
		frame = frame,
		bodyHeight = bodyHeight,
		current = HEADER_H,
		lastHeight = -1,
		expanded = false,
		dropdowns = {},
	}

	local header, headerLabel = UI.button(
		frame,
		page.Name,
		UDim2.fromOffset(0, 0),
		UDim2.new(1, 0, 0, HEADER_H),
		function()
			if section.expanded then
				setSelected(nil)
			else
				setSelected(page.Name)
			end
		end,
		{
			icon = page.Icon,
			color = tokens.color.panelRaised,
			radius = tokens.radius.sm,
			border = false,
			textColor = tokens.color.text,
		}
	)

	header.Name = page.Name .. "Header"
	headerLabel.Position = UDim2.fromOffset(30, 0)
	headerLabel.Size = UDim2.new(1, -60, 1, 0)
	headerLabel.TextXAlignment = Enum.TextXAlignment.Left
	headerLabel.TextYAlignment = Enum.TextYAlignment.Center

	section.chevron = UI.image(header, CHEVRON, UDim2.new(1, -22, 0.5, -6), UDim2.fromOffset(12, 12))
	section.chevron.Rotation = -90

	local body = UI.frame(frame, UDim2.fromOffset(0, HEADER_H), UDim2.new(1, 0, 0, bodyHeight), tokens.color.panel)
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Visible = false
	section.body = body

	UI.separator(body, UDim2.fromOffset(6, 0), UDim2.new(1, -12, 0, 1), colors.line)

	local y = BODY_PAD
	for _, field in ipairs(page.Fields) do
		buildRow(section, page, field, y)
		y += ROW_H + ROW_GAP
	end

	table.insert(sections, section)
end

local footer = UI.frame(content, UDim2.new(0, 0, 1, -FOOTER_H), UDim2.new(1, 0, 0, FOOTER_H), tokens.color.panelRaised)
footer.Name = "Footer"
UI.separator(footer, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 1), colors.line)

local function exportSelected()
	if not selected then
		UI.toast("Select a platform first", {
			type = "warning",
			title = "Export",
			message = "Open a platform and configure it before exporting.",
			duration = 4,
		})
		return
	end

	local config = values[selected]

	print("Exporting for", selected)
	for key, value in pairs(config) do
		print("  ", key, "=", value)
	end

	UI.toast("Export started", {
		type = "success",
		title = "Export",
		message = "Exporting for " .. selected .. ".",
		duration = 5,
	})
end

local _, exportLabelRef =
	UI.button(footer, "Export", UDim2.new(0, LIST_PAD, 0.5, -14), UDim2.new(1, -LIST_PAD * 2, 0, 28), exportSelected, {
		color = tokens.color.accent,
		hoverColor = tokens.color.selectionHover,
		pressedColor = tokens.color.pressed,
		textColor = tokens.color.text,
		textSize = tokens.type.body,
		border = false,
	})
exportLabel = exportLabelRef

local heartbeat = RunService.Heartbeat:Connect(function(dt)
	local total = 0

	for _, section in ipairs(sections) do
		local target = section.expanded and (HEADER_H + section.bodyHeight) or HEADER_H

		section.current = smooth(section.current, target, ANIM_SPEED, dt)

		if math.abs(section.current - target) < 0.5 then
			section.current = target
		end

		local height = math.floor(section.current + 0.5)

		if height ~= section.lastHeight then
			section.lastHeight = height
			section.frame.Size = UDim2.new(1, -(LIST_PAD * 2 + 6), 0, height)

			local alpha = math.clamp((section.current - HEADER_H) / section.bodyHeight, 0, 1)
			section.chevron.Rotation = -90 * (1 - alpha)
			section.body.Visible = section.current > HEADER_H + 1
		end

		total += section.current
	end

	scroll.CanvasSize = UDim2.new(1, 0, 0, LIST_PAD * 2 + total + LIST_GAP * (#sections - 1))
end)

panel.Destroying:Connect(function()
	heartbeat:Disconnect()
end)

if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local UI = require("@internal/editor_ui")
local colors = UI.tokens.color
local NativePlugins = {}
local mounted = {}
local window
local windowRefresh
local startupWarningShown = false

local RISK_TEXT = "Native libraries run inside the Kinemium process, NOT the Luau sandbox. "
	.. "They may read, change or delete local files, connect to the Internet, "
	.. "start operating-system processes, inspect process memory, and crash Kinemium. "
	.. "Manifest capabilities are self-reported, not an enforced security boundary."

local function query()
	local ok, result = pcall(function()
		return game:GetService("PluginLoader"):GetNativePlugins()
	end)
	if not ok then
		return {}, tostring(result)
	end
	if type(result) ~= "table" then
		return {}, "PluginLoader returned an invalid response"
	end
	table.sort(result, function(a, b)
		return tostring(a.Name or a.Id) < tostring(b.Name or b.Id)
	end)
	return result, nil
end

local function text(parent, caption, position, size, color, fontSize)
	local label = UI.label(parent, caption, position, size, fontSize or UI.tokens.type.small, color or colors.subtext)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	return label
end

local function notification(kind, title, message)
	UI.toast("native-plugins", {
		type = kind,
		title = title,
		message = message,
		duration = 7,
	})
end

local function capabilities(plugin)
	local values = {}
	if type(plugin.Capabilities) == "table" then
		for _, value in ipairs(plugin.Capabilities) do
			if type(value) == "string" and value ~= "" then
				table.insert(values, value)
			end
		end
	end
	return #values > 0 and table.concat(values, ", ") or "None declared"
end

local function approval(plugin, refresh)
	if plugin.Loaded or plugin.Enabled == false then
		return
	end
	local name = tostring(plugin.Name or plugin.Id)
	local _, _, controller = UI.prompt({
		name = "NativePluginConsent",
		title = "Allow native plugin: " .. name .. "?",
		description = "This plugin can run unrestricted native code on your computer.",
		size = UDim2.fromOffset(565, 355),
		destroyOnClose = true,
		modal = true,
		dim = true,
		closeOnBackdrop = false,
		buttonAlignment = "right",
		contentHeight = 190,
		buttons = {
			{ id = "cancel", text = "Keep Disabled", role = "secondary" },
			{
				id = "load",
				text = "Load This Session",
				role = "danger",
				callback = function()
					local ok, loaded, err = pcall(function()
						return game:GetService("PluginLoader"):LoadNativePlugin(plugin.Id)
					end)
					if not ok or not loaded then
						notification("error", "Native plugin could not load", tostring(ok and err or loaded))
					else
						notification("success", "Native plugin loaded", name)
					end
					refresh()
				end,
			},
		},
		build = function(content)
			local warning = UI.image(
				content,
				"builtin://global-icons/Warning.svg",
				UDim2.fromOffset(4, 5),
				UDim2.fromOffset(18, 18)
			)
			warning.ImageColor3 = colors.warning
			text(
				content,
				RISK_TEXT,
				UDim2.fromOffset(30, 2),
				UDim2.new(1, -38, 0, 102),
				colors.text,
				UI.tokens.type.small
			)
			local publisher = "Publisher: " .. tostring(plugin.Author ~= "" and plugin.Author or "Unknown")
			local library = "Library: " .. tostring(plugin.Library or "Unspecified")
			local declarations = "Declared capabilities: " .. capabilities(plugin)
			text(
				content,
				publisher .. "\n" .. library .. "\n" .. declarations,
				UDim2.fromOffset(6, 108),
				UDim2.new(1, -12, 0, 77),
				colors.subtext,
				UI.tokens.type.small
			)
		end,
	})
	controller:Open()
end

local function unload(plugin, refresh)
	local ok, unloaded, err = pcall(function()
		return game:GetService("PluginLoader"):UnloadNativePlugin(plugin.Id)
	end)
	if not ok or not unloaded then
		notification("error", "Could not unload plugin", tostring(ok and err or unloaded))
	else
		notification("success", "Plugin unloaded", tostring(plugin.Name or plugin.Id))
	end
	refresh()
end

local function rebuild(mount)
	if not UI.isAlive(mount.page) then
		return
	end
	local entries, err = query()
	local scroll = mount.list
	UI.forgetButtons(scroll)
	UI.clear(scroll)
	scroll.CanvasPosition = Vector2.new(0, 0)
	if err then
		text(
			scroll,
			"Could not query native plugins: " .. err,
			UDim2.fromOffset(12, 8),
			UDim2.new(1, -24, 0, 80),
			colors.error,
			UI.tokens.type.small
		)
		scroll.CanvasSize = UDim2.fromOffset(0, 80)
		mount.status.Text = "Native plugin service unavailable"
		return
	end
	local pending = 0
	for _, plugin in ipairs(entries) do
		if not plugin.Loaded and plugin.Enabled ~= false then
			pending += 1
		end
	end
	mount.status.Text = string.format(
		"%d native plugin(s) found, %d awaiting approval. No native code is loaded during discovery.",
		#entries,
		pending
	)
	if #entries == 0 then
		text(
			scroll,
			"No native plugins found. Place an extension.json and its native library under extensions/<plugin-id>/.",
			UDim2.fromOffset(12, 12),
			UDim2.new(1, -24, 0, 85),
			colors.muted,
			UI.tokens.type.small
		)
		scroll.CanvasSize = UDim2.fromOffset(0, 90)
		return
	end
	local height = 0
	for i, plugin in ipairs(entries) do
		local card = UI.frame(
			scroll,
			UDim2.fromOffset(6, height + 5),
			UDim2.new(1, -18, 0, 116),
			i % 2 == 0 and colors.rowEven or colors.rowOdd
		)
		local title = tostring(plugin.Name or plugin.Id)
		text(
			card,
			title .. "   v" .. tostring(plugin.Version or "?") .. (plugin.Legacy and "   Legacy KNE" or "   SDK v2"),
			UDim2.fromOffset(12, 8),
			UDim2.new(1, -166, 0, 20),
			colors.text,
			UI.tokens.type.body
		)
		local status = plugin.Loaded and "Running"
			or (plugin.Enabled == false and "Disabled by manifest" or "Approval required")
		text(
			card,
			status,
			UDim2.new(1, -156, 0, 8),
			UDim2.fromOffset(146, 20),
			plugin.Loaded and colors.success or colors.warning,
			UI.tokens.type.caption
		)
		text(
			card,
			tostring(plugin.Description or ""),
			UDim2.fromOffset(12, 32),
			UDim2.new(1, -24, 0, 34),
			colors.subtext,
			UI.tokens.type.small
		)
		text(
			card,
			"Declared capabilities: " .. capabilities(plugin),
			UDim2.fromOffset(12, 70),
			UDim2.new(1, -180, 0, 36),
			colors.muted,
			UI.tokens.type.caption
		)
		if plugin.Loaded then
			UI.button(card, "Unload", UDim2.new(1, -148, 1, -38), UDim2.fromOffset(136, 27), function()
				unload(plugin, mount.refresh)
			end, { icon = "builtin://global-icons/x.svg" })
		elseif plugin.Enabled ~= false then
			UI.button(card, "Review and Load", UDim2.new(1, -148, 1, -38), UDim2.fromOffset(136, 27), function()
				approval(plugin, mount.refresh)
			end, { icon = "builtin://global-icons/Warning.svg", textColor = colors.warning })
		end
		height += 124
	end
	scroll.CanvasSize = UDim2.fromOffset(0, height + 10)
end

function NativePlugins.mount(page)
	local existing = mounted[page]
	if existing then
		existing.refresh()
		return existing.refresh
	end
	local inset = UI.metrics.panelInset
	text(
		page,
		"Native SDK Plugins",
		UDim2.fromOffset(14, 8),
		UDim2.new(1, -180, 0, 27),
		colors.text,
		UI.tokens.type.title
	)
	UI.button(page, "Refresh", UDim2.new(1, -118, 0, 9), UDim2.fromOffset(104, 25), function()
		local mount = mounted[page]
		if mount then
			mount.refresh()
		end
	end, { icon = "builtin://global-icons/refresh.svg" })
	local banner =
		UI.image(page, "builtin://global-icons/Warning.svg", UDim2.fromOffset(14, 46), UDim2.fromOffset(19, 19))
	banner.ImageColor3 = colors.warning
	text(
		page,
		"Native plugins can access your computer, not just your project. Review each one before loading.",
		UDim2.fromOffset(41, 43),
		UDim2.new(1, -55, 0, 43),
		colors.warning,
		UI.tokens.type.small
	)
	local status = text(
		page,
		"Scanning native extensions...",
		UDim2.fromOffset(14, 90),
		UDim2.new(1, -28, 0, 23),
		colors.muted,
		UI.tokens.type.caption
	)
	local scroll = UI.create("ScrollingFrame", {
		Position = UDim2.fromOffset(inset, 119),
		Size = UDim2.new(1, -2 * inset, 1, -119 - inset),
		BackgroundColor3 = colors.panel,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasPosition = Vector2.new(0, 0),
		CanvasSize = UDim2.fromOffset(0, 0),
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = colors.subtext,
		ScrollingEnabled = true,
		ScrollSpeed = 38,
		SmoothScrollingEnabled = true,
		ClipsDescendants = true,
		Active = true,
		InputSink = true,
	}, page)
	local mount = { page = page, list = scroll, status = status }
	mount.refresh = function()
		rebuild(mount)
	end
	mounted[page] = mount
	mount.refresh()
	return mount.refresh
end

function NativePlugins.openWindow()
	if window and UI.isAlive(window) then
		window.Visible = true
		if windowRefresh then
			windowRefresh()
		end
		return
	end
	local panel, content = UI.window(
		"NativePlugins",
		UDim2.fromScale(0.5, 0.5),
		UDim2.fromOffset(630, 490),
		"Native Plugins",
		{ closable = true }
	)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Parent = UI.widgetOverlay()
	window = panel
	windowRefresh = NativePlugins.mount(content)
end

function NativePlugins.notifyPending(onReview)
	if startupWarningShown then
		return
	end
	startupWarningShown = true
	local plugins, err = query()
	if err then
		return
	end
	local count = 0
	for _, plugin in ipairs(plugins) do
		if plugin.Enabled ~= false and not plugin.Loaded then
			count += 1
		end
	end
	if count == 0 then
		return
	end
	local _, _, controller = UI.prompt({
		name = "NativePluginsStartupWarning",
		title = "Native plugins detected",
		description = string.format(
			"%d native plugin(s) were found and left disabled. Unlike Luau scripts, native plugins can access files, the network, operating-system processes and Kinemium memory. Only load plugins you trust.",
			count
		),
		size = UDim2.fromOffset(510, 260),
		modal = true,
		dim = true,
		destroyOnClose = true,
		buttons = {
			{ id = "later", text = "Keep Disabled", role = "secondary" },
			{
				id = "review",
				text = "Review Plugins",
				role = "primary",
				callback = function()
					if onReview then
						onReview()
					else
						NativePlugins.openWindow()
					end
				end,
			},
		},
	})
	controller:Open()
end

return NativePlugins

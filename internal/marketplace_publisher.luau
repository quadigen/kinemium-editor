if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local UI = require("@internal/editor_ui")
local API = require("@internal/marketplace_publisher_api")
local DialogService = game:GetService("DialogService")
local Selection = game:GetService("Selection")

local tokens = UI.tokens
local colors = tokens.color
local gap = tokens.space.sm
local inset = UI.metrics.panelInset
local buttonHeight = UI.metrics.buttonHeight
local rowHeight = UI.metrics.propertyRow
local visibleRows = 11
local closeIcon = "builtin://global-icons/x.svg"

local Publisher = {}
local active

local function trim(value)
	return value:match("^%s*(.-)%s*$")
end

local function addField(parent, caption, value, y, maxLength, multiline)
	local height = multiline and rowHeight * 3 or UI.metrics.inputHeight
	UI.label(parent, caption, UDim2.fromOffset(0, y), UDim2.new(1, 0, 0, rowHeight), tokens.type.small, colors.subtext)
	local field = UI.input(parent, caption, UDim2.fromOffset(0, y + rowHeight), UDim2.new(1, 0, 0, height), {
		text = value or "",
		maxLength = maxLength,
	})
	if multiline then
		field.MultiLine = true
		field.TextWrapped = true
		field.TextYAlignment = Enum.TextYAlignment.Top
	end
	return field, y + rowHeight + height + gap
end

local function toast(kind, title, message)
	UI.toast(title, { type = kind, title = title, message = message })
end

local function form(title, height, submitText, onSubmit)
	local submitting = false
	local _, content, controller = UI.prompt({
		title = title,
		titleSize = tokens.type.title,
		size = UDim2.fromOffset(460, height),
		padding = tokens.space.lg,
		footerPadding = tokens.space.lg,
		buttonHeight = buttonHeight,
		buttonLayout = "horizontal",
		buttonAlignment = "right",
		radius = tokens.radius.md,
		destroyOnClose = true,
		beforeClose = function()
			return not submitting
		end,
		buttons = {
			{ id = "cancel", text = "Cancel", role = "secondary" },
			{
				id = "save",
				text = submitText,
				role = "primary",
				close = false,
				callback = function(dialog)
					if submitting then
						return
					end
					submitting = true
					dialog:SetBusy(true, "save", "Working...")
					task.spawn(function()
						local ok, detail = pcall(onSubmit)
						submitting = false
						if ok then
							dialog:Close("saved")
						else
							dialog:SetBusy(false, "save")
							toast("error", title, tostring(detail))
						end
					end)
				end,
			},
		},
	})
	return content, controller
end

local function editPlugin(session, plugin, updated)
	local description, license, repository, tags
	local visibility = plugin.visibility
	local deprecated = plugin.deprecated == true
	local oldTags = table.concat(plugin.tags or {}, ", ")
	local content = form("Edit plugin", 425, "Save", function()
		local changes = {}
		for key, value in pairs({
			description = description.Text,
			license = trim(license.Text),
			repository = trim(repository.Text),
			visibility = visibility,
			deprecated = deprecated,
		}) do
			local previous = plugin[key]
			if previous == nil then
				previous = key ~= "deprecated" and "" or false
			end
			if value ~= previous then
				changes[key] = value
			end
		end
		if tags.Text ~= oldTags then
			changes.tags = {}
			for entry in tags.Text:gmatch("[^,]+") do
				local tag = trim(entry)
				if tag ~= "" then
					table.insert(changes.tags, tag)
				end
			end
		end
		if next(changes) then
			updated(API.updatePlugin(session, plugin, changes), "Plugin updated.")
		end
	end)
	local y
	description, y = addField(content, "Description", plugin.description, 0, 4000, true)
	license, y = addField(content, "License", plugin.license, y, 128)
	repository, y = addField(content, "Repository URL", plugin.repository, y, 512)
	tags, y = addField(content, "Tags (comma separated)", oldTags, y, 700)
	UI.label(content, "Visibility", UDim2.fromOffset(0, y), UDim2.fromOffset(110, buttonHeight), tokens.type.small, colors.subtext)
	UI.dropdown(content, visibility, UDim2.fromOffset(110, y), UDim2.fromOffset(116, buttonHeight),
		"builtin://global-icons/chevron-down.svg", {
			items = { "public", "unlisted", "private" },
			showSearch = false,
			onChanged = function(value)
				visibility = value
			end,
		})
	UI.checkbox(content, "Deprecated", UDim2.fromOffset(244, y), deprecated, function(value)
		deprecated = value
	end)
end

local function uploadVersion(session, plugin, previous, uploaded)
	local version, entrypoint, engine, dependencies
	local archivePath, target
	local dependencyLabels = {}
	for _, dependency in ipairs(previous and previous.dependencies or {}) do
		table.insert(dependencyLabels, `{dependency.namespace}/{dependency.name}@{dependency.constraint}`)
	end
	local content = form("Upload new version", 355, "Upload", function()
		local versionName = trim(version.Text)
		if not versionName:match("^%d+%.%d+%.%d+[%w%.%+%-]*$") then
			error("Enter a version such as 1.2.0.", 0)
		end
		local entry = trim(entrypoint.Text)
		if entry == "" then
			error("Enter the plugin entry point inside the package.", 0)
		end
		if not archivePath and not target then
			error("Choose a ZIP archive or use a selected instance.", 0)
		end
		local requirements = {}
		for item in dependencies.Text:gmatch("[^,]+") do
			local key, constraint = trim(item):match("^([%w%.%-%_]+/[%w%.%-%_]+)@(.+)$")
			if not key then
				error("Use namespace/name@constraint for each dependency.", 0)
			end
			if requirements[key] then
				error(`Duplicate dependency {key}.`, 0)
			end
			requirements[key] = trim(constraint)
		end
		local engineConstraint = trim(engine.Text)
		API.publishVersion(session, {
			namespace = plugin.namespace,
			name = plugin.name,
			spaceId = plugin.spaceId,
			version = versionName,
			entrypoint = entry,
			engineConstraint = engineConstraint ~= "" and engineConstraint or nil,
			dependencies = next(requirements) and requirements or nil,
		}, archivePath, target)
		uploaded(`Version {versionName} uploaded for review.`)
	end)
	local y
	version, y = addField(content, "Version", "", 0, 128)
	entrypoint, y = addField(content, "Entry point", previous and previous.entrypoint or plugin.name .. ".kine", y, 255)
	engine, y = addField(content, "Engine constraint", previous and previous.engineConstraint or plugin.engineConstraint, y, 512)
	dependencies, y = addField(content, "Dependencies (comma separated)", table.concat(dependencyLabels, ", "), y, 5000)
	local source = UI.label(content, "Choose what to upload", UDim2.fromOffset(0, y), UDim2.new(1, 0, 0, rowHeight), tokens.type.small, colors.subtext)
	source.TextTruncate = Enum.TextTruncate.AtEnd
	UI.button(content, "Choose ZIP", UDim2.fromOffset(0, y + rowHeight), UDim2.fromOffset(96, buttonHeight), function()
		local ok, path = pcall(function()
			return DialogService:PickFile()
		end)
		if not ok then
			toast("error", "Upload new version", "Could not open the file picker.")
		elseif type(path) == "string" and path ~= "" and UI.isAlive(source) then
			if not path:lower():match("%.zip$") then
				toast("error", "Upload new version", "Choose a ZIP archive.")
				return
			end
			archivePath, target = path, nil
			source.Text = path:match("[^/\\]+$") or path
		end
	end)
	UI.button(content, "Use selected instance", UDim2.fromOffset(96 + gap, y + rowHeight), UDim2.fromOffset(148, buttonHeight), function()
		local selected = Selection:Get() or {}
		if #selected ~= 1 then
			toast("error", "Upload new version", "Select one plugin instance in Explorer before uploading.")
			return
		end
		archivePath, target = nil, selected[1]
		source.Text = target.Name
	end)
end

local function editChangelog(session, plugin, version, updated)
	local field
	local content = form(`Changelog for {version.version}`, 210, "Save", function()
		API.setChangelog(session, plugin, version.version, field.Text)
		updated("Changelog updated.")
	end)
	field = addField(content, "Changelog", version.changelog, 0, 20000, true)
	field.Size = UDim2.new(1, 0, 1, -rowHeight)
end

function Publisher.open(onChanged)
	if active and active:IsOpen() then
		return
	end
	local session = API.session()
	if not session then
		toast("info", "Marketplace settings", "Sign in to manage your published plugins.")
		return
	end

	local busy = false
	local _, content, manager = UI.prompt({
		title = "My Plugins",
		titleSize = tokens.type.title,
		size = UDim2.fromOffset(596, 366),
		padding = tokens.space.lg,
		radius = tokens.radius.md,
		showFooter = false,
		closable = true,
		closeIcon = closeIcon,
		closeRadius = tokens.radius.sm,
		destroyOnClose = true,
		onClose = function()
			active = nil
		end,
	})
	active = manager
	UI.tooltip(manager.closeButton, "Close Marketplace settings")

	local listTop = buttonHeight + gap
	local listHeight = visibleRows * rowHeight
	local statusY = listTop + listHeight + gap
	local body = UI.frame(content, UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1))
	body.BackgroundTransparency = 1
	local status = UI.label(content, "", UDim2.fromOffset(0, statusY), UDim2.new(1, -160, 0, buttonHeight), tokens.type.caption, colors.muted)
	status.TextTruncate = Enum.TextTruncate.AtEnd
	local render
	local plugin, newest
	local rows, history, nextCursor, pageLoaded = {}, { false }, nil, false
	local pluginPage

	local function fetch(cursor)
		repeat
			local result, items
			if plugin then
				result = API.listVersions(session, plugin, cursor)
				items = result and result.versions
			else
				result = API.listPlugins(session, cursor)
				items = result and result.packages
			end
			if type(items) ~= "table" then
				error("The Marketplace returned an invalid list.", 0)
			end
			local matches = {}
			for _, item in ipairs(items) do
				if plugin or item.itemType == "plugin" or table.find(item.tags or {}, "plugin") then
					table.insert(matches, item)
				end
			end
			local following = result.nextCursor
			if #matches > 0 or not following or following == cursor then
				return matches, following ~= cursor and following or nil
			end
			cursor = following
		until not manager:IsOpen()
		return {}, nil
	end

	local function loadPage(targetHistory)
		if busy then
			return
		end
		busy = true
		status.Text = "Loading..."
		task.spawn(function()
			local ok, entries, following = pcall(fetch, targetHistory[#targetHistory] or nil)
			busy = false
			if not manager:IsOpen() then
				return
			end
			if ok then
				rows, history, nextCursor, pageLoaded = entries, targetHistory, following, true
				if plugin and #history == 1 then
					newest = rows[1]
				end
			end
			render()
			if not ok then
				status.Text = "Could not load Marketplace data."
				toast("error", "Marketplace settings", tostring(entries))
			end
		end)
	end

	local function refreshBrowse()
		if onChanged then
			task.defer(onChanged)
		end
	end

	local function pluginUpdated(updated, message)
		plugin = updated or plugin
		render()
		toast("success", "Marketplace settings", message)
		refreshBrowse()
	end

	local function versionsUpdated(message, firstPage)
		toast("success", "Marketplace settings", message)
		loadPage(firstPage and { false } or history)
		refreshBrowse()
	end

	local function mutate(action, complete)
		if busy or not manager:IsOpen() then
			return
		end
		busy = true
		status.Text = "Saving..."
		task.spawn(function()
			local ok, result = pcall(action)
			busy = false
			if not manager:IsOpen() then
				if ok then
					refreshBrowse()
				end
				return
			end
			if ok then
				complete(result)
			else
				render()
				toast("error", "Marketplace settings", tostring(result))
			end
		end)
	end

	local function showVersions(item)
		pluginPage = history
		plugin, newest = item, nil
		rows, history, nextCursor, pageLoaded = {}, { false }, nil, false
		render()
		loadPage(history)
	end

	local function showPlugins(targetHistory)
		plugin = nil
		rows, history, nextCursor, pageLoaded = {}, { false }, nil, false
		render()
		loadPage(targetHistory)
	end

	local function button(parent, text, position, width, callback, enabled)
		return UI.button(parent, text, position, UDim2.fromOffset(width, buttonHeight), function()
			if not busy then
				callback()
			end
		end, { enabled = enabled ~= false })
	end

	local function renderToolbar()
		if not plugin then
			UI.label(body, session.homeserver, UDim2.fromOffset(0, 0), UDim2.new(1, -90, 0, buttonHeight), tokens.type.small, colors.subtext)
		else
			button(body, "Back", UDim2.fromOffset(0, 0), 56, function()
				showPlugins(pluginPage)
			end)
			button(body, "Edit plugin", UDim2.fromOffset(56 + gap, 0), 86, function()
				editPlugin(session, plugin, pluginUpdated)
			end)
			button(body, "Upload version", UDim2.fromOffset(142 + gap * 2, 0), 111, function()
				uploadVersion(session, plugin, newest, function(message)
					versionsUpdated(message, true)
				end)
			end, pageLoaded)
			button(body, plugin.archived and "Restore plugin" or "Archive plugin", UDim2.new(1, -(202 + gap * 2), 0, 0), 106, function()
				local item = plugin
				local archived = not item.archived
				local function apply()
					mutate(function()
						return API.setArchived(session, item, archived)
					end, function(updated)
						pluginUpdated(updated, archived and "Plugin archived." or "Plugin restored.")
					end)
				end
				if archived then
					UI.confirm("Archive plugin?", `Hide {item.namespace}/{item.name} from the Marketplace.`, apply)
				else
					apply()
				end
			end)
			button(body, "Delete plugin", UDim2.new(1, -(96 + gap), 0, 0), 96, function()
				local item = plugin
				UI.confirm("Delete plugin?", `Permanently delete {item.namespace}/{item.name} and all its versions.`, function()
					mutate(function()
						API.deletePlugin(session, item)
					end, function()
						showPlugins({ false })
						toast("success", "Marketplace settings", "Plugin deleted.")
						refreshBrowse()
					end)
				end)
			end)
		end
		local width = buttonHeight
		local refresh = UI.iconButton(body, "builtin://global-icons/refresh.svg", UDim2.new(1, -width, 0, plugin and statusY or 0),
			UDim2.fromOffset(width, buttonHeight), function()
				loadPage(history)
			end, { iconSize = 14 })
		UI.tooltip(refresh, "Refresh")
		button(body, "Previous", UDim2.new(1, -155, 0, statusY), 66, function()
			local pages = table.clone(history)
			table.remove(pages)
			loadPage(pages)
		end, #history > 1)
		button(body, "Next", UDim2.new(1, -84, 0, statusY), 55, function()
			local pages = table.clone(history)
			table.insert(pages, nextCursor)
			loadPage(pages)
		end, nextCursor ~= nil)
	end

	local function renderList()
		if #rows == 0 then
			if not pageLoaded then
				return
			end
			local empty = UI.card(body, UDim2.fromOffset(0, listTop), UDim2.new(1, 0, 0, rowHeight * 2), { color = colors.panel })
			UI.label(empty, plugin and "No versions uploaded." or "You haven’t published any plugins.",
				UDim2.fromOffset(inset, 0), UDim2.new(1, -inset * 2, 1, 0), tokens.type.small, colors.muted)
			return
		end
		local list = UI.create("ScrollingFrame", {
			Position = UDim2.fromOffset(0, listTop),
			Size = UDim2.new(1, 0, 0, listHeight),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.fromOffset(0, #rows * rowHeight),
			ScrollingEnabled = true,
			ScrollBarThickness = 5,
			ScrollBarImageColor3 = colors.subtext,
			ScrollBarImageTransparency = 0.4,
			ScrollBarAutoHide = true,
			ClipsDescendants = true,
			Active = true,
			InputSink = true,
		}, body)
		local slots = {}
		for i = 1, visibleRows + 5 do
			local slot = {}
		local position = UDim2.fromOffset(0, 0)
		local size = UDim2.new(1, -inset, 0, rowHeight)
		local row
		if plugin then
			row = UI.frame(list, position, size, colors.rowOdd)
		else
			local label
			row, label, slot.record = UI.button(list, "", position, size, function()
				if not busy and slot.item then
					showVersions(slot.item)
				end
			end, { radius = 0, border = false, color = colors.rowOdd })
			label.Visible = false
		end
			local nameWidth = plugin and 0.26 or 0.65
			slot.name = UI.label(row, "", UDim2.fromOffset(inset, 0), UDim2.new(nameWidth, -inset, 1, 0), tokens.type.small, colors.text)
			slot.name.TextTruncate = Enum.TextTruncate.AtEnd
			slot.detail = UI.label(row, "", UDim2.new(nameWidth, gap, 0, 0), UDim2.new(1 - nameWidth, plugin and -170 or -inset, 1, 0),
				tokens.type.caption, colors.subtext)
			slot.detail.TextTruncate = Enum.TextTruncate.AtEnd
			slot.row = row
			if plugin then
			local _, action = UI.button(row, "", UDim2.new(1, -68, 0, 0), UDim2.fromOffset(68, rowHeight), function()
				if busy or not slot.item then
					return
				end
					local item, version = plugin, slot.item
					local yanked = not version.yanked
					local function apply()
						mutate(function()
							API.setYanked(session, item, version.version, yanked)
						end, function()
							versionsUpdated(yanked and "Version yanked." or "Version restored.")
						end)
					end
					if yanked then
						UI.confirm("Yank version?", `Remove version {version.version} from distribution. You can restore it later.`, apply)
					else
						apply()
					end
				end)
				slot.action = action
			UI.button(row, "Changelog", UDim2.new(1, -(148 + gap), 0, 0), UDim2.fromOffset(80, rowHeight), function()
				if not busy and slot.item then
					editChangelog(session, plugin, slot.item, versionsUpdated)
				end
				end)
			end
			slots[i] = slot
		end
		local firstRendered
		local function paint()
			local first = math.floor(list.CanvasPosition.Y / rowHeight) + 1
			if first == firstRendered then
				return
			end
			firstRendered = first
			for index, slot in ipairs(slots) do
				local rowIndex = first + index - 1
				local item = rows[rowIndex]
				slot.item = item
				slot.row.Visible = item ~= nil
				if item then
					slot.row.Position = UDim2.fromOffset(0, (rowIndex - 1) * rowHeight)
				local color = rowIndex % 2 == 0 and colors.rowEven or colors.rowOdd
				if slot.record then
					slot.record.defaultColor = color
					UI.setButtonState(slot.record, nil)
				else
					slot.row.BackgroundColor3 = color
				end
					if plugin then
						slot.name.Text = item.version
						slot.detail.Text = item.yanked and "Yanked" or (item.reviewStatus or "")
						slot.action.Text = item.yanked and "Restore" or "Yank"
					else
						slot.name.Text = item.namespace .. "/" .. item.name
						slot.detail.Text = item.archived and "Archived" or (item.latestVersion or item.reviewStatus or "")
					end
				end
			end
		end
		list:GetPropertyChangedSignal("CanvasPosition"):Connect(paint)
		paint()
	end

	render = function()
		manager:SetTitle(plugin and (plugin.namespace .. "/" .. plugin.name) or "My Plugins")
		UI.clear(body)
		renderToolbar()
		renderList()
		status.Text = pageLoaded and (plugin and plugin.archived and `Page {#history} · Archived plugin` or `Page {#history}`) or ""
	end

	render()
	loadPage(history)
end

return Publisher

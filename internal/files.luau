if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local UI = require("@internal/editor_ui")
local viewport = require("@internal/viewport")

local Project = game:GetService("Project")
local dialog = game:GetService("DialogService")
local export_service = game:GetService("ExportService")
local filesystem = game:GetService("Filesystem")
local zip = game:GetService("ZipService")
local Packages = game:GetService("Packages")
local util = require("@internal/util")

local StudioThemeService = game:GetService("StudioThemeService")
local Selection = game:GetService("Selection")
local theme = StudioThemeService.SelectedTheme

local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local colors = UI.colors
local tokens = UI.tokens

local ImageViewer = require("@internal/image_viewer")

local inset = UI.metrics.panelInset

local LEFT_WIDTH = 150
local TILE_W, TILE_H, TILE_GAP = 76, 84, 6

local MAX_THUMBNAILS = 150

local function selectedObject()
	local selected = Selection:Get()
	local object = selected and selected[1]
	return object
end

local function imageSource(path)
	return ImageViewer.ImageSource(path)
end

local extensionLookup = {}

local function extensionOf(name)
	return string.lower(name):match("%.([%w]+)$")
end

local function registerFileType(definition)
	for _, extension in ipairs(definition.extensions or {}) do
		extensionLookup[string.lower(extension)] = definition
	end
end

local function fileTypeOf(entry)
	if entry == nil or entry.Type == "Directory" then
		return nil
	end

	local extension = extensionOf(entry.Name)

	if extension == nil then
		return nil
	end

	return extensionLookup[extension]
end

local function tween(object, properties, duration, style, direction, delay)
	if object == nil or not UI.isAlive(object) then
		return nil
	end

	if UI.shared and UI.shared().reduceMotion then
		local ok = pcall(function()
			for property, value in pairs(properties) do
				object[property] = value
			end
		end)
		return nil
	end

	local ok, result = pcall(function()
		local info = TweenInfo.new(
			duration,
			style or Enum.EasingStyle.Quad,
			direction or Enum.EasingDirection.Out,
			0,
			false,
			delay or 0
		)

		local created = TweenService:Create(object, info, properties)

		created:Play()

		return created
	end)

	if ok then
		return result
	end

	return nil
end

local function toastMessage(kind, title, message)
	pcall(function()
		UI.toast("files", {
			type = kind,
			title = title,
			message = message,
			details = "",
			detailsTitle = "",
			backgroundTransparency = 0.4,
			blur = true,
			duration = 5,
		})
	end)
end

local function parentDir(path)
	local index = path:gsub("\\", "/"):match("^.*()/")
	return index and path:sub(1, index - 1) or ""
end

local function joinDir(parent, name)
	local sep = parent:find("\\") and "\\" or "/"
	local last = parent:sub(-1)
	if last == "/" or last == "\\" then
		return parent .. name
	end
	return parent .. sep .. name
end

local function extractZip(ctx, intoSubfolder)
	local parent = parentDir(ctx.Path)
	local target = parent

	if intoSubfolder then
		local stem = ctx.Name:gsub("%.[^%.]*$", "")

		local existing = {}
		local ok, entries = pcall(function()
			return Project:GetProjectEntries(parent)
		end)
		if ok and type(entries) == "table" then
			for _, e in ipairs(entries) do
				existing[string.lower(e.Name)] = true
			end
		end

		local name, i = stem, 2
		while existing[string.lower(name)] do
			name = string.format("%s (%d)", stem, i)
			i += 1
		end

		local created
		ok, created = pcall(function()
			return filesystem:CreateFolder(parent, name)
		end)
		if not ok or type(created) ~= "string" or created == "" then
			toastMessage("error", "Extract failed", `Could not create folder {name}.`)
			return
		end
		target = created
	end

	local ok, result = pcall(function()
		return zip:ExtractZip(ctx.Path, target)
	end)

	if ok and result then
		toastMessage("success", "Extracted", `Extracted {ctx.Name}.`)
		ctx.Select(target)
		ctx.Refresh()
	else
		toastMessage("error", "Extract failed", `Could not extract {ctx.Name}.`)
	end
end

local openImageViewer = ImageViewer.Open
local viewerBlocksInput = ImageViewer.BlocksInput

registerFileType({
	name = "Script",
	extensions = { "lua", "luau", "odin", "cs", "py", "js", "ts" },
	icon = "builtin://icons/Script.svg",
})

registerFileType({
	name = "Audio",
	extensions = { "wav", "mp3", "ogg" },
	icon = "builtin://icons/Sound.svg",

	onDrop = function(ctx)
		local sound = Instance.new("Sound")
		sound.Name = ctx.Name
		sound.SoundId = ctx.Path
		sound.Parent = workspace
	end,

	contextItems = {
		{
			label = "Import as Sound",
			icon = "builtin://icons/Sound.svg",
			callback = function(ctx)
				local parent = selectedObject()
				if parent then
					local new = Instance.new("Sound")
					new.SoundId = ctx.Path
					new.Parent = parent
				end
			end,
		},
	},
})

registerFileType({
	name = "Font",
	extensions = { "ttf", "otf" },
	icon = "builtin://icons/Font.svg",

	onDrop = function(ctx)
		local selected = selectedObject()
		if selected:IsA("TextButton") or selected:IsA("TextLabel") then
			local face = Font.new(ctx.Path)
			if face then
				selected.FontFace = face
			end
			return
		end
	end,

	contextItems = {},
})

registerFileType({
	name = "Material",
	extensions = { "mat" },
	icon = "builtin://icons/Texture.svg",
})

registerFileType({
	name = "ZIP",
	extensions = { "zip" },
	icon = "builtin://global-icons/zip.svg",
	thumbnail = false,

	onOpen = function(ctx)
		extractZip(ctx, true)
	end,

	contextItems = {
		{
			label = "Extract to Folder",
			icon = "builtin://global-icons/folder.svg",
			callback = function(ctx)
				extractZip(ctx, true)
			end,
		},
		{
			label = "Extract Here",
			icon = "builtin://global-icons/folder.svg",
			callback = function(ctx)
				extractZip(ctx, false)
			end,
		},
	},
})

registerFileType({
	name = "Image",
	extensions = { "png", "jpg", "jpeg", "webp", "gif", "bmp" },
	icon = "builtin://icons/ImageLabel.svg",
	thumbnail = true,

	onOpen = function(ctx)
		openImageViewer(ctx)
	end,

	onDrop = function(ctx)
		local parent = selectedObject()

		if parent:IsA("ImageLabel") or parent:IsA("ImageButton") then
			parent.Image = ctx.Path
			return
		end

		if parent == nil then
			toastMessage("warning", "Nothing selected", "Select an object to drop the image onto.")
			return
		end

		local new = Instance.new("ImageLabel")
		new.Image = ctx.Path
		new.Parent = parent
	end,

	contextItems = {
		{ label = "Open in Image Viewer", icon = "builtin://icons/ImageLabel.svg", callback = openImageViewer },
		{
			label = "Import as ImageLabel",
			icon = "builtin://icons/ImageLabel.svg",
			callback = function(ctx)
				local parent = selectedObject()
				if parent then
					local new = Instance.new("ImageLabel")
					new.Image = ctx.Path
					new.Parent = parent
				end
			end,
		},
		{
			label = "Import as Decal",
			icon = "builtin://icons/Decal.svg",
			callback = function(ctx)
				local parent = selectedObject()
				if parent then
					local new = Instance.new("Decal")
					new.Image = ctx.Path
					new.Parent = parent
				end
			end,
		},
	},
})

registerFileType({
	name = "SVG",
	extensions = { "svg" },
	icon = "builtin://icons/ImageLabel.svg",
	thumbnail = true,

	onOpen = function(ctx)
		openImageViewer(ctx)
	end,

	contextItems = {
		{ label = "Open in Image Viewer", icon = "builtin://icons/ImageLabel.svg", callback = openImageViewer },
		{
			label = "Edit as Text",
			icon = "builtin://icons/Script.svg",
			callback = function(ctx)
				viewport.OpenFile(ctx.Path, ctx.Name)
			end,
		},
	},
})

local function importKine(ctx)
	local imported = export_service:ImportFile(ctx.Path)

	if imported then
		util.parent(imported)
		toastMessage("success", "Successfully imported!", `Imported {ctx.Name}`)
	else
		toastMessage("error", "Import failure", `Could not import {ctx.Name}.`)
	end
end

registerFileType({
	name = "KINE",
	extensions = { "kine" },
	icon = "builtin://global-icons/KinemiumWhite.png",
	thumbnail = false,
	onDrop = importKine,
	onOpen = importKine,
	contextItems = {
		{ label = "Import as Model", icon = "builtin://global-icons/KinemiumWhite.png", callback = importKine },
	},
})

local templates = {
	{
		label = "Folder",
		value = "Folder",
		name = "Folder",
		icon = "builtin://icons/Folder.svg",
	},

	{
		label = "Luau Script",
		value = "Luau",
		name = "Script.luau",
		icon = "builtin://icons/Script.svg",
	},

	{
		label = "Lua Script",
		value = "Lua",
		name = "Script.lua",
		icon = "builtin://icons/Script.svg",
	},

	{
		label = "Text File",
		value = "Text",
		name = "Text.txt",
		icon = "builtin://icons/File.svg",
	},

	{
		label = "JSON File",
		value = "Json",
		name = "Data.json",
		icon = "builtin://icons/File.svg",
	},

	{
		label = "Markdown File",
		value = "Markdown",
		name = "Notes.md",
		icon = "builtin://icons/File.svg",
	},
}

table.insert(templates, {
	label = "SVG File",
	value = "Svg",
	name = "Image.svg",
	icon = "builtin://icons/ImageLabel.svg",
})

return function(content, windowControls)
	local rootPath = nil
	local expanded = {}
	local filter = ""
	local selectedPath = nil
	local clipboard = nil
	local renaming = nil
	local renamedPath = nil
	local renameCommit = nil
	local pendingRebuild = false
	local rebuilding = false
	local lastHash = ""

	local rowRegistry = {}
	local visibleRows = {}
	local rowIndex = 0

	local wideMode = false
	local wideFolder = nil
	local leftList = nil
	local rightList = nil
	local leftRowRegistry = {}
	local rightRowRegistry = {}
	local leftVisibleRows = {}
	local rightVisibleRows = {}
	local leftRowIndex = 0
	local rightRowIndex = 0

	local animateNext = false
	local animating = false
	local thumbnailCount = 0

	local drag = nil
	local dragLayer = nil

	local matchCache = {}

	local openContextMenu
	local closeContextMenu
	local commitRename
	local cancelRename
	local rebuild
	local beginRename

	local function filesTabActive()
		if windowControls == nil or windowControls.getSelectedTab == nil then
			return true
		end

		return windowControls.getSelectedTab() == "Files"
	end

	local function createList(parent, position, size, fadeIn)
		local l = UI.create("ScrollingFrame", {
			Position = position,
			Size = size,

			BackgroundColor3 = tokens.color.surface,
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,

			CanvasPosition = Vector2.new(0, 0),
			CanvasSize = UDim2.new(1, 0, 0, 0),

			ScrollingEnabled = true,

			VirtualizedScrolling = true,

			ScrollSpeed = 38,

			SmoothScrollingEnabled = true,
			ScrollSmoothness = 18,

			ScrollBarThickness = 5,
			ScrollBarImageColor3 = tokens.color.subtext,
			ScrollBarImageTransparency = 0.4,
			ScrollBarAutoHide = true,
			ScrollBarFadeDelay = 0.45,
			ScrollBarFadeSpeed = 12,
			ScrollBarMinimumHandleSize = 24,

			ClipsDescendants = true,

			Active = true,
			InputSink = true,
		}, parent)

		UI.corner(l, tokens.radius.md)

		if fadeIn then
			l.BackgroundTransparency = 1

			tween(l, { BackgroundTransparency = 0.5 }, 0.22)
		end

		return l
	end

	local searchField =
		UI.input(content, "Search Files...", UDim2.fromOffset(inset, 6), UDim2.new(1, -42, 0, UI.metrics.inputHeight))

	local list = createList(content, UDim2.fromOffset(inset, 36), UDim2.new(1, -inset * 2, 1, -42), false)

	local emptyLabel = UI.label(
		content,
		"No active project",
		UDim2.new(0.5, 0, 0.5, 0),
		UDim2.fromOffset(240, 20),
		tokens.type.small,
		tokens.color.muted
	)

	emptyLabel.AnchorPoint = Vector2.new(0.5, 0.5)

	local function nameOf(path)
		return path:match("[^/\\]+$") or path
	end

	local function parentOf(path)
		local normalized = path:gsub("\\", "/")
		local index = normalized:match("^.*()/")

		return index and path:sub(1, index - 1) or ""
	end

	local function joinPath(parent, name)
		if parent == "" then
			return name
		end

		local last = parent:sub(-1)

		if last == "/" or last == "\\" then
			return parent .. name
		end

		return parent .. (parent:find("\\") and "\\" or "/") .. name
	end

	local function isSameOrDescendantOf(path, ancestor)
		if path == ancestor then
			return true
		end

		local prefix = ancestor

		if prefix:sub(-1) ~= "/" and prefix:sub(-1) ~= "\\" then
			prefix = prefix .. (ancestor:find("\\") and "\\" or "/")
		end

		return string.sub(path, 1, #prefix) == prefix
	end

	local function readEntries(directory)
		local ok, entries = pcall(function()
			return Project:GetProjectEntries(directory)
		end)

		if not ok or type(entries) ~= "table" then
			return nil
		end

		table.sort(entries, function(a, b)
			local aDirectory = a.Type == "Directory"
			local bDirectory = b.Type == "Directory"

			if aDirectory ~= bDirectory then
				return aDirectory
			end

			return string.lower(a.Name) < string.lower(b.Name)
		end)

		return entries
	end

	local function entryIsDirectory(entry)
		return entry ~= nil and entry.Type == "Directory"
	end

	local function findRegistered(path)
		if wideMode then
			return rightRowRegistry[path] or leftRowRegistry[path]
		end

		return rowRegistry[path]
	end

	local function isDirectoryPath(path)
		if path == nil then
			return false
		end

		if path == rootPath then
			return true
		end

		local registered = findRegistered(path)

		return registered ~= nil and entryIsDirectory(registered.entry)
	end

	local function iconFor(entry)
		if entryIsDirectory(entry) then
			return "builtin://icons/Folder.svg"
		end

		local fileType = fileTypeOf(entry)

		if fileType ~= nil and fileType.icon ~= nil then
			return fileType.icon
		end

		return "builtin://icons/File.svg"
	end

	local function targetDirectoryFor(path)
		if path == nil or path == rootPath then
			return rootPath
		end

		if isDirectoryPath(path) then
			return path
		end

		return parentOf(path)
	end

	local function uniqueNameFor(directory, baseName)
		local existing = {}

		local entries = readEntries(directory)

		if entries ~= nil then
			for _, entry in ipairs(entries) do
				existing[string.lower(entry.Name)] = true
			end
		end

		local lower = string.lower(baseName)

		if not existing[lower] then
			return baseName
		end

		local stem, extension = baseName:match("^(.*)(%.[^%.]*)$")

		if stem == nil then
			stem = baseName
			extension = ""
		end

		for index = 2, 100 do
			local candidate = string.format("%s (%d)%s", stem, index, extension)

			if not existing[string.lower(candidate)] then
				return candidate
			end
		end

		return baseName
	end

	local function subtreeMatches(entry)
		if filter == "" then
			return true
		end

		local cached = matchCache[entry.Path]

		if cached ~= nil then
			return cached
		end

		local result = false

		if string.find(string.lower(entry.Name), filter, 1, true) then
			result = true
		elseif entryIsDirectory(entry) then
			for _, child in ipairs(readEntries(entry.Path) or {}) do
				if subtreeMatches(child) then
					result = true
					break
				end
			end
		end

		matchCache[entry.Path] = result

		return result
	end

	local function treeHash(directory)
		local pieces = {}

		local entries = readEntries(directory)

		if entries == nil then
			return ""
		end

		for _, entry in ipairs(entries) do
			table.insert(pieces, entry.Name .. ":" .. entry.Type)

			if entryIsDirectory(entry) and (expanded[entry.Path] or filter ~= "") then
				table.insert(pieces, treeHash(entry.Path))
			end
		end

		return table.concat(pieces, "|")
	end

	local function navigateTo(path)
		wideFolder = path
		animateNext = true

		lastHash = ""
	end

	local suppressClickUntil = 0

	local function contextFor(entry)
		return {
			Path = entry.Path,
			Name = entry.Name,
			Extension = extensionOf(entry.Name),
			Entry = entry,
			Type = fileTypeOf(entry),
			Panel = content,

			Refresh = function()
				lastHash = ""
			end,

			Select = function(path)
				selectedPath = path

				lastHash = ""
			end,
		}
	end

	local function reportHandlerError(entry, err)
		toastMessage("error", "File handler failed", `{entry and entry.Name or "File"}: {tostring(err)}`)
	end

	local function openFile(entry)
		local fileType = fileTypeOf(entry)

		if fileType ~= nil and fileType.onOpen ~= nil then
			local ok, result = pcall(fileType.onOpen, contextFor(entry))

			if not ok then
				reportHandlerError(entry, result)

				return
			end

			if result ~= false then
				return
			end
		end

		viewport.OpenFile(entry.Path, entry.Name)
	end

	local function openPath(path)
		openFile({ Path = path, Name = nameOf(path), Type = "File" })
	end

	local function copyPathWindow(path)
		Project:CopyPathWindow(path)
	end

	local function clickFile(entry)
		if os.clock() < suppressClickUntil then
			return
		end

		local fileType = fileTypeOf(entry)

		if fileType == nil or fileType.onClick == nil then
			return
		end

		local ok, err = pcall(fileType.onClick, contextFor(entry))

		if not ok then
			reportHandlerError(entry, err)
		end
	end

	local registries = function()
		return { leftRowRegistry, rightRowRegistry, rowRegistry }
	end

	local function entryForPath(path)
		for _, registry in ipairs(registries()) do
			local registered = registry[path]

			if registered ~= nil then
				return registered.entry
			end
		end

		return nil
	end

	local function setDropHighlight(path, on)
		if path == nil then
			return
		end

		for _, registry in ipairs(registries()) do
			local registered = registry[path]

			if registered ~= nil and UI.isAlive(registered.row) then
				registered.dropTarget = on

				tween(registered.row, {
					BackgroundTransparency = on and 0 or registered.baseTransparency,
					BackgroundColor3 = on and colors.selection or registered.baseColor,
				}, 0.1)
			end
		end
	end

	local function clearDropHighlight()
		for _, registry in ipairs(registries()) do
			for path, registered in pairs(registry) do
				if registered.dropTarget then
					setDropHighlight(path, false)
				end
			end
		end
	end

	local function disposeDrag()
		if dragLayer ~= nil and UI.isAlive(dragLayer) then
			dragLayer:Destroy()
		end

		viewport.SetDropHighlight(false)

		dragLayer = nil
		drag = nil
	end

	local function canReparent(source, target)
		if source == nil or target == nil then
			return false
		end

		if source == target or target ~= rootPath and not isDirectoryPath(target) then
			return false
		end

		if isSameOrDescendantOf(target, source) then
			return false
		end

		if parentOf(source) == target then
			return false
		end

		return true
	end

	local function moveEntry(source, target)
		local name = nameOf(source)

		for _, other in ipairs(readEntries(target) or {}) do
			if string.lower(other.Name) == string.lower(name) then
				toastMessage("warning", "Could not move", `"{name}" already exists in {nameOf(target)}.`)
				return
			end
		end

		local ok, moved = pcall(function()
			return filesystem:MovePath(source, target)
		end)

		if ok and moved then
			expanded[target] = true
			selectedPath = joinPath(target, name)

			animateNext = true
			lastHash = ""
		end
	end

	local function finishDrop(reparent)
		local source = drag.source
		local target = drag.target

		disposeDrag()
		clearDropHighlight()

		if reparent and source ~= nil and target ~= nil and canReparent(source, target) then
			moveEntry(source, target)
		end
	end

	local function animateDrop(reparent)
		local source, target, layer = drag.source, drag.target, dragLayer

		drag = nil
		dragLayer = nil

		viewport.SetDropHighlight(false)
		clearDropHighlight()

		if reparent and source ~= nil and target ~= nil and canReparent(source, target) then
			moveEntry(source, target)
		end

		if layer == nil then
			return
		end

		local function destroyLayer()
			if UI.isAlive(layer) then
				layer:Destroy()
			end
		end

		local goal = { BackgroundTransparency = 1 }

		if reparent then
			goal.Size = UDim2.fromOffset(110, UI.metrics.treeRow - 4)
		end

		local played = tween(layer, goal, 0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

		if played == nil then
			destroyLayer()
			return
		end

		played.Completed:Once(destroyLayer)
	end

	local function attachRowInput(row, entry, pane)
		row.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				commitRename()
				closeContextMenu()

				if pane ~= "left" then
					selectedPath = entry.Path
				end

				openContextMenu(entry, input.Position)

				return
			end

			if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
				return
			end

			if UI.isAlive(renaming) and renamedPath == entry.Path then
				return
			end

			closeContextMenu()

			if UI.isAlive(renaming) and renamedPath ~= entry.Path then
				commitRename()
			end

			drag = {
				source = entry.Path,
				target = nil,
				startX = input.Position.X,
				startY = input.Position.Y,
				active = false,
				pane = pane,
			}
		end)
	end

	local function attachActivate(row, entry, pane)
		row.Activated:Connect(function(_, clickCount)
			if clickCount ~= 2 then
				return
			end

			if not entryIsDirectory(entry) then
				openFile(entry)
				return
			end

			if pane == "left" then
				return
			end

			if pane == "right" then
				expanded[wideFolder or rootPath] = true

				navigateTo(entry.Path)

				return
			end

			expanded[entry.Path] = not expanded[entry.Path] or nil

			lastHash = ""
		end)
	end

	local function addRowToPane(pane, entry, depth, y)
		local isSelected

		if pane == "left" then
			isSelected = (wideFolder or rootPath) == entry.Path
		else
			isSelected = selectedPath == entry.Path
		end

		local rowIndexVar, rowRegistryVar, visibleRowsVar, listVar

		if pane == "left" then
			leftRowIndex += 1
			rowIndexVar = leftRowIndex
			rowRegistryVar = leftRowRegistry
			visibleRowsVar = leftVisibleRows
			listVar = leftList
		else
			rowIndex += 1
			rowIndexVar = rowIndex
			rowRegistryVar = rowRegistry
			visibleRowsVar = visibleRows
			listVar = list
		end

		local rowColor = rowIndexVar % 2 == 0 and tokens.color.rowEven or tokens.color.rowOdd

		local row = UI.button(listVar, "", UDim2.fromOffset(1, y), UDim2.new(1, -2, 0, UI.metrics.treeRow), function()
			if pane ~= "left" then
				selectedPath = entry.Path

				clickFile(entry)
			end

			if entryIsDirectory(entry) then
				if pane == "left" then
					if (wideFolder or rootPath) == entry.Path then
						expanded[entry.Path] = not expanded[entry.Path] or nil
					else
						expanded[entry.Path] = true

						navigateTo(entry.Path)
					end
				else
					expanded[entry.Path] = not expanded[entry.Path] or nil
				end

				lastHash = ""
			end
		end, {
			color = isSelected and colors.selection or rowColor,

			hoverColor = isSelected and colors.selection or colors.hover,

			radius = isSelected and tokens.radius.sm or 0,

			border = false,

			selected = isSelected,
		})

		attachRowInput(row, entry, pane)

		row.BackgroundTransparency = isSelected and 0 or 0.12

		attachActivate(row, entry, pane)

		rowRegistryVar[entry.Path] = {
			row = row,
			entry = entry,
			depth = depth,
			y = y,
			h = UI.metrics.treeRow,

			baseTransparency = row.BackgroundTransparency,
			baseColor = row.BackgroundColor3,
			dropTarget = false,
			pane = pane,
		}

		visibleRowsVar[#visibleRowsVar + 1] = entry

		local indent = 7 + depth * 16

		if entryIsDirectory(entry) then
			UI.image(
				row,
				"builtin://icons/" .. (expanded[entry.Path] and "ArrowDown.svg" or "ArrowRight.svg"),
				UDim2.fromOffset(indent, 4),
				UDim2.fromOffset(12, 12)
			)
		end

		UI.image(row, iconFor(entry), UDim2.fromOffset(indent + 16, 3), UDim2.fromOffset(14, 14))

		local label = UI.label(
			row,
			entry.Name,
			UDim2.fromOffset(indent + 31, 2),
			UDim2.new(1, -(indent + 34), 0, 17),
			tokens.type.small,
			isSelected and tokens.color.text or colors.text
		)

		rowRegistryVar[entry.Path].label = label

		return y + UI.metrics.treeRow
	end

	local function walkSingle(directory, depth, y)
		local entries = readEntries(directory)

		if entries == nil then
			return y
		end

		for _, entry in ipairs(entries) do
			if subtreeMatches(entry) then
				y = addRowToPane("single", entry, depth, y)

				if entryIsDirectory(entry) and (expanded[entry.Path] or filter ~= "") then
					y = walkSingle(entry.Path, depth + 1, y)
				end
			end
		end

		return y
	end

	local function walkLeft(directory, depth, y)
		local entries = readEntries(directory)

		if entries == nil then
			return y
		end

		for _, entry in ipairs(entries) do
			if entryIsDirectory(entry) then
				y = addRowToPane("left", entry, depth, y)

				if expanded[entry.Path] then
					y = walkLeft(entry.Path, depth + 1, y)
				end
			end
		end

		return y
	end

	local function buildLeft()
		local rootEntry = {
			Path = rootPath,
			Name = nameOf(rootPath),
			Type = "Directory",
		}

		local y = addRowToPane("left", rootEntry, 0, 1)

		if expanded[rootPath] then
			y = walkLeft(rootPath, 1, y)
		end

		return y
	end

	local function gridColumns()
		local width = rightList and rightList.AbsoluteSize.X or 0

		if width <= 0 then
			width = content.AbsoluteSize.X - LEFT_WIDTH - inset * 2
		end

		width -= 10

		return math.max(1, math.floor((width - TILE_GAP) / (TILE_W + TILE_GAP)))
	end

	local function addTile(entry, index, columns)
		rightRowIndex += 1

		local isSelected = selectedPath == entry.Path

		local column = (index - 1) % columns
		local gridRow = math.floor((index - 1) / columns)

		local x = TILE_GAP + column * (TILE_W + TILE_GAP)
		local y = TILE_GAP + gridRow * (TILE_H + TILE_GAP)

		local finalPosition = UDim2.fromOffset(x, y)
		local baseTransparency = isSelected and 0 or 0.35

		local tile = UI.button(rightList, "", finalPosition, UDim2.fromOffset(TILE_W, TILE_H), function()
			selectedPath = entry.Path

			clickFile(entry)
		end, {
			color = isSelected and colors.selection or tokens.color.rowEven,
			hoverColor = isSelected and colors.selection or colors.hover,
			radius = tokens.radius.sm,
			border = false,
			selected = isSelected,
		})

		tile.BackgroundTransparency = baseTransparency

		attachRowInput(tile, entry, "right")
		attachActivate(tile, entry, "right")

		rightRowRegistry[entry.Path] = {
			row = tile,
			entry = entry,
			depth = 0,
			y = y,
			h = TILE_H,

			baseTransparency = baseTransparency,
			baseColor = tile.BackgroundColor3,
			dropTarget = false,
			pane = "right",
		}

		rightVisibleRows[#rightVisibleRows + 1] = entry

		local fileType = fileTypeOf(entry)

		local wantsThumbnail = fileType ~= nil and fileType.thumbnail == true and thumbnailCount < MAX_THUMBNAILS

		local slot = nil
		local visual = nil

		if wantsThumbnail then
			thumbnailCount += 1

			slot = UI.create("Frame", {
				Position = UDim2.fromOffset(6, 6),
				Size = UDim2.fromOffset(TILE_W - 12, 42),
				BackgroundColor3 = tokens.color.input,
				BackgroundTransparency = 0.4,
				BorderSizePixel = 0,
				Active = false,
			}, tile)

			UI.corner(slot, tokens.radius.sm)

			visual = UI.image(slot, imageSource(entry.Path), UDim2.fromOffset(2, 2), UDim2.new(1, -4, 1, -4))

			pcall(function()
				visual.ScaleType = Enum.ScaleType.Fit
			end)
		else
			visual = UI.image(tile, iconFor(entry), UDim2.fromOffset((TILE_W - 36) / 2, 8), UDim2.fromOffset(36, 36))
		end

		local labelY = wantsThumbnail and 52 or 48

		local label = UI.label(
			tile,
			entry.Name,
			UDim2.fromOffset(2, labelY),
			UDim2.new(1, -4, 0, TILE_H - labelY - 4),
			tokens.type.small,
			isSelected and tokens.color.text or colors.text
		)

		rightRowRegistry[entry.Path].label = label

		pcall(function()
			label.TextXAlignment = Enum.TextXAlignment.Center
			label.TextYAlignment = Enum.TextYAlignment.Top
			label.TextWrapped = true
			label.TextTruncate = Enum.TextTruncate.AtEnd
		end)

		if animating then
			local delay = math.min(index - 1, 14) * 0.02
			local labelBase = 0

			pcall(function()
				labelBase = label.TextTransparency or 0
			end)

			pcall(function()
				tile.BackgroundTransparency = 1
				tile.Position = UDim2.fromOffset(x, y + 10)

				visual.ImageTransparency = 1
				label.TextTransparency = 1

				if slot ~= nil then
					slot.BackgroundTransparency = 1
				end
			end)

			tween(tile, {
				BackgroundTransparency = baseTransparency,
				Position = finalPosition,
			}, 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, delay)

			tween(visual, { ImageTransparency = 0 }, 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, delay)

			if slot ~= nil then
				tween(
					slot,
					{ BackgroundTransparency = 0.4 },
					0.2,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.Out,
					delay
				)
			end

			tween(label, { TextTransparency = labelBase }, 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, delay)
		end

		return y + TILE_H
	end

	local function buildGrid(directory)
		local entries = readEntries(directory)

		if entries == nil then
			return 0
		end

		local columns = gridColumns()
		local index = 0
		local bottom = 0

		for _, entry in ipairs(entries) do
			if subtreeMatches(entry) then
				index += 1
				bottom = addTile(entry, index, columns)
			end
		end

		return bottom == 0 and 0 or bottom + TILE_GAP
	end

	rebuild = function()
		if rebuilding then
			return
		end

		if UI.isAlive(renaming) then
			pendingRebuild = true
			return
		end

		rebuilding = true
		matchCache = {}

		animating = animateNext
		animateNext = false

		thumbnailCount = 0

		local isEmpty = false

		if wideMode then
			local oldLeftCanvasPosition = leftList and leftList.CanvasPosition or Vector2.new(0, 0)
			local oldRightCanvasPosition = rightList and rightList.CanvasPosition or Vector2.new(0, 0)

			if animating then
				oldRightCanvasPosition = Vector2.new(0, 0)
			end

			UI.clear(leftList)
			UI.clear(rightList)

			leftRowIndex = 0
			rightRowIndex = 0

			leftRowRegistry = {}
			rightRowRegistry = {}

			leftVisibleRows = {}
			rightVisibleRows = {}

			local leftFinalY = 0
			local rightFinalY = 0

			if rootPath ~= nil then
				if wideFolder ~= nil and readEntries(wideFolder) == nil then
					wideFolder = nil
				end

				leftFinalY = buildLeft()
				rightFinalY = buildGrid(wideFolder or rootPath)
			end

			if leftList then
				leftList.CanvasSize = UDim2.new(1, 0, 0, leftFinalY + 4)
				leftList.CanvasPosition = oldLeftCanvasPosition
			end

			if rightList then
				rightList.CanvasSize = UDim2.new(1, 0, 0, rightFinalY + 4)
				rightList.CanvasPosition = oldRightCanvasPosition
			end

			if #rightVisibleRows > 0 then
				local selectedInRight = false

				if selectedPath ~= nil then
					for _, entry in ipairs(rightVisibleRows) do
						if entry.Path == selectedPath then
							selectedInRight = true
							break
						end
					end
				end

				if not selectedInRight then
					selectedPath = rightVisibleRows[1].Path
				end
			end

			isEmpty = rightFinalY <= 0

			emptyLabel.Position = UDim2.new(0.5, (LEFT_WIDTH + 4) / 2, 0.5, 0)
		else
			local oldCanvasPosition = list.CanvasPosition

			UI.clear(list)

			rowIndex = 0

			rowRegistry = {}

			visibleRows = {}

			local finalY = 0

			if rootPath ~= nil then
				finalY = walkSingle(rootPath, 0, 1)
			end

			list.CanvasSize = UDim2.new(1, 0, 0, finalY + 4)

			list.CanvasPosition = oldCanvasPosition

			isEmpty = finalY <= 1

			emptyLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
		end

		emptyLabel.Visible = rootPath == nil or isEmpty

		if rootPath == nil then
			emptyLabel.Text = "No active project"
		elseif isEmpty then
			emptyLabel.Text = filter ~= "" and "No matching files" or "This folder is empty"
		end

		animating = false

		rebuilding = false
	end

	local function closeDocumentsUnder(path, isDirectory)
		viewport.CloseFile(path)

		if not isDirectory then
			return
		end

		local entries = readEntries(path)

		if entries == nil then
			return
		end

		for _, entry in ipairs(entries) do
			closeDocumentsUnder(entry.Path, entryIsDirectory(entry))
		end
	end

	local function deleteEntry(path)
		if path == nil or path == rootPath then
			return
		end

		closeDocumentsUnder(path, isDirectoryPath(path))

		local ok, deleted = pcall(function()
			return filesystem:DeletePath(path)
		end)

		if not ok or not deleted then
			UI.toast("files", {
				type = "error",
				title = "Could not delete",
				message = `Failed to delete {nameOf(path)}.`,
				details = ``,
				detailsTitle = "",
				backgroundTransparency = 0.4,
				blur = true,
				duration = 5,
			})

			return
		end

		if selectedPath == path then
			selectedPath = nil
		end

		if clipboard ~= nil and isSameOrDescendantOf(clipboard, path) then
			clipboard = nil
		end

		if wideFolder ~= nil and isSameOrDescendantOf(wideFolder, path) then
			wideFolder = nil
			animateNext = true
		end

		expanded[path] = nil

		lastHash = ""
	end

	local function duplicateEntry(path)
		if path == nil or path == rootPath then
			return
		end

		local parent = parentOf(path)

		local ok, newPath = pcall(function()
			return filesystem:CopyPath(path, parent)
		end)

		if ok and type(newPath) == "string" and newPath ~= "" then
			expanded[parent] = true
			selectedPath = newPath

			lastHash = ""
		end
	end

	local function copyEntry(path)
		if path ~= nil and path ~= rootPath then
			clipboard = path
		end
	end

	local function pasteEntry(directory)
		if clipboard == nil or directory == nil then
			return
		end

		local ok, newPath = pcall(function()
			return filesystem:CopyPath(clipboard, directory)
		end)

		if ok and type(newPath) == "string" and newPath ~= "" then
			expanded[directory] = true
			selectedPath = newPath

			lastHash = ""
		end
	end

	beginRename = function(path)
		if path == nil or path == rootPath or UI.isAlive(renaming) then
			return
		end

		local registered = findRegistered(path)

		if registered == nil or not UI.isAlive(registered.row) then
			return
		end

		local isDir = isDirectoryPath(path)
		local label = registered.label

		local renamePosition, renameSize

		if registered.pane == "right" then
			renamePosition = UDim2.fromOffset(2, TILE_H - 26)
			renameSize = UDim2.new(1, -4, 0, 20)
		else
			local indent = 7 + registered.depth * 16

			renamePosition = UDim2.fromOffset(indent + 31, 1)
			renameSize = UDim2.new(1, -(indent + 36), 0, 18)
		end

		local box = UI.input(
			registered.row,
			nameOf(path),
			renamePosition,
			renameSize,
			{ textSize = tokens.type.small, color = tokens.color.input, selectAllOnFocus = true }
		)

		renaming = box
		renamedPath = path
		box.Text = nameOf(path)

		if label ~= nil and UI.isAlive(label) then
			label.Visible = false
		end

		pcall(function()
			box:CaptureFocus()
		end)
		pcall(function()
			box:SelectAll()
		end)

		local committed = false

		local function finish(apply)
			if committed then
				return
			end

			committed = true
			renameCommit = nil
			renamedPath = nil

			local text = ""

			if UI.isAlive(box) then
				text = (box.Text or ""):match("^%s*(.-)%s*$")
				box:Destroy()
			end

			if renaming == box then
				renaming = nil
			end

			if label ~= nil and UI.isAlive(label) then
				label.Visible = true
			end

			if apply and text ~= "" and text ~= nameOf(path) then
				local parent = parentOf(path)
				local problem = nil

				if text:find("[/\\]") then
					problem = "Names cannot contain slashes."
				else
					for _, other in ipairs(readEntries(parent) or {}) do
						if other.Path ~= path and string.lower(other.Name) == string.lower(text) then
							problem = `"{text}" already exists here.`
							break
						end
					end
				end

				if problem ~= nil then
					toastMessage("warning", "Could not rename", problem)
				else
					closeDocumentsUnder(path, isDir)

					local ok, renamed = pcall(function()
						return filesystem:RenamePath(path, text)
					end)

					if ok and renamed then
						local newPath = joinPath(parent, text)

						if expanded[path] then
							expanded[path] = nil
							expanded[newPath] = true
						end

						if wideFolder ~= nil and isSameOrDescendantOf(wideFolder, path) then
							wideFolder = newPath .. wideFolder:sub(#path + 1)
						end

						selectedPath = newPath
					else
						toastMessage("error", "Could not rename", `Failed to rename {nameOf(path)}.`)
					end
				end
			end

			lastHash = ""

			if pendingRebuild then
				pendingRebuild = false
				rebuild()
			end
		end

		renameCommit = finish

		box.FocusLost:Connect(function(_, input)
			finish(not (input and input.KeyCode == Enum.KeyCode.Escape))
		end)

		box.TextSubmitted:Connect(function()
			finish(true)
		end)
	end

	commitRename = function()
		local commit = renameCommit

		if commit ~= nil then
			commit(true)
		end
	end

	cancelRename = function()
		local commit = renameCommit

		if commit ~= nil then
			commit(false)
		end
	end

	local function getVisibleRows()
		return wideMode and rightVisibleRows or visibleRows
	end

	local function getRowRegistry()
		return wideMode and rightRowRegistry or rowRegistry
	end

	local function getList()
		return wideMode and rightList or list
	end

	local function rowIndexOf(path)
		local rows = getVisibleRows()

		for index, entry in ipairs(rows) do
			if entry.Path == path then
				return index
			end
		end

		return nil
	end

	local function selectAndReveal(index)
		local rows = getVisibleRows()
		local entry = rows[index]

		if entry == nil then
			return
		end

		selectedPath = entry.Path

		local registered = getRowRegistry()[entry.Path]
		local l = getList()

		if registered == nil or l == nil then
			return
		end

		local top = l.CanvasPosition.Y
		local height = l.AbsoluteSize.Y

		local itemTop = registered.y
		local itemBottom = itemTop + (registered.h or UI.metrics.treeRow)

		local target = nil

		if itemTop < top then
			target = math.max(0, itemTop - 4)
		elseif itemBottom > top + height then
			target = itemBottom - height + 4
		end

		if target ~= nil then
			l.CanvasPosition = Vector2.new(0, target)
		end
	end

	local function openEntry(path)
		if path == nil then
			return
		end

		if isDirectoryPath(path) then
			if wideMode then
				expanded[wideFolder or rootPath] = true

				navigateTo(path)
			else
				expanded[path] = not expanded[path] or nil

				lastHash = ""
			end

			rebuild()

			return
		end

		openPath(path)
	end

	local function createNamed(directory, name, isFolder, onCreated)
		if directory == nil or name == nil then
			return
		end

		commitRename()

		if filter ~= "" then
			filter = ""
			searchField.Text = ""
		end

		local unique = uniqueNameFor(directory, name)

		local ok, created = pcall(function()
			if isFolder then
				return filesystem:CreateFolder(directory, unique)
			end

			return filesystem:CreateFile(directory, unique)
		end)

		if not ok or type(created) ~= "string" or created == "" then
			UI.toast("files", {
				type = "error",
				title = isFolder and "Could not create folder" or "Could not create file",
				message = `Failed to create {unique} in {nameOf(directory)}.`,
				details = ``,
				detailsTitle = "",
				backgroundTransparency = 0.4,
				blur = true,
				duration = 5,
			})

			return
		end

		expanded[directory] = true
		selectedPath = created

		if wideMode and directory ~= (wideFolder or rootPath) then
			navigateTo(directory)
		end

		lastHash = ""

		rebuild()

		if onCreated ~= nil then
			local ok, err = pcall(
				onCreated,
				contextFor({
					Path = created,
					Name = nameOf(created),
					Type = isFolder and "Directory" or "File",
				})
			)

			if not ok then
				reportHandlerError({ Name = unique }, err)
			end
		end

		beginRename(created)
	end

	local function createEntry(templateValue)
		if rootPath == nil then
			return
		end

		local template = nil

		for _, candidate in ipairs(templates) do
			if candidate.value == templateValue then
				template = candidate

				break
			end
		end

		if template == nil then
			return
		end

		local directory

		if wideMode then
			directory = wideFolder or rootPath
		else
			directory = targetDirectoryFor(selectedPath)
		end

		createNamed(directory, template.name, template.value == "Folder", template.onCreated)
	end

	local function importFile(directory)
		if directory == nil then
			return
		end

		local file = dialog:PickFile()

		if not file then
			return
		end

		local ok, newPath = pcall(function()
			return filesystem:CopyPath(file, directory)
		end)

		if ok and type(newPath) == "string" and newPath ~= "" then
			expanded[directory] = true
			selectedPath = newPath

			lastHash = ""

			UI.toast("files", {
				type = "success",
				title = "Imported successfully!",
				message = `Imported {nameOf(newPath)} into {nameOf(directory)}.`,
				details = ``,
				detailsTitle = "",
				backgroundTransparency = 0.4,
				blur = true,
				duration = 5,
			})
		else
			UI.toast("files", {
				type = "error",
				title = "Could not import file",
				message = `Failed to import {nameOf(file)}.`,
				details = ``,
				detailsTitle = "",
				backgroundTransparency = 0.4,
				blur = true,
				duration = 5,
			})
		end
	end

	local function safePackageFolderName(value)
		local name = tostring(value or "")

		name = name:gsub('[\\/:*?"<>|]', "_")
		name = name:gsub("%s+$", "")
		name = name:gsub("%.+$", "")

		if #name > 200 then
			name = string.sub(name, 1, 200)
			name = name:gsub("%s+$", "")
			name = name:gsub("%.+$", "")
		end

		if name == "" then
			return "package"
		end

		return name
	end

	local function formatPackageSize(bytes)
		bytes = tonumber(bytes) or 0

		if bytes >= 1024 * 1024 then
			return string.format("%.1f MB", bytes / (1024 * 1024))
		elseif bytes >= 1024 then
			return string.format("%.1f KB", bytes / 1024)
		end

		return string.format("%d B", math.floor(bytes))
	end

	local function uniquePackageFolderName(directory, baseName)
		local existing = {}
		local entries = readEntries(directory)

		if entries ~= nil then
			for _, entry in ipairs(entries) do
				existing[string.lower(entry.Name)] = true
			end
		end

		if not existing[string.lower(baseName)] then
			return baseName
		end

		local index = 2

		while true do
			local candidate = string.format("%s (%d)", baseName, index)

			if not existing[string.lower(candidate)] then
				return candidate
			end

			index += 1
		end
	end

	local function importDownloadedPackage(package, directory)
		local packageName = tostring(package.name or "")

		if packageName == "" then
			packageName = "package"
		end

		local version = tostring(package.version or "")

		if version == "" then
			version = "?"
		end

		local folderBase = safePackageFolderName(packageName .. "@" .. version)
		local folderName = uniquePackageFolderName(directory, folderBase)

		local createOk, created = pcall(function()
			return filesystem:CreateFolder(directory, folderName)
		end)

		if not createOk or type(created) ~= "string" or created == "" then
			return nil, `Could not create {folderName}.`
		end

		local entries = readEntries(package.path)

		if entries == nil then
			pcall(function()
				filesystem:DeletePath(created)
			end)

			return nil, "Could not read the downloaded package."
		end

		local copied = 0

		for _, entry in ipairs(entries) do
			if entry.Name ~= ".kinemium-package" then
				local copyOk, copiedPath = pcall(function()
					return filesystem:CopyPath(entry.Path, created)
				end)

				if not copyOk or type(copiedPath) ~= "string" or copiedPath == "" then
					pcall(function()
						filesystem:DeletePath(created)
					end)

					return nil, `Could not copy {entry.Name}.`
				end

				copied += 1
			end
		end

		if copied == 0 then
			pcall(function()
				filesystem:DeletePath(created)
			end)

			return nil, "The downloaded package is empty."
		end

		return created
	end

	local function openImportPackage(directory)
		if directory == nil then
			return
		end

		local listOk, packages = pcall(function()
			return Packages:ListDownloadedPackages()
		end)

		if not listOk or type(packages) ~= "table" then
			toastMessage(
				"error",
				"Could not read downloaded packages",
				"Try again after the Packages service is available."
			)

			return
		end

		local list = {}

		for _, package in ipairs(packages) do
			if type(package) == "table" and type(package.path) == "string" and package.path ~= "" then
				local dirOk, isDir = pcall(function()
					return filesystem:IsDirectory(package.path)
				end)

				if dirOk and isDir then
					list[#list + 1] = package
				end
			end
		end

		table.sort(list, function(a, b)
			local aTime = tonumber(a.downloadedAt) or 0
			local bTime = tonumber(b.downloadedAt) or 0

			if aTime ~= bTime then
				return aTime > bTime
			end

			local aKey = tostring(a.namespace or "")
				.. "/"
				.. tostring(a.name or "")
				.. "@"
				.. tostring(a.version or "")
			local bKey = tostring(b.namespace or "")
				.. "/"
				.. tostring(b.name or "")
				.. "@"
				.. tostring(b.version or "")

			return aKey < bKey
		end)

		local _, content, controller = UI.prompt({
			title = "Import Package",
			description = `Choose a downloaded package to import into {nameOf(directory)}.`,
			size = UDim2.fromOffset(560, 520),
			padding = 14,
			scrollable = true,
			destroyOnClose = true,
			buttons = {
				{
					id = "cancel",
					text = "Cancel",
					role = "secondary",
				},
			},
		})

		local ROW_HEIGHT = 58
		local ROW_GAP = 6

		content.CanvasSize = UDim2.fromOffset(0, math.max(#list * (ROW_HEIGHT + ROW_GAP), 56))

		if #list == 0 then
			local empty = UI.label(
				content,
				"No downloaded packages. Download one from the Marketplace first.",
				UDim2.fromOffset(4, 4),
				UDim2.new(1, -8, 0, 48),
				tokens.type.body,
				tokens.color.muted
			)

			empty.TextWrapped = true
			empty.TextXAlignment = Enum.TextXAlignment.Left
			empty.TextYAlignment = Enum.TextYAlignment.Top

			return
		end

		for index, package in ipairs(list) do
			local namespace = tostring(package.namespace or "")
			local packageName = tostring(package.name or "")

			if packageName == "" then
				packageName = "Unknown Package"
			end

			local version = tostring(package.version or "")

			if version == "" then
				version = "?"
			end

			local row, rowLabel = UI.button(
				content,
				"",
				UDim2.fromOffset(0, (index - 1) * (ROW_HEIGHT + ROW_GAP)),
				UDim2.new(1, -6, 0, ROW_HEIGHT),
				function()
					controller:Close("import")

					local created, err = importDownloadedPackage(package, directory)

					if created == nil then
						toastMessage("error", "Could not import package", err or "Unknown error.")
						return
					end

					expanded[directory] = true
					selectedPath = created
					lastHash = ""

					rebuild()

					toastMessage(
						"success",
						"Package imported",
						`Imported {packageName}@{version} into {nameOf(directory)}.`
					)
				end,
				{
					color = tokens.color.surfaceAlt,
					hoverColor = tokens.color.hover,
					pressedColor = tokens.color.pressed,
					radius = tokens.radius.md,
					border = false,
				}
			)

			row.Name = "PackageRow" .. tostring(index)
			rowLabel.Visible = false

			local title = UI.label(
				row,
				packageName,
				UDim2.fromOffset(12, 8),
				UDim2.new(1, -24, 0, 20),
				tokens.type.body,
				tokens.color.text
			)

			title.TextXAlignment = Enum.TextXAlignment.Left
			title.TextTruncate = Enum.TextTruncate.AtEnd

			local metaText = "v" .. version .. "  |  " .. formatPackageSize(package.size)

			if namespace ~= "" then
				metaText = namespace .. "  |  " .. metaText
			end

			local meta = UI.label(
				row,
				metaText,
				UDim2.fromOffset(12, 30),
				UDim2.new(1, -24, 0, 16),
				tokens.type.caption,
				tokens.color.muted
			)

			meta.TextXAlignment = Enum.TextXAlignment.Left
			meta.TextTruncate = Enum.TextTruncate.AtEnd
		end
	end

	local contextMenu
	local contextMenuOptions
	local contextTarget = nil
	local contextCustom = {}

	openContextMenu = function(entry, screenPoint)
		if entry == nil then
			return
		end

		contextTarget = entry.Path

		if contextMenu == nil then
			contextMenuOptions = {
				items = {},
				menuWidth = 180,
				itemHeight = UI.metrics.inputHeight,
				maxVisibleItems = 12,
				closeOnOutsideClick = false,
				menuPosition = function()
					return UDim2.fromOffset(0, 0)
				end,
				onChanged = function(action)
					local path = contextTarget
					contextTarget = nil

					if path == nil then
						return
					end

					local custom = contextCustom[action]

					if custom ~= nil then
						local ok, err = pcall(custom.callback, custom.context)

						if not ok then
							reportHandlerError(custom.context.Entry, err)
						end

						return
					end

					if action == "new_folder" or action == "new_script" then
						createNamed(
							targetDirectoryFor(path),
							action == "new_folder" and "Folder" or "Script.luau",
							action == "new_folder"
						)

						return
					end

					if action == "open" then
						openEntry(path)
					elseif action == "rename" then
						beginRename(path)
					elseif action == "import" then
						importFile(targetDirectoryFor(path))
					elseif action == "import_package" then
						openImportPackage(targetDirectoryFor(path))
					elseif action == "duplicate" then
						duplicateEntry(path)
					elseif action == "copypath" then
						copyPathWindow(path)
					elseif action == "delete" then
						deleteEntry(path)
					elseif action == "copy" then
						copyEntry(path)
					elseif action == "paste" then
						pasteEntry(targetDirectoryFor(path))
					end
				end,
			}

			local controller = UI.contextMenu(
				content,
				"",
				UDim2.fromOffset(-400, -400),
				UDim2.fromOffset(1, 1),
				nil,
				contextMenuOptions
			)

			contextMenu = controller
		end

		local items = {
			{ label = "New Folder", value = "new_folder", icon = "builtin://global-icons/folder.svg" },
			{ label = "New Luau Script", value = "new_script", icon = "builtin://icons/Script.svg" },
			{ label = "Open", value = "open", icon = "builtin://global-icons/api.png" },
			{ label = "Rename", value = "rename", icon = "builtin://global-icons/pencil.svg" },
			{ label = "Duplicate", value = "duplicate", icon = "builtin://global-icons/plus.svg" },
			{ label = "Delete", value = "delete", icon = "builtin://global-icons/x.svg" },
			{ label = "Copy Path", value = "copypath", icon = "builtin://global-icons/copy.svg" },
			{ label = "Copy", value = "copy", icon = "builtin://global-icons/copy.svg" },
			{ label = "Paste", value = "paste", icon = "builtin://global-icons/paste_clipboard.svg" },
			{ label = "Import File..", value = "import", icon = "builtin://global-icons/folder.svg" },
			{ label = "Import Package..", value = "import_package", icon = "builtin://global-icons/package.svg" },
		}

		contextCustom = {}

		local fileType = fileTypeOf(entry)

		if fileType ~= nil and fileType.contextItems ~= nil then
			local context = contextFor(entry)

			for index, item in ipairs(fileType.contextItems) do
				local value = "custom:" .. index

				contextCustom[value] = { callback = item.callback, context = context }

				items[#items + 1] = {
					label = item.label,
					value = value,
					icon = item.icon or fileType.icon,
				}
			end
		end

		contextMenu:SetItems(items)

		contextMenuOptions.menuPosition = function()
			return UDim2.fromOffset(screenPoint.X, screenPoint.Y)
		end

		contextMenu:Open()
	end

	closeContextMenu = function()
		if contextMenu ~= nil then
			contextMenu:Close()
		end

		contextTarget = nil
	end

	local dropdown =
		UI.dropdown(content, "", UDim2.new(1, -32, 0, 6), UDim2.fromOffset(26, UI.metrics.inputHeight), nil, {
			items = templates,

			searchPlaceholder = "Search files to create...",

			icon = "builtin://global-icons/plus.svg",
			iconSize = 14,

			color = tokens.color.input,
			hoverColor = tokens.color.hover,
			closeOnOutsideClick = false,
			menuWidth = 180,
			menuSide = "left",
			itemBgTransparency = 1,
			menuPosition = function()
				local coordinates = theme.ExplorerCoordinates

				return UDim2.new(
					coordinates.Position.X.Scale,
					coordinates.Position.X.Offset - 174,
					coordinates.Position.Y.Scale,
					coordinates.Position.Y.Offset + 5 + UI.metrics.windowHeader + 6
				)
			end,

			maxVisibleItems = #templates,
			itemHeight = UI.metrics.inputHeight,

			onChanged = function(value)
				createEntry(value)
			end,
		})

	searchField.TextChanged:Connect(function()
		filter = string.lower(searchField.Text or "")

		lastHash = ""

		rebuild()
	end)

	local DRAG_THRESHOLD = 4

	local function pointInGui(gui, mouse)
		local position = gui.AbsolutePosition
		local size = gui.AbsoluteSize

		return mouse.X >= position.X
			and mouse.X <= position.X + size.X
			and mouse.Y >= position.Y
			and mouse.Y <= position.Y + size.Y
	end

	local function mouseInList()
		local mouse = UserInputService:GetMouseLocation()

		local lists = wideMode and { leftList, rightList } or { list }

		for _, l in ipairs(lists) do
			if l and UI.isAlive(l) and pointInGui(l, mouse) then
				return true
			end
		end

		return false
	end

	local function updateDragTarget()
		local mouse = UserInputService:GetMouseLocation()
		local source = drag.source
		local best = nil

		if wideMode then
			for _, registry in ipairs({ leftRowRegistry, rightRowRegistry }) do
				for path, registered in pairs(registry) do
					if
						entryIsDirectory(registered.entry)
						and UI.isAlive(registered.row)
						and pointInGui(registered.row, mouse)
						and canReparent(source, path)
					then
						best = path
					end
				end
			end

			if best == nil and rightList ~= nil and UI.isAlive(rightList) and pointInGui(rightList, mouse) then
				local folder = wideFolder or rootPath

				if canReparent(source, folder) then
					best = folder
				end
			end
		else
			local bestDistance = math.huge

			for path, registered in pairs(rowRegistry) do
				local row = registered.row

				if not UI.isAlive(row) then
					continue
				end

				local size = row.AbsoluteSize
				local offset = mouse.Y - row.AbsolutePosition.Y

				if offset < -size.Y or offset > size.Y * 2 then
					continue
				end

				local target = offset > size.Y / 2 and (entryIsDirectory(registered.entry) and path or parentOf(path))
					or parentOf(path)

				if not canReparent(source, target) then
					continue
				end

				local distance = math.abs(offset - size.Y / 2)

				if distance < bestDistance then
					bestDistance = distance
					best = target
				end
			end
		end

		if best ~= drag.target then
			setDropHighlight(drag.target, false)

			drag.target = best

			setDropHighlight(best, true)
		end
	end

	local function beginDragVisual()
		if dragLayer ~= nil then
			return
		end

		dragLayer = UI.create("Frame", {
			Position = UDim2.fromOffset(drag.startX + 10, drag.startY),
			Size = UDim2.fromOffset(150, UI.metrics.treeRow - 4),
			BackgroundColor3 = colors.selection,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Active = false,
			ZIndex = 5000,
		}, UI.widgetOverlay())

		UI.corner(dragLayer, tokens.radius.sm)

		UI.label(
			dragLayer,
			nameOf(drag.source),
			UDim2.fromOffset(8, 2),
			UDim2.new(1, -16, 0, 16),
			tokens.type.small,
			tokens.color.text
		)

		tween(dragLayer, {
			BackgroundTransparency = 0.2,
			Size = UDim2.fromOffset(180, UI.metrics.treeRow),
		}, 0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end

	local function moveDragVisual()
		if dragLayer == nil then
			return
		end

		local mouse = UserInputService:GetMouseLocation()

		dragLayer.Position = UDim2.fromOffset(mouse.X + 10, mouse.Y)
	end

	UserInputService.InputChanged:Connect(function(input: InputObject)
		if drag == nil then
			return
		end

		if input.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end

		local dx = input.Position.X - drag.startX
		local dy = input.Position.Y - drag.startY

		if not drag.active then
			if math.sqrt(dx * dx + dy * dy) < DRAG_THRESHOLD then
				return
			end

			drag.active = true

			selectedPath = drag.source

			beginDragVisual()
		end

		local mouse = UserInputService:GetMouseLocation()

		if mouseInList() then
			viewport.SetDropHighlight(false)
			updateDragTarget()
		else
			if drag.target ~= nil then
				setDropHighlight(drag.target, false)
			end

			drag.target = nil

			local over = viewport.ContainsPoint(mouse)
			local fileType = fileTypeOf(entryForPath(drag.source))

			viewport.SetDropHighlight(over and fileType ~= nil and fileType.onDrop ~= nil)
		end

		moveDragVisual()
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if drag == nil or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end

		if not drag.active then
			drag = nil
			return
		end

		suppressClickUntil = os.clock() + 0.2

		local source = drag.source
		local hadTarget = drag.target ~= nil
		local mouse = UserInputService:GetMouseLocation()

		if not hadTarget and not mouseInList() then
			local inside, localPosition = viewport.ContainsPoint(mouse)
			local entry = entryForPath(source)
			local fileType = fileTypeOf(entry)

			if inside and fileType ~= nil and fileType.onDrop ~= nil then
				animateDrop(false)

				local context = contextFor(entry)
				context.ScreenPosition = mouse
				context.ViewportPosition = localPosition

				local ok, err = pcall(fileType.onDrop, context)

				if not ok then
					reportHandlerError(entry, err)
				end

				return
			end
		end

		animateDrop(hadTarget)
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end

		if viewerBlocksInput() then
			return
		end

		local typing = UserInputService:GetFocusedTextBox() ~= nil

		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			if not mouseInList() then
				closeContextMenu()
			end

			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local mouse = UserInputService:GetMouseLocation()
			local overMenu = contextMenu ~= nil and contextMenu:ContainsPoint(mouse.X, mouse.Y)

			if not mouseInList() and not overMenu then
				closeContextMenu()
				commitRename()
			end

			return
		end

		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end

		if input.KeyCode == Enum.KeyCode.Escape then
			if drag ~= nil then
				finishDrop(false)
			elseif UI.isAlive(renaming) then
				cancelRename()
			elseif contextMenu ~= nil then
				closeContextMenu()
			elseif typing then
				searchField.Text = ""
			else
				selectedPath = nil

				lastHash = ""
			end

			return
		end

		if not filesTabActive() or typing then
			return
		end

		if input.KeyCode == Enum.KeyCode.Return then
			openEntry(selectedPath)

			return
		end

		local index = selectedPath and rowIndexOf(selectedPath) or nil

		if wideMode then
			local step = nil

			if input.KeyCode == Enum.KeyCode.Up then
				step = -gridColumns()
			elseif input.KeyCode == Enum.KeyCode.Down then
				step = gridColumns()
			elseif input.KeyCode == Enum.KeyCode.Left then
				step = -1
			elseif input.KeyCode == Enum.KeyCode.Right then
				step = 1
			end

			if step ~= nil then
				local rows = getVisibleRows()

				if #rows > 0 then
					selectAndReveal(index and math.clamp(index + step, 1, #rows) or 1)
				end

				return
			end
		end

		if input.KeyCode == Enum.KeyCode.Up or input.KeyCode == Enum.KeyCode.Down then
			local rows = getVisibleRows()

			if #rows == 0 then
				return
			end

			local next_ = index or 0

			if input.KeyCode == Enum.KeyCode.Up then
				next_ = next_ - 1
			else
				next_ = next_ + 1
			end

			selectAndReveal(math.clamp(next_, 1, #rows))

			return
		end

		if input.KeyCode == Enum.KeyCode.Home then
			selectAndReveal(1)
			return
		end

		if input.KeyCode == Enum.KeyCode.End then
			local rows = getVisibleRows()

			selectAndReveal(#rows)
			return
		end

		if input.KeyCode == Enum.KeyCode.Right then
			if selectedPath ~= nil and not expanded[selectedPath] and isDirectoryPath(selectedPath) then
				expanded[selectedPath] = true

				lastHash = ""
			end

			return
		end

		if input.KeyCode == Enum.KeyCode.Left then
			if selectedPath ~= nil then
				if expanded[selectedPath] then
					expanded[selectedPath] = nil

					lastHash = ""
				else
					local parent = parentOf(selectedPath)

					if parent ~= "" and parent ~= rootPath then
						local parentIndex = rowIndexOf(parent)

						if parentIndex ~= nil then
							selectAndReveal(parentIndex)
						end
					end
				end
			end

			return
		end

		if input.KeyCode == Enum.KeyCode.F2 then
			if selectedPath ~= nil then
				beginRename(selectedPath)
			end

			return
		end

		if input.KeyCode == Enum.KeyCode.C then
			local ctrlDown = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)

			if ctrlDown then
				copyEntry(selectedPath)
			end

			return
		end

		if input.KeyCode == Enum.KeyCode.V then
			local ctrlDown = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)

			if ctrlDown then
				if wideMode then
					pasteEntry(wideFolder or rootPath)
				else
					pasteEntry(targetDirectoryFor(selectedPath))
				end
			end

			return
		end

		if input.KeyCode == Enum.KeyCode.D then
			local ctrlDown = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)

			if ctrlDown then
				duplicateEntry(selectedPath)
			end

			return
		end

		if input.KeyCode == Enum.KeyCode.Delete or input.KeyCode == Enum.KeyCode.Backspace then
			deleteEntry(selectedPath)

			return
		end
	end)

	local function loadRoot()
		local project = Project:GetActiveProject()

		rootPath = project and project.Path or nil
	end

	loadRoot()

	rebuild()

	local hashFrame = 0

	renderer.Pool.new("2d", function()
		if not filesTabActive() then
			return
		end

		local explorerWidth = content.AbsoluteSize.X
		local outputWidth = 0

		if theme.OutputCoordinates and theme.OutputCoordinates.Size then
			outputWidth = theme.OutputCoordinates.Size.X.Offset
		end

		local newWideMode = explorerWidth >= outputWidth and outputWidth > 0

		if newWideMode ~= wideMode then
			commitRename()

			rowRegistry, leftRowRegistry, rightRowRegistry = {}, {}, {}
			visibleRows, leftVisibleRows, rightVisibleRows = {}, {}, {}

			wideMode = newWideMode

			if wideMode then
				if list and UI.isAlive(list) then
					list:Destroy()
				end

				leftList = createList(content, UDim2.fromOffset(inset, 36), UDim2.new(0, LEFT_WIDTH, 1, -42), true)

				rightList = createList(
					content,
					UDim2.fromOffset(inset + LEFT_WIDTH + 4, 36),
					UDim2.new(1, -(inset * 2 + LEFT_WIDTH + 4), 1, -42),
					true
				)
			else
				if leftList and UI.isAlive(leftList) then
					leftList:Destroy()
				end

				if rightList and UI.isAlive(rightList) then
					rightList:Destroy()
				end

				leftList = nil
				rightList = nil

				list = createList(content, UDim2.fromOffset(inset, 36), UDim2.new(1, -inset * 2, 1, -42), true)
			end

			expanded = {}
			wideFolder = nil

			if wideMode and rootPath ~= nil then
				expanded[rootPath] = true
			end

			animateNext = true

			lastHash = ""
			rebuild()
		end

		if rootPath == nil then
			hashFrame += 1

			if hashFrame % 15 == 0 then
				loadRoot()

				if rootPath ~= nil then
					if wideMode then
						expanded[rootPath] = true
					end

					lastHash = ""

					rebuild()
				end
			end

			return
		end

		hashFrame += 1

		if hashFrame % 15 ~= 0 then
			return
		end

		local hash = treeHash(rootPath)
			.. "#"
			.. (selectedPath or "")
			.. "#"
			.. (wideMode and (wideFolder or "") or "")
			.. "#"
			.. (wideMode and gridColumns() or 0)
			.. "#"
			.. (wideMode and treeHash(wideFolder or rootPath) or "")

		if hash ~= lastHash then
			lastHash = hash

			rebuild()
		end
	end)

	return {
		RegisterFileType = function(definition)
			registerFileType(definition)

			lastHash = ""
		end,

		Refresh = function()
			loadRoot()

			expanded = {}
			selectedPath = nil
			clipboard = nil
			wideFolder = nil

			if wideMode and rootPath ~= nil then
				expanded[rootPath] = true
			end

			animateNext = true

			lastHash = ""

			rebuild()
		end,

		GetSelectedPath = function()
			return selectedPath
		end,
	}
end

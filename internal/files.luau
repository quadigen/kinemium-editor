if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local UI = require("@internal/editor_ui")
local viewport = require("@internal/viewport")

local Project = game:GetService("Project")
local dialog = game:GetService("DialogService")

local StudioThemeService = game:GetService("StudioThemeService")
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
})

registerFileType({
	name = "Material",
	extensions = { "mat" },
	icon = "builtin://icons/Texture.svg",
})

registerFileType({
	name = "Image",
	extensions = { "png", "jpg", "jpeg", "webp", "gif", "bmp" },
	icon = "builtin://icons/ImageLabel.svg",
	thumbnail = true,

	onOpen = function(ctx)
		openImageViewer(ctx)
	end,

	contextItems = {
		{ label = "Open in Image Viewer", icon = "builtin://icons/ImageLabel.svg", callback = openImageViewer },
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

	local function isDirectoryPath(path)
		if path == nil then
			return false
		end

		if path == rootPath then
			return true
		end

		local registered = rowRegistry[path]

		if registered == nil and wideMode then
			registered = rightRowRegistry[path] or leftRowRegistry[path]
		end

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

		if string.find(string.lower(entry.Name), filter, 1, true) then
			return true
		end

		if not entryIsDirectory(entry) then
			return false
		end

		local entries = readEntries(entry.Path)

		if entries == nil then
			return false
		end

		for _, child in ipairs(entries) do
			if subtreeMatches(child) then
				return true
			end
		end

		return false
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
		local ok, moved = pcall(function()
			return Project:MovePath(source, target)
		end)

		if ok and moved then
			expanded[target] = true
			selectedPath = joinPath(target, nameOf(source))

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
		local source = drag.source
		local target = drag.target

		local function apply()
			disposeDrag()
			clearDropHighlight()

			if reparent and source ~= nil and target ~= nil and canReparent(source, target) then
				moveEntry(source, target)
			end
		end

		if dragLayer == nil then
			apply()
			return
		end

		local layer = dragLayer

		local goal = { BackgroundTransparency = 1 }

		if reparent then
			goal.Size = UDim2.fromOffset(110, UI.metrics.treeRow - 4)
		end

		local played = tween(layer, goal, 0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

		if played == nil then
			apply()
			return
		end

		played.Completed:Once(function()
			apply()
		end)
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

		UI.label(
			row,
			entry.Name,
			UDim2.fromOffset(indent + 31, 2),
			UDim2.new(1, -(indent + 34), 0, 17),
			tokens.type.small,
			isSelected and tokens.color.text or colors.text
		)

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
			return Project:DeletePath(path)
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
			return Project:CopyPath(path, parent)
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
			return Project:CopyPath(clipboard, directory)
		end)

		if ok and type(newPath) == "string" and newPath ~= "" then
			expanded[directory] = true
			selectedPath = newPath

			lastHash = ""
		end
	end

	beginRename = function(path)
		if path == nil or path == rootPath then
			return
		end

		if UI.isAlive(renaming) then
			return
		end

		local registered = rowRegistry[path]

		if registered == nil and wideMode then
			registered = rightRowRegistry[path] or leftRowRegistry[path]
		end

		if registered == nil or not UI.isAlive(registered.row) then
			return
		end

		local renamePosition
		local renameSize

		if registered.pane == "right" then
			renamePosition = UDim2.fromOffset(2, TILE_H - 26)
			renameSize = UDim2.new(1, -4, 0, 20)
		else
			local indent = 7 + registered.depth * 16

			renamePosition = UDim2.fromOffset(indent + 31, 1)
			renameSize = UDim2.new(1, -(indent + 36), 0, 18)
		end

		renaming = UI.input(
			registered.row,
			nameOf(path),
			renamePosition,
			renameSize,
			{ textSize = tokens.type.small, color = tokens.color.input, selectAllOnFocus = true }
		)

		renaming.Text = nameOf(path)

		pcall(function()
			renaming:SelectAll()
		end)

		renamedPath = path

		local committed = false

		local function finish(apply)
			if committed then
				return
			end

			committed = true

			renameCommit = nil
			renamedPath = nil

			local text = renaming.Text

			if renaming ~= nil and UI.isAlive(renaming) then
				renaming:Destroy()
			end

			renaming = nil

			if apply and text ~= nil and text ~= "" and text ~= nameOf(path) then
				local parent = parentOf(path)

				local ok, renamed = pcall(function()
					return Project:RenamePath(path, text)
				end)

				if ok and renamed then
					viewport.CloseFile(path)

					selectedPath = joinPath(parent, text)
				end
			end

			lastHash = ""

			if pendingRebuild then
				pendingRebuild = false

				rebuild()
			end
		end

		renameCommit = finish

		renaming.FocusLost:Connect(function()
			finish(true)
		end)

		renaming.TextSubmitted:Connect(function()
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

		local unique = uniqueNameFor(directory, name)

		local ok, created = pcall(function()
			if isFolder then
				return Project:CreateFolder(directory, unique)
			end

			return Project:CreateFile(directory, unique)
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
			return Project:CopyPath(file, directory)
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
				itemBgTransparency = 1,
				showSearch = false,
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
					elseif action == "duplicate" then
						duplicateEntry(path)
					elseif action == "delete" then
						deleteEntry(path)
					elseif action == "copy" then
						copyEntry(path)
					elseif action == "paste" then
						pasteEntry(targetDirectoryFor(path))
					end
				end,
			}

			local _, _, controller =
				UI.dropdown(content, "", UDim2.fromOffset(-400, -400), UDim2.fromOffset(1, 1), nil, contextMenuOptions)

			contextMenu = controller
		end

		local items = {
			{ label = "New Folder", value = "new_folder", icon = "builtin://global-icons/folder.svg" },
			{ label = "New Luau Script", value = "new_script", icon = "builtin://icons/Script.svg" },
			{ label = "Open", value = "open", icon = "builtin://global-icons/api.png" },
			{ label = "Rename", value = "rename", icon = "builtin://global-icons/pencil.svg" },
			{ label = "Duplicate", value = "duplicate", icon = "builtin://global-icons/plus.svg" },
			{ label = "Delete", value = "delete", icon = "builtin://global-icons/x.svg" },
			{ label = "Copy", value = "copy", icon = "builtin://global-icons/copy.svg" },
			{ label = "Paste", value = "paste", icon = "builtin://global-icons/paste_clipboard.svg" },
			{ label = "Import File..", value = "import", icon = "builtin://global-icons/folder.svg" },
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
			backdrop = true,

			color = tokens.color.input,
			hoverColor = tokens.color.hover,
			closeOnOutsideClick = false,
			menuWidth = 180,
			menuSide = "left",
			itemBgTransparency = 1,
			BackgroundTransparency = 0.5,
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
		}, UI.root())

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

		if mouseInList() then
			updateDragTarget()
		else
			if drag.target ~= nil then
				setDropHighlight(drag.target, false)
			end

			drag.target = nil
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
		animateDrop(drag.target ~= nil)
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
			if not mouseInList() then
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

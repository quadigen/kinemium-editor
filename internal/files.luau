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

local inset = UI.metrics.panelInset

local fileIcons = {
	lua = "builtin://icons/Script.svg",
	luau = "builtin://icons/Script.svg",
	odin = "builtin://icons/Script.svg",
	cs = "builtin://icons/Script.svg",
	py = "builtin://icons/Script.svg",
	js = "builtin://icons/Script.svg",
	ts = "builtin://icons/Script.svg",

	png = "builtin://icons/ImageLabel.svg",
	jpg = "builtin://icons/ImageLabel.svg",
	jpeg = "builtin://icons/ImageLabel.svg",
	webp = "builtin://icons/ImageLabel.svg",
	gif = "builtin://icons/ImageLabel.svg",
	bmp = "builtin://icons/ImageLabel.svg",
	svg = "builtin://icons/ImageLabel.svg",

	wav = "builtin://icons/Sound.svg",
	mp3 = "builtin://icons/Sound.svg",
	ogg = "builtin://icons/Sound.svg",

	mat = "builtin://icons/Texture.svg",
}

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

	local searchField =
		UI.input(content, "Search Files...", UDim2.fromOffset(inset, 6), UDim2.new(1, -42, 0, UI.metrics.inputHeight))

	local list = UI.create("ScrollingFrame", {
		Position = UDim2.fromOffset(inset, 36),
		Size = UDim2.new(1, -inset * 2, 1, -42),

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
	}, content)

	UI.corner(list, tokens.radius.md)

	local emptyLabel = UI.label(
		content,
		"No active project",
		UDim2.new(0.5, 0, 0.5, 0),
		UDim2.fromOffset(240, 20),
		tokens.type.small,
		tokens.color.muted
	)

	emptyLabel.AnchorPoint = Vector2.new(0.5, 0.5)

	-- Paths arrive from the engine in whatever separator style the platform
	-- uses, so every comparison below normalises before matching.
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

		return registered ~= nil and entryIsDirectory(registered.entry)
	end

	local function iconFor(entry)
		if entryIsDirectory(entry) then
			return "builtin://icons/Folder.svg"
		end

		local name = string.lower(entry.Name)
		local extension = name:match("%.([%w]+)$")

		if extension and fileIcons[extension] then
			return fileIcons[extension]
		end

		return "builtin://icons/File.svg"
	end

	local function selectedEntry()
		if selectedPath == nil then
			return nil
		end

		local registered = rowRegistry[selectedPath]

		return registered and registered.entry or nil
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

	local function clearDropHighlight()
		for _, registered in pairs(rowRegistry) do
			local row = registered.row

			if UI.isAlive(row) then
				row.BackgroundTransparency = registered.baseTransparency
			end

			registered.dropTarget = false
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

	local function finishDrop(reparent)
		local source = drag.source
		local target = drag.target

		disposeDrag()
		clearDropHighlight()

		if reparent and source ~= nil and target ~= nil and canReparent(source, target) then
			local ok, moved = pcall(function()
				return Project:MovePath(source, target)
			end)

			if ok and moved then
				expanded[target] = true
				selectedPath = joinPath(target, nameOf(source))

				lastHash = ""
			end
		end
	end

	local function animateDrop(reparent)
		-- Capture the drag now: finishDrop runs from the tween's Completed callback
		-- ~0.12s later, by which point `drag` may describe a different gesture.
		local source = drag.source
		local target = drag.target

		local function apply()
			disposeDrag()
			clearDropHighlight()

			if reparent and source ~= nil and target ~= nil and canReparent(source, target) then
				local ok, moved = pcall(function()
					return Project:MovePath(source, target)
				end)

				if ok and moved then
					expanded[target] = true
					selectedPath = joinPath(target, nameOf(source))

					lastHash = ""
				end
			end
		end

		if dragLayer == nil then
			apply()
			return
		end

		local layer = dragLayer

		local tween = TweenService:Create(layer, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1,
		})

		tween.Completed:Once(function()
			apply()
		end)

		tween:Play()
	end

	local addRow
	local lastClickPath = nil
	local lastClickTime = 0

	addRow = function(entry, depth, y)
		local isSelected = selectedPath == entry.Path

		rowIndex += 1

		local rowColor = rowIndex % 2 == 0 and tokens.color.rowEven or tokens.color.rowOdd

		local row = UI.button(list, "", UDim2.fromOffset(1, y), UDim2.new(1, -2, 0, UI.metrics.treeRow), function()
			-- A second click on the same row inside the double-click window is the
			-- first half of a double-click, so its toggle is undone before applying
			-- a single deliberate one.
			local now = os.clock()
			local doubleClick = lastClickPath == entry.Path and now - lastClickTime < 0.3

			lastClickPath = entry.Path
			lastClickTime = now

			selectedPath = entry.Path

			if entryIsDirectory(entry) then
				if doubleClick then
					expanded[entry.Path] = not expanded[entry.Path] or nil
				end

				expanded[entry.Path] = not expanded[entry.Path] or nil

				lastHash = ""
			elseif doubleClick then
				viewport.OpenFile(entry.Path, entry.Name)
			end
		end, {
			color = isSelected and colors.selection or rowColor,

			hoverColor = isSelected and colors.selection or colors.hover,

			radius = isSelected and tokens.radius.sm or 0,

			border = false,
		})

		row.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton2 then
				-- Commit any in-flight rename and dismiss the previous menu before
				-- opening a new one, so neither outlives the interaction.
				commitRename()
				closeContextMenu()

				selectedPath = entry.Path

				openContextMenu(entry, input.Position)

				return
			end

			if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
				return
			end

			-- Clicking any row dismisses an open context menu and commits an
			-- in-flight rename; neither should survive the interaction.
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
			}
		end)

		row.BackgroundTransparency = isSelected and 0 or 0.12

		rowRegistry[entry.Path] = {
			row = row,
			entry = entry,
			depth = depth,
			y = y,
			baseTransparency = row.BackgroundTransparency,
			dropTarget = false,
		}

		visibleRows[#visibleRows + 1] = entry

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

	local function walk(directory, depth, y)
		local entries = readEntries(directory)

		if entries == nil then
			return y
		end

		for _, entry in ipairs(entries) do
			if subtreeMatches(entry) then
				y = addRow(entry, depth, y)

				if entryIsDirectory(entry) and (expanded[entry.Path] or filter ~= "") then
					y = walk(entry.Path, depth + 1, y)
				end
			end
		end

		return y
	end

	rebuild = function()
		if rebuilding then
			return
		end

		-- A live rename box lives inside a row, so rebuilding would destroy the
		-- field mid-edit. Defer until the rename finishes.
		if UI.isAlive(renaming) then
			pendingRebuild = true
			return
		end

		rebuilding = true

		local oldCanvasPosition = list.CanvasPosition

		UI.clear(list)

		rowIndex = 0

		rowRegistry = {}

		visibleRows = {}

		local finalY = 0

		if rootPath ~= nil then
			finalY = walk(rootPath, 0, 1)
		end

		list.CanvasSize = UDim2.new(1, 0, 0, finalY + 4)

		list.CanvasPosition = oldCanvasPosition

		emptyLabel.Visible = rootPath == nil or finalY <= 1

		if rootPath == nil then
			emptyLabel.Text = "No active project"
		elseif finalY <= 1 then
			emptyLabel.Text = "This folder is empty"
		end

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
		if path == nil then
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

		expanded[path] = nil

		lastHash = ""
	end

	local function duplicateEntry(path)
		if path == nil then
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
		if path ~= nil then
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
		if path == nil then
			return
		end

		if UI.isAlive(renaming) then
			return
		end

		local registered = rowRegistry[path]

		if registered == nil or not UI.isAlive(registered.row) then
			return
		end

		local indent = 7 + registered.depth * 16

		renaming = UI.input(
			registered.row,
			nameOf(path),
			UDim2.fromOffset(indent + 31, 1),
			UDim2.new(1, -(indent + 36), 0, 18),
			{ textSize = tokens.type.small, color = tokens.color.input, selectAllOnFocus = true }
		)

		renaming.Text = nameOf(path)

		-- Preselecting is cosmetic; a runtime that rejects the native call must not
		-- take the whole rename down with it.
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

				local ok = pcall(function()
					return Project:RenamePath(path, text)
				end)

				if ok then
					-- The open document tracked the old path, so it has to go.
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

	-- Applies the pending rename, if any. Clicking elsewhere in the tree should
	-- keep whatever was typed rather than silently discarding it.
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

	local function rowIndexOf(path)
		for index, entry in ipairs(visibleRows) do
			if entry.Path == path then
				return index
			end
		end

		return nil
	end

	local function selectAndReveal(index)
		local entry = visibleRows[index]

		if entry == nil then
			return
		end

		selectedPath = entry.Path

		local registered = rowRegistry[entry.Path]

		if registered ~= nil then
			local target = math.max(0, registered.y - list.AbsoluteSize.Y / 2)

			list.CanvasPosition = Vector2.new(0, target)
		end
	end

	local function openEntry(path)
		if path == nil then
			return
		end

		if isDirectoryPath(path) then
			expanded[path] = not expanded[path] or nil

			lastHash = ""

			rebuild()

			return
		end

		viewport.OpenFile(path, nameOf(path))
	end

	-- Creates `name` inside `directory`, selects the new entry and starts an
	-- inline rename so the placeholder name can be replaced immediately.
	local function createNamed(directory, name, isFolder)
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

		lastHash = ""

		rebuild()

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

		createNamed(targetDirectoryFor(selectedPath), template.name, template.value == "Folder")
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
				maxVisibleItems = 9,
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

		contextMenu:SetItems({
			{ label = "New Folder", value = "new_folder", icon = "builtin://global-icons/folder.svg" },
			{ label = "New Luau Script", value = "new_script", icon = "builtin://icons/Script.svg" },
			{ label = "Open", value = "open", icon = "builtin://global-icons/api.png" },
			{ label = "Rename", value = "rename", icon = "builtin://global-icons/pencil.svg" },
			{ label = "Duplicate", value = "duplicate", icon = "builtin://global-icons/plus.svg" },
			{ label = "Delete", value = "delete", icon = "builtin://global-icons/x.svg" },
			{ label = "Copy", value = "copy", icon = "builtin://global-icons/copy.svg" },
			{ label = "Paste", value = "paste", icon = "builtin://global-icons/paste_clipboard.svg" },
			{ label = "Import File..", value = "import", icon = "builtin://global-icons/folder.svg" },
		})

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

	local function mouseInList()
		local mouse = UserInputService:GetMouseLocation()
		local position = list.AbsolutePosition
		local size = list.AbsoluteSize

		return mouse.X >= position.X
			and mouse.X <= position.X + size.X
			and mouse.Y >= position.Y
			and mouse.Y <= position.Y + size.Y
	end

	local function updateDragTarget()
		-- Read the cursor once. The previous version called GetMouseLocation() (and
		-- ran a full canReparent ancestry walk) for every visible row on every
		-- mouse-move, which made dragging crawl on large trees.
		local mouse = UserInputService:GetMouseLocation()

		local best = nil
		local bestDistance = math.huge
		local source = drag.source

		for path, registered in pairs(rowRegistry) do
			local row = registered.row

			if not UI.isAlive(row) then
				continue
			end

			local position = row.AbsolutePosition
			local size = row.AbsoluteSize
			local offset = mouse.Y - position.Y

			-- Cheap vertical reject before any ancestry work: only rows the cursor
			-- is actually near can win.
			if offset < -size.Y or offset > size.Y * 2 then
				continue
			end

			local entry = registered.entry

			-- The top half reparents as a sibling, the bottom half as a child,
			-- which is the behaviour the Roblox explorer uses.
			local target = offset > size.Y / 2 and (entryIsDirectory(entry) and path or parentOf(path))
				or parentOf(path)

			if target == nil then
				continue
			end

			if not canReparent(source, target) then
				continue
			end

			local distance = math.abs(offset - size.Y / 2)

			if distance < bestDistance then
				bestDistance = distance
				best = target
			end
		end

		if best ~= drag.target then
			-- Only the previously highlighted row needs resetting, rather than
			-- walking the whole registry.
			local previous = drag.target and rowRegistry[drag.target]

			if previous ~= nil and UI.isAlive(previous.row) then
				previous.row.BackgroundTransparency = previous.baseTransparency
				previous.dropTarget = false
			end

			drag.target = best

			local registered = best and rowRegistry[best]

			if registered ~= nil and UI.isAlive(registered.row) then
				registered.row.BackgroundTransparency = 0
				registered.dropTarget = true
			end
		end
	end

	local function beginDragVisual()
		if dragLayer ~= nil then
			return
		end

		dragLayer = UI.create("Frame", {
			Position = UDim2.fromOffset(drag.startX + 10, drag.startY),
			Size = UDim2.fromOffset(180, UI.metrics.treeRow),
			BackgroundColor3 = colors.selection,
			BackgroundTransparency = 0.2,
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
	end

	local function moveDragVisual()
		if dragLayer == nil then
			return
		end

		-- Follow the cursor directly. Tweening the ghost spawned a new TweenService
		-- tween on every mouse-move, each one stepping the VM for the rest of its
		-- duration, which made dragging visibly laggy. The drop still animates, so
		-- the gesture keeps its polish without the per-frame cost.
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
			clearDropHighlight()
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

		animateDrop(drag.target ~= nil)
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
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

			-- A mouse InputObject carries no meaningful KeyCode. Without this guard
			-- the click falls through to the keyboard handling below and can match
			-- Delete/Backspace, destroying the selected file on every click.
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

		if input.KeyCode == Enum.KeyCode.Up or input.KeyCode == Enum.KeyCode.Down then
			if #visibleRows == 0 then
				return
			end

			local next_ = index or 0

			if input.KeyCode == Enum.KeyCode.Up then
				next_ = next_ - 1
			else
				next_ = next_ + 1
			end

			selectAndReveal(math.clamp(next_, 1, #visibleRows))

			return
		end

		if input.KeyCode == Enum.KeyCode.Home then
			selectAndReveal(1)
			return
		end

		if input.KeyCode == Enum.KeyCode.End then
			selectAndReveal(#visibleRows)
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
				pasteEntry(targetDirectoryFor(selectedPath))
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
		if rootPath == nil then
			-- A project may appear or disappear without a Refresh call, so keep
			-- probing until one exists.
			hashFrame += 1

			if hashFrame % 15 == 0 then
				loadRoot()

				if rootPath ~= nil then
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

		local hash = treeHash(rootPath) .. "#" .. (selectedPath or "")

		if hash ~= lastHash then
			lastHash = hash

			rebuild()
		end
	end)

	return {
		Refresh = function()
			loadRoot()

			expanded = {}
			selectedPath = nil
			clipboard = nil

			lastHash = ""

			rebuild()
		end,
	}
end

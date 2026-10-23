return function(ctx)
	local UI = ctx.UI
	local colors = UI.tokens.color

	function UI.tree(parent, position, size, data, options)
		options = options or {}

		local colors = UI.tokens.color

		local rowHeight = options.rowHeight or UI.metrics.treeRow
		local indent = options.indent or 14
		local iconSize = options.iconSize or 14
		local chevronSize = options.chevronSize or 10
		local textSize = options.textSize or UI.tokens.type.small
		local padding = options.padding or UI.tokens.space.sm
		local separator = options.separator or "/"

		local chevronIcon = options.chevronIcon or "builtin://global-icons/chevron-down.svg"
		local folderIcon = options.folderIcon or "builtin://global-icons/folder.svg"
		local fileIcon = options.fileIcon or "builtin://global-icons/file.svg"

		local rowColor = options.rowColor or colors.panel

		local container = UI.frame(
			parent,
			position or UDim2.fromOffset(0, 0),
			size or UDim2.fromOffset(240, 300),
			options.color or colors.panel,
			options.radius or 0
		)

		container.Name = options.name or "Tree"
		container.ClipsDescendants = true

		local list = UI.create("ScrollingFrame", {
			Name = "List",
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(1, 0, 0, 0),
			ScrollBarThickness = 5,
			ScrollBarImageColor3 = colors.subtext,
			ScrollBarImageTransparency = 0.4,
			ScrollBarAutoHide = true,
			ClipsDescendants = true,
		}, container)

		local state = {
			data = data or {},
			expanded = {},
			seen = {},
			selected = nil,
			lastClickKey = nil,
			lastClickTime = 0,
			destroyed = false,
		}

		local controller = { frame = container, list = list }
		local refresh

		local function keyOf(path)
			if type(path) == "string" then
				return path
			end

			local parts = {}

			for index, name in ipairs(path) do
				parts[index] = tostring(name)
			end

			return table.concat(parts, separator)
		end

		local function isBranch(value, name, path)
			if options.isBranch then
				return options.isBranch(value, name, path) == true
			end

			return type(value) == "table"
		end

		local function copyPath(path, name)
			local new = table.clone(path)

			table.insert(new, name)

			return new
		end

		local function flatten(tbl, path, depth, out)
			local entries = {}

			for name, value in pairs(tbl) do
				local entryPath = copyPath(path, name)

				table.insert(entries, {
					name = name,
					text = tostring(name),
					value = value,
					path = entryPath,
					key = keyOf(entryPath),
					branch = isBranch(value, name, entryPath),
					depth = depth,
				})
			end

			if options.sort ~= false then
				table.sort(entries, function(a, b)
					if a.branch ~= b.branch then
						return a.branch
					end

					return string.lower(a.text) < string.lower(b.text)
				end)
			end

			for _, entry in ipairs(entries) do
				table.insert(out, entry)

				if entry.branch then
					if not state.seen[entry.key] then
						state.seen[entry.key] = true
						state.expanded[entry.key] = options.startExpanded == true
					end

					if state.expanded[entry.key] and type(entry.value) == "table" then
						flatten(entry.value, entry.path, depth + 1, out)
					end
				end
			end
		end

		local function setExpanded(entry, expanded)
			if not entry.branch or state.expanded[entry.key] == expanded then
				return
			end

			state.expanded[entry.key] = expanded

			refresh()

			if options.onToggle then
				options.onToggle(entry.path, expanded, controller)
			end
		end

		local function select(entry)
			state.selected = entry.key

			refresh()

			if options.onSelect then
				options.onSelect(entry.path, entry.value, entry.branch, controller)
			end
		end

		local function onRowClick(entry)
			local now = os.clock()
			local doubleClick = state.lastClickKey == entry.key and now - state.lastClickTime < 0.3

			state.lastClickKey = entry.key
			state.lastClickTime = now

			if state.selected ~= entry.key then
				select(entry)
			end

			if doubleClick then
				state.lastClickKey = nil

				if entry.branch then
					setExpanded(entry, not state.expanded[entry.key])
				elseif options.onActivate then
					options.onActivate(entry.path, entry.value, controller)
				end
			end
		end

		refresh = function()
			if state.destroyed then
				return
			end

			UI.clear(list)

			local rows = {}

			flatten(state.data, {}, 0, rows)

			for index, entry in ipairs(rows) do
				local selected = state.selected == entry.key

				local color = selected and colors.selection or rowColor
				local hoverColor = selected and colors.selectionHover or colors.hover

				local button, label = UI.button(
					list,
					entry.text,
					UDim2.fromOffset(0, (index - 1) * rowHeight),
					UDim2.new(1, 0, 0, rowHeight),
					function()
						onRowClick(entry)
					end,
					{
						color = color,
						hoverColor = hoverColor,
						pressedColor = colors.pressed,
						textColor = selected and colors.text or colors.subtext,
						textSize = textSize,
						radius = 0,
						border = false,
						textY = 0,
						selected = selected,
					}
				)

				button.Name = entry.text
				button.BackgroundTransparency = (not selected and options.transparentRows) and 1 or 0

				local x = padding + entry.depth * indent

				if entry.branch then
					local expanded = state.expanded[entry.key] == true

					local _, _, chevron = UI.iconButton(
						button,
						chevronIcon,
						UDim2.fromOffset(x, math.floor((rowHeight - 16) / 2)),
						UDim2.fromOffset(16, 16),
						function()
							setExpanded(entry, not state.expanded[entry.key])
						end,
						{
							bgTransparency = 1,
							hoveringEnabled = false,
							border = false,
							iconSize = chevronSize,
						}
					)

					chevron.Rotation = expanded and 0 or -90
				end

				x += 16 + 2

				local icon = entry.branch and folderIcon or fileIcon

				if options.getIcon then
					icon = options.getIcon(entry.path, entry.value, entry.branch, state.expanded[entry.key] == true)
						or icon
				end

				if icon and icon ~= "" then
					UI.image(
						button,
						icon,
						UDim2.fromOffset(x, math.floor((rowHeight - iconSize) / 2)),
						UDim2.fromOffset(iconSize, iconSize)
					)

					x += iconSize + 5
				end

				label.Position = UDim2.fromOffset(x, 0)
				label.Size = UDim2.new(1, -(x + padding), 1, 0)
				label.TextXAlignment = Enum.TextXAlignment.Left
				label.TextYAlignment = Enum.TextYAlignment.Center
			end

			list.CanvasSize = UDim2.new(1, 0, 0, #rows * rowHeight)
		end

		function controller:SetData(newData)
			state.data = newData or {}
			refresh()
		end

		function controller:GetData()
			return state.data
		end

		function controller:Refresh()
			refresh()
		end

		function controller:IsExpanded(path)
			return state.expanded[keyOf(path)] == true
		end

		function controller:Expand(path)
			if type(path) == "table" then
				for i = 1, #path do
					local key = keyOf({ table.unpack(path, 1, i) })
					state.seen[key] = true
					state.expanded[key] = true
				end
			else
				state.seen[path] = true
				state.expanded[path] = true
			end

			refresh()
		end

		function controller:Collapse(path)
			local key = keyOf(path)
			state.seen[key] = true
			state.expanded[key] = false
			refresh()
		end

		function controller:Toggle(path)
			local key = keyOf(path)
			state.seen[key] = true
			state.expanded[key] = not state.expanded[key]
			refresh()
		end

		local function setAll(value)
			local function walk(tbl, path)
				for name, child in pairs(tbl) do
					local childPath = copyPath(path, name)

					if isBranch(child, name, childPath) and type(child) == "table" then
						local key = keyOf(childPath)
						state.seen[key] = true
						state.expanded[key] = value
						walk(child, childPath)
					end
				end
			end

			walk(state.data, {})
			refresh()
		end

		function controller:ExpandAll()
			setAll(true)
		end

		function controller:CollapseAll()
			setAll(false)
		end

		function controller:GetSelected()
			return state.selected
		end

		function controller:SetSelected(path)
			state.selected = path ~= nil and keyOf(path) or nil
			refresh()
		end

		function controller:Destroy()
			if state.destroyed then
				return
			end

			state.destroyed = true

			UI.forgetButtons(container)
			container:Destroy()
		end

		refresh()

		return container, controller
	end
end

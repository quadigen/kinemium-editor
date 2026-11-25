if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local UI = require("@internal/editor_ui")
local Project = game:GetService("Project")
local UserInputService = game:GetService("UserInputService")

local tokens = UI.tokens
local colors = tokens.color
local inset = UI.metrics.panelInset
local rowHeight = UI.metrics.propertyRow
local headerHeight = UI.metrics.inputHeight + inset * 2
local visibleRows = 10
local maxResults = 200
local searchDelay = 0.10

local function normalize(path)
	return (path:gsub("\\", "/"))
end

local function fuzzy(value, query)
	local previous = 0
	for index = 1, #query do
		previous = string.find(value, query:sub(index, index), previous + 1, true)
		if not previous then
			return nil
		end
	end
	local gaps = previous - #query
	return 1000 - math.min(gaps * 4 + #value, 1000)
end

local function score(name, path, query)
	if query == "" then
		return 0
	end
	if name == query then
		return 10000
	end

	local position = string.find(name, query, 1, true)
	if position then
		return 8000 - math.min(position + #name, 1000)
	end
	position = string.find(path, query, 1, true)
	if position then
		return 6000 - math.min(position + #path, 1000)
	end

	local nameScore = fuzzy(name, query)
	if nameScore then
		return 4000 + nameScore
	end
	return fuzzy(path, query)
end

return function(readEntries, iconFor, openFile)
	local popup, field, list, status
	local slots, files, results = {}, {}, {}
	local selected = 1
	local generation, queryGeneration = 0, 0
	local indexing, failed = false, false
	local rootPath, previousFocus, renderedQuery

	local function close(restoreFocus)
		if not popup then
			return
		end

		generation += 1
		queryGeneration += 1
		local old = popup
		popup = nil
		if UserInputService:GetFocusedTextBox() == field then
			field:ReleaseFocus()
		end
		UI.forgetButtons(old)
		old:Destroy()
		table.clear(slots)
		table.clear(files)
		table.clear(results)
		if restoreFocus and previousFocus and UI.isAlive(previousFocus) then
			previousFocus:CaptureFocus()
		end
		previousFocus = nil
	end

	local function paint()
		if not popup then
			return
		end
		local first = math.max(1, math.floor(list.CanvasPosition.Y / rowHeight) + 1)
		for offset, slot in ipairs(slots) do
			local index = first + offset - 1
			local result = results[index]
			slot.index = index
			slot.row.Visible = result ~= nil
			if result then
				slot.row.Position = UDim2.fromOffset(0, (index - 1) * rowHeight)
				slot.name.Text = result.file.entry.Name
				slot.detail.Text = result.file.directory
				slot.icon.Image = result.file.icon
				local rowColor = index % 2 == 0 and colors.rowEven or colors.rowOdd
				slot.record.defaultColor = rowColor
				UI.setButtonState(slot.record, index == selected and "selected" or nil)
			end
		end
	end

	local function refresh(preserveSelection)
		if not popup then
			return
		end
		local previous = preserveSelection and renderedQuery == field.Text and results[selected]
		local previousY = list.CanvasPosition.Y
		renderedQuery = field.Text
		local query = string.lower(normalize(renderedQuery)):match("^%s*(.-)%s*$")
		local matches = {}
		for _, file in ipairs(files) do
			local rank = score(file.name, file.path, query)
			if rank then
				table.insert(matches, { file = file, rank = rank })
			end
		end
		table.sort(matches, function(a, b)
			if a.rank ~= b.rank then
				return a.rank > b.rank
			end
			if a.file.path ~= b.file.path then
				return a.file.path < b.file.path
			end
			return a.file.entry.Path < b.file.entry.Path
		end)

		local count = #matches
		for index = count, maxResults + 1, -1 do
			matches[index] = nil
		end
		results = matches
		local listHeight = math.min(#results, visibleRows) * rowHeight
		list.Visible = listHeight > 0
		list.Size = UDim2.new(1, -inset * 2, 0, listHeight)
		status.Position = UDim2.fromOffset(inset, headerHeight + listHeight)
		popup.Size = UDim2.new(0.8, 0, 0, headerHeight + listHeight + rowHeight + inset)
		selected = 1
		if previous then
			for index, result in ipairs(results) do
				if result.file == previous.file then
					selected = index
					break
				end
			end
		end
		list.CanvasSize = UDim2.new(1, 0, 0, #results * rowHeight)
		local top = (selected - 1) * rowHeight
		local maxY = math.max(0, (#results - visibleRows) * rowHeight)
		local y = previous and math.clamp(previousY, math.max(0, top - (visibleRows - 1) * rowHeight), top) or 0
		list.CanvasPosition = Vector2.new(0, math.min(y, maxY))
		if indexing then
			status.Text = `Indexing project files... {count} matches`
		elseif failed then
			status.Text = `{count} matches. Some folders could not be read.`
		elseif count == 0 then
			status.Text = query == "" and "No project files" or "No matching files"
		elseif count > maxResults then
			status.Text = `Showing {maxResults} of {count} matches. Type to narrow.`
		else
			status.Text = count == 1 and "1 file" or `{count} files`
		end
		paint()
	end

	local function activate(index, useLatestQuery)
		if renderedQuery ~= field.Text then
			if useLatestQuery then
				refresh()
				index = selected
			end
		end
		local result = results[index]
		if not result then
			return
		end
		local project = Project:GetActiveProject()
		local valid = project and project.Path == rootPath
		local entry = result.file.entry
		close(false)
		if valid then
			task.defer(function()
				local activeProject = Project:GetActiveProject()
				if activeProject and activeProject.Path == project.Path then
					openFile(entry)
				end
			end)
		end
	end

	local function move(delta)
		if #results == 0 then
			return
		end
		selected = (selected - 1 + delta) % #results + 1
		local top = (selected - 1) * rowHeight
		local y = list.CanvasPosition.Y
		if top < y then
			list.CanvasPosition = Vector2.new(0, top)
		elseif top + rowHeight > y + visibleRows * rowHeight then
			list.CanvasPosition = Vector2.new(0, top + rowHeight - visibleRows * rowHeight)
		end
		paint()
	end

	local function show()
		local project = Project:GetActiveProject()
		if not project or not project.Path or project.Path == "" or not UI.widgetOverlay().Enabled then
			return
		end

		rootPath = project.Path
		previousFocus = UserInputService:GetFocusedTextBox()
		generation += 1
		local current = generation
		indexing, failed = true, false
		selected = 1

		local overlay = UI.widgetOverlay()
		local height = headerHeight + visibleRows * rowHeight + rowHeight + inset
		popup =
			UI.frame(overlay, UDim2.new(0.5, 0, 0.5, 0), UDim2.new(0.8, 0, 0, height), colors.panel, tokens.radius.md)
		popup.Position = UDim2.new(0.5, 0, 0.5, 0)
		popup.Name = "QuickOpen"
		popup.AnchorPoint = Vector2.new(0.5, 0.5)
		popup.Active = true
		popup.InputSink = true
		UI.create("UISizeConstraint", { MaxSize = Vector2.new(640, height) }, popup)
		UI.stroke(popup, colors.borderStrong, 1, 0)
		UI.backdrop(popup, 15, Color3.new(0, 0, 0))

		field = UI.input(
			popup,
			"Search project files by name or path",
			UDim2.fromOffset(inset, inset),
			UDim2.new(1, -inset * 2, 0, UI.metrics.inputHeight),
			{
				clearTextOnFocus = false,
			}
		)
		list = UI.create("ScrollingFrame", {
			Position = UDim2.fromOffset(inset, headerHeight),
			Size = UDim2.new(1, -inset * 2, 0, visibleRows * rowHeight),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.fromOffset(0, 0),
			CanvasPosition = Vector2.new(0, 0),
			ScrollingEnabled = true,
			ScrollBarThickness = 5,
			ScrollBarImageColor3 = colors.subtext,
			ScrollBarImageTransparency = 0.4,
			ScrollBarAutoHide = true,
			ClipsDescendants = true,
			Active = true,
			InputSink = true,
		}, popup)
		status = UI.label(
			popup,
			"Indexing project files...",
			UDim2.fromOffset(inset, headerHeight + visibleRows * rowHeight),
			UDim2.new(1, -inset * 2, 0, rowHeight),
			tokens.type.caption,
			colors.muted
		)
		status.TextXAlignment = Enum.TextXAlignment.Left

		for index = 1, visibleRows + 5 do
			local slot = {}
			local row, label, record = UI.button(
				list,
				"",
				UDim2.fromOffset(0, 0),
				UDim2.new(1, -inset, 0, rowHeight),
				function()
					activate(slot.index)
				end,
				{ color = colors.rowOdd, radius = 0, border = false }
			)
			label.Visible = false
			row.Visible = false
			slot.row = row
			slot.record = record
			slot.icon = UI.image(row, "builtin://icons/File.svg", UDim2.fromOffset(4, 4), UDim2.fromOffset(14, 14))
			slot.icon.ImageColor3 = colors.subtext
			slot.name =
				UI.label(row, "", UDim2.fromOffset(24, 0), UDim2.new(0.48, -24, 1, 0), tokens.type.small, colors.text)
			slot.detail = UI.label(
				row,
				"",
				UDim2.new(0.48, 4, 0, 0),
				UDim2.new(0.52, -8, 1, 0),
				tokens.type.caption,
				colors.muted
			)
			slot.name.TextXAlignment = Enum.TextXAlignment.Left
			slot.detail.TextXAlignment = Enum.TextXAlignment.Left
			slot.name.TextTruncate = Enum.TextTruncate.AtEnd
			slot.detail.TextTruncate = Enum.TextTruncate.AtEnd
			table.insert(slots, slot)
		end

		list:GetPropertyChangedSignal("CanvasPosition"):Connect(paint)
		field:GetPropertyChangedSignal("Text"):Connect(function()
			queryGeneration += 1
			local ticket = queryGeneration
			task.delay(searchDelay, function()
				if popup and generation == current and queryGeneration == ticket then
					refresh()
				end
			end)
		end)

		task.defer(function()
			if popup and generation == current then
				field:CaptureFocus()
			end
		end)
		refresh()
		task.spawn(function()
			local root = normalize(rootPath):gsub("/+$", "")
			local prefix = root .. "/"
			local pending = { rootPath }
			local visited, seen = {}, {}
			local deadline = os.clock() + 0.004
			local nextRefresh = os.clock() + 0.12
			local function yieldBudget()
				if os.clock() >= deadline then
					task.wait()
					if not popup or generation ~= current then
						return false
					end
					if os.clock() >= nextRefresh then
						refresh(true)
						nextRefresh = os.clock() + 0.12
					end
					deadline = os.clock() + 0.004
				end
				return true
			end
			while #pending > 0 and popup and generation == current do
				local directory = table.remove(pending)
				if not visited[directory] then
					visited[directory] = true
					local entries = readEntries(directory)
					if not entries then
						failed = true
					end
					for _, entry in ipairs(entries or {}) do
						if not popup or generation ~= current then
							return
						end
						if entry.Type == "Directory" then
							if entry.Name ~= ".git" and not visited[entry.Path] then
								table.insert(pending, entry.Path)
							end
						elseif entry.Type == "File" and not seen[entry.Path] then
							seen[entry.Path] = true
							local path = normalize(entry.Path)
							local relative = path:sub(1, #prefix) == prefix and path:sub(#prefix + 1) or path
							table.insert(files, {
								entry = entry,
								icon = iconFor(entry),
								name = string.lower(entry.Name),
								path = string.lower(relative),
								directory = relative:match("^(.*)/") or "",
							})
						end
						if not yieldBudget() then
							return
						end
					end
				end
				if not yieldBudget() then
					return
				end
			end
			if popup and generation == current then
				indexing = false
				refresh(true)
			end
		end)
	end

	local function onInput(input, enabled)
		if input.UserInputType == Enum.UserInputType.Keyboard then
			local key = input.KeyCode
			local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
			if
				enabled
				and ctrl
				and key == Enum.KeyCode.P
				and not UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
				and not UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
				and not UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt)
				and not UserInputService:IsKeyDown(Enum.KeyCode.RightAlt)
			then
				if popup then
					close(true)
				else
					show()
				end
				return true
			end
			if popup then
				if renderedQuery ~= field.Text and (key == Enum.KeyCode.Up or key == Enum.KeyCode.Down) then
					refresh()
				end
				if key == Enum.KeyCode.Escape then
					close(true)
				elseif key == Enum.KeyCode.Up then
					move(-1)
				elseif key == Enum.KeyCode.Down then
					move(1)
				elseif key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter then
					activate(selected, true)
				end
				return true
			end
		elseif popup and input.UserInputType == Enum.UserInputType.MouseButton1 then
			if not UI.pointInside(popup, UserInputService:GetMouseLocation()) then
				close(false)
			end
			return true
		end
		return false
	end
	return onInput, close
end

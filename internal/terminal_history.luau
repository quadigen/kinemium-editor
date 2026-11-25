local UI = require("@internal/editor_ui")
local TextService = game:GetService("TextService")
local Project = game:GetService("Project")

local History = {}
History.__index = History

local tokens = UI.tokens
local colors = tokens.color
local FONT = "builtin://fonts/RobotoMono-Regular.ttf"
local mono = Font.new(FONT, Enum.FontWeight.Regular, Enum.FontStyle.Normal)
local PATTERN = "__KINE_PROMPT__(%d+):([^\n]-)__KINE_HOME__([^\n]-)__KINE_END__ %$ "

local function ink(fill)
	return fill.R * 0.2126 + fill.G * 0.7152 + fill.B * 0.0722 > 0.52 and Color3.fromRGB(20, 20, 20) or Color3.fromRGB(245, 245, 245)
end

local function pathText(path, home)
	if home and home ~= "" and (path == home or path:sub(1, #home + 1) == home .. "/") then
		return "~" .. path:sub(#home + 1)
	end
	return path
end

local function boundaries(text)
	local positions = {1}
	for i = 2, #text do
		local b = text:byte(i)
		if b < 128 or b >= 192 then table.insert(positions, i) end
	end
	if #text > 0 then table.insert(positions, #text + 1) end
	return positions
end

local function ordered(a, b)
	if a.row > b.row or (a.row == b.row and a.column > b.column) then return b, a end
	return a, b
end

local function badge(parent, name, icon, color)
	local frame, label = UI.badge(parent, "", UDim2.fromOffset(0, 0), {color = color, textColor = ink(color)})
	frame.Name = name
	label.FontFace = mono
	label.TextTruncate = Enum.TextTruncate.AtEnd
	local image = UI.image(frame, icon, UDim2.fromOffset(0, 0), UDim2.fromOffset(1, 1))
	return {frame = frame, label = label, image = image}
end

function History.new(parent, inset)
	local root = UI.frame(parent, UDim2.fromOffset(inset, inset), UDim2.fromOffset(1, 1), colors.panel)
	root.Name = "TerminalHistory"
	root.BackgroundTransparency = 1
	root.Active = false
	return setmetatable({
		root = root, parent = parent, inset = inset, rows = {}, pool = {},
		raw = "", width = 0, height = 0, lineHeight = 1, cell = 1, prefix = 0,
		anchor = nil, focus = nil, dragging = false, revision = 0, rendered = -1,
	}, History)
end

function History:setText(raw, times, offset, shell)
	if self.raw ~= raw or self.offset ~= offset or self.times ~= times or self.shell ~= shell then
		if self.offset ~= offset then self:clearSelection() end
		self.raw, self.times, self.offset, self.shell = raw, times, offset, shell
		self.dirty = true
	end
end

function History:clearSelection()
	if self.anchor or self.focus then
		self.anchor, self.focus = nil, nil
		self.revision += 1
	end
	self.dragging = false
end

function History:layout(width, lineHeight)
	local fontSize = tokens.type.body
	if not self.dirty and self.width == width and self.lineHeight == lineHeight and self.fontSize == fontSize then
		return self.height
	end
	if self.width ~= width or self.fontSize ~= fontSize then self:clearSelection() end
	self.dirty = false
	self.width, self.lineHeight, self.fontSize = width, lineHeight, fontSize
	self.cell = math.max(1, TextService:GetTextWidth("MMMMMMMMMM", fontSize, FONT) / 10)
	self.prefix = tokens.type.caption + tokens.space.sm
	local rows = {}
	local y = 0
	local function add(row)
		row.y = y
		row.positions = boundaries(row.text)
		table.insert(rows, row)
		y += lineHeight
	end
	local function wrap(text, code)
		text = text:gsub("\t", "    "):gsub("\r", "")
		local positions = boundaries(text)
		local count = #positions - 1
		local start = 1
		repeat
			local prefix = code ~= nil and self.prefix or 0
			local capacity = math.max(1, math.floor((width - prefix) / self.cell))
			local finish = math.min(count, start + capacity - 1)
			local value = count == 0 and "" or text:sub(positions[start], positions[finish + 1] - 1)
			add({text = value, code = code, prefix = prefix, breakAfter = finish == count})
			start = finish + 1
			code = nil
		until start > count
	end
	local raw = self.raw
	if raw ~= "" then
		local cursor = 1
		while cursor <= #raw do
			local newline = raw:find("\n", cursor, true)
			local line = raw:sub(cursor, newline and newline - 1 or #raw)
			local code, path, home, tail = line:match("^" .. PATTERN .. "(.*)$")
			if not path and self.shell == "cmd" then
				path, tail = line:match("^([%a]:[^>]+)>(.*)$")
				if path then code = "unknown" end
			end
			if path then
				path = pathText(path, home)
				local duration = self.times and self.times[(self.offset or 0) + cursor]
				add({text = path, path = path, duration = duration, header = true, breakAfter = true, prefix = 0})
				wrap(tail, code)
			else
				wrap(line)
			end
			if not newline then break end
			cursor = newline + 1
		end
	end
	self.rows = rows
	self.height = y
	self.root.Size = UDim2.fromOffset(width, math.max(1, y))
	self.revision += 1
	return y
end

function History:makeRow()
	local frame = UI.frame(self.root, UDim2.fromOffset(0, 0), UDim2.fromOffset(1, 1), colors.panel)
	frame.BackgroundTransparency = 1
	frame.Active = false
	local highlight = UI.frame(frame, UDim2.fromOffset(0, 0), UDim2.fromOffset(0, 0), colors.selection)
	highlight.Name = "TerminalSelection"
	highlight.BackgroundTransparency = 0.25
	highlight.Visible = false
	local label = UI.label(frame, "", UDim2.fromOffset(0, 0), UDim2.fromOffset(1, 1), tokens.type.body, colors.text)
	label.FontFace = mono
	label.RichText = false
	local arrow = UI.image(frame, "builtin://icons/ArrowRight.svg", UDim2.fromOffset(0, 0), UDim2.fromOffset(1, 1))
	arrow.Name = "HistoricalPromptArrow"
	local time = badge(frame, "HistoricalCommandDuration", "builtin://global-icons/clock.svg", colors.warning)
	local path = badge(frame, "HistoricalWorkingDirectory", "builtin://icons/Folder.svg", colors.success)
	return {frame = frame, label = label, arrow = arrow, time = time, path = path, highlight = highlight}
end

local function sizeBadge(item, x, text, width, height, fill)
	local iconSize, padding = tokens.type.caption, tokens.space.sm
	item.frame.Position = UDim2.fromOffset(x, 0)
	item.frame.Size = UDim2.fromOffset(width, height)
	item.frame.BackgroundColor3 = fill
	item.label.Text = text
	item.label.TextSize = tokens.type.caption
	item.label.TextColor3 = ink(fill)
	item.label.Position = UDim2.fromOffset(iconSize + padding * 2, 0)
	item.label.Size = UDim2.new(1, -(iconSize + padding * 3), 1, 0)
	item.image.ImageColor3 = ink(fill)
	item.image.Position = UDim2.fromOffset(padding, math.floor((height - iconSize) / 2))
	item.image.Size = UDim2.fromOffset(iconSize, iconSize)
end

function History:render()
	local top = self.parent.CanvasPosition.Y - self.inset
	local first = math.max(1, math.floor(top / self.lineHeight) - 5)
	local last = math.min(#self.rows, math.ceil((top + self.parent.AbsoluteWindowSize.Y) / self.lineHeight) + 6)
	if first == self.first and last == self.last and self.rendered == self.revision then return end
	self.first, self.last, self.rendered = first, last, self.revision
	local a, b
	if self:hasSelection() then a, b = ordered(self.anchor, self.focus) end
	for index = first, last do
		local slot = index - first + 1
		local view = self.pool[slot]
		if not view then
			view = self:makeRow()
			self.pool[slot] = view
		end
		local row = self.rows[index]
		view.frame.Visible = true
		view.frame.Position = UDim2.fromOffset(0, row.y)
		view.frame.Size = UDim2.fromOffset(self.width, self.lineHeight)
		view.label.Visible = not row.header
		view.arrow.Visible = row.code ~= nil
		view.time.frame.Visible = row.header == true and row.duration ~= nil
		view.path.frame.Visible = row.header == true
		view.highlight.Visible = false
		if row.header then
			local pad = tokens.space.sm
			local start = 0
			if row.duration ~= nil then
				local duration = string.format("%.1fs", row.duration)
				local w = math.ceil(TextService:GetTextWidth(duration, tokens.type.caption, FONT)) + tokens.type.caption + pad * 3
				sizeBadge(view.time, 0, duration, w, self.lineHeight, colors.warning)
				start = w + pad
			end
			local w = math.min(math.max(1, self.width - start), math.ceil(TextService:GetTextWidth(row.path, tokens.type.caption, FONT)) + tokens.type.caption + pad * 3)
			sizeBadge(view.path, start, row.path, w, self.lineHeight, colors.success)
			row.selectX = start + tokens.type.caption + pad * 2
			row.selectCell = math.max(1, TextService:GetTextWidth("MMMMMMMMMM", tokens.type.caption, FONT) / 10)
		else
			view.label.Text = row.text
			view.label.TextSize = self.fontSize
			view.label.TextColor3 = colors.text
			view.label.Position = UDim2.fromOffset(row.prefix, 0)
			view.label.Size = UDim2.fromOffset(math.max(1, self.width - row.prefix), self.lineHeight)
			view.arrow.Position = UDim2.fromOffset(0, math.floor((self.lineHeight - tokens.type.caption) / 2))
			view.arrow.Size = UDim2.fromOffset(tokens.type.caption, tokens.type.caption)
			view.arrow.ImageColor3 = row.code ~= nil and tonumber(row.code) and tonumber(row.code) ~= 0 and colors.error or colors.accent
		end
		if a and index >= a.row and index <= b.row then
			local start = index == a.row and a.column or 0
			local finish = index == b.row and b.column or #row.positions - 1
			if finish > start then
				local cell = row.selectCell or self.cell
				view.highlight.Position = UDim2.fromOffset((row.selectX or row.prefix) + start * cell, 0)
				view.highlight.Size = UDim2.fromOffset((finish - start) * cell, self.lineHeight)
				view.highlight.BackgroundColor3 = colors.selection
				view.highlight.Visible = true
				if row.header then view.highlight.ZIndex = view.path.frame.ZIndex + 2 else view.highlight.ZIndex = 1 end
			end
		end
	end
	for slot = math.max(1, last - first + 2), #self.pool do self.pool[slot].frame.Visible = false end
end

function History:point(point)
	if #self.rows == 0 then return nil end
	local y = point.Y - self.parent.AbsolutePosition.Y + self.parent.CanvasPosition.Y - self.inset
	local x = point.X - self.parent.AbsolutePosition.X - self.inset
	local index = math.clamp(math.floor(y / self.lineHeight) + 1, 1, #self.rows)
	local row = self.rows[index]
	local col = math.clamp(math.floor((x - (row.selectX or row.prefix)) / (row.selectCell or self.cell) + 0.5), 0, #row.positions - 1)
	if y < 0 then col = 0 elseif y >= self.height then col = #row.positions - 1 end
	return {row = index, column = col}
end

function History:contains(point)
	return UI.pointInside(self.parent, point) and point.Y - self.parent.AbsolutePosition.Y + self.parent.CanvasPosition.Y - self.inset < self.height and #self.rows > 0
end

function History:begin(point)
	local position = self:point(point)
	if not position then return end
	self.anchor, self.focus = position, position
	self.dragging = true
	self.revision += 1
end

function History:move(point)
	if not self.dragging then return end
	local position = self:point(point)
	if position and (position.row ~= self.focus.row or position.column ~= self.focus.column) then
		self.focus = position
		self.revision += 1
	end
end

function History:hasSelection()
	return self.anchor ~= nil and self.focus ~= nil and (self.anchor.row ~= self.focus.row or self.anchor.column ~= self.focus.column)
end

function History:selectedText()
	if not self:hasSelection() then return "" end
	local a, b = ordered(self.anchor, self.focus)
	local parts = {}
	for index = a.row, math.min(b.row, #self.rows) do
		local row = self.rows[index]
		local first = index == a.row and a.column or 0
		local last = index == b.row and b.column or #row.positions - 1
		first = math.clamp(first, 0, #row.positions - 1)
		last = math.clamp(last, first, #row.positions - 1)
		table.insert(parts, row.text:sub(row.positions[first + 1], row.positions[last + 1] - 1))
		if index < b.row and row.breakAfter then table.insert(parts, "\n") end
	end
	return table.concat(parts)
end

function History:copy()
	local text = self:selectedText()
	if text == "" then return false end
	local ok, copied = pcall(function() return Project:CopyPathWindow(text) end)
	return ok and copied
end

function History:themeChanged()
	self.dirty = true
	self.revision += 1
end

return History

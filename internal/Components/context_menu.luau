local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

return function(ctx)
	local UI = ctx.UI
	local shared = ctx.shared
	local colors = UI.tokens.color
	local tooltipSmoothTowards = ctx.tooltipSmoothTowards

	local closeActiveDropdown = function(instant)
		if UI.closeDropdown then
			UI.closeDropdown(instant)
		end
	end

	function UI.contextMenu(parent, value, position, size, chevronIcon, options)
		if options == nil then
			options = parent
		end

		options = options or {}

		local colors = UI.tokens.color

		local rowHeight = options.itemHeight or UI.metrics.inputHeight
		local separatorHeight = options.separatorHeight or 9
		local padding = options.padding or 4
		local menuWidth = options.menuWidth or 200
		local maxVisibleItems = options.maxVisibleItems or 12
		local edge = options.menuMargin or 4
		local baseZ = options.menuZIndex or 100050
		local textSize = options.textSize or UI.tokens.type.small
		local textColor = options.textColor or colors.text
		local iconSize = options.iconSize or 14
		local showSearch = options.showSearch == true
		local preferLeft = options.menuSide == "left"
		local itemBgTransparency = options.itemBgTransparency or 1
		local hoverTransparency = options.hoverTransparency or 0.1
		local animationSpeed = options.animationSpeed or 24
		local animate = options.animate ~= false
		local baseColor = options.itemColor or options.menuColor or colors.panelRaised
		local hoverColor = options.hoverColor or colors.accent
		local chevronIcon = options.chevronIcon or "builtin://global-icons/chevron-down.svg"

		local fadeSpeed = options.fadeSpeed or 22
		local rowSpeed = options.rowSpeed or 22
		local rowStagger = options.rowStagger or 0.02
		local maxStagger = options.maxStagger or 0.18
		local slideDistance = options.slideDistance or 8
		local rowSlide = options.rowSlide or 10
		local hoverNudge = options.hoverNudge or 2
		local pressDarken = options.pressDarken or 0.08
		local panelTransparency = options.BackgroundTransparency or 0.5

		local items = options.items
		local categories = options.categories

		local controller = {}
		local stack = {}
		local dying = {}
		local connections = {}
		local heartbeat = nil
		local catcher = nil
		local open = false
		local context = nil

		local function evaluate(value, ...)
			if type(value) == "function" then
				return value(...)
			end

			return value
		end

		local function normalize(raw)
			if type(raw) ~= "table" then
				return { text = tostring(raw), value = raw, enabled = true }
			end

			if raw.separator == true or raw.type == "separator" then
				return { separator = true }
			end

			local value = raw.value

			if value == nil then
				value = raw[1]
			end

			return {
				text = tostring(raw.label or raw.text or raw.name or value or ""),
				value = value,
				icon = raw.icon,
				shortcut = raw.shortcut,
				enabled = evaluate(raw.enabled, context) ~= false,
				check = evaluate(raw.check, context) == true,
				callback = raw.callback or raw.onClick,
				children = raw.submenu or raw.children or raw.items,
				raw = raw,
			}
		end

		local function matches(entry, query)
			if query == "" then
				return true
			end

			if entry.separator then
				return false
			end

			return string.find(string.lower(entry.text or ""), query, 1, true) ~= nil
		end

		local function topEntries(query)
			local out = {}
			local cats = evaluate(categories, context)

			if cats then
				for _, category in ipairs(cats) do
					local matched = {}

					for _, raw in ipairs(category.items or {}) do
						local entry = normalize(raw)

						if matches(entry, query) then
							table.insert(matched, entry)
						end
					end

					if #matched > 0 then
						table.insert(out, { header = category.name })

						for _, entry in ipairs(matched) do
							table.insert(out, entry)
						end
					end
				end
			else
				for _, raw in ipairs(evaluate(items, context) or {}) do
					local entry = normalize(raw)

					if matches(entry, query) then
						table.insert(out, entry)
					end
				end
			end

			return out
		end

		local function childEntries(list)
			local out = {}

			for _, raw in ipairs(evaluate(list, context) or {}) do
				table.insert(out, normalize(raw))
			end

			return out
		end

		local function track(list, obj, prop)
			table.insert(list, { obj = obj, prop = prop, base = obj[prop] })
		end

		local function applyFades(list, a)
			for _, f in ipairs(list) do
				f.obj[f.prop] = 1 - (1 - f.base) * a
			end
		end

		local function closeFrom(level, instant)
			for i = #stack, level, -1 do
				local menu = stack[i]
				stack[i] = nil

				if menu.shell then
					if instant or not animate then
						menu.shell:Destroy()
					else
						menu.closing = true
						menu.alphaTarget = 0
						table.insert(dying, menu)
					end
				end
			end
		end

		local function flushDying()
			for i = #dying, 1, -1 do
				local menu = dying[i]

				if menu.shell then
					menu.shell:Destroy()
				end

				dying[i] = nil
			end
		end

		local function place(menu)
			local screen = workspace:GetWindowDimensions()
			local anchor = menu.anchor
			local x, y

			if anchor.rowRect then
				local rect = anchor.rowRect

				if preferLeft then
					x = rect.left - menuWidth + 2

					if x < edge then
						x = rect.right - 2
					end
				else
					x = rect.right - 2

					if x + menuWidth > screen.X - edge then
						x = rect.left - menuWidth + 2
					end
				end

				y = rect.top - padding
			else
				local point = anchor.point

				x = preferLeft and (point.X - menuWidth) or point.X

				if x + menuWidth > screen.X - edge then
					x = point.X - menuWidth
				end

				if x < edge then
					x = point.X
				end

				y = point.Y

				if y + menu.height > screen.Y - edge then
					y = point.Y - menu.height
				end
			end

			x = math.clamp(x, edge, math.max(edge, screen.X - menuWidth - edge))
			y = math.clamp(y, edge, math.max(edge, screen.Y - menu.height - edge))

			menu.baseX = math.floor(x + 0.5)
			menu.baseY = math.floor(y + 0.5)

			if anchor.rowRect then
				menu.slideX = (menu.baseX >= anchor.rowRect.right - 4) and -1 or 1
				menu.slideY = 0
			else
				menu.slideX = 0
				menu.slideY = (anchor.point.Y + menu.height > screen.Y - edge) and 1 or -1
			end

			menu.shell.Position = UDim2.fromOffset(menu.baseX, menu.baseY)
		end

		local renderRows
		local openLevel

		local function choose(entry)
			controller:Close("select")

			if entry.callback then
				entry.callback(entry.value, entry.raw, context)
			end

			if options.onChanged then
				options.onChanged(entry.value, entry.raw, context)
			end
		end

		renderRows = function(menu, stagger)
			local query = menu.search and string.lower(menu.search.Text or "") or ""
			local entries = menu.source(query)

			UI.clear(menu.list)

			menu.rows = {}
			menu.statics = {}

			local z = menu.z + 3
			local rowWidth = menuWidth - padding * 2
			local y = 0
			local index = 0

			for _, entry in ipairs(entries) do
				index += 1

				if entry.header then
					local header = UI.label(
						menu.list,
						entry.header,
						UDim2.fromOffset(10, y + 3),
						UDim2.new(1, -20, 0, rowHeight - 4),
						options.categoryTextSize or 10,
						colors.muted
					)

					header.TextXAlignment = Enum.TextXAlignment.Left
					header.ZIndex = z + 1

					track(menu.statics, header, "TextTransparency")

					y += rowHeight
				elseif entry.separator then
					local line = UI.separator(
						menu.list,
						UDim2.fromOffset(padding + 6, y + math.floor(separatorHeight / 2)),
						UDim2.fromOffset(menuWidth - (padding + 6) * 2, 1),
						colors.border
					)

					line.ZIndex = z

					track(menu.statics, line, "BackgroundTransparency")

					y += separatorHeight
				else
					local enabled = entry.enabled ~= false

					local row = UI.create("TextButton", {
						Text = "",
						Position = UDim2.fromOffset(padding, y),
						Size = UDim2.fromOffset(rowWidth, rowHeight),
						BackgroundColor3 = baseColor,
						BackgroundTransparency = itemBgTransparency,
						BorderSizePixel = 0,
						AutoButtonColor = false,
						Active = true,
						InputSink = true,
						ZIndex = z,
					}, menu.list)

					UI.corner(row, options.itemRadius or UI.tokens.radius.sm)

					local record = {
						button = row,
						hover = 0,
						hovered = false,
						pressed = 0,
						isPressed = false,
						enabled = enabled,
						baseY = y,
						fades = {},
						appear = (animate and stagger) and 0 or 1,
						age = 0,
						delay = math.min(index * rowStagger, maxStagger),
						labelX = 24,
						lastA = -1,
					}

					local labelX = 24

					if entry.icon then
						local icon = UI.image(
							row,
							entry.icon,
							UDim2.fromOffset(7, math.floor((rowHeight - iconSize) / 2)),
							UDim2.fromOffset(iconSize, iconSize)
						)

						icon.ZIndex = z + 1

						track(record.fades, icon, "ImageTransparency")

						labelX = 7 + iconSize + 7
					elseif entry.check then
						local dot = UI.frame(
							row,
							UDim2.fromOffset(10, math.floor(rowHeight / 2) - 3),
							UDim2.fromOffset(6, 6),
							colors.accent,
							3
						)

						dot.ZIndex = z + 1

						track(record.fades, dot, "BackgroundTransparency")
					end

					record.labelX = labelX

					local label = UI.label(
						row,
						entry.text,
						UDim2.fromOffset(labelX, 0),
						UDim2.new(1, -(labelX + (entry.shortcut and 84 or 22)), 1, 0),
						textSize,
						enabled and textColor or colors.muted
					)

					label.TextXAlignment = Enum.TextXAlignment.Left
					label.TextYAlignment = Enum.TextYAlignment.Center
					label.ZIndex = z + 1

					record.label = label
					track(record.fades, label, "TextTransparency")

					if entry.shortcut then
						local hint = UI.label(
							row,
							entry.shortcut,
							UDim2.new(1, -90, 0, 0),
							UDim2.fromOffset(82, rowHeight),
							UI.tokens.type.caption,
							colors.muted
						)

						hint.TextXAlignment = Enum.TextXAlignment.Right
						hint.TextYAlignment = Enum.TextYAlignment.Center
						hint.ZIndex = z + 1

						track(record.fades, hint, "TextTransparency")
					end

					if entry.children then
						local arrow = UI.image(row, chevronIcon, UDim2.new(1, -18, 0.5, -5), UDim2.fromOffset(10, 10))

						arrow.Rotation = -90
						arrow.ZIndex = z + 1

						record.arrow = arrow
						track(record.fades, arrow, "ImageTransparency")
					end

					table.insert(menu.rows, record)

					local function openChild()
						local position = row.AbsolutePosition

						record.childOpen = true

						openLevel(menu.level + 1, function()
							return childEntries(entry.children)
						end, {
							rowRect = {
								left = position.X,
								right = position.X + row.AbsoluteSize.X + padding,
								top = position.Y,
							},
						})
					end

					row.MouseEnter:Connect(function()
						record.hovered = true

						if not enabled then
							return
						end

						for _, other in ipairs(menu.rows) do
							other.childOpen = false
						end

						if entry.children then
							openChild()
						else
							closeFrom(menu.level + 1)
						end
					end)

					row.MouseLeave:Connect(function()
						record.hovered = false
						record.isPressed = false
					end)

					row.MouseButton1Down:Connect(function()
						if enabled then
							record.isPressed = true
						end
					end)

					row.MouseButton1Up:Connect(function()
						record.isPressed = false
					end)

					row.MouseButton1Click:Connect(function()
						if entry.children then
							openChild()
						else
							choose(entry)
						end
					end)

					y += rowHeight
				end
			end

			menu.contentHeight = math.max(y, rowHeight)

			local screen = workspace:GetWindowDimensions()
			local available = math.max(screen.Y - edge * 2 - padding * 2 - menu.searchHeight, rowHeight)
			local visible = math.min(menu.contentHeight, maxVisibleItems * rowHeight, available)

			menu.list.CanvasSize = UDim2.new(1, 0, 0, menu.contentHeight)
			menu.list.Size = UDim2.new(1, 0, 0, visible)
			menu.list.ScrollingEnabled = menu.contentHeight > visible

			menu.height = menu.searchHeight + visible + padding * 2
			menu.inner.Size = UDim2.fromOffset(menuWidth, menu.height)
		end

		local function updateMenu(menu, dt)
			if animate then
				menu.alpha = tooltipSmoothTowards(menu.alpha, menu.alphaTarget, fadeSpeed, dt)

				if math.abs(menu.alpha - menu.alphaTarget) < 0.01 then
					menu.alpha = menu.alphaTarget
				end
			else
				menu.alpha = menu.alphaTarget
			end

			local a = menu.alpha

			if not menu.closing then
				if animate then
					menu.cur = tooltipSmoothTowards(menu.cur, menu.height, animationSpeed, dt)

					if math.abs(menu.cur - menu.height) < 0.5 then
						menu.cur = menu.height
					end
				else
					menu.cur = menu.height
				end
			end

			menu.shell.Size = UDim2.fromOffset(menuWidth, math.floor(menu.cur + 0.5))

			if menu.baseX then
				local inv = 1 - a

				menu.shell.Position = UDim2.fromOffset(
					math.floor(menu.baseX + menu.slideX * slideDistance * inv + 0.5),
					math.floor(menu.baseY + menu.slideY * slideDistance * inv + 0.5)
				)
			end

			menu.inner.BackgroundTransparency = 1 - (1 - panelTransparency) * a

			applyFades(menu.statics, a)

			for _, st in ipairs(menu.strokes) do
				st.obj.Transparency = 1 - (1 - st.base) * a
			end

			for _, b in ipairs(menu.backdrops) do
				if b.blur ~= nil then
					b.obj.BlurRadius = b.blur * a
				end

				if b.tint ~= nil then
					b.obj.TintTransparency = 1 - (1 - b.tint) * a
				end
			end

			for _, row in ipairs(menu.rows) do
				if row.appear < 1 then
					row.age += dt

					if row.age >= row.delay then
						row.appear = tooltipSmoothTowards(row.appear, 1, rowSpeed, dt)

						if row.appear > 0.995 then
							row.appear = 1
						end
					end
				end

				local hoverTarget = (row.hovered and row.enabled) and 1 or 0
				local pressTarget = row.isPressed and 1 or 0

				row.hover = tooltipSmoothTowards(row.hover, hoverTarget, 26, dt)
				row.pressed = tooltipSmoothTowards(row.pressed, pressTarget, 40, dt)

				row.button.BackgroundColor3 = baseColor:Lerp(hoverColor, row.hover)
				row.button.BackgroundTransparency = math.clamp(
					itemBgTransparency
						+ (hoverTransparency - itemBgTransparency) * row.hover
						- pressDarken * row.pressed,
					0,
					1
				)

				local slide = (1 - row.appear) * -rowSlide
				row.button.Position = UDim2.fromOffset(padding + slide, row.baseY)

				if row.label then
					row.label.Position = UDim2.fromOffset(row.labelX + hoverNudge * row.hover, 0)
				end

				if row.arrow then
					local lit = math.max(row.hover, row.childOpen and 1 or 0)

					row.arrow.Position = UDim2.new(1, -18 + 3 * lit, 0.5, -5)
				end

				local fa = row.appear * a

				if fa ~= row.lastA then
					row.lastA = fa
					applyFades(row.fades, fa)
				end
			end
		end

		local function step(dt)
			for _, menu in ipairs(stack) do
				updateMenu(menu, dt)
			end

			for i = #dying, 1, -1 do
				local menu = dying[i]

				updateMenu(menu, dt)

				if menu.alpha <= 0.02 then
					if menu.shell then
						menu.shell:Destroy()
					end

					table.remove(dying, i)
				end
			end

			if not open and #dying == 0 and heartbeat then
				heartbeat:Disconnect()
				heartbeat = nil
			end
		end

		openLevel = function(level, source, anchor)
			closeFrom(level)

			local overlay = UI.contextMenuOverlay()
			local z = baseZ + level * 10

			local shell = UI.create("Frame", {
				Name = "ContextMenu" .. level,
				Size = UDim2.fromOffset(menuWidth, 0),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ClipsDescendants = true,
				ZIndex = z,
			}, overlay)

			local inner = UI.frame(
				shell,
				UDim2.fromOffset(0, 0),
				UDim2.fromOffset(menuWidth, 10),
				options.menuColor or colors.panelRaised,
				options.radius or UI.tokens.radius.md
			)

			inner.Name = "Panel"
			inner.BackgroundTransparency = animate and 1 or panelTransparency
			inner.ZIndex = z + 1

			local backdrops = {}

			local function trackBackdrop(obj)
				if obj == nil or type(obj) == "number" then
					return
				end

				local okBlur, blur = pcall(function()
					return obj.BlurRadius
				end)

				local okTint, tint = pcall(function()
					return obj.TintTransparency
				end)

				if okBlur or okTint then
					table.insert(backdrops, {
						obj = obj,
						blur = okBlur and blur or nil,
						tint = okTint and tint or nil,
					})
				end
			end

			local strokes = {}

			local function trackStroke(obj)
				if obj == nil or type(obj) == "number" then
					return
				end

				local ok, base = pcall(function()
					return obj.Transparency
				end)

				if ok and type(base) == "number" then
					table.insert(strokes, { obj = obj, base = base })
				end
			end

			trackBackdrop(UI.backdrop(inner, 15, Color3.new(0, 0, 0)))
			trackStroke(
				UI.stroke(inner, options.borderColor or colors.borderStrong, 1, options.borderTransparency or 0)
			)

			if options.backdrop then
				trackBackdrop(UI.create("UIBackdrop", {
					Enabled = true,
					BlurRadius = options.backdropBlur or 18,
					TintColor3 = options.backdropColor or colors.panelRaised,
					TintTransparency = options.backdropTransparency or options.BackgroundTransparency or 0.85,
				}, inner))
			end

			local menu = {
				level = level,
				z = z,
				shell = shell,
				inner = inner,
				source = source,
				anchor = anchor,
				rows = {},
				statics = {},
				backdrops = backdrops,
				strokes = strokes,
				height = 0,
				cur = 0,
				alpha = animate and 0 or 1,
				alphaTarget = 1,
				closing = false,
				slideX = 0,
				slideY = 0,
				searchHeight = (level == 1 and showSearch) and 34 or 0,
			}

			if menu.searchHeight > 0 then
				menu.search = UI.input(
					inner,
					options.searchPlaceholder or "Search...",
					UDim2.fromOffset(5, 5),
					UDim2.new(1, -10, 0, 24),
					{ textSize = textSize }
				)

				menu.search.ZIndex = z + 2
			end

			menu.list = UI.create("ScrollingFrame", {
				Position = UDim2.fromOffset(0, menu.searchHeight + padding),
				Size = UDim2.new(1, 0, 0, 10),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				CanvasPosition = Vector2.new(0, 0),
				CanvasSize = UDim2.new(1, 0, 0, 0),
				ScrollBarThickness = 5,
				ScrollBarImageColor3 = colors.subtext,
				ScrollBarImageTransparency = 0.4,
				ScrollBarAutoHide = true,
				ClipsDescendants = true,
				ZIndex = z + 2,
			}, inner)

			table.insert(stack, menu)

			renderRows(menu, true)
			place(menu)

			menu.cur = animate and 0 or menu.height
			shell.Size = UDim2.fromOffset(menuWidth, math.floor(menu.cur + 0.5))

			if menu.search then
				menu.search.TextChanged:Connect(function()
					renderRows(menu, false)
					place(menu)
				end)
			end

			return menu
		end

		local function toPoint(position)
			local screen = workspace:GetWindowDimensions()

			local ok, scaleX = pcall(function()
				return position.X.Scale
			end)

			if ok and scaleX ~= nil then
				return Vector2.new(
					position.X.Scale * screen.X + position.X.Offset,
					position.Y.Scale * screen.Y + position.Y.Offset
				)
			end

			return position
		end

		function controller:Open(position, newContext)
			if open then
				controller:Close("reopen")
			end

			if shared.activeContextMenu and shared.activeContextMenu ~= controller then
				shared.activeContextMenu:Close("replaced")
			end

			if closeActiveDropdown then
				closeActiveDropdown()
			end

			context = newContext
			controller.context = newContext

			local point

			if position ~= nil then
				point = toPoint(position)
			elseif options.menuPosition then
				local menuPosition = options.menuPosition

				if type(menuPosition) == "function" then
					menuPosition = menuPosition()
				end

				point = toPoint(menuPosition)
			else
				point = UserInputService:GetMouseLocation()
			end

			table.insert(
				connections,
				UserInputService.InputBegan:Connect(function(input)
					if input.KeyCode == Enum.KeyCode.Escape then
						controller:Close("escape")
					end
				end)
			)

			if not heartbeat then
				heartbeat = RunService.Heartbeat:Connect(step)
			end

			open = true
			shared.activeContextMenu = controller

			openLevel(1, topEntries, { point = point })

			if options.onOpen then
				options.onOpen(context)
			end

			return true
		end

		function controller:Close(reason)
			if not open then
				return false
			end

			open = false

			local instant = reason == "destroy" or reason == "reopen"

			closeFrom(1, instant)

			if instant then
				flushDying()
			end

			if catcher then
				catcher:Destroy()
				catcher = nil
			end

			for _, connection in ipairs(connections) do
				connection:Disconnect()
			end

			connections = {}

			if (instant or not animate) and heartbeat then
				heartbeat:Disconnect()
				heartbeat = nil
			end

			if shared.activeContextMenu == controller then
				shared.activeContextMenu = nil
			end

			if options.onClose then
				options.onClose(reason or "closed", context)
			end

			return true
		end

		function controller:Toggle(position, newContext)
			if open then
				return controller:Close("toggle")
			end

			return controller:Open(position, newContext)
		end

		function controller:IsOpen()
			return open
		end

		function controller:ContainsPoint(x, y)
			for _, menu in ipairs(stack) do
				local shell = menu.shell

				if shell and UI.isAlive(shell) then
					local position = shell.AbsolutePosition

					if
						x >= position.X
						and x <= position.X + menuWidth
						and y >= position.Y
						and y <= position.Y + menu.height
					then
						return true
					end
				end
			end

			return false
		end

		function controller:SetItems(newItems)
			items = newItems
			categories = nil

			if open then
				controller:Close("items")
			end
		end

		function controller:SetCategories(newCategories)
			categories = newCategories

			if open then
				controller:Close("items")
			end
		end

		function controller:Destroy()
			controller:Close("destroy")
			flushDying()

			if heartbeat then
				heartbeat:Disconnect()
				heartbeat = nil
			end
		end

		return controller
	end
end

-- The Settings > Themes token editor. Controls are built from the shared UI library.
local UI = require("@internal/editor_ui")
local Preferences = require("@internal/preferences")
local Dialog = game:GetService("DialogService")
local Filesystem = game:GetService("Filesystem")
local BackgroundBundle = require("@internal/theme_background_bundle")

local colors = UI.tokens.color
local FONT_CHOICES = {
    { label = "Montserrat", path = "builtin://fonts/Montserrat-Regular.ttf" },
    { label = "Roboto", path = "builtin://fonts/Roboto-Regular.ttf" },
    { label = "Source Sans 3", path = "builtin://fonts/SourceSans3-Regular.ttf" },
    { label = "Nunito", path = "builtin://fonts/Nunito-Regular.ttf" },
    { label = "Ubuntu", path = "builtin://fonts/Ubuntu-Regular.ttf" },
    { label = "Arimo", path = "builtin://fonts/Arimo-Regular.ttf" },
    { label = "Google Sans Code", path = "builtin://fonts/GoogleSansCode-Regular.ttf" },
    { label = "Roboto Mono", path = "builtin://fonts/RobotoMono-Regular.ttf" },
}

local WEIGHT_CHOICES = {
    "Thin", "ExtraLight", "Light", "Regular", "Medium",
    "SemiBold", "Bold", "ExtraBold", "Heavy",
}
local STYLE_CHOICES = { "Normal", "Italic" }

local sourceName = Preferences.get("theme")
if not UI.getThemeSpec(sourceName) then sourceName = "Dark" end
local draft = UI.getThemeSpec(sourceName)
local draftName = UI.isCustomTheme(sourceName) and sourceName or (sourceName .. " Custom")
local selectedSaved = UI.isCustomTheme(sourceName) and sourceName or nil
local errorSerial = 0

local function notify(message, success)
    errorSerial += 1
    UI.toast("theme-editor-" .. errorSerial, {
        title = success and "Theme saved" or "Theme editor",
        message = tostring(message),
        type = success and "success" or "error",
    })
end

local function toHex(value)
    return string.format("#%02X%02X%02X",
        math.floor(value.R * 255 + 0.5),
        math.floor(value.G * 255 + 0.5),
        math.floor(value.B * 255 + 0.5))
end

local function fromHex(value)
    local r, g, b = tostring(value):match("^#?(%x%x)(%x%x)(%x%x)$")
    if r then return Color3.fromRGB(tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)) end
    return nil
end

local function cleanFileName(value)
    local base = tostring(value):gsub("[^%w_-]", "_"):sub(1, 60)
    return base ~= "" and base or "kinemium-theme"
end

-- Explicitly applying a designed theme should show its authored tokens, not
-- an older independent appearance override left active in General settings.
local function useThemeDefaults()
    for _, key in ipairs({
        "appearanceFont", "appearanceCorners", "appearanceDensity", "appearanceTextSize",
    }) do
        if Preferences.get(key) ~= "Theme Default" then
            Preferences.set(key, "Theme Default")
        end
    end
end

-- Return one root hosted inside the Settings scroller. All children are disposed
-- when the user navigates away; no persistent overlay or per-frame UI update.
return function(scroller)
    local root = UI.frame(scroller, UDim2.fromOffset(0, 0), UDim2.new(1, -8, 0, 0), colors.panel)
    root.BackgroundTransparency = 1
    root.LayoutOrder = 1
    -- The canvas is measured explicitly below; AutomaticSize would fight it.

    local currentTheme = Preferences.get("theme")
    if currentTheme ~= sourceName and UI.getThemeSpec(currentTheme) then
        sourceName = currentTheme
        draft = UI.getThemeSpec(currentTheme)
        selectedSaved = UI.isCustomTheme(currentTheme) and currentTheme or nil
        draftName = selectedSaved or (currentTheme .. " Custom")
    end

    local dropdowns = {}
    local disposed = false
    local rebuild
    local rebuildSerial = 0
    local picker
    local sections = {}
    local sectionByCard = {}
    local sectionGap = UI.tokens.space.lg
    local rowGap = UI.tokens.space.xs
    local valueWidth = 220
    local valueInset = valueWidth + 8

    -- This engine doesn't reliably include nested AutomaticSize frames in a
    -- ScrollingFrame's automatic canvas bounds. Measure the sections ourselves.
    scroller.AutomaticCanvasSize = Enum.AutomaticSize.None
    scroller.ScrollingEnabled = true
    scroller.ScrollingDirection = Enum.ScrollingDirection.Y
    -- Enter the Themes page from its header, never from a previous category's
    -- retained scroll offset. Rebuilding within this page preserves scroll.
    scroller.CanvasPosition = Vector2.new(0, 0)

    local function updateCanvas()
        local height = 12 + math.max(0, #sections - 1) * sectionGap
        for _, meta in ipairs(sections) do
            height += meta.frame.Size.Y.Offset
        end
        root.Size = UDim2.new(1, -16, 0, height)
        scroller.CanvasSize = UDim2.new(0, 0, 0, height + 20)
    end

    local function measureSection(meta)
        local slots = meta.description and 3 or 2
        local outerHeight = 24 + (meta.description and 18 or 0)
            + (slots - 1) * UI.tokens.space.sm + meta.cardHeight
        meta.card.Size = UDim2.new(1, 0, 0, meta.cardHeight)
        meta.frame.Size = UDim2.new(1, 0, 0, outerHeight)
    end

    local function section(title, description)
        local frame = UI.frame(root, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 0), colors.panel)
        frame.BackgroundTransparency = 1
        UI.create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, UI.tokens.space.sm) }, frame)
        local heading = UI.label(frame, title, UDim2.new(), UDim2.new(1, 0, 0, 24), UI.tokens.type.title, colors.text)
        heading.LayoutOrder = 1
        if description then
            local hint = UI.label(frame, description, UDim2.new(), UDim2.new(1, 0, 0, 18), UI.tokens.type.caption, colors.subtext)
            hint.LayoutOrder = 2
            hint.TextWrapped = false
        end
        local card = UI.card(frame, UDim2.new(), UDim2.new(1, 0, 0, 0), {
            color = colors.surface, radius = UI.tokens.radius.md, border = true,
            borderColor = colors.border, borderTransparency = 0.6,
        })
        card.LayoutOrder = 3
        UI.create("UIPadding", {
            PaddingTop = UDim.new(0, UI.tokens.space.sm), PaddingBottom = UDim.new(0, UI.tokens.space.sm),
            PaddingLeft = UDim.new(0, UI.tokens.space.md), PaddingRight = UDim.new(0, UI.tokens.space.md),
        }, card)
        UI.create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, rowGap) }, card)
        local meta = {
            frame = frame, card = card, description = description ~= nil,
            cardHeight = UI.tokens.space.sm * 2, count = 0,
        }
        table.insert(sections, meta)
        sectionByCard[card] = meta
        measureSection(meta)
        return card
    end

    local function row(parent, label, order, height)
        local frame = UI.frame(parent, UDim2.new(), UDim2.new(1, 0, 0, height or 31), colors.surface)
        frame.BackgroundTransparency = 1
        frame.LayoutOrder = order
        local meta = sectionByCard[parent]
        if meta then
            meta.cardHeight += (height or 31) + (meta.count > 0 and rowGap or 0)
            meta.count += 1
            measureSection(meta)
        end
        if label then
            local name = UI.label(frame, label, UDim2.fromOffset(4, 5), UDim2.new(1, -(valueInset + 12), 0, 22), UI.tokens.type.small, colors.text)
            name.TextWrapped = false
        end
        return frame
    end

    local function action(parent, text, x, width, onClick, danger)
        -- x is a pixel offset. Fractional positioning spread actions far apart
        -- and made them collide when the Settings window was resized.
        return UI.button(parent, text, UDim2.fromOffset(x, 3), UDim2.fromOffset(width, 26), onClick, {
            color = colors.input, hoverColor = colors.hover, textColor = danger and colors.error or colors.text,
            textSize = UI.tokens.type.small, radius = UI.tokens.radius.sm, border = false,
        })
    end

    local function dropdown(parent, current, options, changed)
        local items = {}
        for _, item in ipairs(options) do
            table.insert(items, { label = item.label or item, value = item.value or item })
        end
        local function display(value)
            for _, item in ipairs(items) do
                if item.value == value then return item.label end
            end
            return tostring(value or "")
        end
        local button, label, controller = UI.dropdown(parent, current,
            UDim2.new(1, -valueInset, 0, 3), UDim2.fromOffset(valueWidth, 25),
            "builtin://global-icons/chevron-down.svg", {
                items = items, showSearch = #items > 12, maxVisibleItems = 9,
                menuWidth = 200, menuParent = UI.contextMenuOverlay(),
                color = colors.input, hoverColor = colors.hover,
                borderColor = colors.border, radius = UI.tokens.radius.sm,
                textSize = UI.tokens.type.small,
                format = display,
                onChanged = changed,
            })
        button.ClipsDescendants = true
        label.TextWrapped = false
        table.insert(dropdowns, controller)
        return button
    end

    local function save()
        local ok, err = UI.saveCustomTheme(draftName, draft,
            draftName == sourceName and UI.isCustomTheme(sourceName))
        if not ok then
            notify(err, false)
            return false
        end
        sourceName = draftName
        selectedSaved = draftName
        useThemeDefaults()
        Preferences.set("theme", draftName)
        UI.setTheme(draftName, true)
        notify("Saved and applied " .. draftName, true)
        return true
    end

    local function performImport()
        task.spawn(function()
            local ok, path = pcall(function() return Dialog:PickFile() end)
            if disposed then return end
            if not ok then notify("Could not open the file picker", false); return end
            if not path then return end
            if not path:lower():match("%.json$") then
                notify("Choose a .json theme file", false)
                return
            end
            local readOK, data = pcall(function() return Filesystem:ReadFile(path) end)
            if not readOK or type(data) ~= "string" then
                notify("Unable to read the selected file", false)
                return
            end
            local unpacked, bundleError = BackgroundBundle.unpack(data, path)
            if not unpacked then
                notify(bundleError, false)
                return
            end
            local name, err = UI.importThemeJSON(unpacked)
            if not name then
                notify(err, false)
                return
            end
            sourceName, draftName, selectedSaved = name, name, name
            draft = UI.getThemeSpec(name)
            useThemeDefaults()
            Preferences.set("theme", name)
            UI.setTheme(name, true)
            notify("Imported and applied " .. name, true)
            if not disposed then task.defer(rebuild) end
        end)
    end

    local function performExport()
        -- Export saved themes only, so the filename always matches what is shared.
        if not selectedSaved or draftName ~= selectedSaved then
            notify("Save this theme before exporting it", false)
            return
        end
        local data, err = UI.exportThemeJSON(selectedSaved)
        if not data then notify(err, false); return end
        task.spawn(function()
            local packaged, packageError = BackgroundBundle.pack(data)
            if not packaged then
                notify(packageError, false)
                return
            end
            local ok, folder = pcall(function() return Dialog:PickFolder() end)
            if disposed then return end
            if not ok then notify("Could not open the folder picker", false); return end
            if not folder then return end
            local prefix = folder:sub(-1) == "/" and folder or folder .. "/"
            local basename = cleanFileName(selectedSaved)
            local path = prefix .. basename .. ".json"
            local index = 2
            local existsOK, exists = pcall(function() return Filesystem:PathExists(path) end)
            while existsOK and exists and index < 100 do
                path = prefix .. basename .. "-" .. index .. ".json"
                index += 1
                existsOK, exists = pcall(function() return Filesystem:PathExists(path) end)
            end
            if not existsOK or exists then notify("Cannot find a free export filename", false); return end
            local wrote, result = pcall(function() return Filesystem:WriteFileAtomic(path, packaged) end)
            if not wrote or result ~= true then
                notify("Could not write the theme JSON", false)
                return
            end
            notify("Exported to " .. path, true)
        end)
    end

    rebuild = function()
        if disposed then return end
        -- A rebuild briefly clears the scroll canvas. Remember the previous
        -- position before clearing, then restore it after the new bounds exist.
        local previousScrollY = scroller.CanvasPosition.Y
        rebuildSerial += 1
        local serial = rebuildSerial
        -- A newly applied theme can change the spacing tokens. Re-measure with
        -- the current values instead of reusing gaps from the previous theme.
        sectionGap = UI.tokens.space.lg
        rowGap = UI.tokens.space.xs
        for _, controller in ipairs(dropdowns) do
            if controller and controller.Close then controller:Close() end
        end
        dropdowns = {}
        if picker then
            picker:Destroy()
            picker = nil
        end
        sections = {}
        sectionByCard = {}
        UI.forgetButtons(root)
        UI.clear(root)
        UI.create("UIPadding", {
            PaddingTop = UDim.new(0, 12),
        }, root)
        UI.create("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, UI.tokens.space.lg),
        }, root)

        local management = section("Theme Library", "Edit a preset, then save and apply it.")
        local sourceRow = row(management, "Source Theme", 1)
        local names = UI.getThemes()
        table.sort(names)
        dropdown(sourceRow, sourceName, names, function(name)
            sourceName = name
            draft = UI.getThemeSpec(name)
            selectedSaved = UI.isCustomTheme(name) and name or nil
            draftName = selectedSaved or (name .. " Custom")
            task.defer(rebuild)
        end)
        local nameRow = row(management, "Theme Name", 2)
        local nameInput = UI.input(nameRow, "Name your theme", UDim2.new(1, -valueInset, 0, 3),
            UDim2.fromOffset(valueWidth, 25), { text = draftName, maxLength = 64 })
        nameInput.FocusLost:Connect(function()
            draftName = nameInput.Text
        end)

        local controls = row(management, nil, 3, 33)
        action(controls, "Save & Apply", 0, 120, function()
            draftName = nameInput.Text
            if save() then task.defer(rebuild) end
        end)
        action(controls, "Restore Source", 128, 122, function()
            draft = UI.getThemeSpec(sourceName)
            selectedSaved = UI.isCustomTheme(sourceName) and sourceName or nil
            task.defer(rebuild)
        end)
        action(controls, "Delete Saved", 258, 109, function()
            if not UI.isCustomTheme(sourceName) then
                notify("Only saved custom themes can be deleted", false)
                return
            end
            UI.confirm("Delete Theme", "Delete the saved theme '" .. sourceName .. "'?", function()
                local ok, err = UI.deleteCustomTheme(sourceName)
                if not ok then notify(err, false); return end
                sourceName, draftName, selectedSaved = "Dark", "Dark Custom", nil
                draft = UI.getThemeSpec("Dark")
                notify("Theme deleted", true)
                task.defer(rebuild)
            end)
        end, true)

        local exchange = section("Share Themes", "Import or export a theme JSON file.")
        local exchangeRow = row(exchange, nil, 1, 34)
        action(exchangeRow, "Import JSON", 0, 130, performImport)
        action(exchangeRow, "Export JSON", 138, 130, performExport)

        local fontSection = section("Typography", "Font family, weight, style, and sizes.")
        local fontRow = row(fontSection, "Font Family", 1)
        local options = {}
        local current = FONT_CHOICES[1].path
        for _, choice in ipairs(FONT_CHOICES) do
            table.insert(options, { label = choice.label, value = choice.path })
            if draft.font.family == choice.path then current = choice.path end
        end
        dropdown(fontRow, current, options, function(family)
            draft.font.family = family
            selectedSaved = nil
        end)
        local weightRow = row(fontSection, "Font Weight", 2)
        dropdown(weightRow, draft.font.weight.Name, WEIGHT_CHOICES, function(name)
            draft.font.weight = Enum.FontWeight[name]
            selectedSaved = nil
        end)
        local styleRow = row(fontSection, "Font Style", 3)
        dropdown(styleRow, draft.font.style.Name, STYLE_CHOICES, function(name)
            draft.font.style = Enum.FontStyle[name]
            selectedSaved = nil
        end)

        -- Theme-wide ImageLabel background for editor windows.
        local background = section("Window Background", "Image behind editor windows.")
        -- Paths need more space than a normal token value. Place the editable
        -- path on a full-width second line rather than truncating it to 172px.
        local imageRow = row(background, nil, 1, 60)
        UI.label(imageRow, "Image Source", UDim2.fromOffset(4, 2),
            UDim2.new(1, -8, 0, 19), UI.tokens.type.small, colors.text)
        local imageField = UI.input(imageRow, "No image selected",
            UDim2.fromOffset(4, 27), UDim2.new(1, -8, 0, 26),
            { text = draft.window.backgroundImage, maxLength = 2048 })

        -- An empty theme should not reserve a large, unusable preview area.
        -- Create a compact preview only when a source has actually been set.
        local preview
        local overlay
        if draft.window.backgroundImage ~= "" then
            local previewRow = row(background, nil, 3, 90)
            preview = UI.image(previewRow, draft.window.backgroundImage,
                UDim2.fromOffset(4, 3), UDim2.new(1, -8, 1, -6))
            preview.ScaleType = Enum.ScaleType[draft.window.backgroundImageScaleType]
            preview.ImageTransparency = draft.window.backgroundImageTransparency
            overlay = UI.frame(previewRow, UDim2.fromOffset(4, 3),
                UDim2.new(1, -8, 1, -6), colors.panel)
            overlay.BackgroundTransparency = draft.window.contentTransparency
            overlay.ZIndex = preview.ZIndex + 1
        end

        local function updatePreview()
            local hasImage = draft.window.backgroundImage ~= ""
            if (preview ~= nil) ~= hasImage then
                -- The total section height changes when preview appears or
                -- disappears. Rebuild so scroll bounds are recalculated.
                task.defer(rebuild)
                return
            end
            if preview then
                preview.Image = draft.window.backgroundImage
                preview.Visible = hasImage
            end
        end

        imageField.FocusLost:Connect(function()
            if draft.window.backgroundImage ~= imageField.Text then
                draft.window.backgroundImage = imageField.Text
                selectedSaved = nil
                updatePreview()
            end
        end)

        local browseRow = row(background, nil, 2, 33)
        action(browseRow, "Browse Image", 0, 132, function()
            task.spawn(function()
                local ok, path = pcall(function() return Dialog:PickFile() end)
                if disposed or not ok or not path then return end
                local extension = path:lower():match("%.([%a%d]+)$")
                if not ({ png = true, jpg = true, jpeg = true, webp = true,
                    gif = true, svg = true })[extension] then
                    notify("Choose PNG, JPG, WebP, GIF or SVG", false)
                    return
                end
                draft.window.backgroundImage = path
                selectedSaved = nil
                imageField.Text = path
                updatePreview()
            end)
        end)
        action(browseRow, "Remove Image", 140, 125, function()
            draft.window.backgroundImage = ""
            selectedSaved = nil
            imageField.Text = ""
            updatePreview()
        end)

        local scaleRow = row(background, "Image Scaling", 4)
        dropdown(scaleRow, draft.window.backgroundImageScaleType,
            { "Crop", "Fit", "Stretch" }, function(value)
                draft.window.backgroundImageScaleType = value
                if preview then preview.ScaleType = Enum.ScaleType[value] end
                selectedSaved = nil
            end)

        local function percentRow(label, key, order, inverse)
            local optionRow = row(background, label, order)
            local function displayed()
                local value = draft.window[key]
                return tostring(math.floor((inverse and (1 - value) or value) * 100 + 0.5))
            end
            local field = UI.input(optionRow, "0-100",
                UDim2.new(1, -valueInset, 0, 3), UDim2.fromOffset(valueWidth, 25),
                { text = displayed(), maxLength = 3 })
            field.FocusLost:Connect(function()
                local value = tonumber(field.Text)
                if value and value >= 0 and value <= 100 and value % 1 == 0 then
                    draft.window[key] = inverse and (1 - value / 100) or (value / 100)
                    if key == "backgroundImageTransparency" and preview then
                        preview.ImageTransparency = draft.window[key]
                    elseif key == "contentTransparency" and overlay then
                        overlay.BackgroundTransparency = draft.window[key]
                    end
                    selectedSaved = nil
                else
                    notify("Enter an opacity between 0 and 100", false)
                end
                field.Text = displayed()
            end)
        end

        percentRow("Image Opacity %", "backgroundImageTransparency", 5, true)
        percentRow("Panel Tint %", "contentTransparency", 6, true)

        local groups = {
            { title = "Color Tokens", hint = "Edit each color using hex or the picker.", key = "color" },
            { title = "Spacing Tokens", hint = "Control layout spacing in pixels.", key = "space" },
            { title = "Corner Radii", hint = "Adjust control rounding.", key = "radius" },
            { title = "Text Sizes", hint = "Interface text sizes in pixels.", key = "type" },
        }
        local index = 1
        for _, group in ipairs(groups) do
            local card = section(group.title, group.hint)
            local keys = {}
            for key in pairs(draft[group.key]) do table.insert(keys, key) end
            table.sort(keys)
            for _, token in ipairs(keys) do
                local tokenLabel = token:gsub("(%l)(%u)", "%1 %2"):gsub("^%l", string.upper)
                local tokenRow = row(card, tokenLabel, index)
                local value = draft[group.key][token]
                if group.key == "color" then
                    local field = UI.input(tokenRow, "#RRGGBB", UDim2.new(1, -valueInset, 0, 3),
                        UDim2.fromOffset(valueWidth - 32, 25), { text = toHex(value), maxLength = 7 })
                    local swatch, _, swatchRecord
                    local function reflectColor(color)
                        field.Text = toHex(color)
                        if swatch then
                            swatch.BackgroundColor3 = color
                            swatchRecord.color = color
                            swatchRecord.defaultColor = color
                            swatchRecord.hoverColor = color
                            swatchRecord.defaultHoverColor = color
                            swatchRecord.pressedColor = color
                        end
                    end
                    swatch, _, swatchRecord = UI.button(tokenRow, "",
                        UDim2.new(1, -33, 0, 4), UDim2.fromOffset(25, 23), function()
                            if picker then
                                picker:Destroy()
                                picker = nil
                            end
                            local overlay = UI.widgetOverlay()
                            local window = workspace:GetWindowDimensions()
                            local x = math.max(0, math.min(swatch.AbsolutePosition.X - 232, window.X - 232))
                            local y = math.max(0, math.min(swatch.AbsolutePosition.Y, window.Y - 300))
                            picker = UI.colorPicker(overlay, UDim2.fromOffset(x, y),
                                UDim2.fromOffset(226, 286), draft.color[token], function(color)
                                    draft.color[token] = color
                                    selectedSaved = nil
                                    reflectColor(color)
                                end)
                            -- colorPicker returns the picker frame as its first value.
                            local closePicker = UI.iconButton(picker,
                                "builtin://global-icons/x.svg", UDim2.new(1, -25, 0, 5),
                                UDim2.fromOffset(19, 19), function()
                                    if picker then picker:Destroy(); picker = nil end
                                end, { iconSize = 12 })
                            closePicker.ZIndex = picker.ZIndex + 2
                            for _, child in ipairs(closePicker:GetDescendants()) do
                                if child:IsA("GuiObject") then
                                    child.ZIndex = closePicker.ZIndex + 1
                                end
                            end
                            UI.tooltip(closePicker, "Close color picker", { placement = "below" })
                            picker.Visible = true
                        end, {
                            color = value, hoverColor = value, pressedColor = value,
                            radius = UI.tokens.radius.xs, border = false,
                        })
                    UI.tooltip(swatch, "Pick " .. token .. " color", { placement = "below" })
                    field.FocusLost:Connect(function()
                        local parsed = fromHex(field.Text)
                        if parsed then
                            draft.color[token] = parsed
                            selectedSaved = nil
                            reflectColor(parsed)
                        else
                            field.Text = toHex(draft.color[token])
                            notify("Invalid hex color for " .. token, false)
                        end
                    end)
                else
                    local field = UI.input(tokenRow, "Pixels", UDim2.new(1, -valueInset, 0, 3),
                        UDim2.fromOffset(valueWidth, 25), { text = tostring(value), maxLength = 3 })
                    field.FocusLost:Connect(function()
                        local n = tonumber(field.Text)
                        local min, max = group.key == "type" and 8 or 0,
                            group.key == "space" and 48 or (group.key == "radius" and 64 or 32)
                        if n and n % 1 == 0 and n >= min and n <= max then
                            draft[group.key][token] = n
                            selectedSaved = nil
                        else
                            notify("Invalid " .. group.key .. " value for " .. token, false)
                        end
                        field.Text = tostring(draft[group.key][token])
                    end)
                end
                index += 1
            end
        end
        updateCanvas()
        task.defer(function()
            if disposed or serial ~= rebuildSerial or root.Parent ~= scroller then return end
            local maximumY = math.max(0, scroller.CanvasSize.Y.Offset - scroller.AbsoluteSize.Y)
            scroller.CanvasPosition = Vector2.new(0, math.clamp(previousScrollY, 0, maximumY))
        end)
    end

    root.Destroying:Connect(function()
        disposed = true
        for _, controller in ipairs(dropdowns) do
            if controller and controller.Close then controller:Close() end
        end
        if picker then picker:Destroy(); picker = nil end
        dropdowns = {}
    end)
    rebuild()
end

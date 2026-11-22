-- Persistence and portable JSON schema for user-defined Studio themes.
-- Only data tokens are imported; no executable code or arbitrary asset paths.
return function(UI)
    local Http = game:GetService("HttpService")
    local Studio = game:GetService("Studio")
    local STORAGE_KEY = "studio.customThemes.v1"
    local FORMAT = "kinemium-theme"
    local VERSION = 1
    local MAX_FILE_BYTES = 128 * 1024
    local MAX_THEMES = 48
    local DEFAULT = UI.getThemeSpec("Dark")
    local custom = {}
    local builtin = {}
    for _, name in ipairs(UI.getThemes()) do
        builtin[name] = true
    end

    local fonts = {
        "Montserrat-Regular.ttf", "Roboto-Regular.ttf", "SourceSans3-Regular.ttf",
        "Nunito-Regular.ttf", "Ubuntu-Regular.ttf", "Arimo-Regular.ttf",
        "GoogleSansCode-Regular.ttf", "RobotoMono-Regular.ttf",
    }
    local allowedFonts = {}
    for _, filename in ipairs(fonts) do
        allowedFonts["builtin://fonts/" .. filename] = true
    end
    local weights = {
        Thin = true, ExtraLight = true, Light = true, Regular = true,
        Medium = true, SemiBold = true, Bold = true,
        ExtraBold = true, Heavy = true,
    }
    local styles = { Normal = true, Italic = true }

    local function validName(name)
        return type(name) == "string"
            and #name >= 1 and #name <= 64
            and not name:match("^%s") and not name:match("%s$")
            and not name:find("[%c/\\]")
    end

    local function hex(color)
        return string.format("#%02X%02X%02X",
            math.clamp(math.floor(color.R * 255 + 0.5), 0, 255),
            math.clamp(math.floor(color.G * 255 + 0.5), 0, 255),
            math.clamp(math.floor(color.B * 255 + 0.5), 0, 255))
    end

    local function parseHex(value)
        if type(value) ~= "string" then return nil end
        local r, g, b = value:match("^#?(%x%x)(%x%x)(%x%x)$")
        if not r then return nil end
        return Color3.fromRGB(tonumber(r, 16), tonumber(g, 16), tonumber(b, 16))
    end

    local bounds = {
        space = { 0, 48 }, radius = { 0, 64 }, type = { 8, 32 },
    }

    -- Canonical full snapshot. Unknown keys or invalid values reject the file.
    local function normalize(source, serialized)
        if type(source) ~= "table" then
            return nil, "Theme tokens must be an object"
        end
        local result = { color = {}, space = {}, radius = {}, type = {}, font = {} }
        for _, section in ipairs({ "color", "space", "radius", "type" }) do
            local values = source[section]
            if values ~= nil and type(values) ~= "table" then
                return nil, "Invalid " .. section .. " tokens"
            end
            values = values or {}
            for key in pairs(values) do
                if DEFAULT[section][key] == nil then
                    return nil, "Unknown token: " .. section .. "." .. tostring(key)
                end
            end
            for key, defaultValue in pairs(DEFAULT[section]) do
                local value = values[key]
                if value == nil then value = defaultValue end
                if section == "color" then
                    if serialized then value = parseHex(value) end
                    if typeof(value) ~= "Color3" then
                        return nil, "Invalid color token: " .. key
                    end
                    result.color[key] = value
                else
                    local limits = bounds[section]
                    if type(value) ~= "number" or value ~= value or
                        value < limits[1] or value > limits[2] or value % 1 ~= 0 then
                        return nil, "Invalid numeric token: " .. section .. "." .. key
                    end
                    result[section][key] = value
                end
            end
        end
        if source.font ~= nil and type(source.font) ~= "table" then
            return nil, "Font must be an object"
        end
        local font = source.font or {}
        for key in pairs(font) do
            if key ~= "family" and key ~= "weight" and key ~= "style" then
                return nil, "Unknown font token: " .. tostring(key)
            end
        end
        local family = font.family or DEFAULT.font.family
        if not allowedFonts[family] then
            return nil, "Font must be a supported built-in font"
        end
        local weight = font.weight or Enum.FontWeight.Regular
        local style = font.style or Enum.FontStyle.Normal
        if type(weight) == "string" then
            if not weights[weight] then return nil, "Unknown font weight" end
            weight = Enum.FontWeight[weight]
        end
        if type(style) == "string" then
            if not styles[style] then return nil, "Unknown font style" end
            style = Enum.FontStyle[style]
        end
        if typeof(weight) ~= "EnumItem" or not weights[weight.Name] then
            return nil, "Unknown font weight"
        end
        if typeof(style) ~= "EnumItem" or not styles[style.Name] then
            return nil, "Unknown font style"
        end
        result.font.family, result.font.weight, result.font.style = family, weight, style
        return result
    end

    local function document(name, spec)
        local normalized, err = normalize(spec, false)
        if not normalized then return nil, err end
        local data = {
            format = FORMAT,
            version = VERSION,
            name = name,
            tokens = { color = {},
                font = {
                    family = normalized.font.family,
                    weight = normalized.font.weight.Name,
                    style = normalized.font.style.Name,
                },
                space = normalized.space, radius = normalized.radius, type = normalized.type },
        }
        for key, value in pairs(normalized.color) do
            data.tokens.color[key] = hex(value)
        end
        return data
    end

    local function decode(data)
        if type(data) ~= "string" or #data > MAX_FILE_BYTES then
            return nil, nil, "Theme JSON is too large or missing"
        end
        local ok, parsed = pcall(function() return Http:JSONDecode(data) end)
        if not ok or type(parsed) ~= "table" then
            return nil, nil, "Malformed JSON"
        end
        if parsed.format ~= FORMAT or parsed.version ~= VERSION then
            return nil, nil, "Unsupported theme format or version"
        end
        if not validName(parsed.name) then
            return nil, nil, "Theme name must be 1-64 characters without slashes"
        end
        local normalized, err = normalize(parsed.tokens, true)
        if not normalized then return nil, nil, err end
        return parsed.name, normalized
    end

    local function persist(nextCustom)
        local saved = {}
        for name, spec in pairs(nextCustom) do
            local entry, err = document(name, spec)
            if not entry then return false, err end
            table.insert(saved, entry)
        end
        local ok, data = pcall(function() return Http:JSONEncode(saved) end)
        if not ok or #data > MAX_FILE_BYTES then
            return false, "Too many custom themes to save"
        end
        local success, err = pcall(function() Studio:SetSetting(STORAGE_KEY, data) end)
        if not success then return false, tostring(err) end
        return true
    end

    local function cloneCustom()
        local result = {}
        for name, spec in pairs(custom) do result[name] = spec end
        return result
    end

    function UI.getCustomThemes()
        local result = {}
        for name in pairs(custom) do table.insert(result, name) end
        table.sort(result)
        return result
    end

    function UI.isCustomTheme(name)
        return custom[name] ~= nil
    end

    function UI.saveCustomTheme(name, spec, allowOverwrite)
        if not validName(name) then return false, "Enter a valid theme name (1-64 characters)" end
        if builtin[name] then return false, "Built-in themes cannot be overwritten; choose a new name" end
        if custom[name] and allowOverwrite ~= true then
            return false, "A saved theme already uses that name. Choose a different name."
        end
        local normalized, err = normalize(spec, false)
        if not normalized then return false, err end
        local nextCustom = cloneCustom()
        if nextCustom[name] == nil and #UI.getCustomThemes() >= MAX_THEMES then
            return false, "Custom theme limit reached"
        end
        nextCustom[name] = normalized
        local ok, persistErr = persist(nextCustom)
        if not ok then return false, persistErr end
        custom = nextCustom
        UI.registerTheme(name, normalized)
        if UI.getTheme() == name then UI.setTheme(name, true) end
        return true
    end

    function UI.deleteCustomTheme(name)
        if not custom[name] then return false, "Not a saved custom theme" end
        local nextCustom = cloneCustom()
        nextCustom[name] = nil
        local ok, err = persist(nextCustom)
        if not ok then return false, err end
        if UI.getTheme() == name then
            Studio:SetSetting("theme", "Dark")
            UI.setTheme("Dark", true)
        end
        custom = nextCustom
        UI.unregisterTheme(name)
        return true
    end

    function UI.exportThemeJSON(name)
        local spec = UI.getThemeSpec(name)
        if not spec then return nil, "Unknown theme" end
        local doc, err = document(name, spec)
        if not doc then return nil, err end
        local ok, data = pcall(function() return Http:JSONEncode(doc) end)
        if not ok then return nil, "Could not encode theme JSON" end
        return data
    end

    function UI.importThemeJSON(data)
        local name, spec, err = decode(data)
        if not name then return nil, err end
        -- Never overwrite an installed theme simply because a shared JSON
        -- happens to have the same name.
        local stem = tostring(name)
        local index = 2
        while builtin[name] or custom[name] do
            local suffix = " (" .. index .. ")"
            local limit = 64 - #suffix
            -- Never split a UTF-8 codepoint in an international theme name.
            while limit > 0 and limit < #stem do
                local nextByte = string.byte(stem, limit + 1)
                if not nextByte or nextByte < 128 or nextByte > 191 then break end
                limit -= 1
            end
            name = stem:sub(1, limit) .. suffix
            index += 1
            if index > 100 then return nil, "Could not choose a unique imported theme name" end
        end
        local ok, saveErr = UI.saveCustomTheme(name, spec)
        if not ok then return nil, saveErr end
        return name
    end

    -- Stored settings are untrusted too; ignore corrupt entries without crashing Studio.
    local value = Studio:GetSetting(STORAGE_KEY, "[]")
    if type(value) == "string" and #value <= MAX_FILE_BYTES then
        local ok, entries = pcall(function() return Http:JSONDecode(value) end)
        if ok and type(entries) == "table" then
            local count = 0
            for _, entry in ipairs(entries) do
                if count >= MAX_THEMES then break end
                local encodedOk, encoded = pcall(function() return Http:JSONEncode(entry) end)
                if encodedOk then
                    local name, spec = decode(encoded)
                    if name and not builtin[name] and not custom[name] then
                        custom[name] = spec
                        UI.registerTheme(name, spec)
                        count += 1
                    end
                end
            end
        end
    end
end

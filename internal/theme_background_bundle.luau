-- Packs local window background images into shareable theme JSON.
-- On import, extracts the image alongside the selected JSON file so themes
-- keep working across machines and Studio restarts.
local Http = game:GetService("HttpService")
local Encoding = game:GetService("EncodingService")
local Filesystem = game:GetService("Filesystem")

local MAX_BYTES = 8 * 1024 * 1024
local FORMATS = { png = true, jpg = true, jpeg = true, webp = true, gif = true, svg = true }

local function extension(path)
    if type(path) ~= "string" then return nil end
    local ext = path:lower():match("%.([%a%d]+)$")
    return FORMATS[ext] and ext or nil
end

local function builtinSource(source)
    return source:sub(1, 10) == "builtin://" or source:sub(1, 10) == "project://"
end

local function safeFileName(name)
    local result = tostring(name):gsub("[^%w_-]", "_"):sub(1, 48)
    return result ~= "" and result or "theme"
end

local function decodeJSON(data)
    local ok, object = pcall(function() return Http:JSONDecode(data) end)
    if not ok or type(object) ~= "table" or object.format ~= "kinemium-theme" or object.version ~= 1 then
        return nil, "Invalid theme JSON format"
    end
    if type(object.tokens) ~= "table" then
        return nil, "Theme tokens must be an object"
    end
    -- Older version-1 themes do not have window tokens; they still import.
    if object.windowImage ~= nil and type(object.tokens.window) ~= "table" then
        return nil, "Embedded image requires window settings"
    end
    return object
end

local function validImage(bytes, ext)
    if type(bytes) ~= "string" or #bytes < 8 or #bytes > MAX_BYTES then return false end
    if ext == "png" then return bytes:sub(1, 8) == "\137PNG\r\n\26\n" end
    if ext == "jpg" or ext == "jpeg" then return bytes:sub(1, 3) == "\255\216\255" end
    if ext == "webp" then return bytes:sub(1, 4) == "RIFF" and bytes:sub(9, 12) == "WEBP" end
    if ext == "gif" then
        local sig = bytes:sub(1, 6)
        return sig == "GIF87a" or sig == "GIF89a"
    end
    if ext == "svg" then
        return bytes:sub(1, 512):lower():find("<svg", 1, true) ~= nil
    end
    return false
end

local module = {}

function module.pack(data)
    local object, err = decodeJSON(data)
    if not object then return nil, err end
    local window = object.tokens.window or {}
    local source = window.backgroundImage
    if type(source) ~= "string" or source == "" or builtinSource(source) then
        return data
    end
    local ext = extension(source)
    if not ext then return nil, "Window background is not a supported image" end
    local ok, bytes = pcall(function() return Filesystem:ReadFile(source) end)
    if not ok or not validImage(bytes, ext) then
        return nil, "Background file is missing, invalid, or exceeds 8 MB"
    end
    local encodedOK, encoded = pcall(function() return Encoding:EncodeBase64(bytes) end)
    if not encodedOK or type(encoded) ~= "string" then
        return nil, "Could not encode window background"
    end
    object.windowImage = { extension = ext, base64 = encoded }
    local jsonOK, result = pcall(function() return Http:JSONEncode(object) end)
    if not jsonOK then return nil, "Could not package window image" end
    return result
end

function module.unpack(data, importedJsonPath)
    if type(data) ~= "string" or #data > MAX_BYTES * 2 then
        return nil, "Theme JSON is too large"
    end
    local object, err = decodeJSON(data)
    if not object then return nil, err end
    if object.windowImage == nil then
        return data
    end
    local image = object.windowImage
    if type(image) ~= "table" or not FORMATS[image.extension]
        or type(image.base64) ~= "string" or #image.base64 > (MAX_BYTES * 4 / 3 + 8) then
        return nil, "Invalid embedded window image"
    end
    local ok, bytes = pcall(function() return Encoding:DecodeBase64(image.base64) end)
    if not ok or not validImage(bytes, image.extension) then
        return nil, "Embedded window image is invalid or too large"
    end
    local normalized = importedJsonPath:gsub("\\", "/")
    local directory = normalized:match("^(.*)/[^/]+$")
    if not directory or directory == "" then
        return nil, "Theme JSON must be imported from an existing folder"
    end
    local stem = safeFileName(object.name or "theme")
    local base = directory .. "/" .. stem .. "-background"
    local path = base .. "." .. image.extension
    local n = 2
    while Filesystem:PathExists(path) do
        path = base .. "-" .. n .. "." .. image.extension
        n += 1
        if n > 100 then return nil, "Could not find a free background filename" end
    end
    local written, result = pcall(function() return Filesystem:WriteFileAtomic(path, bytes) end)
    if not written or result ~= true then
        return nil, "Could not save imported image alongside theme JSON"
    end
    object.tokens.window.backgroundImage = path
    object.windowImage = nil
    local jsonOK, unpacked = pcall(function() return Http:JSONEncode(object) end)
    if not jsonOK then return nil, "Could not prepare imported theme" end
    return unpacked
end

return module

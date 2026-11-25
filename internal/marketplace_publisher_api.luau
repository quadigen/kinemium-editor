if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local HttpService = game:GetService("HttpService")
local MatrixService = game:GetService("MatrixService")
local Packages = game:GetService("Packages")
local Filesystem = game:GetService("Filesystem")
local KinemiumService = game:GetService("KinemiumService")

local API = {}
local PAGE_SIZE = 24

function API.session()
	local session = MatrixService.Session
	if type(session) == "table" and type(session.homeserver) == "string" and session.homeserver ~= ""
		and type(session.accessToken) == "string" and session.accessToken ~= "" then
		return session
	end
end

local function checkSession(expected)
	local current = API.session()
	if not current or current.homeserver ~= expected.homeserver or current.userId ~= expected.userId
		or current.accessToken ~= expected.accessToken then
		error("Your Marketplace session changed. Reopen settings to continue.", 0)
	end
end

local function decode(body)
	if type(body) == "table" then
		return body
	end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(body)
	end)
	return ok and type(data) == "table" and data or nil
end

local function responseError(body, status)
	local data = decode(body)
	local message = data and (data.message or data.error or data.detail)
	if type(message) == "string" and message ~= "" then
		return message
	end
	if status and status > 0 then
		return `Marketplace request failed (HTTP {status}).`
	end
	return "Could not reach the Marketplace."
end

local function request(session, method, path, body)
	checkSession(session)
	local headers = { Authorization = "Bearer " .. session.accessToken, Accept = "application/json" }
	if body then
		headers["Content-Type"] = "application/json"
	end
	local response = HttpService:RequestAsync({
		Url = session.homeserver:gsub("/+$", "") .. "/_kinemium/v1" .. path,
		Method = method,
		Headers = headers,
		Body = body,
	})
	if not response.Success then
		error(responseError(response.Body, response.StatusCode), 0)
	end
	return decode(response.Body)
end

local function query(cursor)
	return `limit={PAGE_SIZE}` .. (cursor and "&cursor=" .. HttpService:UrlEncode(cursor) or "")
end

local function listingPath(plugin)
	return "/packages/" .. HttpService:UrlEncode(plugin.namespace) .. "/" .. HttpService:UrlEncode(plugin.name)
end

local function versionPath(plugin, version)
	return listingPath(plugin) .. "/versions/" .. HttpService:UrlEncode(version)
end

function API.listPlugins(session, cursor)
	return request(session, "GET", "/me/packages?" .. query(cursor))
end

function API.listVersions(session, plugin, cursor)
	return request(session, "GET", listingPath(plugin) .. "/versions?includeYanked=true&" .. query(cursor))
end

function API.updatePlugin(session, plugin, changes)
	local body = HttpService:JSONEncode(changes)
	if changes.tags and #changes.tags == 0 then
		-- HttpService encodes an empty Luau table as a JSON object.
		local fields = table.clone(changes)
		fields.tags = nil
		local otherFields = HttpService:JSONEncode(fields):sub(2, -2)
		body = '{"tags":[]' .. (otherFields ~= "" and "," .. otherFields or "") .. "}"
	end
	return request(session, "PATCH", listingPath(plugin), body)
end

function API.deletePlugin(session, plugin)
	request(session, "DELETE", listingPath(plugin))
end

function API.setArchived(session, plugin, archived)
	local result = request(session, "POST", listingPath(plugin) .. (archived and "/archive" or "/restore"), "{}")
	return result and result.package
end

function API.setYanked(session, plugin, version, yanked)
	request(session, "POST", versionPath(plugin, version) .. "/yank", HttpService:JSONEncode({ yanked = yanked }))
end

function API.setChangelog(session, plugin, version, changelog)
	request(session, "PUT", versionPath(plugin, version) .. "/changelog", HttpService:JSONEncode({ changelog = changelog }))
end

function API.publishVersion(session, manifest, archivePath, target)
	checkSession(session)
	local ok, data, meta
	if archivePath then
		local archive = Filesystem:ReadFile(archivePath)
		if type(archive) ~= "string" or archive == "" then
			error("Could not read the selected ZIP archive.", 0)
		end
		ok, data, meta = Packages:PublishPackage(session, manifest, archive, {
			filename = archivePath:match("[^/\\]+$"),
			contentType = "application/zip",
		})
	else
		-- PublishInstance resolves the engine's API token before the Studio session.
		if KinemiumService.HasApiToken then
			error("Choose a ZIP to publish with your signed-in Marketplace account.", 0)
		end
		ok, data, meta = Packages:PublishInstance(target, manifest, { contentType = "application/zip" })
	end
	if not ok then
		local detail = meta and meta.status
		if (not detail or detail == 0) and type(data) == "string" and data ~= "" then
			error(data, 0)
		end
		error(responseError(data, detail), 0)
	end
	return data
end

return API

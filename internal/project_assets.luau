if IsServer or IsClient or IsPlaytest then
	return nil
end

local Project = game:GetService("Project")
local Filesystem = game:GetService("Filesystem")
local Assets = {}

function Assets.root()
	local project = Project:GetActiveProject()
	return project and project.Path or nil
end

function Assets.uri(path)
	local root = Assets.root()
	if not root then
		return path
	end
	root = root:gsub("\\", "/"):gsub("/+$", "") .. "/"
	local normalized = path:gsub("\\", "/")
	if normalized:sub(1, #root) == root then
		return "project://" .. normalized:sub(#root + 1)
	end
	return path
end

local function folder(parent, name)
	local path = parent .. "/" .. name
	if Filesystem:IsDirectory(path) then
		return path
	end
	assert(not Filesystem:PathExists(path), "A file already occupies " .. path)
	local created = Filesystem:CreateFolder(parent, name)
	assert(created and created ~= "", "Could not create " .. path)
	return path
end

function Assets.import(root, category, name, extension, bytes)
	assert(root and root == Assets.root(), "Open a project before importing assets, or reopen the original project.")
	assert(category == "fonts" or category == "icons", "Unsupported asset category")
	assert(extension == "ttf" or extension == "otf" or extension == "svg")
	assert(type(bytes) == "string" and #bytes > 0, "Asset download is empty")
	local directory = folder(folder(root, "assets"), category)
	local stem = name:lower():gsub("[^%w%-_]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
	if stem == "" then
		stem = "asset"
	end
	stem = stem:sub(1, 100)
	local filename = stem .. "." .. extension
	local index = 2
	while Filesystem:PathExists(directory .. "/" .. filename) do
		if Filesystem:ReadFile(directory .. "/" .. filename) == bytes then
			return "project://assets/" .. category .. "/" .. filename
		end
		filename = stem .. "-" .. index .. "." .. extension
		index += 1
		assert(index <= 1000, "Too many files with this name")
	end
	assert(Filesystem:WriteFileAtomic(directory .. "/" .. filename, bytes), "Could not write asset")
	return "project://assets/" .. category .. "/" .. filename
end

return Assets

-- Native project source sync. Scene objects are persisted by Project:SaveProject().
local Project = game:GetService("Project")
local Filesystem = game:GetService("Filesystem")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local UI = require("@internal/editor_ui")

local found, save = pcall(function() return Project.SaveProject end)
local Sync = { available = found and type(save) == "function" }
local active
local elapsed = 0
local suffixes = {
	{ ".server.luau", "Script" }, { ".server.lua", "Script" },
	{ ".client.luau", "LocalScript" }, { ".client.lua", "LocalScript" },
	{ ".luau", "ModuleScript" }, { ".lua", "ModuleScript" },
}
local outputSuffix = { Script = ".server.luau", LocalScript = ".client.luau", ModuleScript = ".luau" }

local function check(ok, message)
	if not ok then
		error(message, 0)
	end
	return ok
end

local function validName(name)
	return name ~= "" and name ~= "." and name ~= ".."
		and not name:find('[%z\1-\31/\\:*?"<>|]') and not name:find("[ .]$")
end

local function entries(path)
	local byName = {}
	for _, entry in ipairs(Project:GetProjectEntries(path)) do
		local key = entry.Name:lower()
		check(not byName[key], "Case-insensitive filename collision in " .. path)
		byName[key] = entry
	end
	return byName
end

local function directory(root, relative, create)
	local path = root
	for _, name in ipairs(relative) do
		check(validName(name), "Invalid project path component " .. name)
		local rootPath = path
		local entry = entries(path)[name:lower()]
		path ..= "/" .. name
		if entry then
			check(entry.Type == "Directory", "Expected a real directory at " .. path)
			path = rootPath .. "/" .. entry.Name
		elseif create then
			check(Filesystem:CreateFolder(rootPath, name) ~= "", "Could not create " .. path)
		else
			error("Missing source directory " .. path, 0)
		end
	end
	return path
end

local function scriptFile(name)
	for _, definition in ipairs(suffixes) do
		local suffix = definition[1]
		if #name > #suffix and name:sub(-#suffix) == suffix then
			return name:sub(1, -#suffix - 1), definition[2]
		end
	end
end

local function add(records, names, record)
	local key = table.concat(names, "/"):lower()
	check(not records[key], "Multiple instances or files map to " .. key)
	record.names = names
	records[key] = record
end

local function appendName(names, name)
	local result = table.clone(names)
	table.insert(result, name)
	return result
end

local function scanDisk(root, names, records)
	for _, entry in pairs(entries(root)) do
		local name = entry.Name
		local path = root .. "/" .. name
		if entry.Type == "Directory" and validName(name) and name:sub(1, 1) ~= "." then
			scanDisk(path, appendName(names, name), records)
		elseif entry.Type == "File" then
			local scriptName, class = scriptFile(name)
			if scriptName and validName(scriptName) then
				local isInit = scriptName == "init"
				check(not isInit or #names > 0, "An init script cannot replace a mapped service: " .. path)
				local source = Filesystem:ReadFile(path)
				check(type(source) == "string", "Could not read " .. path)
				add(records, isInit and names or appendName(names, scriptName),
					{ path = path, class = class, source = source, isInit = isInit })
			end
		end
	end
end

local function scanModel(root, names, records)
	for _, child in ipairs(root:GetChildren()) do
		if validName(child.Name) and child.Name:sub(1, 1) ~= "." then
			local childNames = appendName(names, child.Name)
			if child.ClassName == "Folder" then
				scanModel(child, childNames, records)
			elseif outputSuffix[child.ClassName] then
				check(child.Name ~= "init", "The name init is reserved for Rojo directory scripts")
				local children = child:GetChildren()
				add(records, childNames, {
					object = child, class = child.ClassName, source = child.Source, isInit = #children > 0,
				})
				scanModel(child, childNames, records)
			end
		end
	end
end

local function same(a, b)
	return a == b or (a ~= nil and b ~= nil and a.class == b.class and a.source == b.source
		and table.concat(a.names, "/") == table.concat(b.names, "/"))
end

local function modelParent(root, names)
	for index = 1, #names - 1 do
		local name = names[index]
		local child = root:FindFirstChild(name)
		if child then
			check(child.ClassName == "Folder" or outputSuffix[child.ClassName], "Source folder collides with instance " .. name)
		else
			child = Instance.new("Folder")
			child.Name = name
			child.Parent = root
		end
		root = child
	end
	return root
end

local function replaceModel(existing, parent, name, class, source)
	local replacement = Instance.new(class)
	replacement.Name = name
	if source ~= nil then replacement.Source = source end
	replacement.Parent = parent
	if existing then
		for _, child in ipairs(existing:GetChildren()) do
			child.Parent = replacement
		end
		existing:Destroy()
	end
end

local function applyModel(root, disk, model)
	if not disk then
		local object = model.object
		if #object:GetChildren() > 0 then
			replaceModel(object, object.Parent, object.Name, "Folder")
		else
			object:Destroy()
		end
		return
	end
	local name = disk.names[#disk.names]
	if model and model.class == disk.class then
		model.object.Name = name
		model.object.Source = disk.source
		return
	end

	local parent = modelParent(root, disk.names)
	local existing = model and model.object or parent:FindFirstChild(name)
	check(not existing or model or (disk.isInit and existing.ClassName == "Folder"),
		"Source file collides with instance " .. name)
	replaceModel(existing, parent, name, disk.class, disk.source)
end

local function applyDisk(root, disk, model)
	if disk then
		check(Filesystem:ReadFile(disk.path) == disk.source, "Source changed while syncing " .. disk.path)
	end
	if not model then
		check(Filesystem:DeleteFile(disk.path), "Could not remove " .. disk.path)
		return
	end

	local names = table.clone(model.names)
	local name = table.remove(names)
	local useInit = model.isInit or (disk and disk.isInit)
	if useInit then
		table.insert(names, name)
		name = "init"
	end
	local parent = directory(root, names, true)
	local filename = name .. outputSuffix[model.class]
	if disk and disk.class == model.class and disk.isInit == (useInit == true) then
		check(table.concat(disk.names, "/") == table.concat(model.names, "/"),
			"Rename the existing source file on disk to change its spelling: " .. disk.path)
		check(Filesystem:WriteFileAtomic(disk.path, model.source), "Could not write " .. disk.path)
		return
	end

	local path = parent .. "/" .. filename
	check(not entries(parent)[filename:lower()], "Source path already exists: " .. path)
	check(Filesystem:WriteFileAtomic(path, model.source), "Could not write " .. path)
	if disk and not Filesystem:DeleteFile(disk.path) then
		Filesystem:DeleteFile(path)
		error("Could not replace " .. disk.path, 0)
	end
end

local function scanPair(mapping)
	mapping.path = directory(mapping.projectPath, mapping.pieces, false)
	local disk, model = {}, {}
	scanDisk(mapping.path, {}, disk)
	scanModel(mapping.root, {}, model)
	return disk, model
end

local function remember(mapping, key, record)
	if same(mapping.previous[key], record) then return end
	mapping.previous[key] = record and { names = record.names, class = record.class, source = record.source }
	active.dirty = true
end

local function reconcile(mapping, conflicts)
	local disk, model = scanPair(mapping)
	local keys, ordered = {}, {}
	for key in pairs(disk) do keys[key] = true end
	for key in pairs(model) do keys[key] = true end
	for key in pairs(mapping.previous) do keys[key] = true end
	for key in pairs(keys) do table.insert(ordered, key) end
	table.sort(ordered, function(a, b)
		return #a == #b and a < b or #a < #b
	end)

	-- Parents are applied before their children. Deletions run in reverse order.
	local removals = {}
	for _, key in ipairs(ordered) do
		local file, object = disk[key], model[key]
		local baseline = mapping.previous[key]
		if same(file, object) then
			if file and object.isInit and not file.isInit then
				applyDisk(mapping.path, file, object)
			end
			remember(mapping, key, file)
		elseif not mapping.initialized then
			if file then
				applyModel(mapping.root, file, object)
				remember(mapping, key, file)
			elseif mapping.exportInitial then
				applyDisk(mapping.path, nil, object)
				remember(mapping, key, object)
			else
				table.insert(removals, { key = key, object = object })
			end
		elseif same(file, baseline) then
			if object then
				applyDisk(mapping.path, file, object)
				remember(mapping, key, object)
			else
				table.insert(removals, { key = key, file = file })
			end
		elseif same(object, baseline) then
			if file then
				applyModel(mapping.root, file, object)
				remember(mapping, key, file)
			else
				table.insert(removals, { key = key, object = object })
			end
		else
			table.insert(conflicts, { mapping = mapping, key = key, file = file, object = object })
		end
	end
	for index = #removals, 1, -1 do
		local removal = removals[index]
		-- A child conflict must survive a deletion of its ancestor.
		local blocked = false
		for _, conflict in ipairs(conflicts) do
			if conflict.mapping == mapping and conflict.key:sub(1, #removal.key + 1) == removal.key .. "/" then
				blocked = true
				break
			end
		end
		if not blocked then
			if removal.file then
				applyDisk(mapping.path, removal.file, nil)
			else
				applyModel(mapping.root, nil, removal.object)
			end
			remember(mapping, removal.key, nil)
		end
	end
	if not mapping.initialized then active.dirty = true end
	mapping.initialized = true
end

local function configure(project)
	local manifestPath = project.Path .. "/default.project.json"
	local manifestEntry = entries(project.Path)["default.project.json"]
	local generated = manifestEntry == nil
	local manifest
	if generated then
		manifest = {
			name = project.Name,
			tree = {
				["$className"] = "DataModel",
				ServerScriptService = { ["$path"] = "scripts/server" },
				ReplicatedStorage = { ["$path"] = "scripts/shared" },
				StarterPlayer = { StarterPlayerScripts = { ["$path"] = "scripts/client" } },
			},
		}
	else
		check(manifestEntry.Type == "File", "Expected a regular default.project.json file")
		manifest = HttpService:JSONDecode(check(Filesystem:ReadFile(manifestPath), "Could not read default.project.json"))
	end
	check(type(manifest) == "table" and type(manifest.tree) == "table", "Missing Rojo project tree")
	check(not manifest.globIgnorePaths or next(manifest.globIgnorePaths) == nil, "Source sync does not support globIgnorePaths")
	check(manifest.emitLegacyScripts ~= false, "Source sync requires legacy script classes")

	local mappings = {}
	local function visit(node, root, logicalPath)
		local relative = node["$path"]
		if relative then
			check(type(relative) == "string", "Expected a relative directory in $path")
			local pieces = string.split(relative:gsub("\\", "/"), "/")
			check(root ~= game, "Map source directories under a DataModel service")
			local path = directory(project.Path, pieces, generated)
			local folded = path:lower()
			for _, mapping in ipairs(mappings) do
				local existing = mapping.path:lower()
				check(folded ~= existing and folded:sub(1, #existing + 1) ~= existing .. "/"
					and existing:sub(1, #folded + 1) ~= folded .. "/", "Overlapping source paths")
			end
			table.insert(mappings, { root = root, path = path, projectPath = project.Path,
				pieces = pieces, id = logicalPath .. "|" .. table.concat(pieces, "/"), previous = {}, exportInitial = generated })
		end
		for name, child in pairs(node) do
			if name:sub(1, 1) ~= "$" then
				check(not relative, "Explicit children inside mapped source directories are unsupported")
				check(type(child) == "table", "Invalid project node " .. name)
				local target = root:FindFirstChild(name)
				if root == game then
					local ok, service = pcall(game.GetService, game, name)
					if ok then target = service end
				end
				if not target and child["$className"] == "Folder" then
					target = Instance.new("Folder")
					target.Name = name
					target.Parent = root
				end
				check(target, "Source mapping target does not exist: " .. name)
				visit(child, target, logicalPath .. "/" .. name)
			end
		end
	end
	visit(manifest.tree, game, "")
	return mappings, generated and manifestPath or nil, manifest
end

local function journalPath()
	return active.project.Path .. "/.kinemium-sync.json"
end

local function saveJournal()
	if not active.dirty or not active.mappings then return end
	local saved = { paused = active.paused, mappings = {} }
	for _, mapping in ipairs(active.mappings) do
		if mapping.initialized then saved.mappings[mapping.id] = mapping.previous end
	end
	check(Filesystem:WriteFileAtomic(journalPath(), HttpService:JSONEncode(saved)), "Could not save source sync state")
	active.dirty = false
end

local function readJournal()
	local state = Filesystem:ReadFile(journalPath())
	if not state then return end
	local saved = HttpService:JSONDecode(state)
	check(type(saved) == "table" and type(saved.mappings) == "table", "Invalid source sync state")
	active.paused = saved.paused == true
	for _, mapping in ipairs(active.mappings) do
		local previous = saved.mappings[mapping.id]
		if type(previous) == "table" then
			mapping.previous = previous
			mapping.initialized = true
		end
	end
end

function Sync.stop()
	active = nil
end

function Sync.step()
	if not active then return true end
	local ok, message = pcall(function()
		if not active.mappings then
			active.mappings, active.manifestPath, active.manifest = configure(active.project)
			readJournal()
		end
		if active.paused then return end
		local conflicts = {}
		for _, mapping in ipairs(active.mappings) do
			reconcile(mapping, conflicts)
		end
		active.conflicts = conflicts
		if active.manifestPath then
			check(not Filesystem:PathExists(active.manifestPath), "default.project.json appeared while configuring sync")
			check(Filesystem:WriteFileAtomic(active.manifestPath, HttpService:JSONEncode(active.manifest)), "Could not write default.project.json")
			active.manifestPath = nil
		end
		saveJournal()
		check(#conflicts == 0, tostring(#conflicts) .. " source conflicts. Open File > Sync Conflicts to review.")
	end)
	if not ok and message ~= active.error then
		UI.toast("project-sync", { type = "error", title = "Project source sync", message = tostring(message), duration = 8 })
	end
	active.error = not ok and message or nil
	return ok
end

function Sync.setPaused(paused)
	if not active then return false end
	active.paused = paused
	active.dirty = true
	local ok, message = pcall(saveJournal)
	if not ok then
		UI.toast("project-sync", { type = "error", title = "Could not save sync settings", message = tostring(message), duration = 8 })
	end
	if not paused then Sync.step() end
	return ok
end

function Sync.isPaused()
	return active ~= nil and active.paused
end

function Sync.getConflicts()
	return active and active.conflicts or {}
end

function Sync.resolve(conflict, choice)
	if not active then return false, "This project is no longer open." end
	local currentIndex
	for index, current in ipairs(active.conflicts) do
		if current.mapping == conflict.mapping and current.key == conflict.key then
			currentIndex = index
			break
		end
	end
	if not currentIndex then return false, "This conflict is no longer current." end
	local ok, message = pcall(function()
		local mapping, key = conflict.mapping, conflict.key
		local disk, model = scanPair(mapping)
		local file, object = disk[key], model[key]
		check(same(file, conflict.file) and same(object, conflict.object), "The sources changed. Review the current conflict before resolving it.")
		if choice == "disk" then
			applyModel(mapping.root, file, object)
			remember(mapping, key, file)
		else
			applyDisk(mapping.path, file, object)
			remember(mapping, key, object)
		end
		table.remove(active.conflicts, currentIndex)
		saveJournal()
	end)
	if not active.paused then Sync.step() end
	return ok, message
end

function Sync.start(project)
	if not Sync.available then return end
	active = { project = project, paused = false, conflicts = {} }
	elapsed = 0
	Sync.step()
end

RunService.Heartbeat:Connect(function(dt)
	if not active or active.paused then return end
	elapsed += dt
	if elapsed >= 1 then
		elapsed = 0
		Sync.step()
	end
end)

return Sync

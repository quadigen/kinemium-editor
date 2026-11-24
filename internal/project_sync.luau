local Project = game:GetService("Project")
local Filesystem = game:GetService("Filesystem")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local UI = require("@internal/editor_ui")

local found, save = pcall(function()
	return Project.SaveProject
end)
local Sync = { available = found and type(save) == "function" }
local active
local scheduled
local bootstrapConnection
local scheduleGeneration = 0

local function stopPolling()
	scheduleGeneration += 1
	if scheduled then
		task.cancel(scheduled)
		scheduled = nil
	end
	if bootstrapConnection then
		bootstrapConnection:Disconnect()
		bootstrapConnection = nil
	end
end

local function schedulePoll()
	if not active or active.paused or scheduled then return end
	local generation = scheduleGeneration
	scheduled = task.delay(1, function()
		if generation ~= scheduleGeneration then return end
		scheduled = nil
		if not active or active.paused then return end
		Sync.step()
		if generation == scheduleGeneration then schedulePoll() end
	end)
end
local suffixes = {
	{ ".server.luau", "Script" },
	{ ".server.lua", "Script" },
	{ ".client.luau", "LocalScript" },
	{ ".client.lua", "LocalScript" },
	{ ".luau", "ModuleScript" },
	{ ".lua", "ModuleScript" },
}
local outputSuffix = { Script = ".server.luau", LocalScript = ".client.luau", ModuleScript = ".luau" }

local function check(ok, message)
	if not ok then
		error(message, 0)
	end
	return ok
end

local function cachedScriptSource(path)
	local cache = active and active.fileCache
	if not cache then
		local source = Filesystem:ReadFile(path)
		check(type(source) == "string", "Could not read " .. path)
		return source
	end

	active.seenFiles[path] = true
	local version = Filesystem:GetFileVersion(path)
	check(type(version) == "string", "Could not stat " .. path)
	local hit = cache[path]
	if hit and hit.version == version then
		return hit.source
	end

	local source = Filesystem:ReadFile(path)
	check(type(source) == "string", "Could not read " .. path)
	local after = Filesystem:GetFileVersion(path)
	if after ~= version then
		version = after
		source = Filesystem:ReadFile(path)
		check(type(source) == "string", "Could not read " .. path)
		check(
			version ~= nil and Filesystem:GetFileVersion(path) == version,
			"Source was modified while syncing " .. path
		)
	end
	cache[path] = { version = version, source = source }
	return source
end

local function validName(name)
	return name ~= ""
		and name ~= "."
		and name ~= ".."
		and not name:find('[%z\1-\31/\\:*?"<>|]')
		and not name:find("[ .]$")
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

local function readSourcemap(projectPath)
	local entry = entries(projectPath)["sourcemap.json"]
	if not entry then
		return nil
	end
	check(entry.Type == "File", "Expected a regular sourcemap.json file")
	local path = projectPath .. "/" .. entry.Name
	local tree = HttpService:JSONDecode(check(Filesystem:ReadFile(path), "Could not read " .. path))
	check(type(tree) == "table" and tree.className == "DataModel", "Invalid Rojo sourcemap")
	return tree
end

local function scanSourcemap(projectPath, tree)
	local sources, directories = {}, {}
	local function findFile(relative)
		local pieces = string.split(relative:gsub("\\", "/"), "/")
		for _, piece in ipairs(pieces) do
			check(validName(piece), "Invalid sourcemap path " .. relative)
		end
		local path = projectPath
		for index, name in ipairs(pieces) do
			local contents = directories[path]
			if not contents then
				contents = entries(path)
				directories[path] = contents
			end
			local entry = contents[name:lower()]
			if not entry then
				return nil
			end
			local expected = index == #pieces and "File" or "Directory"
			check(entry.Type == expected, "Expected a regular source path in " .. relative)
			path ..= "/" .. entry.Name
		end
		return path
	end
	local function visit(node, names)
		if outputSuffix[node.className] then
			for _, relative in ipairs(node.filePaths or {}) do
				if type(relative) == "string" and scriptFile(relative) then
					local path = findFile(relative)
					if path then
						local source = cachedScriptSource(path)
						local filename = path:match("[^/]+$")
						add(sources, names, {
							path = path,
							class = node.className,
							source = source,
							isInit = scriptFile(filename) == "init",
							sourcemapped = true,
						})
					end
					break
				end
			end
		end
		for _, child in ipairs(node.children or {}) do
			check(type(child.name) == "string" and validName(child.name), "Invalid sourcemap instance name")
			visit(child, appendName(names, child.name))
		end
	end
	if tree then
		visit(tree, {})
	end
	return sources
end

local function scanDisk(root, names, records, mappedPaths)
	for _, entry in pairs(entries(root)) do
		local name = entry.Name
		local path = root .. "/" .. name
		if entry.Type == "Directory" and validName(name) and name:sub(1, 1) ~= "." then
			scanDisk(path, appendName(names, name), records, mappedPaths)
		elseif entry.Type == "File" and not mappedPaths[path:lower()] then
			local scriptName, class = scriptFile(name)
			if scriptName and validName(scriptName) then
				local isInit = scriptName == "init"
				check(not isInit or #names > 0, "An init script cannot replace a mapped service: " .. path)
				local source = cachedScriptSource(path)
				add(
					records,
					isInit and names or appendName(names, scriptName),
					{ path = path, class = class, source = source, isInit = isInit }
				)
			end
		end
	end
end

-- An imported .kine scene may contain duplicate sibling script names, which
-- Roblox permits but a Rojo directory mapping cannot represent. Cache that
-- unresolvable mapping rather than rebuilding 22k-instance trees every second.
local function clearModelConflict(mapping)
	if mapping.conflictConnections then
		for _, connection in ipairs(mapping.conflictConnections) do
			connection:Disconnect()
		end
	end
	mapping.conflictConnections = nil
	mapping.invalidModel = nil
	mapping.conflictRetryAt = nil
	mapping.conflictMessage = nil
	mapping.modelDirty = true
end

local function recordModelConflict(mapping, first, second, key)
	if not mapping or mapping.invalidModel then
		return
	end
	mapping.invalidModel = true
	mapping.conflictMessage = "Multiple instances or files map to " .. key
	mapping.conflictRetryAt = os.clock() + 60
	mapping.conflictConnections = {}

	-- Track just the two offending instances. No observers on the other
	-- thousands of scene objects, and normal source sync remains enabled.
	local function retry()
		clearModelConflict(mapping)
	end
	for _, object in ipairs({ first, second }) do
		if object then
			for _, property in ipairs({ "Name", "Parent" }) do
				local ok, connection = pcall(function()
					return object:GetPropertyChangedSignal(property):Connect(retry)
				end)
				if ok and connection then
					table.insert(mapping.conflictConnections, connection)
				end
			end
			local ok, connection = pcall(function()
				return object.Destroying:Connect(retry)
			end)
			if ok and connection then
				table.insert(mapping.conflictConnections, connection)
			end
		end
	end
end

-- Keep a cached snapshot of the in-memory scripts until a relevant
-- hierarchy or property edit occurs. Disk polling continues independently.
local function disposeModelObservers(mapping)
	if mapping.modelRootConnections then
		for _, connection in ipairs(mapping.modelRootConnections) do
			connection:Disconnect()
		end
	end
	if mapping.modelObjectConnections then
		for _, connections in pairs(mapping.modelObjectConnections) do
			for _, connection in ipairs(connections) do
				connection:Disconnect()
			end
		end
	end
	mapping.modelRootConnections = nil
	mapping.modelObjectConnections = nil
	mapping.modelSnapshot = nil
	mapping.modelDirty = true
end

local function installModelObservers(mapping)
	if mapping.modelRootConnections then
		return
	end
	local tracked = {}
	mapping.modelObjectConnections = tracked
	local function dirty()
		mapping.modelDirty = true
	end
	local function relevant(instance)
		return instance.ClassName == "Folder" or outputSuffix[instance.ClassName] ~= nil
	end
	local function unwatch(instance)
		local connections = tracked[instance]
		if not connections then
			return
		end
		tracked[instance] = nil
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
	end
	local function watch(instance)
		if not relevant(instance) or tracked[instance] then
			return
		end
		local connections = {}
		table.insert(connections, instance:GetPropertyChangedSignal("Name"):Connect(dirty))
		table.insert(connections, instance:GetPropertyChangedSignal("Parent"):Connect(dirty))
		if outputSuffix[instance.ClassName] then
			table.insert(connections, instance:GetPropertyChangedSignal("Source"):Connect(dirty))
		end
		table.insert(connections, instance.Destroying:Connect(dirty))
		tracked[instance] = connections
	end
	mapping.modelRootConnections = {
		mapping.root.DescendantAdded:Connect(function(instance)
			if relevant(instance) then
				dirty()
				watch(instance)
			end
		end),
		mapping.root.DescendantRemoving:Connect(function(instance)
			if relevant(instance) then
				dirty()
				unwatch(instance)
			end
		end),
	}
	for _, instance in ipairs(mapping.root:GetDescendants()) do
		watch(instance)
	end
end

local function scanModel(root, names, records, mapping)
	for _, child in ipairs(root:GetChildren()) do
		if validName(child.Name) and child.Name:sub(1, 1) ~= "." then
			local childNames = appendName(names, child.Name)
			if child.ClassName == "Folder" then
				scanModel(child, childNames, records, mapping)
			elseif outputSuffix[child.ClassName] then
				check(child.Name ~= "init", "The name init is reserved for Rojo directory scripts")
				local children = child:GetChildren()
				local key = table.concat(childNames, "/"):lower()
				if records[key] then
					recordModelConflict(mapping, records[key].object, child, key)
				end
				add(records, childNames, {
					object = child,
					class = child.ClassName,
					source = child.Source,
					isInit = #children > 0,
				})
				scanModel(child, childNames, records, mapping)
			end
		end
	end
end

-- The on-disk journal stores SHA-256 rather than full script contents.
-- In-memory records still retain Source for conflict resolution and exports.
local function sourceHash(record)
	if not record then
		return nil
	end
	if type(record.hash) == "string" then
		return record.hash
	end
	if type(record.source) ~= "string" then
		return nil
	end
	record.hash = Filesystem:HashSource(record.source)
	check(type(record.hash) == "string" and #record.hash == 64, "Could not hash script source")
	return record.hash
end

local function same(a, b)
	if a == b then
		return true
	end
	if not a or not b or a.class ~= b.class then
		return false
	end
	if table.concat(a.names, "/") ~= table.concat(b.names, "/") then
		return false
	end
	if type(a.source) == "string" and type(b.source) == "string" then
		return a.source == b.source
	end
	local ah, bh = sourceHash(a), sourceHash(b)
	return ah ~= nil and ah == bh
end

local function modelParent(root, names)
	for index = 1, #names - 1 do
		local name = names[index]
		local child = root:FindFirstChild(name)
		if child then
			check(
				child.ClassName == "Folder" or outputSuffix[child.ClassName],
				"Source folder collides with instance " .. name
			)
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
	if source ~= nil then
		replacement.Source = source
	end
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
	check(
		not existing or model or (disk.isInit and existing.ClassName == "Folder"),
		"Source file collides with instance " .. name
	)
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

	if disk and disk.sourcemapped then
		check(
			disk.class == model.class and table.concat(disk.names, "/") == table.concat(model.names, "/"),
			"Update the sourcemap before renaming or reclassifying " .. disk.path
		)
		check(Filesystem:WriteFileAtomic(disk.path, model.source), "Could not write " .. disk.path)
		return
	end
	check(root, "Add a directory mapping in default.project.json before exporting a new source file")

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
		check(
			table.concat(disk.names, "/") == table.concat(model.names, "/"),
			"Rename the existing source file on disk to change its spelling: " .. disk.path
		)
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

local function scanPair(mapping, mappedSources)
	local disk, model, mappedPaths = {}, {}, {}
	for _, source in pairs(mappedSources) do
		mappedPaths[source.path:lower()] = true
		local prefix = mapping.names
		local underMapping = #source.names > #prefix
		for index, name in ipairs(prefix) do
			if source.names[index] ~= name then
				underMapping = false
				break
			end
		end
		if underMapping then
			local relative = table.move(source.names, #prefix + 1, #source.names, 1, {})
			add(disk, relative, table.clone(source))
		end
	end
	if mapping.pieces then
		mapping.path = directory(mapping.projectPath, mapping.pieces, false)
		scanDisk(mapping.path, {}, disk, mappedPaths)
	end
	if mapping.modelSnapshot and not mapping.modelDirty and os.clock() < (mapping.modelRefreshAt or 0) then
		model = mapping.modelSnapshot
	else
		scanModel(mapping.root, {}, model, mapping)
		mapping.modelSnapshot = model
		mapping.modelDirty = false
		mapping.modelRefreshAt = os.clock() + 60
		installModelObservers(mapping)
	end
	if not mapping.path then
		model = table.clone(model) -- Never prune records from the cached snapshot.
		-- A sourcemap-only project has no rule for emitting unmapped objects.
		for key in pairs(model) do
			if not disk[key] and not mapping.previous[key] then
				model[key] = nil
			end
		end
	end
	return disk, model
end

local function remember(mapping, key, record)
	if same(mapping.previous[key], record) then
		return
	end
	mapping.previous[key] = record
		and {
			names = record.names,
			class = record.class,
			source = record.source,
			hash = record.hash,
		}
	active.dirty = true
end

local function reconcile(mapping, conflicts, mappedSources)
	local disk, model = scanPair(mapping, mappedSources)
	local keys, ordered = {}, {}
	for key in pairs(disk) do
		keys[key] = true
	end
	for key in pairs(model) do
		keys[key] = true
	end
	for key in pairs(mapping.previous) do
		keys[key] = true
	end
	for key in pairs(keys) do
		table.insert(ordered, key)
	end
	table.sort(ordered, function(a, b)
		return #a == #b and a < b or #a < #b
	end)

	-- Parents are applied before their children. Deletions run in reverse order.
	local removals = {}
	for _, key in ipairs(ordered) do
		local file, object = disk[key], model[key]
		local baseline = mapping.previous[key]
		if mapping.recovering and file then
			if not same(file, object) then
				applyModel(mapping.root, file, object)
			end
			remember(mapping, key, file)
		elseif mapping.opening and file and not same(file, object) then
			-- On opening a disk-backed project, the serialized .kine snapshot can
			-- be older than both the on-disk source and the sync journal. Always
			-- import the on-disk source here instead of overwriting external edits
			-- with a stale snapshot (including after a previous successful sync).
			applyModel(mapping.root, file, object)
			remember(mapping, key, file)
		elseif same(file, object) then
			if file and object.isInit and not file.isInit and not file.sourcemapped and not mapping.opening then
				applyDisk(mapping.path, file, object)
			end
			remember(mapping, key, file)
		elseif not mapping.initialized then
			if file then
				applyModel(mapping.root, file, object)
				remember(mapping, key, file)
			elseif mapping.path then
				applyDisk(mapping.path, nil, object)
				remember(mapping, key, object)
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
	if not mapping.initialized then
		active.dirty = true
	end
	mapping.initialized = true
	mapping.opening = false
	mapping.recovering = false
end

local function configureSourcemap(project, sourcemap)
	local mappings = {}
	for _, node in ipairs(sourcemap.children or {}) do
		local ok, root = pcall(game.GetService, game, node.name)
		if ok and root then
			table.insert(mappings, {
				root = root,
				projectPath = project.Path,
				names = { node.name },
				id = "/" .. node.name .. "|sourcemap",
				previous = {},
				opening = true,
			})
		end
	end
	return mappings
end

local function configure(project, sourcemap)
	local manifestPath = project.Path .. "/default.project.json"
	local manifestEntry = entries(project.Path)["default.project.json"]
	local generated = manifestEntry == nil
	local manifest
	if generated and sourcemap then
		return configureSourcemap(project, sourcemap)
	end
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
		manifestPath = project.Path .. "/" .. manifestEntry.Name
		manifest =
			HttpService:JSONDecode(check(Filesystem:ReadFile(manifestPath), "Could not read default.project.json"))
	end
	check(type(manifest) == "table" and type(manifest.tree) == "table", "Missing Rojo project tree")
	check(
		not manifest.globIgnorePaths or next(manifest.globIgnorePaths) == nil,
		"Source sync does not support globIgnorePaths"
	)
	check(manifest.emitLegacyScripts ~= false, "Source sync requires legacy script classes")

	local mappings = {}
	local function visit(node, root, names)
		local relative = node["$path"]
		if relative then
			check(type(relative) == "string", "Expected a relative directory in $path")
			local pieces = string.split(relative:gsub("\\", "/"), "/")
			check(root ~= game, "Map source directories under a DataModel service")
			local path = directory(project.Path, pieces, generated)
			local folded = path:lower()
			for _, mapping in ipairs(mappings) do
				local existing = mapping.path:lower()
				check(
					folded ~= existing
						and folded:sub(1, #existing + 1) ~= existing .. "/"
						and existing:sub(1, #folded + 1) ~= folded .. "/",
					"Overlapping source paths"
				)
			end
			table.insert(mappings, {
				root = root,
				path = path,
				projectPath = project.Path,
				pieces = pieces,
				names = names,
				id = "/" .. table.concat(names, "/") .. "|" .. table.concat(pieces, "/"),
				previous = {},
				opening = true,
			})
		end
		for name, child in pairs(node) do
			if name:sub(1, 1) ~= "$" then
				check(not relative, "Explicit children inside mapped source directories are unsupported")
				check(type(child) == "table", "Invalid project node " .. name)
				local target = root:FindFirstChild(name)
				if root == game then
					local ok, service = pcall(game.GetService, game, name)
					if ok then
						target = service
					end
				end
				if not target and child["$className"] == "Folder" then
					target = Instance.new("Folder")
					target.Name = name
					target.Parent = root
				end
				check(target, "Source mapping target does not exist: " .. name)
				visit(child, target, appendName(names, name))
			end
		end
	end
	visit(manifest.tree, game, {})
	if #mappings == 0 and sourcemap then
		return configureSourcemap(project, sourcemap)
	end
	return mappings, generated and manifestPath or nil, manifest
end

local function journalPath()
	return active.project.Path .. "/.kinemium-sync.json"
end

local function saveJournal()
	if not active.dirty or not active.mappings then
		return
	end
	local saved = { formatVersion = 2, paused = active.paused, mappings = {} }
	for _, mapping in ipairs(active.mappings) do
		if mapping.initialized then
			local compact = {}
			for key, record in pairs(mapping.previous) do
				compact[key] = {
					names = record.names,
					class = record.class,
					hash = sourceHash(record),
				}
			end
			saved.mappings[mapping.id] = compact
		end
	end
	check(Filesystem:WriteFileAtomic(journalPath(), HttpService:JSONEncode(saved)), "Could not save source sync state")
	active.dirty = false
end

local function readJournal(mappings)
	local state = Filesystem:ReadFile(journalPath())
	if not state then
		return
	end
	local decoded, saved = pcall(HttpService.JSONDecode, HttpService, state)
	if not decoded or type(saved) ~= "table" or type(saved.mappings) ~= "table" then
		check(active.recovering, "Invalid source sync state")
		active.dirty = true
		return
	end
	active.paused = saved.paused == true
	-- Transparently upgrade v1 journals (which embed full script bodies).
	if saved.formatVersion ~= 2 then
		active.dirty = true
	end
	for _, mapping in ipairs(mappings) do
		local previous = saved.mappings[mapping.id]
		if type(previous) == "table" then
			if not active.recovering then
				mapping.previous = previous
				mapping.initialized = true
			end
		end
	end
end

function Sync.stop()
	stopPolling()
	if active and active.mappings then
		for _, mapping in ipairs(active.mappings) do
			clearModelConflict(mapping)
			disposeModelObservers(mapping)
		end
	end
	active = nil
end

function Sync.step()
	if not active then
		return true
	end
	local ok, message = pcall(function()
		local sourcemap = readSourcemap(active.project.Path)
		if not active.mappings then
			local configured, mappings, manifestPath, manifest = pcall(configure, active.project, sourcemap)
			if not configured then
				-- Rojo can describe explicit files and filters that directory
				-- sync cannot infer. Use its resolved file paths when available.
				check(sourcemap, mappings)
				mappings = configureSourcemap(active.project, sourcemap)
			end
			readJournal(mappings)
			for _, mapping in ipairs(mappings) do
				mapping.recovering = active.recovering
			end
			active.mappings, active.manifestPath, active.manifest = mappings, manifestPath, manifest
		end
		if active.paused then
			return
		end
		active.seenFiles = {}
		local mappedSources = scanSourcemap(active.project.Path, sourcemap)
		local conflicts = {}
		local blockingError
		for _, mapping in ipairs(active.mappings) do
			if mapping.invalidModel and os.clock() >= mapping.conflictRetryAt then
				-- Safety retry if an engine path changed without firing an event.
				clearModelConflict(mapping)
			end
			if mapping.invalidModel then
				blockingError = blockingError or mapping.conflictMessage
				continue
			end
			local success, err = pcall(reconcile, mapping, conflicts, mappedSources)
			if not success then
				if not mapping.invalidModel then
					error(err, 0)
				end
				blockingError = blockingError or mapping.conflictMessage
			end
		end
		active.conflicts = conflicts
		-- Drop deleted/renamed files so stale sources cannot leak across scans.
		for path in pairs(active.fileCache) do
			if not active.seenFiles[path] then
				active.fileCache[path] = nil
			end
		end
		if active.manifestPath then
			check(
				not Filesystem:PathExists(active.manifestPath),
				"default.project.json appeared while configuring sync"
			)
			check(
				Filesystem:WriteFileAtomic(active.manifestPath, HttpService:JSONEncode(active.manifest)),
				"Could not write default.project.json"
			)
			active.manifestPath = nil
		end
		saveJournal()
		if blockingError then
			error(blockingError, 0)
		end
		check(#conflicts == 0, tostring(#conflicts) .. " source conflicts. Open File > Sync Conflicts to review.")
	end)
	if not ok and message ~= active.error then
		UI.toast(
			"project-sync",
			{ type = "error", title = "Project source sync", message = tostring(message), duration = 8 }
		)
	end
	active.error = not ok and message or nil
	return ok
end

function Sync.setPaused(paused)
	if not active then
		return false
	end
	active.paused = paused
	stopPolling()
	active.dirty = true
	local ok, message = pcall(saveJournal)
	if not ok then
		UI.toast(
			"project-sync",
			{ type = "error", title = "Could not save sync settings", message = tostring(message), duration = 8 }
		)
	end
	if not paused then
		Sync.step()
		schedulePoll()
	end
	return ok
end

function Sync.isPaused()
	return active ~= nil and active.paused
end

function Sync.getConflicts()
	return active and active.conflicts or {}
end

function Sync.resolve(conflict, choice)
	if not active then
		return false, "This project is no longer open."
	end
	local currentIndex
	for index, current in ipairs(active.conflicts) do
		if current.mapping == conflict.mapping and current.key == conflict.key then
			currentIndex = index
			break
		end
	end
	if not currentIndex then
		return false, "This conflict is no longer current."
	end
	local ok, message = pcall(function()
		local mapping, key = conflict.mapping, conflict.key
		local sourcemap = readSourcemap(active.project.Path)
		local disk, model = scanPair(mapping, scanSourcemap(active.project.Path, sourcemap))
		local file, object = disk[key], model[key]
		check(
			same(file, conflict.file) and same(object, conflict.object),
			"The sources changed. Review the current conflict before resolving it."
		)
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
	if not active.paused then
		Sync.step()
	end
	return ok, message
end

function Sync.start(project, nextHeartbeat)
	if not Sync.available then
		return true
	end
	Sync.stop()
	active = {
		project = project,
		paused = false,
		conflicts = {},
		recovering = not Filesystem:PathExists(project.Path .. "/autosave.kine"),
		fileCache = {},
		seenFiles = {},
	}
	-- Editor bootstrap can run before the .kine scene deserializes. Never
	-- reconcile with an empty world: an older in-memory source could otherwise
	-- overwrite changes made on disk before project startup.
	if nextHeartbeat then
		bootstrapConnection = RunService.Heartbeat:Connect(function()
			bootstrapConnection:Disconnect()
			bootstrapConnection = nil
			if active and not active.paused then
				Sync.step()
				schedulePoll()
			end
		end)
		return true
	end
	local result = Sync.step()
	schedulePoll()
	return result
end

return Sync

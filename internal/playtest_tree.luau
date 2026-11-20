if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local service = game:GetService("PlaytestService")
local UI = require("@internal/editor_ui")
local Selection = game:GetService("Selection")
local Tree = { role = nil, root = nil, nodes = {}, selected = nil, revision = 0, error = nil }
local nextTree, nextProperties = 0, 0
local pending, edits = {}, {}
local copyQueued, copySerial = nil, 0
Tree.clipboard = nil
Tree.copyPending = false
local generation = 0
local treeVersion = nil
local selectionGeneration = 0
local clock = 0
local lastStatus = 0
Tree.changed = Signal.new()
local values = {}
local function notify(message)
	UI.toast("playtest-tree", { type = "warning", title = "Playtest inspection", message = tostring(message) })
end
local function available(role)
	return service.IsRunning
		and (
			service.IsSingleplayer
			or (role == "Server" and service.ServerProcessId > 0)
			or (role == "Client" and service.ClientProcessId > 0)
		)
end
function Tree.select(node)
	if node and (type(node) ~= "table" or Tree.nodes[node.Id] ~= node) then
		return
	end
	if Tree.selected == node then
		return
	end
	Tree.selected = node
	selectionGeneration += 1
	values = {}
	nextProperties = 0
end
function Tree.setRole(role)
	if role and not available(role) then
		notify(role .. " is not running.")
		return false
	end
	generation += 1
	if #edits > 0 then
		notify("Unsent property edits were discarded when switching runtimes.")
	end
	table.clear(edits)
	treeVersion = nil
	Tree.role, Tree.root, Tree.nodes, Tree.error = role, nil, {}, nil
	Tree.select(nil)
	Tree.revision += 1
	nextTree = 0
	Selection:Set({})
	Tree.changed:Fire()
	return true
end
function Tree.cycle()
	if not service.IsRunning then
		notify("Start a playtest first.")
		return
	end
	if Tree.role == nil then
		Tree.setRole(available("Client") and "Client" or "Server")
	elseif Tree.role == "Client" and available("Server") and not service.IsSingleplayer then
		Tree.setRole("Server")
	else
		Tree.setRole(nil)
	end
end
function Tree.caption()
	if not Tree.role then
		return "Editor"
	end
	return service.IsSingleplayer and "Singleplayer" or Tree.role
end
local function applyTree(rows)
	Tree.error = nil
	local old, new, changed = Tree.nodes, {}, false
	for _, row in ipairs(rows) do
		local node = old[row.Id]
		if not node then
			node = { Id = row.Id, children = {} }
			function node:GetChildren()
				return table.clone(self.children)
			end
			changed = true
		end
		if node.Name ~= row.Name or node.ClassName ~= row.ClassName or node.ParentId ~= row.ParentId then
			changed = true
		end
		node.Name, node.ClassName, node.ParentId = row.Name, row.ClassName, row.ParentId
		new[row.Id] = node
	end
	for id in pairs(old) do
		if not new[id] then
			changed = true
			break
		end
	end
	if not changed then
		return
	end
	Tree.root = nil
	for _, node in pairs(new) do
		node.children = {}
		node.Parent = new[node.ParentId]
		if not node.Parent then
			Tree.root = node
		end
	end
	for _, row in ipairs(rows) do
		local node = new[row.Id]
		if node.Parent then
			table.insert(node.Parent.children, node)
		end
	end
	Tree.nodes = new
	if Tree.selected and not new[Tree.selected.Id] then
		Tree.select(nil)
	end
	Tree.revision += 1
end
function Tree.properties()
	return values
end

local function begin(role, kind, node, edit)
	local ok, token, err = pcall(function()
		if kind == "tree" then
			return service:RequestGameTree(role, treeVersion or "")
		end
		if kind == "properties" then
			return service:RequestInstanceProperties(role, node.Id)
		end
		if kind == "copy" then
			return service:RequestCopyInstance(role, node.Id)
		end
		if type(edit.value) == "table" and edit.value.InstanceId ~= nil then
			return service:RequestSetInstanceReference(role, node.Id, edit.key, edit.value.InstanceId)
		end
		return service:RequestSetInstanceProperty(role, node.Id, edit.key, edit.value)
	end)
	if ok and type(token) == "number" then
		pending[role] = {
			token = token,
			kind = kind,
			generation = generation,
			selection = selectionGeneration,
			node = node,
			copySerial = kind == "copy" and edit.serial or nil,
		}
		return true
	end
	Tree.error = tostring(err or token or "Unable to send request")
	if kind == "edit" then
		notify(Tree.error)
	end
	return false
end

local function poll(dt)
	clock += math.max(tonumber(dt) or 0, 0)
	if clock >= lastStatus then
		lastStatus = clock + 0.2
		if Tree.role and not available(Tree.role) then
			Tree.setRole(nil)
		end
	end
	for role, request in pairs(pending) do
		local ok, result, err = pcall(function()
			return service:PollTreeRequest(role, request.token)
		end)
		if ok and result == nil and err == nil then
			continue
		end
		pending[role] = nil
		if request.kind == "copy" then
			if request.copySerial == copySerial then
				Tree.copyPending = false
				if ok and typeof(result) == "buffer" then
					Tree.clipboard = result
					UI.toast(
						"playtest-copy",
						{
							type = "success",
							title = "Instance copied",
							message = "Switch to Editor and paste to insert " .. request.node.Name .. ".",
						}
					)
				else
					notify(err or result or "Could not copy the live instance.")
				end
			end
			continue
		end
		if request.generation ~= generation or role ~= Tree.role then
			if request.kind == "edit" and (not ok or result == nil) then
				notify(err or result or "A submitted edit failed.")
			end
			continue
		end
		if not ok or result == nil then
			Tree.error = tostring(err or result or "Request failed")
			if request.kind == "edit" then
				notify(Tree.error)
			end
			if request.kind == "tree" then
				nextTree = clock + 2
			else
				nextProperties = clock + 0.5
			end
		elseif request.kind == "tree" then
			treeVersion = err
			Tree.error = nil
			if type(result) == "table" then
				applyTree(result)
			end
		elseif request.kind == "properties" then
			if request.selection == selectionGeneration then
				values = result
			end
		else
			nextTree, nextProperties = clock, clock
		end
	end
	if copyQueued and not pending[copyQueued.role] then
		local request = copyQueued
		copyQueued = nil
		if not available(request.role) or not begin(request.role, "copy", request.node, request) then
			Tree.copyPending = false
			notify("Could not copy the live instance. The playtest may have ended.")
		end
	end
	local role = Tree.role
	if not role or pending[role] then
		return
	end
	if #edits > 0 then
		local edit = table.remove(edits, 1)
		if Tree.nodes[edit.node.Id] == edit.node then
			begin(role, "edit", edit.node, edit)
		end
	elseif clock >= nextTree then
		nextTree = clock + 1
		if not begin(role, "tree") then
			nextTree = clock + 2
		end
	elseif Tree.selected and clock >= nextProperties then
		nextProperties = clock + 0.5
		if not begin(role, "properties", Tree.selected) then
			nextProperties = clock + 2
		end
	end
end

function Tree.copy(node)
	if not Tree.role or not node or Tree.nodes[node.Id] ~= node then
		return false
	end
	-- The root and direct services cannot be copied.
	if not node.Parent or not node.Parent.Parent then
		notify("Select an instance beneath a game service.")
		return false
	end
	copySerial += 1
	Tree.clipboard = nil
	Tree.copyPending = true
	copyQueued = { role = Tree.role, node = node, serial = copySerial }
	return true
end

function Tree.clearClipboard()
	copySerial += 1
	copyQueued, Tree.clipboard = nil, nil
	Tree.copyPending = false
end

function Tree.setProperty(node, key, value)
	if not Tree.role or Tree.selected ~= node or Tree.nodes[node.Id] ~= node then
		return false
	end
	if #edits >= 128 then
		notify("Too many pending property edits.")
		return false
	end
	-- Queue edits without blocking the UI. The next property snapshot confirms
	-- the authoritative value; no local editor Instance is modified.
	table.insert(edits, { node = node, key = key, value = value })
	return true
end

game:GetService("RunService").Heartbeat:Connect(poll)
return Tree

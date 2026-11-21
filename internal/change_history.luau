local History = {}

local UserInputService = game:GetService("UserInputService")
local Preferences = require("@internal/preferences")
local service = game:GetService("ChangeHistoryService")

local entries = {}
local order = {}
local undoStack = {}
local redoStack = {}
local nextId = 0
local replaying = false
local latest = nil
local serviceConnected = false
local MAX_ENTRIES = 256
local propertyMergeKeys = setmetatable({}, { __mode = "k" })

local function propertyMergeKey(object, property)
	local keys = propertyMergeKeys[object]
	if not keys then
		keys = {}
		propertyMergeKeys[object] = keys
	end
	local key = keys[property]
	if not key then
		key = {}
		keys[property] = key
	end
	return key
end

local function invoke(entry, field)
	if entry == nil or replaying then
		return false
	end
	replaying = true
	local success, err = pcall(entry[field])
	replaying = false
	if not success then
		warn("Change history " .. field .. " failed (" .. entry.label .. "): " .. tostring(err))
	end
	return success
end

local function dropRedoEntries()
	for _, entry in ipairs(redoStack) do
		entries[entry.id] = nil
	end
	table.clear(redoStack)
end

local function markUndo(id)
	local entry = entries[id]
	if not entry or entry.undone then
		return
	end
	if not invoke(entry, "undo") then
		return
	end
	entry.undone = true
	if undoStack[#undoStack] == entry then
		table.remove(undoStack)
	else
		for index = #undoStack, 1, -1 do
			if undoStack[index] == entry then
				table.remove(undoStack, index)
				break
			end
		end
	end
	table.insert(redoStack, entry)
	latest = nil
end

local function markRedo(id)
	local entry = entries[id]
	if not entry or not entry.undone then
		return
	end
	if not invoke(entry, "redo") then
		return
	end
	entry.undone = false
	for index = #redoStack, 1, -1 do
		if redoStack[index] == entry then
			table.remove(redoStack, index)
			break
		end
	end
	table.insert(undoStack, entry)
	latest = entry
end

if service then
	local connected = pcall(function()
		service.OnUndo:Connect(markUndo)
		service.OnRedo:Connect(markRedo)
	end)
	serviceConnected = connected
end

function History.isReplaying()
	return replaying
end

function History.record(label, undo, redo, mergeKey)
	if replaying or type(undo) ~= "function" or type(redo) ~= "function" then
		return nil
	end
	local now = os.clock()
	if
		mergeKey
		and latest
		and not latest.undone
		and latest.mergeKey == mergeKey
		and now - latest.time <= 0.8
		and undoStack[#undoStack] == latest
	then
		latest.redo = redo
		latest.time = now
		return latest.id
	end

	dropRedoEntries()
	nextId += 1
	local id = "__kinemium_editor_" .. tostring(nextId)
	local entry = {
		id = id,
		label = label or "Edit",
		undo = undo,
		redo = redo,
		mergeKey = mergeKey,
		time = now,
		undone = false,
	}
	entries[id] = entry
	table.insert(undoStack, entry)
	table.insert(order, entry)
	latest = entry

	if serviceConnected then
		local success, err = pcall(function()
			service:SetWaypoint(id)
		end)
		if not success then
			warn("ChangeHistoryService:SetWaypoint failed: " .. tostring(err))
			serviceConnected = false
		else
			-- An engine with history disabled accepts SetWaypoint but silently
			-- discards it. Detect this and retain working local undo instead.
			local checked, canUndo, newest = pcall(function()
				return service:GetCanUndo()
			end)
			if checked and (not canUndo or newest ~= id) then
				serviceConnected = false
			end
		end
	end

	while #order > MAX_ENTRIES do
		local old = table.remove(order, 1)
		entries[old.id] = nil
		for _, stack in ipairs({ undoStack, redoStack }) do
			for index = #stack, 1, -1 do
				if stack[index] == old then
					table.remove(stack, index)
					break
				end
			end
		end
	end
	return id
end

function History.recordProperty(object, property, before, after, mergeKey)
	if before == after then
		return nil
	end
	local function restore(value)
		local success, err = pcall(function()
			if string.sub(property, 1, 5) == "attr:" then
				object:SetAttribute(string.sub(property, 6), value)
			else
				object[property] = value
			end
		end)
		if not success then
			error(err)
		end
	end
	return History.record("Edit " .. property, function()
		restore(before)
	end, function()
		restore(after)
	end, mergeKey ~= nil and propertyMergeKey(object, property) or nil)
end

function History.recordParents(label, changes, afterRestore)
	if #changes == 0 then
		return nil
	end
	return History.record(label, function()
		for index = #changes, 1, -1 do
			local change = changes[index]
			change.object.Parent = change.before
		end
		if afterRestore then
			afterRestore()
		end
	end, function()
		for _, change in ipairs(changes) do
			change.object.Parent = change.after
		end
		if afterRestore then
			afterRestore()
		end
	end)
end

function History.canUndo()
	return #undoStack > 0
end

function History.canRedo()
	return #redoStack > 0
end

function History.undo()
	if replaying or #undoStack == 0 then
		return false
	end
	if serviceConnected then
		local success, err = pcall(function()
			service:Undo()
		end)
		if not success then
			warn("ChangeHistoryService:Undo failed: " .. tostring(err))
			return false
		end
	else
		markUndo(undoStack[#undoStack].id)
	end
	return true
end

function History.redo()
	if replaying or #redoStack == 0 then
		return false
	end
	if serviceConnected then
		local success, err = pcall(function()
			service:Redo()
		end)
		if not success then
			warn("ChangeHistoryService:Redo failed: " .. tostring(err))
			return false
		end
	else
		markRedo(redoStack[#redoStack].id)
	end
	return true
end

function History.clear()
	table.clear(entries)
	table.clear(order)
	table.clear(undoStack)
	table.clear(redoStack)
	latest = nil
	propertyMergeKeys = setmetatable({}, { __mode = "k" })
	if serviceConnected then
		pcall(function()
			service:ResetWaypoints()
		end)
	end
end

local function isKeyDown(key)
	return key ~= nil and UserInputService:IsKeyDown(key)
end

local function ctrlDown()
	return isKeyDown(Enum.KeyCode.LeftControl)
		or isKeyDown(Enum.KeyCode.RightControl)
		or isKeyDown(Enum.KeyCode.LeftSuper)
		or isKeyDown(Enum.KeyCode.RightSuper)
end

local function shiftDown()
	return isKeyDown(Enum.KeyCode.LeftShift) or isKeyDown(Enum.KeyCode.RightShift)
end

-- Bind once on module initialization. Text fields retain their own native undo
-- stacks, and tools that need special handling must register actions here.
UserInputService.InputBegan:Connect(function(input, processed)
	if
		processed
		or input.UserInputType ~= Enum.UserInputType.Keyboard
		or not Preferences.get("enableKeyboardShortcuts")
		or UserInputService:GetFocusedTextBox() ~= nil
		or not ctrlDown()
	then
		return
	end
	if input.KeyCode == Enum.KeyCode.Z then
		if shiftDown() then
			History.redo()
		else
			History.undo()
		end
	elseif input.KeyCode == Enum.KeyCode.Y or input.KeyCode == Enum.KeyCode.R then
		History.redo()
	end
end)

return History

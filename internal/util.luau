local Selection = game:GetService("Selection")

local function selectedObject()
	local selected = Selection:Get()
	local object = selected and selected[1]
	return object
end

local function mergeChildren(source, destination)
	if not destination then
		return
	end

	for _, child in source:GetChildren() do
		if not destination:FindFirstChild(child.Name) then
			child.Parent = destination
		end
	end
end

local function serviceDestination(source)
	-- A service can have a custom display name. Its class identifies the singleton.
	return game:FindService(source.ClassName)
end

local function parent(source, target)
	if source:IsA("DataModel") then
		for _, child in source:GetChildren() do
			if child:IsA("Service") then
				mergeChildren(child, serviceDestination(child))
			else
				mergeChildren(child, game:FindFirstChild(child.Name))
			end
		end
	elseif source:IsA("Service") then
		mergeChildren(source, serviceDestination(source))
	else
		source.Parent = target or selectedObject() or workspace
	end
end

return {
	parent = parent,
}

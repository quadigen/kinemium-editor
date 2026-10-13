local Selection = game:GetService("Selection")

local function selectedObject()
	local selected = Selection:Get()
	local object = selected and selected[1]
	return object
end

local function parent(sourceDataModel)
	if sourceDataModel:IsA("Datamodel") then
		for _, sourceService in sourceDataModel:GetChildren() do
			local currentService = game:FindFirstChild(sourceService.Name)

			if currentService then
				for _, child in sourceService:GetChildren() do
					local exists = false

					for _, existingChild in currentService:GetChildren() do
						if child.Name == existingChild.Name then
							exists = true
							break
						end
					end

					if not exists then
						child.Parent = currentService
					end
				end
			end
		end
	else
		local object = selectedObject()
		sourceDataModel.Parent = object or workspace
	end
end

return {
	parent = parent,
}

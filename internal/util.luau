local function parent(sourceDataModel)
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
end

return {
	parent = parent,
}

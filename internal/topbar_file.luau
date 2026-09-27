if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local export_service = game:GetService("ExportService")
local dialog = game:GetService("DialogService")

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
	name = "File",
	buttons = {
		{
			name = "Project Settings",
			route = "new_project",
		},
		{
			name = "Import Object",
			callback = function()
				local file = dialog:PickFile()
				if file then
					local imported = export_service:ImportFile(file)
					parent(imported)
				end
			end,
		},
		{
			name = "Save",
			route = "save_project",
		},
		{
			name = "Save to File",
			route = "save_project",
		},
		{
			type = "separator",
		},
		{
			name = "Close Project",
			route = "close_project",
		},
		{
			name = "Exit",
			route = "exit",
		},
	},
}

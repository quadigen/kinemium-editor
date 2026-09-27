if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local export_service = game:GetService("ExportService")
local dialog = game:GetService("DialogService")

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
					print(imported)
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

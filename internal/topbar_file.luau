if (IsServer or IsClient) or IsPlaytest then
	return nil
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
			route = "open_project",
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

if (IsServer or IsClient) and not IsPlaytest then
	return nil
end

return {
	name = "File",
	buttons = {
		{
			name = "New Project",
			icon = "Plus.svg",
			route = "new_project",
		},
		{
			name = "Open Project",
			icon = "FolderOpen.svg",
			route = "open_project",
		},
		{
			name = "Save",
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

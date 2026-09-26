if (IsServer or IsClient) or IsPlaytest then
	return nil
end
return {
	name = "Projects",
	buttons = {
		{
			name = "Open Projects",
			icon = "FolderOpen.svg",
			route = "open_projects",
		},
		{
			name = "New Project",
			icon = "Plus.svg",
			route = "new_project",
		},
		{
			name = "Marketplace",
			route = "open_marketplace",
		},
		{
			name = "Settings",
			icon = "Property.svg",
			route = "open_settings",
		},
	},
}

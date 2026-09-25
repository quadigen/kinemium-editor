if IsServer or IsClient then
	return nil
end

return {
	name = "View",
	buttons = {
		{
			name = "Explorer",
			icon = "FolderOpen.svg",
			route = "toggle_explorer",
		},
		{
			name = "Inspector",
			icon = "Property.svg",
			route = "toggle_inspector",
		},
		{
			name = "Output",
			icon = "LogService.svg",
			route = "toggle_output",
		},
	},
}

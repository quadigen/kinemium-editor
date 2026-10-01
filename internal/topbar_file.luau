if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local export_service = game:GetService("ExportService")
local dialog = game:GetService("DialogService")
local UI = require("@internal/editor_ui")
local util = require("@internal/util")

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
					if imported then
						util.parent(imported)

						UI.toast("creation", {
							type = "success",
							title = "Successfully imported!",
							message = `Successfully imported {file}`,
							details = `Wow.`,
							detailsTitle = "",
							backgroundTransparency = 0.4,
							blur = true,
							duration = 5,
						})
					else
						UI.toast("import", {
							type = "error",
							title = "Importing faliure",
							message = `Did not import project successfully.`,
							details = ``,
							detailsTitle = "",
							backgroundTransparency = 0.4,
							blur = true,
							duration = 5,
						})
					end
				end
			end,
		},
		{
			name = "Save",
			route = "save_project",
		},
		{
			name = "Save to File",
			callback = function()
				local file = dialog:PickFile()
				if file then
					local success = export_service:ExportToFile(file)
					if success then
						UI.toast("import", {
							type = "success",
							title = "Exported successfully!",
							message = `Exported KINE file to {file}`,
							details = ``,
							detailsTitle = "",
							backgroundTransparency = 0.4,
							blur = true,
							duration = 5,
						})
					end
				end
			end,
		},
		{
			type = "separator",
		},
		{
			name = "Close Project",
			callback = function()
				local gui = game.CoreGui.Home
				if gui then
					gui.Enabled = true
					UI.root().Enabled = false
					UI.RootOverlay().Enabled = false
				end
			end,
		},
		{
			name = "Exit",
			route = "exit",
		},
	},
}

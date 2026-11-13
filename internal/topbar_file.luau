if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local export_service = game:GetService("ExportService")
local dialog = game:GetService("DialogService")
local UI = require("@internal/editor_ui")
local util = require("@internal/util")
local HttpService = game:GetService("HttpService")

local Preferences = require("@internal/preferences")
local Exit = require("@internal/editor_exit")
local Project = game:GetService("Project")
local Sync = require("@internal/project_sync")
local Tools = require("@internal/project_tools")
local nativeExit, exitEditor = pcall(function() return Project.ExitEditor end)
nativeExit = nativeExit and type(exitEditor) == "function"

local function saveProject()
	if not Sync.available then return false end
	local ok, saved = pcall(Project.SaveProject, Project)
	if not ok or not saved then
		UI.toast("project-save", { type = "error", title = "Could not save project",
			message = "Check that the active project's folder is writable.", duration = 5 })
		return false
	end
	UI.toast("project-save", { type = "success", title = "Project saved", duration = 3 })
	return true
end

local menu = {
	name = "File",
	buttons = {
		{
			name = "Project Settings",
			route = "new_project",
		},
		{
			name = "Report Bug",
			callback = function()
				HttpService:OpenURL("https://github.com/quadigen/canary-recode/issues/new")
			end,
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
			route = not Sync.available and "save_project" or nil,
			callback = Sync.available and function()
				Sync.step()
				saveProject()
			end or nil,
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
				if Sync.available and Project:GetActiveProject() then
					Sync.step()
					if not saveProject() then return end
					Sync.stop()
				end
				Preferences.set("sessionProject", "")
				local gui = game.CoreGui.Home
				if gui then
					gui.Enabled = true
					UI.root().Enabled = false
					UI.RootOverlay().Enabled = false
					UI.widgetOverlay().Enabled = false
					if shared.ScriptLayer then
						shared.ScriptLayer.Enabled = false
					end
				end
			end,
		},
		{
			name = "Exit",
			route = not nativeExit and "exit" or nil,
			callback = nativeExit and Exit.request or nil,
		},
	},
}

if Sync.available then
	local tools = {
		{ name = "Pause / Resume Source Sync", callback = Tools.toggleSync },
		{ name = "Sync Conflicts", callback = function() Tools.conflicts(1, true) end },
	}
	if Tools.backupsAvailable then
		table.insert(tools, { name = "Restore Project Backup", callback = Tools.backups })
	end
	for index, button in ipairs(tools) do
		table.insert(menu.buttons, 5 + index, button)
	end
end

return menu
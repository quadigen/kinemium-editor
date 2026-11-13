local Preferences = require("@internal/preferences")
local UI = require("@internal/editor_ui")
local Sync = require("@internal/project_sync")
local Project = game:GetService("Project")
local Exit = {}
local prompt

function Exit.confirm()
	if prompt then
		return
	end
	local function saveAndExit()
		Sync.step()
		if not Project:SaveProject() then
			UI.toast("project-save", { type = "error", title = "Could not save project" })
			return false
		end
		Project:ExitEditor()
	end
	local _, _, controller = UI.prompt({
		title = "Exit Engine?",
		description = "The active project has unsaved changes.",
		modal = true,
		destroyOnClose = true,
		onClose = function()
			prompt = nil
		end,
		buttons = {
			{ id = "cancel", text = "Cancel" },
			{
				id = "discard",
				text = "Exit without saving",
				role = "danger",
				callback = function()
					Project:ExitEditor(true)
				end,
			},
			{ id = "save", text = "Save and exit", role = "primary", callback = saveAndExit },
		},
	})
	prompt = controller
	controller:Open()
end

function Exit.request()
	if Preferences.get("confirmExit") and Project.HasUnsavedChanges and Project:HasUnsavedChanges() then
		Exit.confirm()
	else
		Project:ExitEditor()
	end
end

return Exit

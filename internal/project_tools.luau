local UI = require("@internal/editor_ui")
local Sync = require("@internal/project_sync")
local Project = game:GetService("Project")
local TextService = game:GetService("TextService")

local Tools = {}
local available, backups = pcall(function()
	return Project.GetProjectBackups
end)
Tools.backupsAvailable = available and type(backups) == "function"

local function notify(kind, title, message)
	UI.toast("project-tools", { type = kind, title = title, message = message, duration = 5 })
end

function Tools.toggleSync()
	if Sync.setPaused(not Sync.isPaused()) then
		local paused = Sync.isPaused()
		notify(
			"success",
			paused and "Source sync paused" or "Source sync resumed",
			paused and "The editor and filesystem can be edited independently."
				or "The editor is syncing with the filesystem."
		)
	end
end

local function sourcePane(parent, title, record, x)
	local text = record and record.source or "(deleted)"
	if text == "" then
		text = "(empty file)"
	end
	local heading = UI.label(parent, title, UDim2.new(x, 4, 0, 0), UDim2.new(0.5, -8, 0, 24), 13, UI.tokens.color.text)
	heading.TextXAlignment = Enum.TextXAlignment.Left
	local scroll = UI.create("ScrollingFrame", {
		Position = UDim2.new(x, 4, 0, 26),
		Size = UDim2.new(0.5, -8, 1, -60),
		CanvasSize = UDim2.fromOffset(0, 0),
		ScrollBarThickness = 6,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
	}, parent)
	local label = UI.label(scroll, text, UDim2.fromOffset(6, 4), UDim2.new(1, -20, 0, 0), 13, UI.tokens.color.text)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextWrapped = true
	label.RichText = false
	local function resize()
		local width = math.max(scroll.AbsoluteSize.X - 20, 1)
		local size = TextService:GetTextSize(text, label.TextSize, label.FontFace, Vector2.new(width, 1000000))
		label.Size = UDim2.new(1, -20, 0, size.Y + 8)
		scroll.CanvasSize = UDim2.fromOffset(0, size.Y + 16)
	end
	scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
	resize()
end

function Tools.conflicts(index, refresh)
	if refresh then
		Sync.step()
	end
	local conflicts = Sync.getConflicts()
	if #conflicts == 0 then
		notify("info", "Source sync", "There are no current conflicts.")
		return
	end
	index = math.clamp(index or 1, 1, #conflicts)
	local conflict = conflicts[index]
	local function resolve(choice)
		local ok, message = Sync.resolve(conflict, choice)
		if not ok then
			notify("error", "Could not resolve conflict", tostring(message))
		end
		task.defer(function()
			if #Sync.getConflicts() > 0 then
				Tools.conflicts(index)
			end
		end)
	end
	UI.prompt({
		name = "ProjectSyncConflicts",
		title = "Source conflict " .. index .. " of " .. #conflicts,
		description = conflict.mapping.id:match("^[^|]*") .. "/" .. conflict.key,
		size = UDim2.fromOffset(780, 480),
		destroyOnClose = true,
		buttons = {
			{ id = "close", text = "Close", role = "secondary" },
			{
				id = "disk",
				text = "Keep Filesystem",
				role = "secondary",
				callback = function()
					resolve("disk")
				end,
			},
			{
				id = "editor",
				text = "Keep Editor",
				role = "primary",
				callback = function()
					resolve("editor")
				end,
			},
		},
		build = function(content, controller)
			sourcePane(content, "Editor", conflict.object, 0)
			sourcePane(content, "Filesystem", conflict.file, 0.5)
			local function move(nextIndex)
				controller:Close()
				task.defer(Tools.conflicts, nextIndex)
			end
			if index > 1 then
				UI.button(content, "Previous", UDim2.new(0, 4, 1, -28), UDim2.fromOffset(90, 26), function()
					move(index - 1)
				end)
			end
			if index < #conflicts then
				UI.button(content, "Next", UDim2.new(1, -94, 1, -28), UDim2.fromOffset(90, 26), function()
					move(index + 1)
				end)
			end
		end,
	})
end

function Tools.backups()
	local backups = Project:GetProjectBackups()
	if #backups == 0 then
		notify("info", "Project backups", "A backup appears after a newer save replaces the current snapshot.")
		return
	end
	local selected
	UI.prompt({
		name = "ProjectBackups",
		title = "Restore Project Backup",
		description = "Select a snapshot. Restoring saves the current scene first and pauses source sync.",
		size = UDim2.fromOffset(560, 155 + #backups * 38),
		destroyOnClose = true,
		buttons = {
			{ id = "cancel", text = "Cancel", role = "secondary" },
			{
				id = "restore",
				text = "Restore",
				role = "primary",
				callback = function()
					if not selected then
						return false
					end
					local wasPaused = Sync.isPaused()
					if not Sync.setPaused(true) then
						return false
					end
					if not Project:RestoreProjectBackup(selected.Id) then
						Sync.setPaused(wasPaused)
						notify(
							"error",
							"Could not restore backup",
							"Check that the snapshot is readable and the project folder is writable."
						)
						return false
					end
					notify(
						"success",
						"Backup restored",
						"Source sync is paused. Resume it when you're ready to reconcile source changes."
					)
				end,
			},
		},
		build = function(content, controller)
			local records = {}
			for index, backup in ipairs(backups) do
				local date = backup.Timestamp and os.date("%Y-%m-%d %H:%M:%S", backup.Timestamp) or backup.Id
				local _, _, record = UI.button(
					content,
					date,
					UDim2.fromOffset(0, (index - 1) * 38),
					UDim2.new(1, 0, 0, 32),
					function()
						selected = backup
						for entry, state in pairs(records) do
							UI.setButtonState(state, entry == selected and "selected" or nil)
						end
						controller:SetButtonEnabled("restore", true)
					end
				)
				records[backup] = record
			end
			controller:SetButtonEnabled("restore", false)
		end,
	})
end

return Tools

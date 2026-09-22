local UpdateService = game:GetService("UpdateService")
local UI = require("@internal/editor_ui")

local function ShowEngineUpdatePrompt(report)
	if not report or not report.available then
		return
	end

	local current = report.current
	local latest = report.latest
	local staged = report.staged

	local function formatBytes(bytes)
		if not bytes then
			return "Unknown size"
		end

		if bytes >= 1024 * 1024 * 1024 then
			return string.format("%.2f GB", bytes / (1024 * 1024 * 1024))
		elseif bytes >= 1024 * 1024 then
			return string.format("%.1f MB", bytes / (1024 * 1024))
		elseif bytes >= 1024 then
			return string.format("%.1f KB", bytes / 1024)
		end

		return string.format("%d B", bytes)
	end

	local prompt, content, controller = UI.prompt({
		name = "EngineUpdate",

		title = "Kinemium Update Available",
		description = string.format("%s is ready to install.", latest.version),

		size = UDim2.fromOffset(520, 410),

		modal = true,
		dim = true,
		dimTransparency = 0.5,
		renderOnTop = true,

		blur = 12,
		glass = true,
		transparency = 0.5,
		glassBlur = 18,

		draggable = false,
		closable = true,
		closeOnBackdrop = false,
		shadow = true,

		buttonAlignment = "right",

		buttons = {
			{
				id = "later",
				text = "Later",
				role = "secondary",

				callback = function(controller)
					controller:Close("later")
				end,
			},

			{
				id = "install",
				text = "Install & Restart",
				role = "primary",

				callback = function(controller)
					controller:SetBusy(true, "install", "Starting installer...")

					local success = UpdateService:ApplyUpdate()

					-- ApplyUpdate exits the process when successful,
					-- so reaching this point with false means launch failed.
					if not success then
						controller:SetBusy(false)

						warn("Failed to launch the Kinemium updater.")
					end
				end,
			},
		},

		build = function(content, controller)
			local y = 0

			local versionPanel =
				UI.frame(content, UDim2.fromOffset(0, y), UDim2.new(1, 0, 0, 76), UI.tokens.color.panel, 6)

			local installedTitle = UI.label(
				versionPanel,
				"Installed",
				UDim2.fromOffset(14, 10),
				UDim2.new(0.5, -20, 0, 18),
				11,
				UI.tokens.color.subtext
			)

			installedTitle.TextXAlignment = Enum.TextXAlignment.Left

			local installedVersion = UI.label(
				versionPanel,
				current.display or "Unknown",
				UDim2.fromOffset(14, 32),
				UDim2.new(0.5, -20, 0, 24),
				15,
				UI.tokens.color.text
			)

			installedVersion.TextXAlignment = Enum.TextXAlignment.Left

			local latestTitle = UI.label(
				versionPanel,
				"Available",
				UDim2.new(0.5, 8, 0, 10),
				UDim2.new(0.5, -22, 0, 18),
				11,
				UI.tokens.color.subtext
			)

			latestTitle.TextXAlignment = Enum.TextXAlignment.Left

			local latestVersion = UI.label(
				versionPanel,
				latest.version,
				UDim2.new(0.5, 8, 0, 32),
				UDim2.new(0.5, -22, 0, 24),
				15,
				UI.tokens.color.accent
			)

			latestVersion.TextXAlignment = Enum.TextXAlignment.Left

			y += 90

			local info = UI.label(
				content,
				string.format(
					"%s  •  %s%s",
					formatBytes(latest.asset_size),
					staged and staged.ready and "Ready to install" or "Update staged",
					latest.published and ("  •  " .. latest.published) or ""
				),
				UDim2.fromOffset(0, y),
				UDim2.new(1, 0, 0, 20),
				11,
				UI.tokens.color.subtext
			)

			info.TextXAlignment = Enum.TextXAlignment.Left

			y += 32

			local notesTitle = UI.label(
				content,
				"What's new",
				UDim2.fromOffset(0, y),
				UDim2.new(1, 0, 0, 20),
				13,
				UI.tokens.color.text
			)

			notesTitle.TextXAlignment = Enum.TextXAlignment.Left

			y += 26

			local notesPanel =
				UI.frame(content, UDim2.fromOffset(0, y), UDim2.new(1, 0, 0, 145), UI.tokens.color.panel, 6)

			local notes = UI.label(
				notesPanel,
				latest.notes or "No release notes were provided for this update.",
				UDim2.fromOffset(12, 10),
				UDim2.new(1, -24, 1, -20),
				12,
				UI.tokens.color.subtext
			)

			notes.TextXAlignment = Enum.TextXAlignment.Left
			notes.TextYAlignment = Enum.TextYAlignment.Top
			notes.TextWrapped = true

			y += 157

			local restartNotice = UI.label(
				content,
				"Kinemium will close, install the update, and restart.",
				UDim2.fromOffset(0, y),
				UDim2.new(1, 0, 0, 20),
				11,
				UI.tokens.color.subtext
			)

			restartNotice.TextXAlignment = Enum.TextXAlignment.Left
		end,

		onResult = function(id, value)
			print("Update prompt result:", id, value)
		end,

		onClose = function(reason, result)
			print("Update prompt closed:", reason, result)
		end,
	})

	prompt.BackgroundTransparency = 0.12

	return prompt, controller
end

local report = UpdateService:IsUpdateAvailable()

if report then
	if report.available then
		ShowEngineUpdatePrompt(report)
	elseif report.status == "check_failed" then
		warn("Kinemium update check failed:", report.error or "Unknown error")
	end
end

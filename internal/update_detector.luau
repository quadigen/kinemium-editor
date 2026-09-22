local UpdateService = game:GetService("UpdateService")
local RunService = game:GetService("RunService")
local UI = require("@internal/editor_ui")

local function ShowEngineUpdatePrompt(report)
	if not report or not report.available then
		return
	end

	local current = report.current
	local latest = report.latest
	local staged = report.staged

	local progressLabel
	local progressConnection
	local installing = false

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
					controller:SetBusy(true, "install", "Installing...")

					if installing then
						return
					end

					local started = UpdateService:ApplyUpdate()
					if not started then
						controller:SetBusy(false)
						warn("Failed to start the update installer.")
						return
					end

					installing = true

					progressConnection = RunService.Heartbeat:Connect(function()
						local progress = UpdateService:GetUpdateProgress()
						if not progress then
							return
						end

						local status = progress.status or "waiting"

						if status == "ready" then
							if progressConnection then
								progressConnection:Disconnect()
							end
							progressConnection = nil

							local restarted = UpdateService:FinishUpdateRestart()
							if not restarted then
								installing = false
								controller:SetBusy(false)
								warn("Failed to launch the update installer, please retry.")
							end
							return
						end

						if status == "failed" then
							if progressConnection then
								progressConnection:Disconnect()
							end
							progressConnection = nil
							installing = false
							controller:SetBusy(false)
							warn("Update failed: " .. tostring(progress.message or "unknown error"))
							return
						end

						if progressLabel then
							if status == "downloading" then
								local percent = typeof(progress.percent) == "number"
									and math.floor(progress.percent + 0.5)

								if percent then
									progressLabel.Text = string.format(
										"Downloading update: %d%% (%s of %s)",
										percent,
										formatBytes(progress.downloaded),
										formatBytes(progress.total)
									)
								else
									progressLabel.Text = "Downloading update: " .. formatBytes(progress.downloaded)
								end
							elseif status == "extracting" then
								progressLabel.Text = "Installing update files..."
							elseif status == "fetching" then
								progressLabel.Text = "Checking for updates..."
							end
						end
					end)
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

			y += 20

			local progress =
				UI.label(content, "", UDim2.fromOffset(0, y), UDim2.new(1, 0, 0, 20), 12, UI.tokens.color.accent)

			progress.TextXAlignment = Enum.TextXAlignment.Left
			progressLabel = progress
		end,

		onResult = function(id, value)
			print("Update prompt result:", id, value)
		end,

		onClose = function(reason, result)
			print("Update prompt closed:", reason, result)

			if progressConnection then
				progressConnection:Disconnect()
			end
			progressConnection = nil
			installing = false
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

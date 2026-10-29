local UI = require("@internal/editor_ui")
local MatrixService = game:GetService("MatrixService")

local Auth = {}

local colors = UI.tokens.color
local tokens = UI.tokens

local LABEL_WIDTH = 104
local ROW_HEIGHT = 30
local BULLET = "-"

local function fieldRow(parent, index, labelText, placeholder, options)
	local y = (index - 1) * ROW_HEIGHT

	local label = UI.label(
		parent,
		labelText,
		UDim2.fromOffset(0, y),
		UDim2.fromOffset(LABEL_WIDTH, UI.metrics.inputHeight),
		tokens.type.small,
		colors.subtext
	)

	label.TextXAlignment = Enum.TextXAlignment.Left

	local box = UI.input(
		parent,
		placeholder,
		UDim2.fromOffset(LABEL_WIDTH, y),
		UDim2.new(1, -LABEL_WIDTH, 0, UI.metrics.inputHeight),
		options
	)

	return box
end

local NATIVE_MASK_PROPERTIES = { "PasswordMode", "MaskText", "Masked", "IsPassword" }

local function passwordRow(parent, index, labelText, placeholder)
	local box = fieldRow(parent, index, labelText, placeholder, {})

	local native = false

	for _, name in ipairs(NATIVE_MASK_PROPERTIES) do
		local ok, current = pcall(function()
			return box[name]
		end)

		if ok and type(current) == "boolean" then
			native = pcall(function()
				box[name] = true
			end)

			if native then
				break
			end
		end
	end

	if not native then
		box.TextTransparency = 1

		local overlay = UI.label(box, "", UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), box.TextSize, colors.text)

		overlay.Name = "Mask"
		overlay.ZIndex = box.ZIndex + 1

		pcall(function()
			overlay.Active = false
			overlay.InputSink = false
		end)

		local function redraw()
			local text = box.Text or ""

			overlay.Text = string.rep(BULLET, utf8.len(text) or #text)
		end

		box:GetPropertyChangedSignal("Text"):Connect(redraw)
		box.FocusLost:Connect(redraw)

		redraw()
	end

	return box, function()
		return box.Text
	end
end

local function statusLine(parent, y)
	local label = UI.label(parent, "", UDim2.fromOffset(0, y), UDim2.new(1, 0, 0, 34), tokens.type.small, colors.muted)

	label.TextWrapped = true
	label.TextYAlignment = Enum.TextYAlignment.Top

	return function(text, kind)
		if not UI.isAlive(label) then
			return
		end

		label.Text = text or ""
		label.TextColor3 = kind == "error" and colors.error or kind == "success" and colors.success or colors.muted
	end
end

local function run(controller, setStatus, work, onSuccess, options)
	if controller.busy then
		return
	end

	controller:SetBusy(true, "submit", "Working...")
	setStatus("Contacting server...", "info")

	task.spawn(function()
		local ok, result = work()

		if controller.destroyed then
			return
		end

		controller:SetBusy(false, "submit")

		if not ok then
			setStatus(tostring(result), "error")
			return
		end

		MatrixService:SetSession(result)

		controller:Close("success", result)

		if options.onSuccess then
			options.onSuccess(result)
		end

		onSuccess(result)
	end)
end

function Auth.Login(options)
	options = options or {}

	local fields = {}
	local setStatus

	local _, _, controller = UI.prompt({
		title = "Log in",
		description = "Sign in to a Matrix homeserver",
		size = UDim2.fromOffset(440, 288),
		destroyOnClose = true,
		closeOnBackdrop = false,

		build = function(content)
			fields.homeserver = fieldRow(
				content,
				1,
				"Homeserver",
				MatrixService.DefaultHomeserver,
				{ text = options.homeserver or MatrixService.DefaultHomeserver }
			)

			fields.username = fieldRow(content, 2, "Username", "alice", { text = options.username or "" })

			fields.password, fields.getPassword = passwordRow(content, 3, "Password", "Password")

			setStatus = statusLine(content, ROW_HEIGHT * 3 + 4)
		end,

		buttons = {
			{
				id = "cancel",
				text = "Cancel",
				role = "ghost",
			},
			{
				id = "switch",
				text = "Sign up instead",
				role = "secondary",
				width = 120,
				callback = function()
					if options.switch == false then
						return false
					end

					Auth.SignUp({ homeserver = fields.homeserver.Text, onSuccess = options.onSuccess })
				end,
			},
			{
				id = "submit",
				text = "Log in",
				role = "primary",
				callback = function(controller)
					local username = MatrixService:NormalizeUsername(fields.username.Text)
					local password = fields.getPassword()

					if username == "" or password == "" then
						setStatus("Enter your username and password.", "error")
						return false
					end

					local homeserver = fields.homeserver.Text

					run(controller, setStatus, function()
						local ok, base = MatrixService:ResolveHomeserver(homeserver)

						if not ok then
							return false, base
						end

						return MatrixService:Login(base, username, password)
					end, function() end, options)

					return false
				end,
			},
		},
	})

	fields.password.FocusLost:Connect(function(enterPressed)
		if enterPressed and controller:IsOpen() then
			local data = controller:GetButton("submit")

			if data and data.record then
				data.record.callback()
			end
		end
	end)

	return controller
end

function Auth.SignUp(options)
	options = options or {}

	local fields = {}
	local setStatus

	local _, _, controller = UI.prompt({
		title = "Create account",
		description = "Register on a Matrix homeserver",
		size = UDim2.fromOffset(440, 352),
		destroyOnClose = true,
		closeOnBackdrop = false,

		build = function(content)
			fields.homeserver = fieldRow(
				content,
				1,
				"Homeserver",
				MatrixService.DefaultHomeserver,
				{ text = options.homeserver or MatrixService.DefaultHomeserver }
			)

			fields.username = fieldRow(content, 2, "Username", "alice", { text = options.username or "" })

			fields.password, fields.getPassword = passwordRow(content, 3, "Password", "Password")

			fields.confirm, fields.getConfirm = passwordRow(content, 4, "Confirm", "Repeat password")

			fields.token = fieldRow(content, 5, "Invite token", "Only if the server asks for one", {})

			setStatus = statusLine(content, ROW_HEIGHT * 5 + 4)
		end,

		buttons = {
			{
				id = "cancel",
				text = "Cancel",
				role = "ghost",
			},
			{
				id = "switch",
				text = "I have an account",
				role = "secondary",
				width = 130,
				callback = function()
					if options.switch == false then
						return false
					end

					Auth.Login({ homeserver = fields.homeserver.Text, onSuccess = options.onSuccess })
				end,
			},
			{
				id = "submit",
				text = "Sign up",
				role = "primary",
				callback = function(controller)
					local username = MatrixService:NormalizeUsername(fields.username.Text)
					local password = fields.getPassword()

					if username == "" then
						setStatus("Choose a username.", "error")
						return false
					end

					if not username:match("^[a-z0-9._=/+%-]+$") then
						setStatus("Usernames may only use a-z, 0-9 and . _ = - / +", "error")
						return false
					end

					if password == "" then
						setStatus("Choose a password.", "error")
						return false
					end

					if password ~= fields.getConfirm() then
						setStatus("Passwords do not match.", "error")
						return false
					end

					local homeserver = fields.homeserver.Text
					local registrationToken = fields.token.Text

					run(controller, setStatus, function()
						local ok, base = MatrixService:ResolveHomeserver(homeserver)

						if not ok then
							return false, base
						end

						return MatrixService:Register(
							base,
							username,
							password,
							{ registrationToken = registrationToken }
						)
					end, function() end, options)

					return false
				end,
			},
		},
	})

	return controller
end

function Auth.Refresh()
	return UI.refreshAllWindows()
end

return Auth

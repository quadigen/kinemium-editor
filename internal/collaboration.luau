local UI = require("@internal/editor_ui")

local REQUIRED = {
	"ListSessions", "ListInvites", "StartSession", "RequestJoin", "AcceptInvite",
	"DeclineInvite", "EndSession", "LeaveSession", "Invite", "ListParticipants",
	"ListSessionJoinRequests", "ApproveJoinRequest", "DenyJoinRequest",
	"RotateJoinCode", "RemoveParticipant",
}
local WARNING = "Team collaboration requires a newer engine build."

local function getService()
	local service = game:GetService("CollaborationService")
	for _, name in ipairs(REQUIRED) do
		if type(service[name]) ~= "function" then
			return nil
		end
	end
	return service
end

return function()
	local window
	local function open()
		if window then
			window.Visible = true
			return
		end

		local supported, service = pcall(getService)
		local frame, _, _, controls = UI.window(
			"Team",
			UDim2.fromScale(0.5, 0.5),
			UDim2.fromOffset(560, supported and service and 460 or 120),
			"Team",
			{ tabs = { "Team" }, selectedTab = "Team", closable = true }
		)
		window = frame
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Parent = UI.widgetOverlay()
		frame.Visible = true
		local page = controls.pages.Team
		local colors = UI.tokens.color

		if not supported or not service then
			warn(WARNING)
			local label = UI.label(page, WARNING, UDim2.fromOffset(12, 8),
				UDim2.new(1, -24, 0, 52), UI.tokens.type.small, colors.text)
			label.TextWrapped = true
			return
		end

		local status = UI.label(page, "Sign in through Studio Settings to use Team.",
			UDim2.fromOffset(10, 0), UDim2.new(1, -20, 0, 28),
			UI.tokens.type.small, colors.text)
		local matrix = game:GetService("MatrixService")

		local function call(name, ...)
			local session = matrix:GetSession()
			if not session then
				status.Text = "Sign in through Studio Settings to use Team."
				return nil
			end
			local invoked, ok, data, meta = pcall(service[name], service, session, ...)
			if not invoked or not ok then
				local code = type(meta) == "table" and (meta.status or meta.statusCode)
				status.Text = name .. " failed" .. (code and (" (HTTP " .. tostring(code) .. ")") or ".")
				return nil
			end
			return data or true
		end

		local list = Instance.new("ScrollingFrame")
		list.BackgroundTransparency = 1
		list.Position = UDim2.fromOffset(10, 118)
		list.Size = UDim2.new(1, -20, 1, -126)
		list.AutomaticCanvasSize = Enum.AutomaticSize.Y
		list.CanvasSize = UDim2.fromOffset(0, 0)
		list.Parent = page
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 4)
		layout.Parent = list

		local function button(parent, title, position, size, callback)
			local control = Instance.new("TextButton")
			control.BackgroundColor3 = colors.surface or colors.background
			control.TextColor3 = colors.text
			control.TextSize = UI.tokens.type.small
			control.Text = title
			control.Position = position
			control.Size = size
			control.Parent = parent
			control.Activated:Connect(callback)
		end

		local function row(title, callback)
			button(list, title, UDim2.fromOffset(0, 0), UDim2.new(1, -12, 0, 26), callback)
		end

		local function clearRows()
			for _, child in ipairs(list:GetChildren()) do
				if child ~= layout then
					child:Destroy()
				end
			end
		end

		local refresh
		local function showSession(session, hosted)
			clearRows()
			local id = session.sessionId
			status.Text = session.gameName or session.name or "Team session"
			row("Back to sessions", refresh)
			row("Refresh session", function() showSession(session, hosted) end)
			local participants = call("ListParticipants", id)
			if type(participants) == "table" then
				for _, participant in ipairs(participants.participants or {}) do
					local label = participant.userId or "Participant"
					UI.label(list, label, UDim2.fromOffset(0, 0),
						UDim2.new(1, -12, 0, 24), UI.tokens.type.small, colors.text)
					if hosted and participant.userId and participant.userId ~= session.hostUserId then
						row("Remove " .. label, function()
							if call("RemoveParticipant", id, participant.userId) then showSession(session, true) end
						end)
					end
				end
			end
			if hosted then
				row("Rotate join code", function()
					local result = call("RotateJoinCode", id)
					if type(result) == "table" and result.joinCode then
						status.Text = "Join code: " .. result.joinCode
					end
				end)
				local invite = UI.input(list, "Developer Matrix ID", UDim2.fromOffset(0, 0),
					UDim2.new(1, -12, 0, 28), {})
				row("Send invitation", function()
					if invite.Text ~= "" and call("Invite", id, { userId = invite.Text }) then
						status.Text = "Invitation sent."
					end
				end)
				local pending = call("ListSessionJoinRequests", id, { status = "pending" })
				if type(pending) == "table" then
					for _, request in ipairs(pending.joinRequests or {}) do
						local name = request.userId or "developer"
						row("Approve " .. name, function()
							if call("ApproveJoinRequest", id, request.requestId) then showSession(session, true) end
						end)
						row("Deny " .. name, function()
							if call("DenyJoinRequest", id, request.requestId) then showSession(session, true) end
						end)
					end
				end
			end
			row(hosted and "End session" or "Leave session", function()
				if call(hosted and "EndSession" or "LeaveSession", id) then refresh() end
			end)
		end

		refresh = function()
			clearRows()
			status.Text = "Team sessions"
			for _, role in ipairs({ "hosted", "joined" }) do
				local result = call("ListSessions", { role = role })
				if type(result) == "table" then
					for _, session in ipairs(result.sessions or {}) do
						row(role .. ": " .. (session.gameName or session.name or session.sessionId), function()
							showSession(session, role == "hosted")
						end)
					end
				end
			end
			local result = call("ListInvites", { status = "pending" })
			if type(result) == "table" then
				for _, invite in ipairs(result.invites or {}) do
					local name = invite.gameName or invite.inviterUserId or "game"
					row("Accept invitation to " .. name, function()
						if call("AcceptInvite", invite.inviteId) then refresh() end
					end)
					row("Decline invitation to " .. name, function()
						if call("DeclineInvite", invite.inviteId) then refresh() end
					end)
				end
			end
		end

		local gameId = UI.input(page, "Owned game ID", UDim2.fromOffset(10, 32),
			UDim2.new(1, -146, 0, 26), {})
		button(page, "Host", UDim2.new(1, -126, 0, 32), UDim2.fromOffset(116, 26), function()
			if gameId.Text == "" then return end
			local session = call("StartSession", gameId.Text, {})
			if type(session) == "table" then
				showSession(session, true)
				if session.joinCode then status.Text = "Join code: " .. session.joinCode end
			end
		end)
		local code = UI.input(page, "Join code", UDim2.fromOffset(10, 62),
			UDim2.new(1, -146, 0, 26), {})
		button(page, "Request to join", UDim2.new(1, -126, 0, 62), UDim2.fromOffset(116, 26), function()
			if code.Text ~= "" and call("RequestJoin", { code = code.Text }) then
				code.Text = ""
				refresh()
				status.Text = "Join request submitted. Refresh to check for approval."
			end
		end)
		button(page, "Refresh", UDim2.fromOffset(10, 92), UDim2.fromOffset(116, 22), refresh)
	end

	return open
end

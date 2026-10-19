local Auth = require("@internal/auth")
local UI = require("@internal/editor_ui")
local Matrix = require("@internal/matrix")
local http = game:GetService("HttpService")

shared.CurrentSession = nil

local function SetImage(session, image)
	local ok, profile = Matrix.getProfile(session)

	if not ok or not profile.avatarUrl then
		return
	end

	local url = Matrix.mxcToHttp(session.homeserver, profile.avatarUrl, {
		authenticated = true,
		width = 128,
		height = 128,
		method = "crop",
	})

	if not url then
		return
	end

	local content = http:GetImageBytes(url, {
		Authorization = "Bearer " .. session.accessToken,
	})

	image.Image = content
end

return function(parent)
	local id = ""
	local tooltip
	local profileButton, _, image

	profileButton, _, image = UI.iconButton(
		parent,
		"assets/icons/Play.svg",
		UDim2.new(1, -5, 0, 5),
		UDim2.fromOffset(25, 25),
		function()
			Auth.Login({
				onSuccess = function(session)
					shared.CurrentSession = session

					id = session.userId
					if tooltip then
						tooltip:SetText(id)
					end

					SetImage(session, image)
				end,
			})
		end
	)

	tooltip = UI.tooltip(profileButton, "Not logged in", {
		placement = "below",
		hoverDelay = 0.35,
	})

	profileButton.AnchorPoint = Vector2.new(1, 0)
end

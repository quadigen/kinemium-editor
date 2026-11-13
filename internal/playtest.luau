local Preferences = require("@internal/preferences")
local UI = require("@internal/editor_ui")
local service = game:GetService("PlaytestService")
local Playtest = {}

function Playtest.start(mode, singleplayer)
	mode = mode or Preferences.get("playtestMode")
	if singleplayer == nil then
		singleplayer = Preferences.get("playtestSingleplayer")
	end
	if Preferences.get("playtestClearOutput") then
		game:GetService("LogService"):Clear()
	end
	local headlessClient = Preferences.get("playtestHeadlessClient")
	local headlessServer = Preferences.get("playtestHeadlessServer")
	local pauseOnError = Preferences.get("playtestPauseOnError")
	local ok
	if singleplayer then
		ok = service:StartSinglePlayer(nil, headlessClient, pauseOnError)
	elseif mode == "Server" then
		ok = service:StartServer(nil, headlessServer, pauseOnError)
	elseif mode == "Client" then
		ok = service:StartClient(nil, nil, headlessClient, pauseOnError)
	else
		ok = service:Start(nil, false, headlessServer, headlessClient, pauseOnError)
	end
	if not ok then
		UI.toast("playtest", { type = "error", title = "Could not start playtest", message = service.LastError })
	end
end

return Playtest

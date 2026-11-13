if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local PlaytestService = game:GetService("PlaytestService")

local Playtest = require("@internal/playtest")

local buttons = {}

if not IsPlaytest then
	table.insert(buttons, {
		name = "Play",
		icon = "Play.svg",
		callback = function()
			Playtest.start()
		end,
	})
end

table.insert(buttons, {
	name = "Stop",
	icon = "Stop.svg",
	callback = function()
		PlaytestService:Stop()
	end,
})

return {
	name = "Test",
	buttons = buttons,
}

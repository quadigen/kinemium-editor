if (IsServer or IsClient) and not IsPlaytest then
	return nil
end

local PlaytestService = game:GetService("PlaytestService")

-- Inside a playtest there is nothing left to start, so the Play button is
-- dropped and Stop remains the only useful action.
local buttons = {}

if not IsPlaytest then
	table.insert(buttons, {
		name = "Play",
		icon = "Play.svg",
		callback = function()
			PlaytestService:Start()
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

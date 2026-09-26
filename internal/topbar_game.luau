if (IsServer or IsClient) and not IsPlaytest then
	return nil
end

local PlaytestService = game:GetService("PlaytestService")

return {
	name = "Game",
	buttons = {
		{
			name = "Play",
			icon = "Play.svg",
			callback = function()
				PlaytestService:Start()
			end,
		},
		{
			name = "Stop",
			icon = "Stop.svg",
			callback = function()
				PlaytestService:Stop()
			end,
		},
	},
}

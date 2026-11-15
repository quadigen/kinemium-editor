if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local fip = require("@internal/fip")

return {
	name = "Script",
	buttons = {
		{
			name = "Find In Project",
			icon = "Stop.svg",
			callback = function()
				print("Find In Project")
				fip.Toggle()
			end,
		},
	},
}

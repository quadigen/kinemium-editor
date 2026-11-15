if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local fip = require("@internal/fip")
local profiler = require("@internal/profiler")

return {
	name = "Script",
	buttons = {
		{
			name = "Find In Project",
			icon = "Stop.svg",
			callback = function()
				fip.Toggle()
			end,
		},

		{
			name = "Profiler",
			icon = "Stop.svg",
			callback = function()
				profiler.Toggle()
			end,
		},
	},
}

if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local fip = require("@internal/fip")
local profiler = require("@internal/profiler")
local debugger = require("@internal/debugger")
local dep_explorer = require("@internal/dependency_explorer")

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

		{
			name = "Debugger",
			icon = "Stop.svg",
			callback = function()
				debugger.Toggle()
			end,
		},
		{
			name = "Dependencies",
			icon = "Stop.svg",
			callback = function()
				dep_explorer.Toggle()
			end,
		},
	},
}

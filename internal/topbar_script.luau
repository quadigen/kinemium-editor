if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local fip = require("@internal/fip")
local profiler = require("@internal/profiler")
local debugger = require("@internal/debugger")
local dep_explorer = require("@internal/dependency_explorer")
local console = require("@internal/console")

return {
	name = "Script",
	buttons = {
		{
			name = "Terminal",
			icon = "Script.svg",
			callback = function()
				console.ShowTerminal()
			end,
		},
		{
			name = "Find In Project",
			icon = "Script.svg",
			callback = function()
				fip.Toggle()
			end,
		},

		{
			name = "Profiler",
			icon = "ProfilerService.svg",
			callback = function()
				profiler.Toggle()
			end,
		},

		{
			name = "Debugger",
			icon = "DebugOverlay.svg",
			callback = function()
				debugger.Toggle()
			end,
		},
		{
			name = "Dependencies",
			icon = "ModuleScript.svg",
			callback = function()
				dep_explorer.Toggle()
			end,
		},
	},
}

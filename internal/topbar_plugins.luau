if (IsServer or IsClient) or IsPlaytest then
	return nil
end
local native_plugins = require("@internal/native_plugins")
return {
	name = "Plugins",
	buttons = {
		{
			name = "Native Plugins",
			icon = "Settings.svg",
			callback = native_plugins.openWindow,
		},
	},
}

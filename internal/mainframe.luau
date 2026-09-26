print(IsServer)
print(IsClient)
print(IsPlaytest)
if (IsServer or IsClient) and not IsPlaytest then
	return
end

local UI = require("@internal/editor_ui")

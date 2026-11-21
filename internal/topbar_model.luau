if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local Selection = game:GetService("Selection")
local History = require("@internal/change_history")

return {
	name = "Model",
	buttons = {
		{
			name = "Part",
			icon = "Part.svg",
			callback = function()
				local part = Instance.new("Part")
				part.Parent = game.Workspace
				History.recordParents("Insert " .. part.ClassName, {
					{ object = part, before = nil, after = game.Workspace },
				})
				Selection:Set({ part })
			end,
		},
		{
			name = "MeshPart",
			icon = "MeshPart.svg",
			callback = function()
				local part = Instance.new("MeshPart")
				part.Parent = game.Workspace
				History.recordParents("Insert " .. part.ClassName, {
					{ object = part, before = nil, after = game.Workspace },
				})
				Selection:Set({ part })
			end,
		},
	},
}

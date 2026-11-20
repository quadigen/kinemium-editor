if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local PlaytestService = game:GetService("PlaytestService")

local Playtest = require("@internal/playtest")
local Tree = require("@internal/playtest_tree")

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

table.insert(buttons, {
	name = "Runtime",
	icon = "Switch.svg",
	tooltip = "Switch Explorer between Editor, Client and Server",
	callback = Tree.cycle,
	bind = function(controller)
		local function refresh()
			controller:SetText(Tree.caption())
			controller:SetSelected(Tree.role ~= nil, true)
		end
		refresh()
		return Tree.changed:Connect(refresh)
	end,
})

return {
	name = "Test",
	buttons = buttons,
}

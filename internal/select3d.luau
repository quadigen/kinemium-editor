if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")
local UserInputService = game:GetService("UserInputService")
local Mouse: Mouse = UserInputService:GetMouse()

local editor_ui = require("@internal/editor_ui")
local accent = editor_ui.tokens.color.accent

local highlight = Instance.new("Highlight")
highlight.Name = "SelectionHighlight"
highlight.FillTransparency = 1
highlight.OutlineColor = accent
highlight.Parent = workspace

RunService.RenderStepped:Connect(function()
	local target = Mouse.Target
	if target then
		highlight.Adornee = target
	else
		highlight.Adornee = nil
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local target = Mouse.Target
		if target then
			Selection:Set({ target })
		end
	end
end)

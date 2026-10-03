if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Mouse: Mouse = UserInputService:GetMouse()

local editor_ui = require("@internal/editor_ui")
local accent = editor_ui.tokens.accent

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

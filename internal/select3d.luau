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
highlight.Enabled = false
highlight.Parent = workspace

local function isOutOfBounds(num)
	return num >= 100
end

local function isOutOfBoundsTarget(target)
	if isOutOfBounds(target.Size.X) or isOutOfBounds(target.Size.Y) or isOutOfBounds(target.Size.Z) then
		return true
	else
		return false
	end
end

RunService.RenderStepped:Connect(function()
	local target = Mouse.Target

	if target and target:IsA("BasePart") then
		if isOutOfBoundsTarget(target) then
			highlight.Adornee = nil
			highlight.Enabled = false
			return
		end
		if target then
			highlight.Adornee = target
			highlight.Enabled = true
		else
			highlight.Adornee = nil
			highlight.Enabled = false
		end
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local target = Mouse.Target
		if target and target:IsA("BasePart") then
			if isOutOfBoundsTarget(target) then
				return
			end
			Selection:Set({ target })
		end
	end
end)

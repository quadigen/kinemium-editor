if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local Workspace = game:GetService("Workspace")

local Part = Instance.new("Part")
Part.Anchored = true
Part.Size = vector.create(1000, 3, 1000)
Part.Material = Enum.Material.Grass
Part.Parent = Workspace

Workspace.SimulatePhysics = false

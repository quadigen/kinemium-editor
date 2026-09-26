if (IsServer or IsClient) or IsPlaytest then
	return nil
end
local Part = Instance.new("Part")
Part.Anchored = true
Part.Size = vector.create(1000, 3, 1000)
Part.Material = Enum.Material.Grass
Part.Parent = workspace

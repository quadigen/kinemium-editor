local material = Instance.new("MaterialVariant", game:GetService("ReplicatedStorage"))
material.Name = "Copper"
material.Color = Color3.fromRGB(184, 115, 51)
material.Roughness = 0.3
material.Metalness = 0.9

workspace.MyPart.MaterialVariant = "Copper"
game:GetService("Terrain").MaterialVariant = "Copper"

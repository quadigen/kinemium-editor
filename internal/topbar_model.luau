if (IsServer or IsClient) and not IsPlaytest then
	return nil
end

return {
	name = "Model",
	buttons = {
		{
			name = "Part",
			icon = "Part.svg",
			route = "insert_part",
		},
		{
			name = "MeshPart",
			icon = "MeshPart.svg",
			route = "insert_mesh_part",
		},
		{
			name = "Material",
			icon = "Texture.svg",
			route = "insert_material",
		},
	},
}

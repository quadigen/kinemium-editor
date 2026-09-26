if (IsServer or IsClient) and not IsPlaytest then
	return nil
end

return {
	name = "Plugins",
	buttons = {},
}

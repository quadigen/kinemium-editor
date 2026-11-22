return function(ctx)
	local UI = ctx.UI
	local shared = ctx.shared

	function UI.corner(parent, radius, role)
		local corner = UI.create("UICorner", { CornerRadius = UDim.new(0, radius or UI.tokens.radius.sm) }, parent)
		if role and UI.tokens.radius[role] ~= nil then
			shared.themeCornerRoles[corner] = role
		end
		return corner
	end
end

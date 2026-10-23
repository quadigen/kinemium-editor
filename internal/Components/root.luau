return function(ctx)
	local UI = ctx.UI
	local shared = ctx.shared

	local closeActiveDropdown = function(instant)
		if UI.closeDropdown then
			UI.closeDropdown(instant)
		end
	end

	function UI.root()
		if shared.root then
			return shared.root
		end

		local root = UI.create("ScreenGui", { Name = "Studio", DisplayOrder = 1000, IgnoreGuiInset = true }, game.CoreGui)

		shared.root = root

		shared.background = UI.create("TextButton", {

			Name = "EditorBackground",

			Text = "",

			Position = UDim2.fromOffset(0, 0),

			Size = UDim2.new(1, 0, 1, 0),

			BackgroundColor3 = UI.tokens.color.canvas,

			BorderSizePixel = 0,

			Active = true,

			InputSink = false,

			AutoButtonColor = false,

			ZIndex = -100000,
		}, root)

		shared.background.MouseButton1Click:Connect(function()
			local active = shared.activeDropdown

			if active and closeActiveDropdown and active.closeOnOutsideClick ~= false then
				closeActiveDropdown()
			end
		end)

		return root
	end
end

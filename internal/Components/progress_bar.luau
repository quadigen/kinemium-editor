return function(ctx)
	local UI = ctx.UI
	local colors = UI.tokens.color
	local tooltipSmoothTowards = ctx.tooltipSmoothTowards

	function UI.progressBar(parent, position, size, value, options)
		options = options or {}

		local colors = UI.tokens.color

		local progress = math.clamp(value or 0, 0, 1)

		local animate = options.animate ~= false
		local animationSpeed = options.animationSpeed or 18

		local displayProgress = progress
		local animation
		local destroyed = false

		local background = UI.frame(
			parent,
			position,
			size or UDim2.fromOffset(160, 6),
			options.color or colors.input,
			options.radius or UI.tokens.radius.xs
		)

		background.ClipsDescendants = true

		local fill = UI.frame(
			background,
			UDim2.fromOffset(0, 0),
			UDim2.new(progress, 0, 1, 0),
			options.fillColor or colors.accent,
			options.radius or UI.tokens.radius.xs
		)

		local function stopAnimation()
			animation:Stop()
		end

		local function redraw()
			fill.Size = UDim2.new(displayProgress, 0, 1, 0)
		end

		local function snapVisual()
			stopAnimation()

			displayProgress = progress

			redraw()
		end

		animation = ctx.animations.newTask(function(dt)
			if destroyed then return false end
			if not ctx.isVisible(background) then
				displayProgress = progress
				redraw()
				return false
			end
			displayProgress = tooltipSmoothTowards(displayProgress, progress, animationSpeed, dt)
			local finished = math.abs(displayProgress - progress) < 0.0005
			if finished then displayProgress = progress end
			redraw()
			return not finished
		end)

		local function wake()
			if not animate or not ctx.isVisible(background) then
				snapVisual()
			elseif displayProgress ~= progress then
				animation:Wake()
			end
		end

		background.Destroying:Connect(function()
			destroyed = true
			animation:Destroy()
		end)

		local controller = {}

		function controller:GetValue()
			return progress
		end

		function controller:SetValue(newValue, instant)
			if destroyed then return end
			local nextValue = math.clamp(newValue, 0, 1)
			if nextValue == progress and not instant then return end
			progress = nextValue

			if instant then
				snapVisual()
			else
				wake()
			end
		end

		controller.frame = background

		controller.fill = fill

		return background, controller
	end
end

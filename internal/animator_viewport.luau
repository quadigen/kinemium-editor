local UI = require("@internal/editor_ui")
local viewport = require("@internal/viewport")
local UIS = game:GetService("UserInputService")

local DOT_SIZE = 8
local PICK_RADIUS = 10
local NEAR_COINCIDENT = 3
local color = Color3.fromRGB(111, 210, 255)
local selectedColor = Color3.fromRGB(255, 192, 93)

local function sceneHelper(className, name, props)
	local instance = UI.create(className, props)
	instance.Name = name
	UI.mountSceneHelper(instance)
	return instance
end

local function frame(parent, size, zIndex)
	return UI.create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BorderSizePixel = 0,
		ZIndex = zIndex,
		Active = false,
	}, parent)
end

local function distanceToSegment(point, a, b)
	local segment = b - a
	local lengthSquared = segment:Dot(segment)
	if lengthSquared <= 0 then
		return (point - a).Magnitude
	end
	local fraction = math.clamp((point - a):Dot(segment) / lengthSquared, 0, 1)
	return (point - (a + segment * fraction)).Magnitude
end

local function new(callbacks)
	local tool = { mode = "Move" }
	local rig, bones, parents, chosen
	local dots, links = {}, {}
	local points, depths = {}, {}
	local frames = {}
	local activeHandle
	local armed = false

	local overlay = UI.create("Frame", {
		Name = "AnimatorSkeleton",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Active = false,
		Visible = false,
		ZIndex = 1,
	}, viewport.GetOverlay())
	tool.overlay = overlay

	local proxy = sceneHelper("Part", "AnimatorBonePivot", {
		Anchored = true,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		CastShadow = false,
		Locked = true,
		Transparency = 1,
		Size = Vector3.new(0.05, 0.05, 0.05),
	})
	local move = sceneHelper("Handles", "AnimatorBoneHandles", {
		Adornee = proxy,
		Style = Enum.HandlesStyle.Movement,
		Snap = 0,
		Visible = false,
	})
	local rotate = sceneHelper("ArcHandles", "AnimatorBoneArcHandles", {
		Adornee = proxy,
		Snap = 0,
		Visible = false,
	})

	for _, handle in ipairs({ move, rotate }) do
		handle.MouseButton1Down:Connect(function()
			if armed and frames[chosen] and overlay.Visible and callbacks.begin(proxy.CFrame, frames) then
				activeHandle = handle
			end
			armed = false
		end)
		handle.MouseDrag:Connect(function()
			if activeHandle == handle then
				callbacks.move(proxy.CFrame)
			end
		end)
		handle.MouseButton1Up:Connect(function()
			if activeHandle == handle then
				activeHandle = nil
				callbacks.finish()
			end
		end)
	end

	local endInput = UIS.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			armed = false
		end
	end)

	function tool:Cancel()
		activeHandle = nil
		armed = false
	end

	function tool:SetRig(mesh, names, parentNames, selection)
		if mesh ~= rig then
			self:Cancel()
			UI.clear(overlay)
			dots, links, points, depths, frames = {}, {}, {}, {}, {}
		end
		rig, bones, parents, chosen = mesh, names, parentNames, selection
		if not mesh then
			overlay.Visible, move.Visible, rotate.Visible = false, false, false
		end
	end

	function tool:Update()
		local camera = workspace.CurrentCamera
		local visible = UI.isAlive(rig)
			and camera
			and viewport.IsSceneVisible()
			and workspace.Dimension == Enum.Dimension.D3
		overlay.Visible = visible == true
		if not visible then
			move.Visible, rotate.Visible = false, false
			if activeHandle then
				callbacks.cancel()
			end
			return
		end

		frames = rig:GetBoneWorldCFrames()
		table.clear(points)
		table.clear(depths)
		local origin = overlay.AbsolutePosition
		for _, bone in ipairs(bones) do
			local transform = frames[bone]
			if transform then
				local projected, inView = camera:WorldToViewportPoint(transform.Position)
				if inView then
					points[bone] = viewport.ViewportToScreenPoint(Vector2.new(projected.X, projected.Y))
					depths[bone] = projected.Z
				end
			end
			local point = points[bone]
			local dot = dots[bone]
			if point and not dot then
				dot = frame(overlay, DOT_SIZE, 3)
				dots[bone] = dot
				UI.create("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
			end
			if dot then
				dot.Visible = point ~= nil
				if point then
					dot.Position = UDim2.fromOffset(point.X - origin.X, point.Y - origin.Y)
					dot.BackgroundColor3 = if bone == chosen then selectedColor else color
					local size = if bone == chosen then DOT_SIZE + 3 else DOT_SIZE
					dot.Size = UDim2.fromOffset(size, size)
				end
			end
		end
		for _, bone in ipairs(bones) do
			local a, b = points[parents[bone]], points[bone]
			local link = links[bone]
			if a and b then
				if not link then
					link = frame(overlay, 0, 2)
					links[bone] = link
					link.BackgroundTransparency = 0.25
				end
				local middle = (a + b) / 2 - origin
				local segment = b - a
				link.Position = UDim2.fromOffset(middle.X, middle.Y)
				link.Size = UDim2.fromOffset(segment.Magnitude, 2)
				link.Rotation = math.deg(math.atan2(segment.Y, segment.X))
				link.BackgroundColor3 = if bone == chosen then selectedColor else color
				link.Visible = true
			elseif link then
				link.Visible = false
			end
		end

		local transform = frames[chosen]
		local showHandles = transform ~= nil and points[chosen] ~= nil
		if showHandles and not (move.Dragging or rotate.Dragging) then
			local right = transform.RightVector.Unit
			local back = right:Cross(transform.UpVector).Unit
			proxy.CFrame = CFrame.fromMatrix(transform.Position, right, back:Cross(right), back)
		end
		move.Visible = (showHandles or activeHandle == move) and self.mode == "Move"
		rotate.Visible = (showHandles or activeHandle == rotate) and self.mode == "Rotate"
	end

	function tool:CapturesMouse()
		return (move.Visible and (move.Hovered or move.Dragging))
			or (rotate.Visible and (rotate.Hovered or rotate.Dragging))
	end

	function tool:Pick(point)
		if not overlay.Visible then
			return false
		end
		if self:CapturesMouse() then
			armed = true
			return true
		end
		local hits = {}
		for _, bone in ipairs(bones) do
			local joint = points[bone]
			if joint then
				local distance = (point - joint).Magnitude
				if distance <= PICK_RADIUS then
					table.insert(hits, { bone = bone, distance = distance, depth = depths[bone] })
				end
			end
		end
		table.sort(hits, function(a, b)
			if a.distance ~= b.distance then
				return a.distance < b.distance
			end
			if a.depth ~= b.depth then
				return a.depth < b.depth
			end
			return a.bone < b.bone
		end)
		local target = hits[1] and hits[1].bone
		if target then
			local overlap = {}
			for _, hit in ipairs(hits) do
				if (points[hit.bone] - points[target]).Magnitude <= NEAR_COINCIDENT then
					table.insert(overlap, hit.bone)
				end
			end
			local index = table.find(overlap, chosen)
			if index and #overlap > 1 then
				target = overlap[index % #overlap + 1]
			end
		else
			local distance = 5
			for _, bone in ipairs(bones) do
				local a, b = points[parents[bone]], points[bone]
				if a and b then
					local hit = distanceToSegment(point, a, b)
					if hit < distance then
						target, distance = bone, hit
					end
				end
			end
		end
		if target then
			callbacks.select(target)
		else
			armed = true
		end
	end

	function tool:Destroy()
		viewport.SetSelectionTool(nil)
		endInput:Disconnect()
		overlay:Destroy()
		move:Destroy()
		rotate:Destroy()
		proxy:Destroy()
	end

	return tool
end

return new

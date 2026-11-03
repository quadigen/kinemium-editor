local UI = require("@internal/editor_ui")
local UserInputService = game:GetService("UserInputService")

local Preview = {}
local hovered
local card
local width, viewportHeight, height = 236, 122, 202
local maxObjects = 500

local function isContainer(object)
	return object:IsA("Model") or object:IsA("Folder")
end

local function addGeometry(viewport, source)
	if not (source:IsA("BasePart") or isContainer(source)) then
		return nil, "No 3D preview for this object"
	end

	-- Bound the amount of work before cloning anything.
	local pending = { source }
	local index = 1
	while index <= #pending do
		local children = pending[index]:GetChildren()
		if #pending + #children > maxObjects then
			return nil, "Object is too large to preview"
		end
		for _, child in ipairs(children) do
			table.insert(pending, child)
		end
		index += 1
	end

	local copy = source:Clone()
	if not copy then
		return nil, "Preview unavailable"
	end

	local low = Vector3.new(math.huge, math.huge, math.huge)
	local high = -low
	local count = 0
	local function prepare(object)
		if object:IsA("BasePart") then
			count += 1
			local half = object.Size * 0.5
			local x, y, z, a, b, c, d, e, f, g, h, i = object.CFrame:GetComponents()
			local ex = math.abs(a) * half.X + math.abs(b) * half.Y + math.abs(c) * half.Z
			local ey = math.abs(d) * half.X + math.abs(e) * half.Y + math.abs(f) * half.Z
			local ez = math.abs(g) * half.X + math.abs(h) * half.Y + math.abs(i) * half.Z
			low = Vector3.new(math.min(low.X, x - ex), math.min(low.Y, y - ey), math.min(low.Z, z - ez))
			high = Vector3.new(math.max(high.X, x + ex), math.max(high.Y, y + ey), math.max(high.Z, z + ez))
		end

		for _, child in ipairs(object:GetChildren()) do
			if child:IsA("BasePart") or isContainer(child)
				or child:IsA("DataModelMesh") or child:IsA("Decal") or child:IsA("SurfaceAppearance")
			then
				prepare(child)
			else
				child:Destroy()
			end
		end
	end

	local ok, size = pcall(function()
		prepare(copy)
		if count == 0 then
			return nil
		end
		local bounds = high - low
		local center = (low + high) * 0.5
		local radius = math.max(bounds.Magnitude * 0.5, 0.05)
		if radius ~= radius or radius == math.huge then
			return nil
		end
		local camera = Instance.new("Camera", viewport)
		camera.FieldOfView = 35
		local distance = radius / math.sin(math.rad(camera.FieldOfView * 0.5)) * 1.12
		camera.CFrame = CFrame.lookAt(center + Vector3.new(1, 0.65, 1).Unit * distance, center)
		viewport.CurrentCamera = camera
		copy.Parent = viewport
		return bounds
	end)
	if not ok or not size then
		copy:Destroy()
		return nil, "No previewable geometry"
	end
	return size
end

local function closeCard()
	if card then
		card:Destroy()
		card = nil
	end
end

local function openCard(value)
	local colors = UI.tokens.color
	card = UI.create("Frame", {
		Name = "InspectorObjectPreview",
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = colors.panelRaised,
		BorderSizePixel = 0,
		Active = false,
		InputSink = false,
		ZIndex = 6100,
	}, UI.widgetOverlay())
	UI.corner(card, UI.tokens.radius.md)
	UI.stroke(card, colors.borderStrong, 1, 0)

	local viewport = UI.create("ViewportFrame", {
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.fromOffset(width - 12, viewportHeight),
		BackgroundColor3 = colors.input,
		BorderSizePixel = 0,
		Active = false,
		InputSink = false,
		Ambient = Color3.new(0.7, 0.7, 0.7),
		LightDirection = Vector3.new(-1, -1, -1),
		Shadows = false,
		PostProcessing = false,
		UpdateRate = 1,
		ZIndex = 6101,
	}, card)
	UI.corner(viewport, UI.tokens.radius.sm)

	local function line(parent, message, y, textSize, color)
		local label = UI.label(parent, message, UDim2.fromOffset(9, y), UDim2.new(1, -18, 0, 16), textSize, color)
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.ZIndex = 6102
		return label
	end

	local ok, size, reason = pcall(addGeometry, viewport, value)
	if not ok then
		size = nil
	end
	if not size then
		local label = line(viewport, reason or "Preview unavailable", 53, UI.tokens.type.small, colors.subtext)
		label.TextXAlignment = Enum.TextXAlignment.Center
	end
	local caption = UI.tokens.type.caption
	line(card, value.Name, 133, UI.tokens.type.small, colors.text)
	local dimensions = size and string.format("  ·  %.3g × %.3g × %.3g", size.X, size.Y, size.Z) or ""
	line(card, value.ClassName .. dimensions, 151, caption, colors.subtext)
	line(card, value:GetFullName(), 171, caption, colors.muted)
end

function Preview.clear()
	hovered = nil
	closeCard()
end

function Preview.track(row, getValue)
	row.MouseEnter:Connect(function()
		Preview.clear()
		hovered = { row = row, getValue = getValue, since = os.clock() }
	end)
	local function leave()
		if hovered and hovered.row == row then
			Preview.clear()
		end
	end
	row.MouseLeave:Connect(leave)
	row.Destroying:Connect(leave)
end

function Preview.update(list, enabled)
	local entry = hovered
	if not entry then
		return
	end

	local mouse = UserInputService:GetMouseLocation()
	local row = entry.row
	if not enabled
		or not list:ContainsPoint(mouse.X, mouse.Y)
		or not row:ContainsPoint(mouse.X, mouse.Y)
		or not row.Parent:ContainsPoint(mouse.X, mouse.Y)
	then
		closeCard()
		entry.since = os.clock()
		return
	end
	if os.clock() - entry.since < 0.2 then
		return
	end

	local value = entry.getValue()
	if typeof(value) ~= "Instance" or not UI.isAlive(value) then
		closeCard()
		return
	end
	if not card or entry.value ~= value then
		closeCard()
		entry.value = value
		openCard(value)
	end

	local pos, size = row.AbsolutePosition, row.AbsoluteSize
	local window = workspace:GetWindowDimensions()
	local x = pos.X + size.X - width
	local y = pos.Y - height - 5
	if y < 4 then
		y = pos.Y + size.Y + 5
	end
	card.Position = UDim2.fromOffset(
		math.clamp(x, 4, math.max(4, window.X - width - 4)),
		math.clamp(y, 4, math.max(4, window.Y - height - 4))
	)
end

return Preview

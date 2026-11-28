-- Shared geometry for editor-only multi-selection transforms.
-- The native Handles move a temporary proxy; selected parts retain their
-- original rotations and are updated from an immutable drag snapshot.
local MultiTransform = {}

local MIN_SIZE = 0.05

function MultiTransform.collect(selection)
	local parts = {}
	local seen = {}
	local function add(instance)
		if instance:IsA("BasePart") and not instance:IsA("Terrain") and not instance.Locked and not seen[instance] then
			seen[instance] = true
			table.insert(parts, instance)
		end
	end
	for _, instance in ipairs(selection) do
		if instance and instance.Parent then
			add(instance)
			for _, descendant in ipairs(instance:GetDescendants()) do
				add(descendant)
			end
		end
	end
	return parts
end

function MultiTransform.bounds(parts)
	local minPoint, maxPoint
	for _, part in ipairs(parts) do
		if part.Parent then
			local cf, half = part.CFrame, part.Size * 0.5
			local right, up, forward = cf.RightVector, cf.UpVector, cf.LookVector
			local radius = Vector3.new(
				math.abs(right.X) * half.X + math.abs(up.X) * half.Y + math.abs(forward.X) * half.Z,
				math.abs(right.Y) * half.X + math.abs(up.Y) * half.Y + math.abs(forward.Y) * half.Z,
				math.abs(right.Z) * half.X + math.abs(up.Z) * half.Y + math.abs(forward.Z) * half.Z
			)
			local low, high = cf.Position - radius, cf.Position + radius
			if not minPoint then
				minPoint, maxPoint = low, high
			else
				minPoint = Vector3.new(math.min(minPoint.X, low.X), math.min(minPoint.Y, low.Y), math.min(minPoint.Z, low.Z))
				maxPoint = Vector3.new(math.max(maxPoint.X, high.X), math.max(maxPoint.Y, high.Y), math.max(maxPoint.Z, high.Z))
			end
		end
	end
	if not minPoint then
		return nil, nil
	end
	local size = maxPoint - minPoint
	return (minPoint + maxPoint) * 0.5, Vector3.new(
		math.max(MIN_SIZE, size.X),
		math.max(MIN_SIZE, size.Y),
		math.max(MIN_SIZE, size.Z)
	)
end

function MultiTransform.apply(parts, originalCFrames, originalSizes, initialPivot, initialSize, currentPivot, currentSize, mode)
	local delta = currentPivot * initialPivot:Inverse()
	local factor = Vector3.new(
		math.max(MIN_SIZE, currentSize.X) / math.max(MIN_SIZE, initialSize.X),
		math.max(MIN_SIZE, currentSize.Y) / math.max(MIN_SIZE, initialSize.Y),
		math.max(MIN_SIZE, currentSize.Z) / math.max(MIN_SIZE, initialSize.Z)
	)
	for _, part in ipairs(parts) do
		local original = originalCFrames[part]
		if original and part.Parent then
			if mode == "Move" or mode == "Rotate" then
				part.CFrame = delta * original
			elseif mode == "Size" then
				local localPosition = initialPivot:PointToObjectSpace(original.Position)
				local scaledPosition = Vector3.new(
					localPosition.X * factor.X,
					localPosition.Y * factor.Y,
					localPosition.Z * factor.Z
				)
				local position = currentPivot:PointToWorldSpace(scaledPosition)
				local originalRotation = original - original.Position
				-- CFrame can represent rotation and scale-free translation, not
				-- shear. Preserve each part's orientation and project its local
				-- edge lengths onto the selection axes.
				local function stretch(axis)
					local v = initialPivot:VectorToObjectSpace(axis)
					return math.sqrt(
						(v.X * factor.X)^2 + (v.Y * factor.Y)^2 + (v.Z * factor.Z)^2
					)
				end
				local size = originalSizes[part]
				part.Size = Vector3.new(
					math.max(MIN_SIZE, size.X * stretch(original.RightVector)),
					math.max(MIN_SIZE, size.Y * stretch(original.UpVector)),
					math.max(MIN_SIZE, size.Z * stretch(original.LookVector))
				)
				part.CFrame = CFrame.new(position) * originalRotation
			end
		end
	end
end

return MultiTransform

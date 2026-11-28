-- Precision face and center alignment for the native 3D move gizmo.
local PartSnap = {}

local function projectedRadius(cf: CFrame, size: Vector3, axis: Vector3): number
	return (math.abs(cf.RightVector:Dot(axis)) * size.X
		+ math.abs(cf.UpVector:Dot(axis)) * size.Y
		+ math.abs(cf.LookVector:Dot(axis)) * size.Z) * 0.5
end

local function sharesFaceArea(movingCF, movingSize, targetCF, targetSize, axes, active)
	for i, axis in ipairs(axes) do
		if i ~= active then
			local gap = math.abs((targetCF.Position - movingCF.Position):Dot(axis))
			local reach = projectedRadius(movingCF, movingSize, axis)
				+ projectedRadius(targetCF, targetSize, axis)
			if gap > reach + 0.02 then
				return false
			end
		end
	end
	return true
end

-- Calculate correction from the original CFrames, not incrementally corrected
-- positions, so a previous magnetic snap cannot feed back into the next frame.
function PartSnap.find(moving, originals, targets, excluded, rawDelta, axes, tolerance, centersOnly)
	local bestDistance = tolerance + 1e-8
	local bestOffset, bestPart, bestKind = nil, nil, nil
	for axisIndex, axis in ipairs(axes) do
		local along = rawDelta:Dot(axis)
		if math.abs(along) <= 1e-6 then
			continue
		end
		for _, part in ipairs(moving) do
			local originalCF = originals[part]
			if not originalCF or not part.Parent then
				continue
			end
			local movedCF = originalCF + rawDelta
			local movingSize = part.Size
			local movingRadius = movingSize.Magnitude * 0.5
			for _, target in ipairs(targets) do
				if excluded[target] or not target.Parent or target:IsA("Terrain") then
					continue
				end
				local targetCF = target.CFrame
				local targetSize = target.Size
				if (movedCF.Position - targetCF.Position).Magnitude
					> movingRadius + targetSize.Magnitude * 0.5 + tolerance then
					continue
				end
				if not sharesFaceArea(movedCF, movingSize, targetCF, targetSize, axes, axisIndex) then
					continue
				end
				local centerGap = (targetCF.Position - movedCF.Position):Dot(axis)
				local gap
				local kind = centersOnly and "Center" or "Face"
				if centersOnly then
					gap = centerGap
				elseif along > 0 then
					gap = centerGap - projectedRadius(targetCF, targetSize, axis)
						- projectedRadius(movedCF, movingSize, axis)
				else
					gap = centerGap + projectedRadius(targetCF, targetSize, axis)
						+ projectedRadius(movedCF, movingSize, axis)
				end
				local distance = math.abs(gap)
				if distance <= tolerance and distance < bestDistance then
					bestDistance = distance
					bestOffset = axis * gap
					bestPart = target
					bestKind = kind
				end
			end
		end
	end
	return bestOffset, bestPart, bestKind
end

return PartSnap

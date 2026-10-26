local part1 = Instance.new("Part")
part1.CFrame = CFrame.new(0, 14, 0)
part1.Anchored = true
part1.Parent = workspace

local part2 = Instance.new("Part")
part2.CFrame = CFrame.new(0, 10, 0)
part2.Anchored = false
part2.Parent = workspace

local attach0 = Instance.new("Attachment")
attach0.Parent = part1

local attach1 = Instance.new("Attachment")
attach1.Parent = part2

local rope = Instance.new("RopeConstraint")
rope.Attachment0 = attach0
rope.Attachment1 = attach1
rope.Parent = workspace

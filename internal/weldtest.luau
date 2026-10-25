local part1 = Instance.new("Part")
part1.CFrame = CFrame.new(0, 10, 0)
part1.Parent = workspace

local part2 = Instance.new("Part")
part2.CFrame = CFrame.new(0, 14, 0)
part2.Parent = workspace

local weld = Instance.new("WeldConstraint")
weld.Part0 = part1
weld.Part1 = part2
weld.Parent = workspace

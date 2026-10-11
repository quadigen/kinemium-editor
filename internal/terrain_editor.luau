local terrain = game:GetService("Terrain")
local UserInputService = game:GetService("UserInputService")
local mouse: Mouse = UserInputService:GetMouse()
local RunService = game:GetService("RunService")

local CHEVRON = "builtin://global-icons/chevron-down.svg"

local UI = require("@internal/editor_ui")
local colors = UI.tokens.color

local VOXEL = 4
local MAX_SIZE = 512
local MAX_HISTORY = 60
local WEDGE_TALL_SIDE = 1

local MATERIAL_LIST = {
	{ "Grass", Enum.Material.Grass },
	{ "LeafyGrass", Enum.Material.LeafyGrass },
	{ "Sand", Enum.Material.Sand },
	{ "Sandstone", Enum.Material.Sandstone },
	{ "Rock", Enum.Material.Rock },
	{ "Basalt", Enum.Material.Basalt },
	{ "Slate", Enum.Material.Slate },
	{ "Limestone", Enum.Material.Limestone },
	{ "Mud", Enum.Material.Mud },
	{ "Ground", Enum.Material.Ground },
	{ "Snow", Enum.Material.Snow },
	{ "Ice", Enum.Material.Ice },
	{ "Glacier", Enum.Material.Glacier },
	{ "Salt", Enum.Material.Salt },
	{ "Concrete", Enum.Material.Concrete },
	{ "Pavement", Enum.Material.Pavement },
	{ "Asphalt", Enum.Material.Asphalt },
	{ "Cobblestone", Enum.Material.Cobblestone },
	{ "Brick", Enum.Material.Brick },
	{ "WoodPlanks", Enum.Material.WoodPlanks },
	{ "CrackedLava", Enum.Material.CrackedLava },
	{ "Water", Enum.Material.Water },
}

local materialByName = {}
local materialNames = {}
for _, entry in ipairs(MATERIAL_LIST) do
	materialByName[entry[1]] = entry[2]
	table.insert(materialNames, entry[1])
end

local sourceNames = { "Any" }
for _, name in ipairs(materialNames) do
	table.insert(sourceNames, name)
end

local cfg = {
	mode = "Add", -- Add | Subtract | Paint
	shape = "Ball", -- Ball | Block | Cylinder | Wedge
	material = Enum.Material.Grass,
	source = nil, -- Paint only: nil = any material
	radius = 4, -- Ball / Cylinder
	height = 8, -- Cylinder
	size = Vector3.new(4, 4, 4), -- Block / Wedge
	rotation = 0, -- degrees around Y
	snap = false,
	grid = 4,
	offset = 0, -- vertical offset from the hit position
	hold = true,
	spacing = 2,
	interval = 0.05,
	showPreview = true,
	previewColor = Color3.new(0, 0.701961, 1),
	previewTransparency = 0.6,
}

------------------------------------------------------------------ noise

local Noise = {}
Noise.__index = Noise

function Noise.new(seed)
	local self = setmetatable({}, Noise)

	local state = math.floor(seed) % 4294967296
	local function nextRandom()
		state = (state * 1664525 + 1013904223) % 4294967296
		return state / 4294967296
	end

	local perm = {}
	for i = 0, 255 do
		perm[i] = i
	end
	for i = 255, 1, -1 do
		local j = math.floor(nextRandom() * (i + 1))
		perm[i], perm[j] = perm[j], perm[i]
	end

	local p = {}
	for i = 0, 511 do
		p[i] = perm[i % 256]
	end

	self.p = p
	return self
end

local function fade(t)
	return t * t * t * (t * (t * 6 - 15) + 10)
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function grad(hash, x, y, z)
	local h = hash % 16
	local u = h < 8 and x or y
	local v = h < 4 and y or ((h == 12 or h == 14) and x or z)
	return ((h % 2 == 0) and u or -u) + ((h % 4 < 2) and v or -v)
end

-- 3D improved Perlin noise, roughly -1..1
function Noise:Get(x, y, z)
	local p = self.p

	local fx, fy, fz = math.floor(x), math.floor(y), math.floor(z)
	local X, Y, Z = fx % 256, fy % 256, fz % 256

	x, y, z = x - fx, y - fy, z - fz

	local u, v, w = fade(x), fade(y), fade(z)

	local A = p[X] + Y
	local AA, AB = p[A] + Z, p[A + 1] + Z
	local B = p[X + 1] + Y
	local BA, BB = p[B] + Z, p[B + 1] + Z

	return lerp(
		lerp(
			lerp(grad(p[AA], x, y, z), grad(p[BA], x - 1, y, z), u),
			lerp(grad(p[AB], x, y - 1, z), grad(p[BB], x - 1, y - 1, z), u),
			v
		),
		lerp(
			lerp(grad(p[AA + 1], x, y, z - 1), grad(p[BA + 1], x - 1, y, z - 1), u),
			lerp(grad(p[AB + 1], x, y - 1, z - 1), grad(p[BB + 1], x - 1, y - 1, z - 1), u),
			v
		),
		w
	)
end

-- fractal noise, normalized to roughly -1..1. `layer` is a z-offset so each use is independent
function Noise:Fbm(x, y, layer, octaves, persistence, lacunarity)
	local sum, amp, freq, norm = 0, 1, 1, 0

	for _ = 1, octaves do
		sum += self:Get(x * freq, y * freq, layer) * amp
		norm += amp
		amp *= persistence
		freq *= lacunarity
	end

	return sum / norm
end

-- ridged noise, 0..1, sharp crests (good for mountain ranges)
function Noise:Ridged(x, y, layer, octaves, persistence, lacunarity)
	local sum, amp, freq, norm = 0, 1, 1, 0

	for _ = 1, octaves do
		local n = 1 - math.abs(self:Get(x * freq, y * freq, layer))
		sum += n * n * amp
		norm += amp
		amp *= persistence
		freq *= lacunarity
	end

	return sum / norm
end

local function smoothstep(a, b, x)
	local t = math.clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

local history = {}
local strokeId = 0
local painting = false
local lastPos, lastTime = nil, 0

local generating = false
local cancelRequested = false
local lastWorld = nil

local gen = {
	seed = 1337,
	scale = 400, -- feature size in studs
	octaves = 5,
	persistence = 0.5,
	lacunarity = 2,
	amplitude = 160, -- max height above Base Y
	sea = 0.14, -- sea level as a fraction of amplitude
	mountains = 0.7, -- 0 = no mountains, 1 = lots
	cliff = 0.9, -- slope (rise/run) above which terrain turns to rock
	baseY = 0,
	depth = 32, -- solid ground below Base Y
	areaX = 512,
	areaZ = 512,
	centerX = 0,
	centerZ = 0,
	biomes = true, -- off = uses the Material dropdown for the surface
	caves = false,
	caveSize = 0.08,
	replace = true, -- off = only adds terrain, never removes existing
	undoable = true,
}

local gui = Instance.new("ScreenGui")
gui.Name = "TerrainEditor"
gui.RenderOnTop = true
gui.Parent = game.CoreGui

local panel, content = UI.window("Terrain", UDim2.fromOffset(120, 120), UDim2.fromOffset(320, 480), "Terrain", {
	closable = true,
})
content.BackgroundTransparency = 1
panel.Visible = false
panel.BackgroundTransparency = 0.5
panel.ClipsDescendants = true
panel.Parent = gui

UI.backdrop(panel, 15, Color3.new(0, 0, 0))

local scroller = Instance.new("ScrollingFrame")
scroller.BackgroundTransparency = 1
scroller.BorderSizePixel = 0
scroller.Size = UDim2.new(1, -10, 1, 0)
scroller.CanvasSize = UDim2.new(0, 0, 0, 0)
scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroller.ScrollBarThickness = 5
scroller.ClipsDescendants = true
scroller.Parent = content

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Vertical
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 2)
layout.Parent = scroller

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 8)
padding.PaddingBottom = UDim.new(0, 8)
padding.PaddingLeft = UDim.new(0, 6)
padding.PaddingRight = UDim.new(0, 10)
padding.Parent = scroller

local nextOrder = 0
local function place(object)
	nextOrder += 1
	object.LayoutOrder = nextOrder
	return object
end

local function section(text)
	local header = UI.sectionHeader(scroller, text)
	UI.corner(header, 5)
	return place(header)
end

local function numberRow(text, value, min, max, decimals, onChanged)
	local row, ctrl = UI.property(scroller, text, nil, nil, value, function(v)
		onChanged(v)
	end, { numeric = true, min = min, max = max, decimals = decimals, transparent = true })

	return place(row), ctrl
end

local function dropdownRow(text, list, initial, onChanged)
	local items = {}
	for _, name in ipairs(list) do
		table.insert(items, { value = name, label = name })
	end

	local row, ctrl = UI.property(scroller, text, nil, nil, initial, function(v)
		onChanged(v)
	end, {
		transparent = true,
		custom = function(holder, ctrl, c)
			local innerHeight = UI.metrics.propertyRow - 2

			local dropOptions = {
				items = items,
				menuWidth = 140,
				showSearch = #items > 8,
				menuPosition = function()
					local button = ctrl.custom.button
					local p, s = button.AbsolutePosition, button.AbsoluteSize
					return UDim2.fromOffset(p.X, p.Y + s.Y + 2)
				end,
				onChanged = function(v)
					ctrl:Fire(v)
				end,
			}

			local button, label, dropdown = UI.dropdown(
				holder,
				initial,
				UDim2.new(0, 0, 0.5, -math.floor(innerHeight / 2)),
				UDim2.new(1, 0, 0, innerHeight),
				CHEVRON,
				dropOptions
			)

			local function syncWidth()
				local width = button.AbsoluteSize.X
				if width > 0 then
					dropOptions.menuWidth = width
				end
			end

			syncWidth()
			button:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncWidth)

			return {
				button = button,
				GetValue = function()
					return dropdown:GetValue()
				end,
				SetValue = function(_, v, silent)
					dropdown:SetValue(v, true)
					if not silent then
						ctrl:Fire(v)
					end
				end,
				SetEnabled = function(_, enabled)
					dropdown.record.enabled = enabled
					button.Active = enabled
					label.TextColor3 = enabled and c.subtext or c.muted
				end,
				Destroy = function()
					dropdown:Close()
				end,
			}
		end,
	})

	return place(row), ctrl
end

local function hexToColor(text)
	local raw = string.gsub(text, "#", "")
	if #raw ~= 6 then
		return nil
	end

	local r, g, b =
		tonumber(string.sub(raw, 1, 2), 16), tonumber(string.sub(raw, 3, 4), 16), tonumber(string.sub(raw, 5, 6), 16)

	if r and g and b then
		return Color3.fromRGB(r, g, b)
	end

	return nil
end

local function brushDims()
	if cfg.shape == "Ball" then
		local d = cfg.radius * 2
		return Vector3.new(d, d, d)
	elseif cfg.shape == "Cylinder" then
		local d = cfg.radius * 2
		return Vector3.new(d, cfg.height, d)
	end

	return cfg.size
end

local function snapVec(v, g)
	return Vector3.new(math.floor(v.X / g + 0.5) * g, math.floor(v.Y / g + 0.5) * g, math.floor(v.Z / g + 0.5) * g)
end

local function brushCFrame()
	local hit = mouse.Hit

	if not hit then
		return nil
	end

	local pos = hit.Position + Vector3.new(0, cfg.offset, 0)

	if cfg.snap then
		pos = snapVec(pos, cfg.grid)
	end

	return CFrame.new(pos) * CFrame.Angles(0, math.rad(cfg.rotation), 0)
end

-- voxel-aligned world region that fully contains the (rotated) brush
local function brushRegion(cf, dims)
	local h = dims / 2
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector

	local ext = Vector3.new(
		math.abs(r.X) * h.X + math.abs(u.X) * h.Y + math.abs(l.X) * h.Z,
		math.abs(r.Y) * h.X + math.abs(u.Y) * h.Y + math.abs(l.Y) * h.Z,
		math.abs(r.Z) * h.X + math.abs(u.Z) * h.Y + math.abs(l.Z) * h.Z
	) + Vector3.new(VOXEL, VOXEL, VOXEL)

	local p = cf.Position

	return Region3.new(p - ext, p + ext):ExpandToGrid(VOXEL)
end

-- lp = point in brush-local space
local function insideBrush(lp, dims)
	local h = dims / 2
	local shape = cfg.shape

	if shape == "Ball" then
		return lp.Magnitude <= cfg.radius
	elseif shape == "Cylinder" then
		return math.sqrt(lp.X * lp.X + lp.Z * lp.Z) <= cfg.radius and math.abs(lp.Y) <= h.Y
	elseif shape == "Block" then
		return math.abs(lp.X) <= h.X and math.abs(lp.Y) <= h.Y and math.abs(lp.Z) <= h.Z
	end

	-- Wedge
	if math.abs(lp.X) > h.X or math.abs(lp.Z) > h.Z or math.abs(lp.Y) > h.Y then
		return false
	end

	local t = lp.Z / dims.Z + 0.5

	if WEDGE_TALL_SIDE < 0 then
		t = 1 - t
	end

	return (lp.Y + h.Y) <= dims.Y * t
end

local function trimHistory()
	local seen, count = {}, 0

	for i = #history, 1, -1 do
		local id = history[i].id

		if not seen[id] then
			seen[id] = true
			count += 1

			if count > MAX_HISTORY then
				for _ = 1, i do
					table.remove(history, 1)
				end
				break
			end
		end
	end
end

local function pushRegionHistory(region)
	local mats, occs = terrain:ReadVoxels(region, VOXEL)

	table.insert(history, { id = strokeId, region = region, mats = mats, occs = occs })
	trimHistory()
end

local function pushHistory(cf, dims)
	pushRegionHistory(brushRegion(cf, dims))
end

local function undo()
	if generating then
		return
	end

	local top = history[#history]

	if not top then
		return
	end

	while #history > 0 and history[#history].id == top.id do
		local entry = table.remove(history)
		terrain:WriteVoxels(entry.region, VOXEL, entry.mats, entry.occs)
	end
end

------------------------------------------------------------------ applying the brush

local function paintBrush(cf, dims)
	local region = brushRegion(cf, dims)
	local mats, occs = terrain:ReadVoxels(region, VOXEL)

	local sz = mats.Size
	local origin = region.CFrame.Position - region.Size / 2

	for x = 1, sz.X do
		for y = 1, sz.Y do
			for z = 1, sz.Z do
				if occs[x][y][z] > 0 then
					local current = mats[x][y][z]

					if not cfg.source or current == cfg.source then
						local p = origin + Vector3.new(x - 0.5, y - 0.5, z - 0.5) * VOXEL

						if insideBrush(cf:PointToObjectSpace(p), dims) then
							mats[x][y][z] = cfg.material
						end
					end
				end
			end
		end
	end

	terrain:WriteVoxels(region, VOXEL, mats, occs)
end

local function applyBrush(cf)
	local dims = brushDims()

	pushHistory(cf, dims)

	if cfg.mode == "Paint" then
		paintBrush(cf, dims)
		return
	end

	local material = cfg.mode == "Subtract" and Enum.Material.Air or cfg.material

	if cfg.shape == "Ball" then
		terrain:FillBall(cf.Position, cfg.radius, material)
	elseif cfg.shape == "Block" then
		terrain:FillBlock(cf, dims, material)
	elseif cfg.shape == "Cylinder" then
		terrain:FillCylinder(cf, cfg.height, cfg.radius, material)
	else
		terrain:FillWedge(cf, dims, material)
	end
end

------------------------------------------------------------------ generator

local statusLabel, progressCtrl

local function setStatus(text)
	if statusLabel then
		statusLabel.Text = text
	end
end

local Mat = Enum.Material

-- returns surface material, subsurface material
local function pickBiome(h, slope, temp, moist)
	local above = h - gen.sea

	-- shore + sea floor
	if above < 0.012 then
		if above > -0.05 then
			return Mat.Sand, Mat.Sand
		end
		return Mat.Mud, Mat.Rock
	end

	-- cliffs
	if slope > gen.cliff then
		return (h > 0.6) and Mat.Slate or Mat.Rock, Mat.Rock
	end

	-- high altitude
	local snowline = 0.7 + (temp - 0.5) * 0.2

	if h > snowline + 0.12 and temp < 0.45 then
		return Mat.Glacier, Mat.Rock
	elseif h > snowline then
		return Mat.Snow, Mat.Rock
	elseif h > 0.55 then
		return (moist > 0.5) and Mat.Slate or Mat.Rock, Mat.Rock
	end

	-- climate biomes
	if temp < 0.3 then
		if moist > 0.4 then
			return Mat.Snow, Mat.Ground -- taiga / snowfield
		end
		return Mat.Ground, Mat.Rock -- tundra
	elseif temp > 0.68 then
		if moist < 0.35 then
			return Mat.Sand, Mat.Sandstone -- desert
		elseif moist < 0.6 then
			return Mat.Ground, Mat.Mud -- savanna
		end
		return Mat.LeafyGrass, Mat.Mud -- jungle
	end

	if moist > 0.75 and above < 0.08 then
		return Mat.Mud, Mat.Mud -- swamp
	elseif moist > 0.55 then
		return Mat.LeafyGrass, Mat.Ground -- forest
	end

	return Mat.Grass, Mat.Ground -- plains
end

local function runGeneration()
	local noise = Noise.new(gen.seed)

	local inv = 1 / gen.scale
	local amp = gen.amplitude
	local seaY = gen.baseY + gen.sea * amp

	local function heightAt(x, z)
		local nx, nz = x * inv, z * inv

		-- lowlands / ocean basins
		local base = noise:Fbm(nx, nz, 0.37, gen.octaves, gen.persistence, gen.lacunarity) * 0.5 + 0.5
		base = math.clamp((base - 0.5) * 1.5 + 0.5, 0, 1)

		-- where mountain ranges are allowed
		local m = noise:Fbm(nx * 0.5, nz * 0.5, 17.13, 3, 0.5, 2) * 0.5 + 0.5
		local mask = smoothstep(0.48, 0.72, m) * gen.mountains

		-- the ranges themselves
		local r = noise:Ridged(nx * 1.2, nz * 1.2, 41.71, gen.octaves, gen.persistence, gen.lacunarity)
		r = math.clamp((r - 0.45) * 2.2, 0, 1)

		return math.clamp((base ^ 1.4) * 0.5 + mask * r * 0.6, 0, 1)
	end

	local function climateAt(x, z, h)
		local t = noise:Fbm(x * inv * 0.35, z * inv * 0.35, 73.29, 3, 0.5, 2) * 0.5 + 0.5
		t = math.clamp((t - 0.5) * 1.8 + 0.5 - math.max(h - gen.sea, 0) * 0.5, 0, 1)

		local w = noise:Fbm(x * inv * 0.45, z * inv * 0.45, 91.57, 3, 0.5, 2) * 0.5 + 0.5
		w = math.clamp((w - 0.5) * 1.8 + 0.5, 0, 1)

		return t, w
	end

	local CHUNK = 16

	local totalX = math.ceil(gen.areaX / VOXEL)
	local totalZ = math.ceil(gen.areaZ / VOXEL)

	local minX = math.floor((gen.centerX - gen.areaX / 2) / VOXEL) * VOXEL
	local minZ = math.floor((gen.centerZ - gen.areaZ / 2) / VOXEL) * VOXEL
	local minY = math.floor((gen.baseY - gen.depth) / VOXEL) * VOXEL

	local totalY = math.ceil((gen.baseY + amp - minY) / VOXEL) + 1

	local totalChunks = math.ceil(totalX / CHUNK) * math.ceil(totalZ / CHUNK)
	local done = 0

	local caveScale = 1 / 60

	for ox = 0, totalX - 1, CHUNK do
		for oz = 0, totalZ - 1, CHUNK do
			if cancelRequested then
				setStatus("Cancelled")
				return
			end

			local cw = math.min(CHUNK, totalX - ox)
			local cd = math.min(CHUNK, totalZ - oz)

			local rmin = Vector3.new(minX + ox * VOXEL, minY, minZ + oz * VOXEL)
			local rmax = rmin + Vector3.new(cw * VOXEL, totalY * VOXEL, cd * VOXEL)
			local region = Region3.new(rmin, rmax)

			if gen.undoable then
				pushRegionHistory(region)
			end

			local mats, occs = terrain:ReadVoxels(region, VOXEL)
			local sz = mats.Size
			local origin = region.CFrame.Position - region.Size / 2

			-- heights for the chunk plus a 1-column border (for slope)
			local hs = {}
			for ix = 0, sz.X + 1 do
				local col = {}
				hs[ix] = col

				local wx = origin.X + (ix - 0.5) * VOXEL

				for iz = 0, sz.Z + 1 do
					col[iz] = heightAt(wx, origin.Z + (iz - 0.5) * VOXEL)
				end
			end

			for ix = 1, sz.X do
				local wx = origin.X + (ix - 0.5) * VOXEL

				for iz = 1, sz.Z do
					local wz = origin.Z + (iz - 0.5) * VOXEL

					local h = hs[ix][iz]
					local surfaceY = gen.baseY + h * amp

					local dx = (hs[ix + 1][iz] - hs[ix - 1][iz]) * amp / (2 * VOXEL)
					local dz = (hs[ix][iz + 1] - hs[ix][iz - 1]) * amp / (2 * VOXEL)
					local slope = math.max(math.abs(dx), math.abs(dz))

					local top, sub

					if gen.biomes then
						local temp, moist = climateAt(wx, wz, h)
						top, sub = pickBiome(h, slope, temp, moist)
					else
						top, sub = cfg.material, Mat.Rock
					end

					for iy = 1, sz.Y do
						local yc = origin.Y + (iy - 0.5) * VOXEL
						local bottom = yc - VOXEL / 2

						local occ = math.clamp((surfaceY - bottom) / VOXEL, 0, 1)
						local mat = Mat.Air

						if occ > 0 then
							local depth = surfaceY - yc

							if depth < 3.5 then
								mat = top
							elseif depth < 10 then
								mat = sub
							elseif depth < 48 then
								mat = Mat.Rock
							else
								mat = Mat.Basalt
							end

							-- tunnels where two noise fields are both near zero
							if gen.caves and depth > 8 and yc > minY + 8 then
								local a = noise:Get(wx * caveScale, yc * caveScale, wz * caveScale)
								local b = noise:Get(wx * caveScale + 31.4, yc * caveScale + 17.7, wz * caveScale + 53.2)

								if math.abs(a) < gen.caveSize and math.abs(b) < gen.caveSize then
									occ = 0
									mat = Mat.Air
								end
							end
						elseif bottom < seaY then
							occ = math.clamp((seaY - bottom) / VOXEL, 0, 1)
							mat = Mat.Water
						end

						if gen.replace or occ > occs[ix][iy][iz] then
							mats[ix][iy][iz] = mat
							occs[ix][iy][iz] = occ
						end
					end
				end
			end

			terrain:WriteVoxels(region, VOXEL, mats, occs)

			done += 1

			if progressCtrl then
				progressCtrl:SetValue(done / totalChunks)
			end

			setStatus(string.format("Generating... %d / %d chunks", done, totalChunks))

			RunService.Heartbeat:Wait() -- let the editor breathe
		end
	end

	setStatus("Done")
end

local function startGeneration()
	if generating then
		return
	end

	generating = true
	cancelRequested = false
	painting = false

	strokeId += 1 -- the whole generation is one undo step

	setStatus("Starting...")

	if progressCtrl then
		progressCtrl:SetValue(0)
	end

	coroutine.wrap(function()
		local ok, err = pcall(runGeneration)

		generating = false

		if not ok then
			warn("Terrain generation failed: " .. tostring(err))
			setStatus("Failed (see output)")
		end
	end)()
end

local rows = {}
local radiusCtrl, heightCtrl, sizeCtrl, rotationCtrl

local function refreshRows()
	rows.material.Visible = cfg.mode ~= "Subtract"
	rows.source.Visible = cfg.mode == "Paint"
	rows.radius.Visible = cfg.shape == "Ball" or cfg.shape == "Cylinder"
	rows.height.Visible = cfg.shape == "Cylinder"
	rows.size.Visible = cfg.shape == "Block" or cfg.shape == "Wedge"
end

section("Tool")

rows.mode = dropdownRow("Mode", { "Add", "Subtract", "Paint" }, cfg.mode, function(v)
	cfg.mode = v
	refreshRows()
end)

rows.shape = dropdownRow("Shape", { "Ball", "Block", "Cylinder", "Wedge" }, cfg.shape, function(v)
	cfg.shape = v
	refreshRows()
end)

section("Material")

rows.material = dropdownRow("Material", materialNames, "Grass", function(v)
	cfg.material = materialByName[v]
end)

rows.source = dropdownRow("Replace", sourceNames, "Any", function(v)
	cfg.source = v ~= "Any" and materialByName[v] or nil
end)

section("Brush")

rows.radius, radiusCtrl = numberRow("Radius", cfg.radius, 1, MAX_SIZE, 1, function(v)
	cfg.radius = v
end)

rows.height, heightCtrl = numberRow("Height", cfg.height, 1, MAX_SIZE, 1, function(v)
	cfg.height = v
end)

local sizeRow
sizeRow, sizeCtrl = UI.property(scroller, "Size", nil, nil, { 4, 4, 4 }, function(values)
	cfg.size = Vector3.new(values[1], values[2], values[3])
end, {
	fields = { { prefix = "X" }, { prefix = "Y" }, { prefix = "Z" } },
	numeric = true,
	min = 1,
	max = MAX_SIZE,
	transparent = true,
	decimals = 1,
	prefixColors = { colors.error, colors.success, colors.accent },
})
rows.size = place(sizeRow)

rows.rotation, rotationCtrl = numberRow("Rotation", cfg.rotation, nil, nil, 1, function(v)
	cfg.rotation = v % 360
end)

section("Placement")

do
	local box = UI.checkbox(scroller, "Snap to grid", nil, cfg.snap, function(v)
		cfg.snap = v
	end, { size = UDim2.new(1, 0, 0, UI.metrics.propertyRow) })
	place(box)

	numberRow("Grid size", cfg.grid, 1, 64, 1, function(v)
		cfg.grid = v
	end)

	numberRow("Y offset", cfg.offset, -256, 256, 1, function(v)
		cfg.offset = v
	end)
end

section("Stroke")

do
	local box = UI.checkbox(scroller, "Hold to paint", nil, cfg.hold, function(v)
		cfg.hold = v
	end, { size = UDim2.new(1, 0, 0, UI.metrics.propertyRow) })
	place(box)

	numberRow("Spacing", cfg.spacing, 0.5, 64, 1, function(v)
		cfg.spacing = v
	end)

	numberRow("Interval", cfg.interval, 0.01, 2, 2, function(v)
		cfg.interval = v
	end)
end

section("Preview")

local refreshPreviewStyle

do
	local box = UI.checkbox(scroller, "Show preview", nil, cfg.showPreview, function(v)
		cfg.showPreview = v
	end, { size = UDim2.new(1, 0, 0, UI.metrics.propertyRow) })
	place(box)

	local colorRow = UI.property(scroller, "Color", nil, nil, "#00B3FF", function(v)
		cfg.previewColor = hexToColor(v) or cfg.previewColor
		refreshPreviewStyle()
	end, {
		transparent = true,
		validate = function(text)
			local c = hexToColor(text)
			if not c then
				return false
			end
			return true, "#" .. string.upper((string.gsub(text, "#", "")))
		end,
	})
	place(colorRow)

	numberRow("Opacity", 1 - cfg.previewTransparency, 0, 1, 2, function(v)
		cfg.previewTransparency = 1 - v
		refreshPreviewStyle()
	end)
end

section("Actions")

local function confirmClear()
	UI.prompt({
		title = "Clear terrain",
		description = "Removes ALL terrain. This can't be undone.",
		size = UDim2.fromOffset(360, 150),
		destroyOnClose = true,
		buttons = {
			{ id = "cancel", text = "Cancel", role = "ghost" },
			{
				id = "clear",
				text = "Clear",
				role = "danger",
				callback = function()
					terrain:Clear()
					table.clear(history)
				end,
			},
		},
	})
end

place((UI.button(scroller, "Undo (Ctrl+Z)", nil, UDim2.new(1, 0, 0, UI.metrics.buttonHeight), undo)))
place((UI.button(scroller, "Clear terrain", nil, UDim2.new(1, 0, 0, UI.metrics.buttonHeight), confirmClear, {
	textColor = colors.error,
})))

do
	local hint = UI.label(
		scroller,
		"[ / ]  brush size     Q / E  rotate     Ctrl+Z  undo",
		nil,
		UDim2.new(1, 0, 0, 30),
		UI.tokens.type.caption,
		colors.muted
	)
	hint.TextWrapped = true
	place(hint)
end

section("Generator")

local seedCtrl, centerCtrl

do
	local _
	_, seedCtrl = numberRow("Seed", gen.seed, 0, 999999, 0, function(v)
		gen.seed = v
	end)

	place((UI.button(scroller, "Randomize seed", nil, UDim2.new(1, 0, 0, UI.metrics.buttonHeight), function()
		gen.seed = math.random(0, 999999)
		seedCtrl:SetValue(gen.seed, true)
	end)))

	numberRow("Feature size", gen.scale, 50, 4000, 0, function(v)
		gen.scale = v
	end)

	numberRow("Height", gen.amplitude, 16, 1024, 0, function(v)
		gen.amplitude = v
	end)

	numberRow("Octaves", gen.octaves, 1, 8, 0, function(v)
		gen.octaves = math.floor(v)
	end)

	numberRow("Roughness", gen.persistence, 0.1, 0.9, 2, function(v)
		gen.persistence = v
	end)

	numberRow("Sea level", gen.sea, 0, 0.6, 2, function(v)
		gen.sea = v
	end)

	numberRow("Mountains", gen.mountains, 0, 1, 2, function(v)
		gen.mountains = v
	end)

	numberRow("Cliff slope", gen.cliff, 0.3, 3, 2, function(v)
		gen.cliff = v
	end)

	numberRow("Base Y", gen.baseY, -1000, 1000, 0, function(v)
		gen.baseY = v
	end)

	numberRow("Ground depth", gen.depth, 8, 512, 0, function(v)
		gen.depth = v
	end)

	place((UI.property(scroller, "Area", nil, nil, { gen.areaX, gen.areaZ }, function(v)
		gen.areaX, gen.areaZ = v[1], v[2]
	end, {
		fields = { { prefix = "X" }, { prefix = "Z" } },
		numeric = true,
		min = 16,
		max = 4096,
		decimals = 0,
		transparent = true,
	})))

	local centerRow
	centerRow, centerCtrl = UI.property(scroller, "Center", nil, nil, { gen.centerX, gen.centerZ }, function(v)
		gen.centerX, gen.centerZ = v[1], v[2]
	end, {
		fields = { { prefix = "X" }, { prefix = "Z" } },
		numeric = true,
		decimals = 0,
		transparent = true,
	})
	place(centerRow)

	place((UI.button(scroller, "Center on cursor", nil, UDim2.new(1, 0, 0, UI.metrics.buttonHeight), function()
		if not lastWorld then
			return
		end

		gen.centerX, gen.centerZ = math.floor(lastWorld.X), math.floor(lastWorld.Z)
		centerCtrl:SetValue({ gen.centerX, gen.centerZ }, true)
	end)))

	place((UI.checkbox(scroller, "Biomes", nil, gen.biomes, function(v)
		gen.biomes = v
	end, { size = UDim2.new(1, 0, 0, UI.metrics.propertyRow) })))

	place((UI.checkbox(scroller, "Caves", nil, gen.caves, function(v)
		gen.caves = v
	end, { size = UDim2.new(1, 0, 0, UI.metrics.propertyRow) })))

	numberRow("Cave size", gen.caveSize, 0.02, 0.2, 2, function(v)
		gen.caveSize = v
	end)

	place((UI.checkbox(scroller, "Replace existing", nil, gen.replace, function(v)
		gen.replace = v
	end, { size = UDim2.new(1, 0, 0, UI.metrics.propertyRow) })))

	place((UI.checkbox(scroller, "Undoable (uses memory)", nil, gen.undoable, function(v)
		gen.undoable = v
	end, { size = UDim2.new(1, 0, 0, UI.metrics.propertyRow) })))

	place((UI.button(scroller, "Generate", nil, UDim2.new(1, 0, 0, UI.metrics.buttonHeight), startGeneration, {
		color = colors.accent,
		textColor = colors.text,
	})))

	place((UI.button(scroller, "Cancel", nil, UDim2.new(1, 0, 0, UI.metrics.buttonHeight), function()
		cancelRequested = true
	end)))

	local bar
	bar, progressCtrl = UI.progressBar(scroller, nil, UDim2.new(1, 0, 0, 6), 0)
	place(bar)

	statusLabel = UI.label(scroller, "Idle", nil, UDim2.new(1, 0, 0, 16), UI.tokens.type.caption, colors.muted)
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	place(statusLabel)
end

refreshRows()

------------------------------------------------------------------ preview parts

local previewFolder = Instance.new("Folder")
previewFolder.Name = "TerrainBrushPreview"
previewFolder.Parent = workspace

mouse.TargetFilter = previewFolder

local previews = {}

local function makePreview(className, partShape)
	local part = Instance.new(className)
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false
	part.Transparency = 1

	if partShape then
		part.Shape = partShape
	end

	local highlight = Instance.new("Highlight")
	highlight.OutlineTransparency = 1
	highlight.Parent = part

	return { part = part, highlight = highlight }
end

previews.Ball = makePreview("Part", Enum.PartType.Ball)
previews.Block = makePreview("Part", Enum.PartType.Block)
previews.Cylinder = makePreview("Part", Enum.PartType.Cylinder)
previews.Wedge = makePreview("Part", Enum.PartType.Wedge)

refreshPreviewStyle = function()
	for _, p in pairs(previews) do
		p.highlight.FillColor = cfg.previewColor
		p.highlight.FillTransparency = cfg.previewTransparency
		p.highlight.OutlineColor = cfg.previewColor
		p.highlight.OutlineTransparency = 0.3
	end
end

refreshPreviewStyle()

local function overUI()
	local point = Vector2.new(mouse.X, mouse.Y)

	if panel.Visible and UI.pointInside(panel, point) then
		return true
	end

	local active = UI.shared().activeDropdown

	if active and active.menu and UI.pointInside(active.menu, point) then
		return true
	end

	return false
end

local function tryApply(cf)
	local ok, err = pcall(applyBrush, cf)

	if not ok then
		warn("Terrain brush failed: " .. tostring(err))
	end
end

mouse.Button1Down:Connect(function()
	if generating or not panel.Visible or overUI() then
		return
	end

	local cf = brushCFrame()

	if not cf then
		return
	end

	painting = true
	strokeId += 1
	lastPos = cf.Position
	lastTime = os.clock()

	tryApply(cf)
end)

mouse.Button1Up:Connect(function()
	painting = false
end)

local function scaleBrush(factor)
	cfg.radius = math.clamp(math.floor(cfg.radius * factor * 2 + 0.5) / 2, 1, MAX_SIZE)
	cfg.height = math.clamp(math.floor(cfg.height * factor * 2 + 0.5) / 2, 1, MAX_SIZE)
	cfg.size = Vector3.new(
		math.clamp(math.floor(cfg.size.X * factor * 2 + 0.5) / 2, 1, MAX_SIZE),
		math.clamp(math.floor(cfg.size.Y * factor * 2 + 0.5) / 2, 1, MAX_SIZE),
		math.clamp(math.floor(cfg.size.Z * factor * 2 + 0.5) / 2, 1, MAX_SIZE)
	)

	radiusCtrl:SetValue(cfg.radius, true)
	heightCtrl:SetValue(cfg.height, true)
	sizeCtrl:SetValue({ cfg.size.X, cfg.size.Y, cfg.size.Z }, true)
end

local function rotateBrush(degrees)
	cfg.rotation = (cfg.rotation + degrees) % 360
	rotationCtrl:SetValue(cfg.rotation, true)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not panel.Visible or UserInputService:GetFocusedTextBox() then
		return
	end

	local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)

	if input.KeyCode == Enum.KeyCode.Z and ctrl then
		undo()
	elseif input.KeyCode == Enum.KeyCode.RightBracket then
		scaleBrush(1.25)
	elseif input.KeyCode == Enum.KeyCode.LeftBracket then
		scaleBrush(0.8)
	elseif input.KeyCode == Enum.KeyCode.C then
		rotateBrush(-15)
	elseif input.KeyCode == Enum.KeyCode.V then
		rotateBrush(15)
	end
end)

RunService.RenderStepped:Connect(function()
	local visible = panel.Visible

	if not visible then
		painting = false
	end

	local cf = visible and brushCFrame() or nil
	local show = cf ~= nil and cfg.showPreview and not overUI()

	if cf and not overUI() then
		lastWorld = mouse.Hit.Position
	end

	for shape, p in pairs(previews) do
		local active = show and shape == cfg.shape
		local want = active and previewFolder or game.ReplicatedStorage

		if p.part.Parent ~= want then
			p.part.Parent = want
		end

		p.highlight.Enabled = active
	end

	if not cf then
		return
	end

	local dims = brushDims()
	local p = previews[cfg.shape]

	if cfg.shape == "Cylinder" then
		p.part.Size = Vector3.new(dims.Y, dims.X, dims.Z)
		p.part.CFrame = cf * CFrame.Angles(0, 0, math.pi / 2)
	else
		p.part.Size = dims
		p.part.CFrame = cf
	end

	if painting and cfg.hold then
		local now = os.clock()

		if now - lastTime >= cfg.interval and (cf.Position - lastPos).Magnitude >= cfg.spacing then
			lastPos = cf.Position
			lastTime = now

			tryApply(cf)
		end
	end
end)

painting = false

return {
	Enable = function()
		panel.Visible = true
	end,

	Disable = function()
		panel.Visible = false
		painting = false
	end,

	Toggle = function()
		panel.Visible = not panel.Visible
		if not panel.Visible then
			painting = false
		end
	end,
}

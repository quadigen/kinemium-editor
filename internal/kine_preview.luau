local UI = require("@internal/editor_ui")
local Export = game:GetService("ExportService")
local RunService = game:GetService("RunService")
local Preview = {}
local queue, worker, pending = {}, nil, nil
local active, cache, failures = {}, {}, {}
local storage = Instance.new("Folder")
local generation = 0
local CACHE_SECONDS, MAX_CACHED, MAX_CACHED_PARTS = 30, 24, 20000
local FRAME_BUDGET, MAX_OBJECTS_PER_FRAME = 0.002, 96

local function alive(object)
	local ok, parent = pcall(function() return object.Parent end)
	return ok and parent ~= nil
end

local function isPart(object)
	return object:IsA("Part") or object:IsA("BasePart")
end

local function onScreen(object)
	local position, size = object.AbsolutePosition, object.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then return false end
	local left, top, right, bottom = position.X, position.Y, position.X+size.X, position.Y+size.Y
	local ancestor = object
	while ancestor do
		if ancestor:IsA("GuiObject") then
			if not ancestor.Visible then return false end
			if ancestor.ClipsDescendants or ancestor:IsA("ScrollingFrame") then
				local p, s = ancestor.AbsolutePosition, ancestor.AbsoluteSize
				left, top = math.max(left,p.X), math.max(top,p.Y)
				right, bottom = math.min(right,p.X+s.X), math.min(bottom,p.Y+s.Y)
				if right <= left or bottom <= top then return false end
			end
		end
		ancestor = ancestor.Parent
	end
	return true
end

local function discard(record)
	pcall(function() record.frame:Destroy() end)
end

local function trimCache()
	local count = 0
	for i = #cache, 1, -1 do
		local record = cache[i]
		if record.expires < os.clock() or record.generation ~= generation then
			table.remove(cache, i)
			discard(record)
		else
			count += record.count
		end
	end
	while #cache > MAX_CACHED or count > MAX_CACHED_PARTS do
		local record = table.remove(cache, 1)
		count -= record.count
		discard(record)
	end
end

-- Detach previews before the browser destroys its old rows. Reuse the actual
-- frame, geometry and GPU resources instead of importing and cloning again.
function Preview.Release(root)
	if not root then return end
	for frame, record in pairs(active) do
		local ok, belongs = pcall(function() return frame:IsDescendantOf(root) end)
		if not ok then
			active[frame] = nil
		elseif belongs then
			active[frame] = nil
			frame.Parent = storage
			cache[#cache + 1] = record
		end
	end
	trimCache()
end

function Preview.Invalidate()
	generation += 1
	failures = {}
	trimCache()
end

local function place(record, parent, fallback)
	local frame = record.frame
	frame.Position, frame.Size = fallback.Position, fallback.Size
	local size = fallback.AbsoluteSize
	local aspect = size.X > 0 and size.Y > 0 and size.X / size.Y or 1
	local angle = math.atan(math.tan(math.rad(35)*0.5)*math.min(1,aspect))
	local distance = math.max(record.radius / math.sin(angle)*1.12, 0.25)
	frame.CurrentCamera.CFrame = CFrame.lookAt(record.center + Vector3.new(1,0.7,1).Unit*distance, record.center)
	frame.Parent = parent
	fallback.Visible = false
	active[frame] = record
end

local function cached(path, parent, fallback)
	trimCache()
	for i = #cache, 1, -1 do
		local record = cache[i]
		if record.path == path then
			table.remove(cache, i)
			place(record, parent, fallback)
			return true
		end
	end
	return false
end

local function cleanup(job)
	if job.frame then pcall(function() job.frame:Destroy() end) end
	if job.imported then pcall(function() job.imported:Destroy() end) end
end

local function start(job)
	job.imported = Export:ImportFile(job.path)
	if not job.imported or not (isPart(job.imported) or job.imported:IsA("Model")) then return false end
	job.stack, job.count = {job.imported}, 0
	job.low, job.high = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	return true
end

local function prepare(job)
	local deadline = os.clock() + FRAME_BUDGET
	local processed = 0
	while (#job.stack > 0 or job.children) and processed < MAX_OBJECTS_PER_FRAME do
		if job.children then
			local child = job.children[job.childIndex]
			if child then
				job.childIndex += 1
				if isPart(child) or child:IsA("Model") or child:IsA("Folder") then
					job.stack[#job.stack + 1] = child
				else
					child:Destroy()
				end
			else
				job.children = nil
			end
			processed += 1
			if os.clock() >= deadline then break end
			continue
		end
		local object = table.remove(job.stack)
		if isPart(object) then
			job.count += 1
			local half = object.Size * 0.5
			local x,y,z,a,b,c,d,e,f,g,h,i = object.CFrame:GetComponents()
			-- Exact rotated box extents, using one native call instead of eight
			-- corner transforms and repeated native vector property lookups.
			local ex = math.abs(a)*half.X + math.abs(b)*half.Y + math.abs(c)*half.Z
			local ey = math.abs(d)*half.X + math.abs(e)*half.Y + math.abs(f)*half.Z
			local ez = math.abs(g)*half.X + math.abs(h)*half.Y + math.abs(i)*half.Z
			local lo, hi = job.low, job.high
			job.low = Vector3.new(math.min(lo.X,x-ex),math.min(lo.Y,y-ey),math.min(lo.Z,z-ez))
			job.high = Vector3.new(math.max(hi.X,x+ex),math.max(hi.Y,y+ey),math.max(hi.Z,z+ez))
		end
		job.children, job.childIndex = object:GetChildren(), 1
		processed += 1
		if os.clock() >= deadline then break end
	end
	return #job.stack == 0 and job.children == nil
end

local function finish(job)
	if job.count == 0 then return false end
	local center = (job.low + job.high)*0.5
	local radius = math.max((job.high-job.low).Magnitude*0.5, 0.05)
	if radius ~= radius or radius == math.huge then return false end
	job.frame = UI.create("ViewportFrame", {
		Name = "KineThumbnail", BackgroundTransparency = 1, BorderSizePixel = 0,
		Active = false, InputSink = false, Ambient = Color3.new(0.7,0.7,0.7),
		LightDirection = Vector3.new(-1,-1,-1), Shadows = false,
		PostProcessing = false, UpdateRate = 1,
	}, storage)
	local camera = Instance.new("Camera", job.frame)
	camera.FieldOfView = 35
	job.frame.CurrentCamera = camera
	job.imported.Parent = job.frame
	-- Move the camera, rather than rewriting every Part's CFrame.
	place({frame=job.frame, path=job.path, center=center, radius=radius, count=job.count,
		expires=os.clock()+CACHE_SECONDS, generation=generation}, job.parent, job.fallback)
	return true
end

local function step()
	trimCache()
	if pending and (not alive(pending.parent) or not alive(pending.fallback)) then
		cleanup(pending)
		pending = nil
	end
	local ok, message = pcall(function()
		if not pending then
			for _ = 1, math.min(#queue, 12) do
				local job = table.remove(queue, 1)
				if alive(job.parent) and alive(job.fallback) then
					if not onScreen(job.fallback) then
						queue[#queue + 1] = job
						continue
					end
					if not cached(job.path, job.parent, job.fallback) and (failures[job.path] or 0) <= os.clock() then
						pending = job
						if not start(job) then
							cleanup(job)
							failures[job.path] = os.clock()+CACHE_SECONDS
							pending = nil
						end
					end
					-- Even cache hits and unsupported files share the per-frame limit.
					return
				end
			end
		elseif prepare(pending) then
			if not finish(pending) then
				failures[pending.path] = os.clock()+CACHE_SECONDS
				cleanup(pending)
			end
			pending = nil
		end
	end)
	if not ok and pending then
		failures[pending.path] = os.clock()+CACHE_SECONDS
		warn(`Could not preview {pending.path}: {message}`)
		cleanup(pending)
		pending = nil
	end
	if not pending and #queue == 0 and #cache == 0 then
		worker:Disconnect()
		worker = nil
	end
end

function Preview.Attach(parent, path, fallback)
	queue[#queue + 1] = {parent=parent, path=path, fallback=fallback}
	-- Signals retain the editor's capabilities; task.defer currently drops them.
	if not worker then worker = RunService.Heartbeat:Connect(step) end
end
return Preview

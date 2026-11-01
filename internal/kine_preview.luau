local UI = require("@internal/editor_ui")
local Export = game:GetService("ExportService")
local Preview = {}
local queue, running = {}, false

local function alive(object)
	local ok, parent = pcall(function() return object.Parent end)
	return ok and parent ~= nil
end

local function isPart(object)
	return object:IsA("Part") or object:IsA("BasePart")
end

local function populate(parent, path, fallback)
	local imported, frame
	local ok = pcall(function()
		imported = Export:ImportFile(path)
		if not imported or not (isPart(imported) or imported:IsA("Model")) then return end
		local parts = {}
		local function collect(object)
			if isPart(object) then parts[#parts + 1] = object end
			for _, child in ipairs(object:GetChildren()) do
				-- Preview geometry only: scripts, lights and adornments never enter the editor scene.
				if isPart(child) or child:IsA("Model") or child:IsA("Folder") then
					collect(child)
				else
					child:Destroy()
				end
			end
		end
		collect(imported)
		if #parts == 0 then return end
		local low, high = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
		for _, part in ipairs(parts) do
			local half = part.Size * 0.5
			for x = -1, 1, 2 do for y = -1, 1, 2 do for z = -1, 1, 2 do
				local p = part.CFrame:PointToWorldSpace(Vector3.new(half.X*x, half.Y*y, half.Z*z))
				low = Vector3.new(math.min(low.X,p.X),math.min(low.Y,p.Y),math.min(low.Z,p.Z))
				high = Vector3.new(math.max(high.X,p.X),math.max(high.Y,p.Y),math.max(high.Z,p.Z))
			end end end
		end
		local center, radius = (low + high)*0.5, math.max((high-low).Magnitude*0.5, 0.05)
		if radius ~= radius or radius == math.huge then return end
		for _, part in ipairs(parts) do part.CFrame = CFrame.new(-center) * part.CFrame end
		if not alive(parent) or not alive(fallback) then return end
		frame = UI.create("ViewportFrame", {
			Name = "KineThumbnail", Position = fallback.Position, Size = fallback.Size,
			BackgroundTransparency = 1, BorderSizePixel = 0, Active = false, InputSink = false,
			Ambient = Color3.new(0.7,0.7,0.7), LightDirection = Vector3.new(-1,-1,-1),
			Shadows = false, PostProcessing = false, UpdateRate = 5,
		}, parent)
		local camera = Instance.new("Camera", frame)
		camera.FieldOfView = 35
		local size = fallback.AbsoluteSize
		local aspect = size.Y > 0 and size.X / size.Y or 1
		local angle = math.atan(math.tan(math.rad(35)*0.5)*math.min(1,aspect))
		local distance = math.max(radius / math.sin(angle)*1.12, 0.25)
		camera.CFrame = CFrame.lookAt(Vector3.new(1,0.7,1).Unit*distance, Vector3.zero)
		frame.CurrentCamera = camera
		imported.Parent = frame
		fallback.Visible = false
	end)
	if not ok or not frame then
		if imported then pcall(function() imported:Destroy() end) end
		if frame then pcall(function() frame:Destroy() end) end
	end
end

function Preview.Attach(parent, path, fallback)
	queue[#queue + 1] = {parent, path, fallback}
	if running then return end
	running = true
	task.defer(function()
		while #queue > 0 do
			local job = table.remove(queue, 1)
			if alive(job[1]) and alive(job[3]) then populate(job[1],job[2],job[3]) end
			task.wait()
		end
		running = false
	end)
end
return Preview

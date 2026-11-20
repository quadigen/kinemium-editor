if IsServer or IsClient or IsPlaytest then
	return nil
end

local UI = require("@internal/editor_ui")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")
local colors, fonts = UI.tokens.color, UI.tokens.type
local Animator = {}
local LEFT, HEADER, ROW, TOOL, INSPECT, STATUS, PAD = 190, 25, 24, 34, 96, 24, 12
local FPS, MAX_TIME = 30, 36000
local panel, content = UI.window(
	"Animator",
	UDim2.fromScale(0.5, 0.76),
	UDim2.fromOffset(1080, 400),
	"Animation Editor",
	{ closable = true, closeIcon = "builtin://global-icons/x.svg" }
)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Parent = UI.widgetOverlay()
panel.Visible = false
panel.ClipsDescendants = true
content.ClipsDescendants = true

local connections = {}
local function connect(signal, callback)
	local c = signal:Connect(callback)
	table.insert(connections, c)
	return c
end
local function rect(parent, name, p, s, color, opaque)
	local o = UI.frame(parent, p, s, color or colors.panel)
	o.Name = name
	o.BorderSizePixel = 0
	o.BackgroundTransparency = opaque and 0 or 1
	return o
end
local function label(parent, text, p, s, color)
	local o = UI.label(parent, text, p, s, fonts.caption or fonts.small, color or colors.text)
	return o
end
local function input(parent, text, p, s)
	local o = UI.input(
		parent,
		text,
		p,
		s,
		{ selectAllOnFocus = true, caretColor = colors.accent, selectionColor = colors.selection }
	)
	o.Text = text
	return o
end
local function line(parent, p, s)
	local o = rect(parent, "Line", p, s, colors.border or colors.subtext, true)
	o.BackgroundTransparency = 0.48
	return o
end
local function clear(o)
	UI.clear(o)
end
local function safeDestroy(o)
	if o then
		pcall(function()
			o:Destroy()
		end)
	end
end
local function msg(s) -- assigned after constructing status bar
	print("[Animator] " .. tostring(s))
end

local toolbar = UI.create("ScrollingFrame", {
	Name = "Toolbar",
	Position = UDim2.fromOffset(0, 0),
	Size = UDim2.new(1, 0, 0, TOOL),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollingEnabled = true,
	ScrollingDirection = Enum.ScrollingDirection.X,
	ScrollBarThickness = 3,
	ScrollBarImageColor3 = colors.subtext,
	ScrollBarImageTransparency = 0.4,
	ScrollBarAutoHide = true,
	ClipsDescendants = true,
}, content)
local ruler = rect(content, "Ruler", UDim2.fromOffset(LEFT, TOOL), UDim2.new(1, -LEFT, 0, HEADER))
ruler.ClipsDescendants = true
local trackHeader =
	label(content, "  BONE CHANNELS", UDim2.fromOffset(0, TOOL), UDim2.fromOffset(LEFT, HEADER), colors.subtext)
local body = UI.create("ScrollingFrame", {
	Name = "Tracks",
	Position = UDim2.fromOffset(0, TOOL + HEADER),
	Size = UDim2.new(1, 0, 1, -TOOL - HEADER - INSPECT - STATUS),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	CanvasPosition = Vector2.new(0, 0),
	ScrollingEnabled = true,
	ScrollBarThickness = 4,
	ClipsDescendants = true,
	Active = true,
	InputSink = true,
}, content)
local rows = rect(body, "Rows", UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 0))
local grid = rect(body, "TimelineGrid", UDim2.fromOffset(LEFT, 0), UDim2.new(1, -LEFT, 0, 0))
grid.ClipsDescendants = true
local marks = rect(body, "Keyframes", UDim2.fromOffset(LEFT, 0), UDim2.new(1, -LEFT, 0, 0))
marks.ClipsDescendants = true
local playLayer =
	rect(content, "PlayheadLayer", UDim2.fromOffset(LEFT, TOOL), UDim2.new(1, -LEFT, 1, -TOOL - INSPECT - STATUS))
playLayer.ClipsDescendants = true
local playLine = rect(playLayer, "Playhead", UDim2.fromOffset(0, 0), UDim2.new(0, 1, 1, 0), colors.accent, true)
playLine.ZIndex = 8
local playTag = label(playLayer, "0", UDim2.fromOffset(0, 0), UDim2.fromOffset(32, HEADER - 2), colors.text)
playTag.BackgroundColor3 = colors.accent
playTag.BackgroundTransparency = 0
playTag.TextXAlignment = Enum.TextXAlignment.Center
playTag.ZIndex = 9
local inspector = rect(content, "Inspector", UDim2.new(0, 0, 1, -INSPECT - STATUS), UDim2.new(1, 0, 0, INSPECT))
local status = label(
	content,
	"Select a rigged MeshPart, then click Rig.",
	UDim2.new(0, 8, 1, -STATUS),
	UDim2.new(1, -16, 0, STATUS),
	colors.subtext
)
local pickerStatus
local pickerOpen = true
msg = function(s)
	status.Text = tostring(s)
	if pickerOpen and pickerStatus then
		pickerStatus.Text = tostring(s)
	end
end
line(content, UDim2.fromOffset(0, TOOL - 1), UDim2.new(1, 0, 0, 1))
line(content, UDim2.fromOffset(0, TOOL + HEADER - 1), UDim2.new(1, 0, 0, 1))
line(content, UDim2.fromOffset(LEFT - 1, TOOL), UDim2.new(0, 1, 1, -TOOL - STATUS - INSPECT))
line(inspector, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 1))

local rig, animation, sequence, controller, track
local ownsController = false
local saved = false
local bones, boneSet = {}, {}
local chosenBone, chosenTime
local cursor, first, span, endFrame = 0, 0, 120, 120
local playTime = 0
local playing = false
local drag
local clipboard
local history, future = {}, {}
local generated = setmetatable({}, { __mode = "k" })
local dirty = false
local destroyed = false
local render, seek, editFields, reload, pause, setPlaying, closeSession
local setMode, showPicker, pickerClick
local cancelPoseDrag, updatePoseDrag, finishPoseDrag, beginPoseDrag
local frameInput, endInput, nameInput, inspectorTitle, weightInput
local axisLabels = {}
local bindTransforms, boneDepth = {}, {}
local keyColor = Color3.fromRGB(227, 178, 92) -- data marker, not window chrome
local EPS = 0.000001
local function same(a, b)
	return a ~= nil and b ~= nil and math.abs(a - b) < EPS
end
local function frameOf(t)
	return t * FPS
end
local function timeOf(f)
	return f / FPS
end
local function finite(n)
	return n and n == n and math.abs(n) < math.huge
end
local function round(n)
	return math.floor(n + 0.5)
end
local function boundFrame(f)
	return math.clamp(round(f), 0, MAX_TIME * FPS)
end
local function maxFrame()
	local last = 0
	if sequence then
		for _, k in ipairs(sequence:GetKeyframes()) do
			last = math.max(last, frameOf(k.Time))
		end
	end
	return math.ceil(last)
end
local function eachPose(parent, visit)
	local children = parent:IsA("Keyframe") and parent:GetPoses() or parent:GetSubPoses()
	for _, p in ipairs(children) do
		visit(p)
		eachPose(p, visit)
	end
end
local function keyframesAt(t)
	local result = {}
	if sequence then
		for _, k in ipairs(sequence:GetKeyframes()) do
			if same(k.Time, t) then
				table.insert(result, k)
			end
		end
	end
	return result
end
local function findPose(bone, t)
	for _, k in ipairs(keyframesAt(t)) do
		local found
		eachPose(k, function(p)
			if p.Name == bone then
				found = p
			end
		end)
		if found then
			return found, k
		end
	end
	return nil, nil
end
local function makeKey(t)
	local matches = keyframesAt(t)
	if matches[1] then
		return matches[1]
	end
	local k = Instance.new("Keyframe")
	k.Time = t
	k.Name = "Frame_" .. tostring(round(frameOf(t)))
	sequence:AddKeyframe(k)
	generated[k] = true
	return k
end
local function poseData(p)
	return { cf = p.CFrame, weight = p.Weight }
end
local function insertPose(bone, t, data)
	local p = findPose(bone, t)
	if not p then
		p = Instance.new("Pose")
		p.Name = bone
		makeKey(t):AddPose(p)
	end
	p.CFrame, p.Weight = data.cf, data.weight
	return p
end
local function removePose(bone, t)
	local p, k = findPose(bone, t)
	if not p then
		return
	end
	local parent = p.Parent
	-- Preserve child channels when deleting just this bone's key.
	for _, child in ipairs(p:GetSubPoses()) do
		child.Parent = parent
	end
	p:Destroy()
	-- Authored event-only keyframes remain intact. Only prune our generated frames.
	if generated[k] and #k:GetPoses() == 0 and #k:GetMarkers() == 0 then
		generated[k] = nil
		sequence:RemoveKeyframe(k)
		k:Destroy()
	end
end

local previewAnimation, previewSequence
local function releaseTrack()
	if track then
		pcall(function()
			track:Stop(0)
		end)
	end
	if ownsController then
		safeDestroy(controller)
		controller = nil
		ownsController = false
	elseif track then
		-- Some engine builds expose Destroy on tracks, others only Stop.
		pcall(function()
			track:Destroy()
		end)
	end
	track = nil
	safeDestroy(previewAnimation)
	safeDestroy(previewSequence)
	previewAnimation, previewSequence = nil, nil
end
local suppliedHost
local function findHost()
	if suppliedHost then
		return suppliedHost, false
	end
	-- Reuse is opt-in; do not destroy/steal an existing character's Animator.
	for _, c in ipairs(rig:GetChildren()) do
		if c:IsA("AnimationController") or c:IsA("Animator") or c:IsA("Humanoid") then
			error("Rig already has an animation host. Pass it as the third argument to Open().")
		end
	end
	local host = Instance.new("AnimationController")
	host.Name = "__AnimatorPreview"
	host.MeshPart = rig
	host.Parent = rig
	return host, true
end
reload = function()
	releaseTrack()
	playing = false
	if not rig or not sequence then
		return false
	end
	local ok, err = pcall(function()
		previewSequence = sequence:Clone()
		previewSequence.Loop = false
		-- An empty draft still needs a compiled channel to show a bind pose.
		if #previewSequence:GetKeyframes() == 0 then
			local k = Instance.new("Keyframe")
			k.Time = 0
			previewSequence:AddKeyframe(k)
			for _, name in ipairs(bones) do
				local p = Instance.new("Pose")
				p.Name = name
				p.CFrame = CFrame.new()
				p.Weight = 1
				k:AddPose(p)
			end
		end
		local duration = timeOf(math.max(endFrame, maxFrame(), 1))
		local startExists, endExists = false, false
		for _, k in ipairs(previewSequence:GetKeyframes()) do
			startExists = startExists or same(k.Time, 0)
			endExists = endExists or same(k.Time, duration)
		end
		if not startExists then
			local k = Instance.new("Keyframe")
			k.Time = 0
			previewSequence:AddKeyframe(k)
		end
		if not endExists then
			local k = Instance.new("Keyframe")
			k.Time = duration
			previewSequence:AddKeyframe(k)
		end
		previewAnimation = Instance.new("Animation")
		previewSequence.Parent = previewAnimation
		previewAnimation.Source = previewSequence
		controller, ownsController = findHost()
		track = controller:LoadAnimation(previewAnimation)
		-- Keep a zero-speed track alive for deterministic manual scrubbing.
		track:Play(0, 1, 0)
		track.TimePosition = math.clamp(playTime, 0, track.Length)
	end)
	if not ok then
		releaseTrack()
		msg("Preview unavailable: " .. tostring(err))
		return false
	end
	return true
end
local function xFor(f)
	return PAD + (f - first) / span * math.max(1, ruler.AbsoluteSize.X - 2 * PAD)
end
local function frameFor(x)
	return boundFrame(first + (x - ruler.AbsolutePosition.X - PAD) / math.max(1, ruler.AbsoluteSize.X - 2 * PAD) * span)
end
local function displayHead()
	local f = frameOf(playTime)
	local x = xFor(f)
	local show = f >= first and f <= first + span
	playLine.Visible, playTag.Visible = show, show
	playLine.Position = UDim2.fromOffset(x, 0)
	playTag.Position = UDim2.fromOffset(math.clamp(x - 16, 0, math.max(0, ruler.AbsoluteSize.X - 32)), 0)
	playTag.Text = tostring(round(f))
	if frameInput then
		local focused = UIS:GetFocusedTextBox()
		if focused ~= frameInput then
			frameInput.Text = tostring(cursor)
		end
	end
end
local function follow(f)
	if f < first then
		first = math.max(0, f)
	elseif f > first + span then
		first = math.max(0, f - span * 0.8)
	end
end
local function applyPreview(t)
	if track then
		local ok, err = pcall(function()
			if not track.IsPlaying then
				track:Play(0, 1, 0)
			end
			track.TimePosition = math.clamp(t, 0, track.Length)
		end)
		if not ok then
			msg("Scrub failed: " .. tostring(err))
		end
	end
end
pause = function()
	playing = false
	if track then
		pcall(function()
			track:AdjustSpeed(0)
		end)
	end
end
seek = function(frame, keepSelection, exact)
	pause()
	cursor = boundFrame(frame)
	if not keepSelection then
		chosenTime = chosenBone and timeOf(cursor) or nil
	end
	playTime = exact or timeOf(cursor)
	applyPreview(playTime)
	local old = first
	follow(frameOf(playTime))
	if first ~= old then
		render()
	else
		displayHead()
	end
	if not keepSelection then
		editFields()
	end
end

local function snapshot()
	local clone = sequence:Clone()
	local flags = {}
	for i, k in ipairs(sequence:GetKeyframes()) do
		flags[i] = generated[k] == true
	end
	return { source = clone, flags = flags }
end
local function disposeStack(stack)
	for _, s in ipairs(stack) do
		safeDestroy(s.source)
	end
	table.clear(stack)
end
local function checkpoint()
	table.insert(history, snapshot())
	if #history > 20 then
		safeDestroy(table.remove(history, 1).source)
	end
	disposeStack(future)
end
local function restore(snapshotData)
	local s = snapshotData.source
	-- Keep the source instance itself stable for the weak Animation.Source reference.
	for _, k in ipairs(sequence:GetKeyframes()) do
		k:Destroy()
	end
	sequence.Name, sequence.Loop, sequence.Priority = s.Name, s.Loop, s.Priority
	generated = setmetatable({}, { __mode = "k" })
	for i, k in ipairs(s:GetKeyframes()) do
		local copy = k:Clone()
		sequence:AddKeyframe(copy)
		if snapshotData.flags[i] then
			generated[copy] = true
		end
	end
	nameInput.Text = sequence.Name
	if saved and animation then
		animation.Name = sequence.Name
	end
	safeDestroy(s)
end
local function commit(message)
	dirty = true
	endFrame = math.max(endFrame, maxFrame(), 1)
	endInput.Text = tostring(endFrame)
	playTime = chosenTime or timeOf(cursor)
	cursor = boundFrame(frameOf(playTime))
	render()
	editFields()
	if reload() then
		msg(message)
	end
end
local function undo(redo)
	if not sequence then
		return
	end
	local from, to = redo and future or history, redo and history or future
	if #from == 0 then
		msg(redo and "Nothing to redo." or "Nothing to undo.")
		return
	end
	pause()
	table.insert(to, snapshot())
	restore(table.remove(from))
	commit(redo and "Redone." or "Undone.")
end
local function interpolate(bone, t)
	local before, after, bt, at
	for _, k in ipairs(sequence:GetKeyframes()) do
		eachPose(k, function(p)
			if p.Name ~= bone then
				return
			end
			if k.Time <= t and (not bt or k.Time > bt) then
				before, bt = p, k.Time
			end
			if k.Time >= t and (not at or k.Time < at) then
				after, at = p, k.Time
			end
		end)
	end
	if before and after and not same(bt, at) then
		local a = (t - bt) / (at - bt)
		local ok, cf = pcall(function()
			return before.CFrame:Lerp(after.CFrame, a)
		end)
		return { cf = ok and cf or before.CFrame, weight = before.Weight + (after.Weight - before.Weight) * a }
	end
	if before or after then
		return poseData(before or after)
	end
	return { cf = CFrame.new(), weight = 1 }
end
local function getNumbers(data)
	local cf = data.cf
	local v = cf.Position
	local rx, ry, rz
	local ok = pcall(function()
		rx, ry, rz = cf:ToEulerAnglesXYZ()
	end)
	if not ok or not finite(rx) or not finite(ry) or not finite(rz) then
		-- XYZ decomposition from the local basis for builds without the helper.
		ok = pcall(function()
			local r, u, b = cf.RightVector, cf.UpVector, -cf.LookVector
			ry = math.asin(math.clamp(b.X, -1, 1))
			if math.abs(math.cos(ry)) > 0.00001 then
				rx = math.atan2(-b.Y, b.Z)
				rz = math.atan2(-u.X, r.X)
			else
				rx = math.atan2(u.Z, u.Y)
				rz = 0
			end
		end)
	end
	if not ok or not finite(rx) or not finite(ry) or not finite(rz) then
		return nil
	end
	return { v.X, v.Y, v.Z, math.deg(rx), math.deg(ry), math.deg(rz), data.weight }
end
editFields = function()
	if not chosenBone or not sequence then
		inspectorTitle.Text = "Select a bone channel to edit a pose"
		if weightInput then
			weightInput.Text = ""
		end
		return
	end
	local t = chosenTime or timeOf(cursor)
	local p = findPose(chosenBone, t)
	inspectorTitle.Text = chosenBone
		.. "  |  "
		.. string.format("Frame %.2f", frameOf(t))
		.. (p and "  •  keyframe" or "  •  sampled pose")
	if weightInput then
		weightInput.Text = string.format("%.3g", (p and poseData(p) or interpolate(chosenBone, t)).weight)
	end
end
local function dataFromNumbers(v)
	return {
		cf = CFrame.new(v[1], v[2], v[3]) * CFrame.Angles(math.rad(v[4]), math.rad(v[5]), math.rad(v[6])),
		weight = math.clamp(v[7], 0, 1),
	}
end
local function dragValues(d, delta)
	local v = table.clone(d.values)
	v[d.axis] += delta
	return v
end

local function startDragPreview(d)
	-- A game-owned animator still owns the mesh pose. Never override its tracks.
	if suppliedHost then
		return false
	end
	releaseTrack()
	local transforms = {}
	for _, bone in ipairs(bones) do
		local bind = bindTransforms[bone]
		if bind then
			local data = interpolate(bone, d.t)
			transforms[bone] = bind * CFrame.new():Lerp(data.cf, data.weight)
		end
	end
	local ok, applied = pcall(function()
		return rig:SetBoneTransforms(transforms)
	end)
	if not ok or not applied then
		msg("Direct bone preview unavailable. The pose will be applied on release.")
		return false
	end
	return true
end
beginPoseDrag = function(axis, mouseX)
	if not chosenBone or not sequence or drag then
		return
	end
	pause()
	local t = chosenTime or timeOf(cursor)
	local p = findPose(chosenBone, t)
	local v = getNumbers(p and poseData(p) or interpolate(chosenBone, t))
	if not v then
		msg("Cannot read this bone transform.")
		return
	end
	local range = 180
	if axis <= 3 then
		local size = rig.Size
		range = math.clamp(size.Magnitude * 0.75, 2, 1000)
	end
	drag = {
		kind = "pose",
		bone = chosenBone,
		t = t,
		axis = axis,
		values = v,
		startX = mouseX,
		range = range,
		delta = 0,
		moved = false,
		preview = false,
	}
end
updatePoseDrag = function(d, mouseX)
	local dx = mouseX - d.startX
	if not d.moved then
		if math.abs(dx) < 3 then
			return
		end
		d.moved = true
		d.preview = startDragPreview(d)
	end
	local fine = UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)
	local delta = math.clamp(dx * d.range / (fine and 1800 or 360), -d.range, d.range)
	d.delta = delta
	if d.preview then
		local data = dataFromNumbers(dragValues(d, delta))
		local bind = bindTransforms[d.bone]
		if bind then
			local ok = pcall(function()
				rig:SetBoneTransform(d.bone, bind * CFrame.new():Lerp(data.cf, data.weight))
			end)
			if not ok then
				d.preview = false
			end
		end
	end
end
finishPoseDrag = function(d)
	if not d.moved or not sequence then
		return
	end
	if math.abs(d.delta) < EPS then
		if d.preview or not track then
			reload()
		end
		editFields()
		return
	end
	checkpoint()
	chosenBone, chosenTime = d.bone, d.t
	cursor = boundFrame(frameOf(d.t))
	insertPose(d.bone, d.t, dataFromNumbers(dragValues(d, d.delta)))
	commit("Moved " .. d.bone .. " — keyframe set at frame " .. tostring(cursor))
end
cancelPoseDrag = function()
	if not drag or drag.kind ~= "pose" then
		return false
	end
	local d = drag
	drag = nil
	if d.moved and sequence then
		reload()
	end
	editFields()
	msg("Bone edit cancelled.")
	return true
end
local function resetPose()
	if not chosenBone or not sequence then
		return
	end
	pause()
	checkpoint()
	chosenTime = chosenTime or timeOf(cursor)
	insertPose(chosenBone, chosenTime, { cf = CFrame.new(), weight = 1 })
	commit("Reset " .. chosenBone .. " to its local bind pose.")
end

local function addKey(all)
	if not sequence or (not all and not chosenBone) then
		msg("Select a rig and bone first.")
		return
	end
	local t = timeOf(cursor)
	checkpoint()
	for _, b in ipairs(all and bones or { chosenBone }) do
		if not findPose(b, t) then
			insertPose(b, t, interpolate(b, t))
		end
	end
	chosenTime = t
	commit(all and "Keyed all bones." or "Keyframe inserted.")
end
local function deleteKey()
	if not sequence or not chosenBone or not chosenTime or not findPose(chosenBone, chosenTime) then
		msg("Select a diamond to delete.")
		return
	end
	checkpoint()
	removePose(chosenBone, chosenTime)
	commit("Keyframe removed.")
end
local function moveKey(bone, old, new)
	if same(old, new) then
		return
	end
	local p = findPose(bone, old)
	if not p then
		return
	end
	if findPose(bone, new) then
		msg("Destination already has a key for this bone.")
		return
	end
	checkpoint()
	local data = poseData(p)
	removePose(bone, old)
	insertPose(bone, new, data)
	chosenBone, chosenTime, cursor = bone, new, boundFrame(frameOf(new))
	commit("Keyframe moved.")
end
local function copyKey()
	local p = chosenBone and chosenTime and findPose(chosenBone, chosenTime)
	if p then
		clipboard = poseData(p)
		msg("Pose copied.")
	else
		msg("Select a diamond to copy.")
	end
end
local function pasteKey()
	if not clipboard or not chosenBone or not sequence then
		msg("Copy a pose and select a target bone.")
		return
	end
	checkpoint()
	chosenTime = timeOf(cursor)
	insertPose(chosenBone, chosenTime, clipboard)
	commit("Pose pasted.")
end
local function neighbor(dir)
	if not sequence then
		return
	end
	local current, nextTime = playTime, nil
	for _, k in ipairs(sequence:GetKeyframes()) do
		local p = not chosenBone or findPose(chosenBone, k.Time)
		if
			p
			and (
				(dir > 0 and k.Time > current + EPS and (not nextTime or k.Time < nextTime))
				or (dir < 0 and k.Time < current - EPS and (not nextTime or k.Time > nextTime))
			)
		then
			nextTime = k.Time
		end
	end
	if nextTime then
		chosenTime = nextTime
		seek(frameOf(nextTime), true, nextTime)
		render()
		editFields()
	end
end
setPlaying = function()
	if not sequence or not track then
		msg("Load a rig before playing.")
		return
	end
	if playing then
		pause()
		msg("Paused.")
		return
	end
	if playTime >= timeOf(endFrame) then
		playTime = 0
		cursor = 0
	end
	playing = true
	msg("Playing " .. sequence.Name)
end

local markers = {}
render = function()
	if destroyed or pickerOpen then
		return
	end
	clear(rows)
	clear(grid)
	clear(marks)
	clear(ruler)
	table.clear(markers)
	local h = #bones * ROW
	local viewH = math.max(body.AbsoluteSize.Y, h)
	rows.Size = UDim2.new(1, 0, 0, h)
	grid.Size = UDim2.new(1, -LEFT, 0, viewH)
	marks.Size = UDim2.new(1, -LEFT, 0, h)
	body.CanvasSize = UDim2.fromOffset(0, h)
	local width = math.max(1, ruler.AbsoluteSize.X - 2 * PAD)
	local interval = 1
	for _, step in ipairs({
		1,
		2,
		5,
		10,
		12,
		15,
		24,
		30,
		60,
		120,
		240,
		300,
		600,
		1200,
		3000,
		6000,
		12000,
		30000,
		60000,
		120000,
		300000,
		600000,
	}) do
		interval = step
		if width / span * step >= 53 then
			break
		end
	end
	local minor = interval >= 5 and interval / (interval % 5 == 0 and 5 or 4) or interval
	for f = math.ceil(first / minor) * minor, first + span, minor do
		local x = xFor(f)
		local major = math.abs(f / interval - round(f / interval)) < EPS
		local tick = line(grid, UDim2.fromOffset(x, 0), UDim2.new(0, 1, 1, 0))
		tick.BackgroundTransparency = major and 0.35 or 0.75
		if major then
			local l = label(
				ruler,
				tostring(round(f)),
				UDim2.fromOffset(x + 3, 0),
				UDim2.fromOffset(54, HEADER),
				colors.subtext
			)
			l.TextXAlignment = Enum.TextXAlignment.Left
		end
	end
	for i, b in ipairs(bones) do
		local y = (i - 1) * ROW
		if b == chosenBone then
			local bg = rect(
				rows,
				"Selected",
				UDim2.fromOffset(0, y),
				UDim2.new(1, 0, 0, ROW),
				colors.selection or colors.accent,
				true
			)
			bg.BackgroundTransparency = 0.58
		end
		local title = label(
			rows,
			b,
			UDim2.fromOffset(23 + math.min(boneDepth[b] or 0, 6) * 12, y),
			UDim2.fromOffset(LEFT - 28 - math.min(boneDepth[b] or 0, 6) * 12, ROW),
			b == chosenBone and colors.accent or colors.text
		)
		title.TextTruncate = Enum.TextTruncate.AtEnd
		UI.image(
			rows,
			"builtin://icons/Attachment.svg",
			UDim2.fromOffset(5 + math.min(boneDepth[b] or 0, 6) * 12, y + 5),
			UDim2.fromOffset(14, 14)
		)
		line(rows, UDim2.fromOffset(0, y + ROW - 1), UDim2.new(1, 0, 0, 1)).BackgroundTransparency = 0.72
	end
	if sequence then
		local index = {}
		for i, b in ipairs(bones) do
			index[b] = i
		end
		for _, k in ipairs(sequence:GetKeyframes()) do
			local f = frameOf(k.Time)
			if f < first or f > first + span then
				continue
			end
			eachPose(k, function(p)
				local i = index[p.Name]
				if not i then
					return
				end
				local x, y = xFor(f), (i - 0.5) * ROW
				local selected = p.Name == chosenBone and same(k.Time, chosenTime)
				local diamond = rect(
					marks,
					"Keyframe",
					UDim2.fromOffset(x, y),
					UDim2.fromOffset(9, 9),
					selected and (colors.accent or keyColor) or keyColor,
					true
				)
				diamond.AnchorPoint = Vector2.new(0.5, 0.5)
				diamond.Rotation = 45
				diamond.ZIndex = 5
				table.insert(markers, { bone = p.Name, t = k.Time, x = x, y = y, visual = diamond })
			end)
		end
	end
	displayHead()
end

local function closeDraft()
	if not saved then
		safeDestroy(animation)
	end
	animation, sequence = nil, nil
end
closeSession = function()
	pause()
	drag = nil
	releaseTrack()
	closeDraft()
	disposeStack(history)
	disposeStack(future)
	rig, suppliedHost = nil, nil
	bones, boneSet = {}, {}
	bindTransforms, boneDepth = {}, {}
	chosenBone, chosenTime = nil, nil
	saved, dirty = false, false
	generated = setmetatable({}, { __mode = "k" })
end
local function openRig(mesh, source, host, newName)
	if not mesh or not mesh:IsA("MeshPart") then
		msg("Select a rigged MeshPart in Explorer.")
		return false
	end
	local ok, names = pcall(function()
		return mesh:GetBoneNames()
	end)
	if not ok or type(names) ~= "table" or #names == 0 then
		msg("No bones found. Wait for the mesh to load, or choose a skinned mesh.")
		return false
	end
	if source and not (source:IsA("Animation") or source:IsA("KeyframeSequence")) then
		msg("Expected Animation or KeyframeSequence.")
		return false
	end
	local seq, anim
	if source and source:IsA("Animation") then
		anim, seq = source, source.Source
		if not seq or not seq:IsA("KeyframeSequence") then
			msg("Imported clips are playback-only here; choose an Animation with a KeyframeSequence source.")
			return false
		end
	elseif source then
		seq = source
		if seq.Parent and seq.Parent:IsA("Animation") and seq.Parent.Source == seq then
			anim = seq.Parent
		end
	end
	if not saved and dirty and sequence then
		msg("Save your current draft or use Animator.Discard() before switching rigs.")
		return false
	end
	if sequence and seq == sequence and mesh == rig then
		if setMode then
			setMode(false)
		end
		panel.Visible = true
		if not track then
			reload()
		end
		render()
		editFields()
		return true
	end
	closeSession()
	rig, suppliedHost = mesh, host
	local seen = {}
	for _, b in ipairs(names) do
		if not seen[b] then
			seen[b] = true
			table.insert(bones, b)
			boneSet[b] = true
		end
	end
	-- Order channels by the actual skeleton hierarchy.
	local children, roots = {}, {}
	for _, bone in ipairs(bones) do
		local okBind, bind = pcall(function()
			return mesh:GetBoneBindTransform(bone)
		end)
		bindTransforms[bone] = okBind and bind or mesh:GetBoneTransform(bone)
		local parent = mesh:GetBoneParent(bone)
		if parent and boneSet[parent] and parent ~= bone then
			children[parent] = children[parent] or {}
			table.insert(children[parent], bone)
		else
			table.insert(roots, bone)
		end
	end
	local ordered, visited = {}, {}
	local function visit(bone, depth)
		if visited[bone] then
			return
		end
		visited[bone], boneDepth[bone] = true, depth
		table.insert(ordered, bone)
		for _, child in ipairs(children[bone] or {}) do
			visit(child, depth + 1)
		end
	end
	for _, bone in ipairs(roots) do
		visit(bone, 0)
	end
	for _, bone in ipairs(bones) do
		visit(bone, 0)
	end
	bones = ordered
	chosenBone, chosenTime = bones[1], 0
	if seq then
		sequence, animation, saved = seq, anim, true
	else
		animation = Instance.new("Animation")
		animation.Name = newName or "NewAnimation"
		sequence = Instance.new("KeyframeSequence")
		sequence.Name = animation.Name
		sequence.Priority = Enum.AnimationPriority.Action
		sequence.Parent = animation
		animation.Source = sequence
	end
	cursor, playTime, first = 0, 0, 0
	endFrame = math.max(120, maxFrame())
	span = endFrame
	body.CanvasPosition = Vector2.new(0, 0)
	nameInput.Text, endInput.Text = sequence.Name, tostring(endFrame)
	trackHeader.Text = "  " .. mesh.Name .. "  /  " .. tostring(#bones) .. " bones"
	if setMode then
		setMode(false)
	end
	panel.Visible = true
	render()
	editFields()
	if reload() then
		msg("Loaded " .. mesh.Name .. ". Select a bone and drag an axis label to pose it.")
	end
	return true
end
local function selectedObjects()
	local ok, selected = pcall(function()
		return Selection:Get()
	end)
	if not ok then
		selected = nil
	end
	if type(selected) ~= "table" then
		return nil, nil
	end
	local mesh, source
	for _, obj in ipairs(selected) do
		if obj:IsA("MeshPart") then
			mesh = obj
		elseif obj:IsA("Animation") or obj:IsA("KeyframeSequence") then
			source = obj
		elseif obj:IsA("Model") and not mesh then
			for _, d in ipairs(obj:GetDescendants()) do
				if d:IsA("MeshPart") then
					local success, n = pcall(function()
						return d:GetBoneNames()
					end)
					if success and type(n) == "table" and #n > 0 then
						mesh = d
						break
					end
				end
			end
		end
	end
	if not mesh and source then
		local p = source.Parent
		while p and not p:IsA("MeshPart") do
			p = p.Parent
		end
		mesh = p
	end
	return mesh, source
end
local function save()
	if not sequence or not rig then
		msg("Nothing to save.")
		return
	end
	local n = string.match(nameInput.Text, "^%s*(.-)%s*$")
	if n == "" then
		msg("Enter an animation name.")
		return
	end
	if not animation then
		animation = Instance.new("Animation")
		animation.Source = sequence
	end
	sequence.Name, animation.Name = n, n
	animation.Looped = sequence.Loop
	animation.Priority = sequence.Priority
	if not sequence.Parent then
		sequence.Parent = animation
	end
	if not animation.Parent then
		animation.Parent = rig
	end
	saved, dirty = true, false
	msg("Saved " .. n .. " as an Animation instance. Save the project to persist it.")
end

local x = 6
local function tool(text, w, callback, tip, icon)
	local o, _, rec = UI.button(
		toolbar,
		text,
		UDim2.fromOffset(x, 4),
		UDim2.fromOffset(w, 24),
		callback,
		icon and { icon = icon, iconSize = 14 } or {}
	)
	if tip and UI.tooltip then
		UI.tooltip(o, tip)
	end
	x += w + 3
	return o, rec
end
tool("Rig", 45, function()
	showPicker()
end, "Choose a rig or start a new animation")
tool("Save", 49, save)
tool("First", 42, function()
	seek(0)
end, "First frame")
tool("Prev", 42, function()
	neighbor(-1)
end, "Previous keyframe")
local playButton, playRecord = tool("Play", 44, function()
	setPlaying()
end, "Play / pause")
tool("Next", 42, function()
	neighbor(1)
end, "Next keyframe")
tool("Last", 42, function()
	seek(endFrame)
end, "Last frame")
tool("Key", 48, function()
	addKey(false)
end, "Insert a key for the selected bone")
tool("Key all", 56, function()
	addKey(true)
end, "Key every bone")
tool("Delete", 60, deleteKey)
tool("Undo", 48, function()
	undo(false)
end)
tool("Redo", 48, function()
	undo(true)
end)
tool("Zoom out", 68, function()
	span = math.min(MAX_TIME * FPS, span * 1.5)
	render()
end, "Zoom out")
tool("Zoom in", 62, function()
	span = math.max(5, span / 1.5)
	follow(cursor)
	render()
end, "Zoom in")
tool("Fit", 36, function()
	first = 0
	span = math.max(endFrame, 5)
	render()
end)
tool("Earlier", 53, function()
	first = math.max(0, first - span / 2)
	render()
end, "Pan earlier")
tool("Later", 47, function()
	first = math.min(MAX_TIME * FPS - span, first + span / 2)
	render()
end, "Pan later")
local loopRecord
local _loopButton
_loopButton, loopRecord = tool("Loop", 48, function()
	if not sequence then
		return
	end
	checkpoint()
	sequence.Loop = not sequence.Loop
	dirty = true
	if loopRecord then
		UI.setButtonState(loopRecord, sequence.Loop and "selected" or nil)
	end
	msg(sequence.Loop and "Loop on." or "Loop off.")
end)
label(toolbar, "Frame", UDim2.fromOffset(x, 0), UDim2.fromOffset(42, TOOL), colors.subtext)
x += 43
frameInput = input(toolbar, "0", UDim2.fromOffset(x, 4), UDim2.fromOffset(54, 26))
x += 58
label(toolbar, "End", UDim2.fromOffset(x, 0), UDim2.fromOffset(29, TOOL), colors.subtext)
x += 30
endInput = input(toolbar, "120", UDim2.fromOffset(x, 4), UDim2.fromOffset(58, 24))
toolbar.CanvasSize = UDim2.fromOffset(x + 64, 0)

inspectorTitle = label(
	inspector,
	"Select a bone channel to edit a pose",
	UDim2.fromOffset(8, 3),
	UDim2.new(1, -16, 0, 24),
	colors.subtext
)
nameInput = input(inspector, "NewAnimation", UDim2.new(1, -174, 0, 4), UDim2.fromOffset(166, 23))
inspectorTitle.Size = UDim2.new(1, -190, 0, 24)
local fieldLabels = { "Move X", "Move Y", "Move Z", "Rotate X", "Rotate Y", "Rotate Z" }
for i, title in ipairs(fieldLabels) do
	local axis, group = (i - 1) % 3 + 1, math.floor((i - 1) / 3)
	local button = UI.button(
		inspector,
		title,
		UDim2.new((i - 1) / 6, 4, 0, 31),
		UDim2.new(1 / 6, -8, 0, UI.metrics.buttonHeight),
		nil,
		{
			textColor = ({ UI.axisColors.X, UI.axisColors.Y, UI.axisColors.Z })[axis] or colors.text,
		}
	)
	axisLabels[i] = button
	UI.tooltip(
		button,
		(group == 0 and "Move" or "Rotate") .. " the selected bone. Drag horizontally; Shift for precision."
	)
end
UI.button(inspector, "Copy", UDim2.fromOffset(8, 60), UDim2.fromOffset(58, 24), copyKey, {})
UI.button(inspector, "Paste", UDim2.fromOffset(70, 60), UDim2.fromOffset(58, 24), pasteKey, {})
UI.button(inspector, "Reset", UDim2.fromOffset(132, 60), UDim2.fromOffset(68, 24), resetPose, {})
label(inspector, "Weight", UDim2.fromOffset(208, 60), UDim2.fromOffset(48, 24), colors.subtext)
weightInput = input(inspector, "1", UDim2.fromOffset(256, 60), UDim2.fromOffset(48, 24))
UI.tooltip(weightInput, "Blend weight of the selected bone pose")
connect(weightInput.FocusLost, function()
	local n = tonumber(weightInput.Text)
	if not chosenBone or not sequence or not finite(n) then
		editFields()
		return
	end
	local t = chosenTime or timeOf(cursor)
	local p = findPose(chosenBone, t)
	local data = p and poseData(p) or interpolate(chosenBone, t)
	n = math.clamp(n, 0, 1)
	if math.abs(n - data.weight) < 0.00001 then
		editFields()
		return
	end
	pause()
	checkpoint()
	insertPose(chosenBone, t, { cf = data.cf, weight = n })
	chosenTime = t
	commit("Updated pose weight.")
end)
label(
	inspector,
	"Drag an axis to pose the bone. Shift for precision; Esc to cancel.",
	UDim2.fromOffset(312, 60),
	UDim2.new(1, -320, 0, 20),
	colors.subtext
)
connect(frameInput.FocusLost, function()
	local n = tonumber(frameInput.Text)
	if finite(n) then
		seek(n)
		render()
	else
		frameInput.Text = tostring(cursor)
	end
end)
connect(endInput.FocusLost, function()
	local n = tonumber(endInput.Text)
	if finite(n) then
		endFrame = math.max(1, maxFrame(), boundFrame(n))
		if playTime > timeOf(endFrame) then
			seek(endFrame)
		end
		if sequence then
			reload()
		end
	end
	endInput.Text = tostring(endFrame)
end)

local function inside(o, p)
	local a, s = o.AbsolutePosition, o.AbsoluteSize
	return p.X >= a.X and p.Y >= a.Y and p.X < a.X + s.X and p.Y < a.Y + s.Y
end
local timelineChildren = {}
for _, child in ipairs(content:GetChildren()) do
	if child:IsA("GuiObject") then
		table.insert(timelineChildren, child)
	end
end
local picker = rect(content, "RigPicker", UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1))
local pickerTitle =
	label(picker, "Create an animation", UDim2.fromOffset(16, 8), UDim2.new(0.55, -195, 0, 25), colors.text)
label(
	picker,
	"Choose a rigged MeshPart from the scene, name the animation, then press Start.",
	UDim2.fromOffset(16, 35),
	UDim2.new(1, -32, 0, 21),
	colors.subtext
)
local searchBox = UI.input(
	picker,
	"Filter rigs...",
	UDim2.fromOffset(16, 64),
	UDim2.new(0.55, -20, 0, 26),
	{ selectAllOnFocus = false }
)
searchBox.Text = ""
local rigList = UI.create("ScrollingFrame", {
	Name = "RigList",
	Position = UDim2.fromOffset(16, 100),
	Size = UDim2.new(0.55, -20, 1, -140),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	CanvasPosition = Vector2.new(0, 0),
	ScrollBarThickness = 5,
	ScrollingEnabled = true,
	Active = true,
	InputSink = true,
	ClipsDescendants = true,
}, picker)
local rigRows = rect(rigList, "RigRows", UDim2.fromOffset(0, 0), UDim2.new(1, -6, 0, 0))
line(picker, UDim2.new(0.55, 8, 0, 64), UDim2.new(0, 1, 1, -104))
local detail = rect(picker, "RigDetails", UDim2.new(0.55, 20, 0, 64), UDim2.new(0.45, -36, 1, -104))
label(detail, "SELECTED RIG", UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 21), colors.subtext)
local selectedRigName = label(detail, "No rig selected", UDim2.fromOffset(0, 23), UDim2.new(1, 0, 0, 25), colors.text)
selectedRigName.TextTruncate = Enum.TextTruncate.AtEnd
local selectedRigInfo = label(
	detail,
	"Select a MeshPart containing bones.",
	UDim2.fromOffset(0, 49),
	UDim2.new(1, 0, 0, 38),
	colors.subtext
)
selectedRigInfo.TextWrapped = true
label(detail, "Animation name", UDim2.fromOffset(0, 95), UDim2.new(1, 0, 0, 20), colors.subtext)
local pickerName = input(detail, "NewAnimation", UDim2.fromOffset(0, 117), UDim2.new(1, 0, 0, 26))
local startButton, _, startRecord = UI.button(
	detail,
	"Start",
	UDim2.fromOffset(0, 153),
	UDim2.new(1, 0, 0, 30),
	function()
		if Animator.StartSelected then
			Animator.StartSelected()
		end
	end,
	{}
)
local backButton = UI.button(picker, "Back", UDim2.new(1, -80, 0, 12), UDim2.fromOffset(64, 26), function()
	if sequence then
		setMode(false)
		if not track then
			reload()
		end
		render()
		editFields()
	else
		panel.Visible = false
	end
end, {})
local discardButton = UI.button(
	detail,
	"Discard draft",
	UDim2.new(0.5, 3, 0, 191),
	UDim2.new(0.5, -3, 0, 26),
	function()
		if sequence and not saved then
			closeSession()
			showPicker()
			msg("Draft discarded. Choose a rig to start again.")
		end
	end,
	{}
)
pickerStatus =
	label(picker, "Looking for rigged MeshParts...", UDim2.new(0, 16, 1, -32), UDim2.new(1, -32, 0, 25), colors.subtext)
local rigEntries, filteredRigs = {}, {}
local selectedEntry
local reuseExisting = false
local reuseButton, reuseRecord
local _reuseUnused
reuseButton, _reuseUnused, reuseRecord = UI.button(
	detail,
	"Reuse host",
	UDim2.fromOffset(0, 191),
	UDim2.new(0.5, -3, 0, 26),
	function()
		reuseExisting = not reuseExisting
		if reuseRecord then
			UI.setButtonState(reuseRecord, reuseExisting and "selected" or nil)
		end
		msg(
			reuseExisting and "Existing host allowed. Stop competing tracks before editing."
				or "Use a temporary animation host only."
		)
	end,
	{}
)
if UI.tooltip then
	UI.tooltip(
		reuseButton,
		"Allow preview on an existing AnimationController, Animator or Humanoid. Does not stop other tracks; drag preview updates on release."
	)
end
local function existingHost(mesh)
	for _, c in ipairs(mesh:GetChildren()) do
		if
			not (ownsController and c == controller)
			and (c:IsA("AnimationController") or c:IsA("Animator") or c:IsA("Humanoid"))
		then
			return c
		end
	end
	return nil
end
local scanRevision = 0
local PICK_ROW = 29
local function entryFor(mesh)
	if not mesh or not mesh.Parent or not mesh:IsA("MeshPart") then
		return nil
	end
	local ok, names = pcall(function()
		return mesh:GetBoneNames()
	end)
	if not ok or type(names) ~= "table" or #names == 0 then
		return nil
	end
	local path = mesh.Name
	pcall(function()
		path = mesh:GetFullName()
	end)
	return { mesh = mesh, name = mesh.Name, path = path, count = #names }
end
local function updatePickerSelection()
	selectedRigName.Text = selectedEntry and selectedEntry.name or "No rig selected"
	selectedRigInfo.Text = selectedEntry and (tostring(selectedEntry.count) .. " bones  •  " .. selectedEntry.path)
		or "Select a MeshPart containing bones."
	if startRecord then
		UI.setButtonState(startRecord, selectedEntry and "selected" or nil)
	end
	discardButton.Visible = sequence ~= nil and not saved
	local host = selectedEntry and selectedEntry.mesh.Parent and existingHost(selectedEntry.mesh)
	reuseButton.Visible = host ~= nil
	if not host then
		reuseExisting = false
	end
	if reuseRecord then
		UI.setButtonState(reuseRecord, reuseExisting and "selected" or nil)
	end
end
local function drawPickerRows()
	if destroyed or not pickerOpen then
		return
	end
	clear(rigRows)
	local h = #filteredRigs * PICK_ROW
	rigRows.Size = UDim2.new(1, -6, 0, h)
	local top = math.max(1, math.floor(rigList.CanvasPosition.Y / PICK_ROW))
	local bottom = math.min(#filteredRigs, top + math.ceil(rigList.AbsoluteSize.Y / PICK_ROW) + 3)
	for i = top, bottom do
		local e = filteredRigs[i]
		local y = (i - 1) * PICK_ROW
		if selectedEntry and e.mesh == selectedEntry.mesh then
			local bg = rect(
				rigRows,
				"SelectedRig",
				UDim2.fromOffset(0, y),
				UDim2.new(1, 0, 0, PICK_ROW),
				colors.selection or colors.accent,
				true
			)
			bg.BackgroundTransparency = 0.55
		end
		local name = label(
			rigRows,
			"◇  " .. e.path,
			UDim2.fromOffset(8, y),
			UDim2.new(1, -94, 0, PICK_ROW),
			selectedEntry and e.mesh == selectedEntry.mesh and colors.accent or colors.text
		)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local count = label(
			rigRows,
			tostring(e.count) .. " bones",
			UDim2.new(1, -85, 0, y),
			UDim2.fromOffset(77, PICK_ROW),
			colors.subtext
		)
		count.TextXAlignment = Enum.TextXAlignment.Right
		line(rigRows, UDim2.fromOffset(0, y + PICK_ROW - 1), UDim2.new(1, 0, 0, 1)).BackgroundTransparency = 0.8
	end
end
local function filterRigs(resetScroll)
	local q = string.lower(searchBox.Text or "")
	table.clear(filteredRigs)
	for _, e in ipairs(rigEntries) do
		if q == "" or string.find(string.lower(e.path), q, 1, true) then
			table.insert(filteredRigs, e)
		end
	end
	rigList.CanvasSize = UDim2.fromOffset(0, #filteredRigs * PICK_ROW)
	if resetScroll then
		rigList.CanvasPosition = Vector2.new(0, 0)
	end
	drawPickerRows()
	updatePickerSelection()
end
local function selectEntry(e)
	if not selectedEntry or not e or selectedEntry.mesh ~= e.mesh then
		reuseExisting = false
	end
	selectedEntry = e
	updatePickerSelection()
	drawPickerRows()
end
local function useExplorerSelection()
	local mesh = selectedObjects()
	local e = entryFor(mesh)
	if not e then
		msg("Select a loaded rigged MeshPart in Explorer, then click Use selection.")
		return
	end
	for _, row in ipairs(rigEntries) do
		if row.mesh == mesh then
			e = row
			break
		end
	end
	local exists = false
	for _, row in ipairs(rigEntries) do
		if row.mesh == mesh then
			exists = true
			break
		end
	end
	if not exists then
		table.insert(rigEntries, e)
	end
	searchBox.Text = ""
	filterRigs(true)
	selectEntry(e)
	for i, row in ipairs(filteredRigs) do
		if row.mesh == mesh then
			rigList.CanvasPosition = Vector2.new(0, math.max(0, (i - 1) * PICK_ROW - rigList.AbsoluteSize.Y / 2))
			break
		end
	end
	msg("Selected " .. e.name .. ". Enter a name and press Start.")
end
local function scanRigs()
	scanRevision += 1
	local rev = scanRevision
	local previous = selectedEntry and selectedEntry.mesh
	local preferred = selectedObjects()
	if not previous then
		previous = preferred
	end
	msg("Scanning Workspace for rigged MeshParts...")
	task.spawn(function()
		local found = {}
		local ok, objects = pcall(function()
			return workspace:GetDescendants()
		end)
		if not ok then
			if rev == scanRevision then
				msg("Cannot enumerate Workspace.")
			end
			return
		end
		for i, obj in ipairs(objects) do
			if destroyed or rev ~= scanRevision then
				return
			end
			if obj:IsA("MeshPart") then
				local e = entryFor(obj)
				if e then
					table.insert(found, e)
				end
			end
			if i % 150 == 0 then
				task.wait()
			end
		end
		if destroyed or rev ~= scanRevision then
			return
		end
		table.sort(found, function(a, b)
			return string.lower(a.path) < string.lower(b.path)
		end)
		if selectedEntry then
			previous = selectedEntry.mesh
		end
		rigEntries = found
		selectedEntry = nil
		for _, e in ipairs(found) do
			if e.mesh == previous then
				selectedEntry = e
				break
			end
		end
		filterRigs(true)
		msg(
			#found == 0 and "No loaded rigs found. Import a skinned mesh, then Refresh."
				or (tostring(#found) .. " rig(s) found. Choose one and press Start.")
		)
	end)
end
UI.button(picker, "Refresh", UDim2.new(0.55, -174, 0, 8), UDim2.fromOffset(68, 26), scanRigs, {})
UI.button(picker, "Use selection", UDim2.new(0.55, -100, 0, 8), UDim2.fromOffset(96, 26), useExplorerSelection, {})
UI.button(detail, "Open selected animation", UDim2.fromOffset(0, 223), UDim2.new(1, 0, 0, 26), function()
	local mesh, source = selectedObjects()
	mesh = mesh or (selectedEntry and selectedEntry.mesh)
	if not source then
		msg("Select an Animation or KeyframeSequence in Explorer first.")
		return
	end
	if not mesh then
		msg("Select the animation's rig too.")
		return
	end
	local host = existingHost(mesh)
	if host and (not reuseExisting or not selectedEntry or selectedEntry.mesh ~= mesh) then
		msg("Select this rig and enable Reuse host first.")
		return
	end
	openRig(mesh, source, host)
end, {})
connect(searchBox:GetPropertyChangedSignal("Text"), function()
	filterRigs(true)
end)
connect(rigList:GetPropertyChangedSignal("CanvasPosition"), drawPickerRows)
connect(rigList:GetPropertyChangedSignal("AbsoluteSize"), drawPickerRows)
setMode = function(isPicker)
	pickerOpen = isPicker
	if not isPicker then
		scanRevision += 1
	end
	for _, child in ipairs(timelineChildren) do
		child.Visible = not isPicker
	end
	picker.Visible = isPicker
	if isPicker then
		updatePickerSelection()
	end
end
showPicker = function()
	if destroyed then
		return
	end
	cancelPoseDrag()
	pause()
	drag = nil
	releaseTrack()
	panel.Visible = true
	setMode(true)
	scanRigs()
end
pickerClick = function(p)
	if inside(rigList, p) and p.X < rigList.AbsolutePosition.X + rigList.AbsoluteSize.X - 6 then
		local i = math.floor((p.Y - rigList.AbsolutePosition.Y + rigList.CanvasPosition.Y) / PICK_ROW) + 1
		if filteredRigs[i] then
			selectEntry(filteredRigs[i])
		end
	end
end
function Animator.StartSelected()
	if not selectedEntry then
		msg("Choose a rigged MeshPart first.")
		return false
	end
	local e = entryFor(selectedEntry.mesh)
	if not e then
		msg("This rig is no longer ready. Refresh the list.")
		return false
	end
	local name = string.match(pickerName.Text or "", "^%s*(.-)%s*$")
	if name == "" then
		msg("Enter an animation name.")
		return false
	end
	local host = existingHost(e.mesh)
	if host and not reuseExisting then
		msg("This rig has an animation host. Toggle Reuse host to continue.")
		return false
	end
	return openRig(e.mesh, nil, host, name)
end
setMode(true)

local function markerAt(p)
	local x, y = p.X - marks.AbsolutePosition.X, p.Y - body.AbsolutePosition.Y + body.CanvasPosition.Y
	local nearest, dist = nil, 9
	for _, m in ipairs(markers) do
		local d = math.abs(m.x - x) + math.abs(m.y - y)
		if d < dist then
			nearest, dist = m, d
		end
	end
	return nearest
end
connect(UIS.InputBegan, function(event, processed)
	if destroyed or not panel.Visible then
		return
	end
	local p = UIS:GetMouseLocation()
	if pickerOpen then
		if event.UserInputType == Enum.UserInputType.MouseButton1 then
			pickerClick(p)
		end
		return
	end
	if event.UserInputType == Enum.UserInputType.MouseButton1 then
		for i, axis in ipairs(axisLabels) do
			if inside(axis, p) then
				beginPoseDrag(i, p.X)
				return
			end
		end
		if inside(ruler, p) then
			drag = { kind = "scrub" }
			seek(frameFor(p.X))
			render()
		elseif inside(body, p) and p.X < body.AbsolutePosition.X + body.AbsoluteSize.X - 6 then
			local i = math.floor((p.Y - body.AbsolutePosition.Y + body.CanvasPosition.Y) / ROW) + 1
			if p.X < ruler.AbsolutePosition.X then
				if bones[i] then
					chosenBone, chosenTime = bones[i], timeOf(cursor)
					render()
					editFields()
				end
				return
			end
			local m = markerAt(p)
			if m then
				chosenBone, chosenTime = m.bone, m.t
				seek(frameOf(m.t), true, m.t)
				render()
				editFields()
				drag = { kind = "key", bone = m.bone, t = m.t, startX = p.X, moved = false }
			else
				if bones[i] then
					chosenBone = bones[i]
				end
				seek(frameFor(p.X))
				render()
				drag = { kind = "scrub" }
			end
		end
	elseif
		event.UserInputType == Enum.UserInputType.Keyboard
		and (inside(panel, p) or drag ~= nil)
		and not UIS:GetFocusedTextBox()
	then
		if drag and drag.kind == "pose" then
			if event.KeyCode == Enum.KeyCode.Escape then
				cancelPoseDrag()
			end
			return
		end
		if processed then
			return
		end
		local key = event.KeyCode
		local ctrl = UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)
		local shift = UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)
		if key == Enum.KeyCode.Space then
			setPlaying()
		elseif key == Enum.KeyCode.Delete then
			deleteKey()
		elseif key == Enum.KeyCode.I then
			addKey(shift)
		elseif key == Enum.KeyCode.Left then
			seek(cursor - 1)
			render()
		elseif key == Enum.KeyCode.Right then
			seek(cursor + 1)
			render()
		elseif ctrl and key == Enum.KeyCode.C then
			copyKey()
		elseif ctrl and key == Enum.KeyCode.V then
			pasteKey()
		elseif ctrl and key == Enum.KeyCode.Z then
			undo(shift)
		elseif ctrl and key == Enum.KeyCode.Y then
			undo(true)
		elseif ctrl and key == Enum.KeyCode.S then
			save()
		end
	end
end)
connect(UIS.InputChanged, function(event)
	if destroyed or not panel.Visible or not drag or event.UserInputType ~= Enum.UserInputType.MouseMovement then
		return
	end
	local p = UIS:GetMouseLocation()
	if drag.kind == "pose" then
		updatePoseDrag(drag, p.X)
	elseif drag.kind == "scrub" then
		seek(frameFor(p.X))
	elseif drag.kind == "key" then
		if math.abs(p.X - drag.startX) > 3 then
			drag.moved = true
		end
		if drag.moved then
			local f = frameFor(p.X)
			playTime = timeOf(f)
			cursor = f
			displayHead()
			for _, m in ipairs(markers) do
				if m.bone == drag.bone and same(m.t, drag.t) then
					m.visual.Position = UDim2.fromOffset(xFor(f), m.y)
				end
			end
		end
	end
end)
connect(UIS.InputEnded, function(event)
	if event.UserInputType ~= Enum.UserInputType.MouseButton1 or not drag then
		return
	end
	local d = drag
	drag = nil
	if d.kind == "pose" then
		if d.moved then
			updatePoseDrag(d, UIS:GetMouseLocation().X)
		end
		finishPoseDrag(d)
	elseif d.kind == "key" and d.moved then
		local f = frameFor(UIS:GetMouseLocation().X)
		moveKey(d.bone, d.t, timeOf(f))
		if same(chosenTime, d.t) then
			seek(frameOf(d.t), true, d.t)
			render()
			editFields()
		end
	elseif d.kind == "scrub" then
		render()
		editFields()
	end
end)
connect(ruler:GetPropertyChangedSignal("AbsoluteSize"), function()
	if panel.Visible then
		render()
	end
end)
connect(body:GetPropertyChangedSignal("AbsoluteSize"), function()
	if panel.Visible then
		render()
	end
end)
connect(panel:GetPropertyChangedSignal("Visible"), function()
	if not panel.Visible then
		pause()
		drag = nil
		releaseTrack()
		scanRevision += 1
	end
end)
local lastPlayState, lastLoopState
connect(RunService.Heartbeat, function(dt)
	if destroyed or not panel.Visible or pickerOpen then
		return
	end
	local loop = sequence ~= nil and sequence.Loop == true
	if playRecord and lastPlayState ~= playing then
		UI.setButtonState(playRecord, playing and "selected" or nil)
		lastPlayState = playing
	end
	if loopRecord and lastLoopState ~= loop then
		UI.setButtonState(loopRecord, loop and "selected" or nil)
		lastLoopState = loop
	end
	if playing and track and sequence then
		playTime += math.max(0, dt)
		local duration = timeOf(endFrame)
		if playTime >= duration then
			if sequence.Loop then
				playTime = playTime % duration
			else
				playTime = duration
				pause()
			end
		end
		cursor = boundFrame(frameOf(playTime))
		chosenTime = chosenBone and timeOf(cursor) or nil
		applyPreview(playTime)
		local old = first
		follow(frameOf(playTime))
		if old ~= first then
			render()
		else
			displayHead()
		end
		if not playing then
			editFields()
			render()
		end
	end
end)

function Animator.Enable()
	if destroyed then
		return
	end
	if not sequence or pickerOpen then
		showPicker()
		return
	end
	panel.Visible = true
	setMode(false)
	if sequence and not track then
		reload()
	end
	render()
	editFields()
end
function Animator.Disable()
	panel.Visible = false
end
function Animator.Toggle()
	if panel.Visible then
		Animator.Disable()
	else
		Animator.Enable()
	end
end
function Animator.IsVisible()
	return panel.Visible
end
function Animator.Open(mesh, source, host)
	return openRig(mesh, source, host)
end
function Animator.ShowRigPicker()
	showPicker()
end
function Animator.GetSelectedBone()
	return chosenBone
end
function Animator.SelectBone(name)
	if not sequence or not boneSet[name] then
		return false
	end
	cancelPoseDrag()
	pause()
	chosenBone, chosenTime = name, timeOf(cursor)
	render()
	editFields()
	return true
end
function Animator.Save()
	save()
	return animation
end
function Animator.GetSequence()
	return sequence
end
function Animator.GetAnimation()
	return animation
end
function Animator.SetFrame(f)
	seek(f)
	render()
end
function Animator.SetPose(bone, frame, cf, weight)
	if not sequence or not boneSet[bone] then
		return false
	end
	if not finite(frame) then
		return false
	end
	if weight ~= nil and not finite(weight) then
		return false
	end
	checkpoint()
	chosenBone, cursor = bone, boundFrame(frame)
	chosenTime = timeOf(cursor)
	insertPose(bone, chosenTime, { cf = cf, weight = math.clamp(weight or 1, 0, 1) })
	commit("Pose set: " .. bone)
	return true
end
function Animator.Refresh()
	if sequence then
		endFrame = math.max(endFrame, maxFrame())
		reload()
	end
	render()
	editFields()
end
function Animator.Discard()
	closeSession()
	trackHeader.Text = "  BONE CHANNELS"
	showPicker()
	msg("Session closed. Choose a rig to start again.")
end
function Animator.Destroy()
	if destroyed then
		return
	end
	destroyed = true
	closeSession()
	for _, c in ipairs(connections) do
		c:Disconnect()
	end
	table.clear(connections)
	panel:Destroy()
end
return Animator

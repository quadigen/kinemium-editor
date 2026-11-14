local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local SOURCE = [[
    uniform shader content;
    uniform float2 size;
    uniform float4 windowRect;

    uniform float2 d00;
    uniform float2 d10;
    uniform float2 d20;
    uniform float2 d01;
    uniform float2 d11;
    uniform float2 d21;
    uniform float2 d02;
    uniform float2 d12;
    uniform float2 d22;

    float2 displacement(float2 uv) {
        uv = clamp(uv, float2(0.0), float2(1.0));

        float tx0 = clamp(uv.x * 2.0, 0.0, 1.0);
        float tx1 = clamp(uv.x * 2.0 - 1.0, 0.0, 1.0);
        float ty0 = clamp(uv.y * 2.0, 0.0, 1.0);
        float ty1 = clamp(uv.y * 2.0 - 1.0, 0.0, 1.0);

        float2 r0 = mix(mix(d00, d10, tx0), d20, tx1);
        float2 r1 = mix(mix(d01, d11, tx0), d21, tx1);
        float2 r2 = mix(mix(d02, d12, tx0), d22, tx1);
        return mix(mix(r0, r1, ty0), r2, ty1);
    }

    half4 main(float2 p) {
        float2 canvasUV = p / size;
        float2 targetUV = (canvasUV - windowRect.xy) / windowRect.zw;

        // Invert the forward cloth deformation to find the source pixel.
        float2 sourceUV = targetUV;
        for (int i = 0; i < 5; i++) {
            sourceUV = targetUV - displacement(sourceUV);
        }

        if (sourceUV.x < 0.0 || sourceUV.x > 1.0 ||
            sourceUV.y < 0.0 || sourceUV.y > 1.0) {
            return half4(0.0);
        }

        return content.eval(sourceUV * size);
    }
]]

local SPRING = 115
local DAMPING = 16
local NEIGHBOR_STRENGTH = 32
local DRAG_INFLUENCE = 0.85
local MAX_OFFSET = 110
local PADDING = 124

local NAMES = { "d00", "d10", "d20", "d01", "d11", "d21", "d02", "d12", "d22" }

return function(window: GuiObject, dragHandle: GuiObject?)
	dragHandle = dragHandle or window
	assert(window.AbsoluteSize.X > 0 and window.AbsoluteSize.Y > 0, "Lay out the window before adding wobble")

	local shader = Instance.new("UIShader")
	shader.Name = "WobblyWindow"
	shader.Source = SOURCE
	shader.FullContentSampling = true

	local nodes = {}
	for y = 0, 2 do
		for x = 0, 2 do
			local index = y * 3 + x + 1
			local neighbors = {}
			if x > 0 then
				table.insert(neighbors, index - 1)
			end
			if x < 2 then
				table.insert(neighbors, index + 1)
			end
			if y > 0 then
				table.insert(neighbors, index - 3)
			end
			if y < 2 then
				table.insert(neighbors, index + 3)
			end

			nodes[index] = {
				uv = Vector2.new(x / 2, y / 2),
				offset = Vector2.zero,
				velocity = Vector2.zero,
				influence = 1,
				neighbors = neighbors,
			}
		end
	end

	local alive = true
	local dragging = false
	local activeInput = nil
	local startMouse = Vector2.zero
	local lastDelta = Vector2.zero
	local startPosition = window.Position
	local stepConnection = nil
	local connections = {}
	local oldActive = dragHandle.Active
	dragHandle.Active = true

	local function syncUniforms()
		local s = window.AbsoluteSize
		if s.X <= 0 or s.Y <= 0 then
			return
		end
		for index, node in ipairs(nodes) do
			shader:SetUniform(NAMES[index], {
				node.offset.X / s.X,
				node.offset.Y / s.Y,
			})
		end
	end

	local function updateTransform()
		local s = window.AbsoluteSize
		if s.X <= 0 or s.Y <= 0 then
			return
		end
		local width = s.X + PADDING * 2
		local height = s.Y + PADDING * 2
		shader:SetUniform("guiTransform", {
			width / s.X,
			height / s.Y,
			-PADDING,
			-PADDING,
		})
		shader:SetUniform("windowRect", {
			PADDING / width,
			PADDING / height,
			s.X / width,
			s.Y / height,
		})
		syncUniforms()
	end

	local function step(dt)
		if not alive then
			return
		end
		dt = math.min(dt, 1 / 30)

		local nextOffsets = table.create(9)
		local nextVelocities = table.create(9)
		local maxMotion = 0

		for index, node in ipairs(nodes) do
			local acceleration = -node.offset * SPRING - node.velocity * DAMPING
			for _, adjacent in ipairs(node.neighbors) do
				acceleration += (nodes[adjacent].offset - node.offset) * NEIGHBOR_STRENGTH
			end

			local velocity = node.velocity + acceleration * dt
			local offset = node.offset + velocity * dt
			offset = Vector2.new(
				math.clamp(offset.X, -MAX_OFFSET, MAX_OFFSET),
				math.clamp(offset.Y, -MAX_OFFSET, MAX_OFFSET)
			)

			nextOffsets[index] = offset
			nextVelocities[index] = velocity
			maxMotion = math.max(maxMotion, offset.Magnitude, velocity.Magnitude * 0.03)
		end

		for index, node in ipairs(nodes) do
			node.offset = nextOffsets[index]
			node.velocity = nextVelocities[index]
		end

		if not dragging and maxMotion < 0.12 then
			for _, node in ipairs(nodes) do
				node.offset = Vector2.zero
				node.velocity = Vector2.zero
			end
			syncUniforms()
			if stepConnection then
				stepConnection:Disconnect()
				stepConnection = nil
			end
			return
		end

		syncUniforms()
	end

	local function wake()
		if not stepConnection then
			stepConnection = RunService.RenderStepped:Connect(step)
		end
	end

	local function beginDrag(input)
		if dragging then
			return
		end
		local inputType = input.UserInputType
		if inputType ~= Enum.UserInputType.MouseButton1 and inputType ~= Enum.UserInputType.Touch then
			return
		end

		dragging = true
		activeInput = input
		startMouse = Vector2.new(input.Position.X, input.Position.Y)
		lastDelta = Vector2.zero
		startPosition = window.Position

		local s = window.AbsoluteSize
		local p = window.AbsolutePosition
		local grip = Vector2.new(
			math.clamp((startMouse.X - p.X) / math.max(s.X, 1), 0, 1),
			math.clamp((startMouse.Y - p.Y) / math.max(s.Y, 1), 0, 1)
		)
		for _, node in ipairs(nodes) do
			local dist = (node.uv - grip).Magnitude
			node.influence = math.clamp(dist * 1.35, 0.07, 1)
		end
		wake()
	end

	local function moveDrag(input)
		if not dragging or not activeInput then
			return
		end
		if activeInput.UserInputType == Enum.UserInputType.Touch then
			if input ~= activeInput then
				return
			end
		elseif input.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end

		local mouse = Vector2.new(input.Position.X, input.Position.Y)
		local delta = mouse - startMouse
		window.Position = UDim2.new(
			startPosition.X.Scale,
			startPosition.X.Offset + delta.X,
			startPosition.Y.Scale,
			startPosition.Y.Offset + delta.Y
		)

		local movement = delta - lastDelta
		lastDelta = delta
		movement = Vector2.new(math.clamp(movement.X, -80, 80), math.clamp(movement.Y, -80, 80))
		if movement.Magnitude > 0 then
			for _, node in ipairs(nodes) do
				local offset = node.offset - movement * (node.influence * DRAG_INFLUENCE)
				node.offset = Vector2.new(
					math.clamp(offset.X, -MAX_OFFSET, MAX_OFFSET),
					math.clamp(offset.Y, -MAX_OFFSET, MAX_OFFSET)
				)
			end
			wake()
			syncUniforms()
		end
	end

	local function endDrag(input)
		if not dragging or not activeInput then
			return
		end
		if activeInput.UserInputType == Enum.UserInputType.Touch then
			if input ~= activeInput then
				return
			end
		elseif input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		dragging = false
		activeInput = nil
	end

	updateTransform()
	shader.Parent = window

	table.insert(connections, dragHandle.InputBegan:Connect(beginDrag))
	table.insert(connections, UserInputService.InputChanged:Connect(moveDrag))
	table.insert(connections, UserInputService.InputEnded:Connect(endDrag))
	table.insert(connections, window:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateTransform))

	local function destroy()
		if not alive then
			return
		end
		alive = false
		dragging = false
		if stepConnection then
			stepConnection:Disconnect()
			stepConnection = nil
		end
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		if dragHandle.Parent then
			dragHandle.Active = oldActive
		end
		shader:Destroy()
	end

	return shader, destroy
end

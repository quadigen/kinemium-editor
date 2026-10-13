local UI = require("@internal/editor_ui")

local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local colors = UI.colors
local tokens = UI.tokens

local ImageViewer = {}

local WINDOW_WIDTH = 720
local WINDOW_HEIGHT = 520

local BUTTON_W, BUTTON_H, BUTTON_GAP = 58, 24, 4

local viewerBackgrounds = {
	{ name = "Dark", color = Color3.fromRGB(24, 24, 28) },
	{ name = "Gray", color = Color3.fromRGB(110, 110, 118) },
	{ name = "Light", color = Color3.fromRGB(235, 235, 240) },
}

local viewerTints = {
	{ name = "None", color = Color3.fromRGB(255, 255, 255) },
	{ name = "Warm", color = Color3.fromRGB(255, 226, 190) },
	{ name = "Cool", color = Color3.fromRGB(190, 215, 255) },
	{ name = "Red", color = Color3.fromRGB(255, 150, 150) },
	{ name = "Green", color = Color3.fromRGB(150, 255, 150) },
	{ name = "Blue", color = Color3.fromRGB(150, 170, 255) },
}

local viewerOpacities = { 0, 0.25, 0.5, 0.75 }

local activeViewer = nil
local viewerClosedAt = -10

local sourceResolver = function(path)
	return path
end

local function tween(object, properties, duration, style, direction, delay)
	if object == nil or not UI.isAlive(object) then
		return nil
	end

	local ok, result = pcall(function()
		local info = TweenInfo.new(
			duration,
			style or Enum.EasingStyle.Quad,
			direction or Enum.EasingDirection.Out,
			0,
			false,
			delay or 0
		)

		local created = TweenService:Create(object, info, properties)

		created:Play()

		return created
	end)

	if ok then
		return result
	end

	return nil
end

local function toastMessage(kind, title, message)
	pcall(function()
		UI.toast("files", {
			type = kind,
			title = title,
			message = message,
			details = "",
			detailsTitle = "",
			backgroundTransparency = 0.4,
			blur = true,
			duration = 5,
		})
	end)
end

local function mouseOver(gui)
	local mouse = UserInputService:GetMouseLocation()
	local position = gui.AbsolutePosition
	local size = gui.AbsoluteSize

	return mouse.X >= position.X
		and mouse.X <= position.X + size.X
		and mouse.Y >= position.Y
		and mouse.Y <= position.Y + size.Y
end

local function createWindow(title, onGone)
	local gui = Instance.new("ScreenGui")
	gui.Name = "ImageViewer"
	gui.RenderOnTop = true
	gui.Parent = game.CoreGui

	local ok, window, pageContent, _, controls = pcall(
		UI.window,
		title,
		UDim2.new(0.5, -WINDOW_WIDTH / 2, 0.5, -WINDOW_HEIGHT / 2),
		UDim2.fromOffset(WINDOW_WIDTH, WINDOW_HEIGHT),
		"ImageViewer",
		{
			tabs = { "Viewer" },
			selectedTab = "Viewer",
			closable = true,
		}
	)

	pageContent.BackgroundTransparency = 1
	window.BackgroundTransparency = 0.5
	window.ClipsDescendants = true
	window.Parent = gui

	UI.backdrop(pageContent, 15, Color3.new(0, 0, 0))

	if not ok then
		gui:Destroy()

		error(window, 0)
	end

	window.Parent = gui

	local content = controls and controls.pages and controls.pages.Viewer or pageContent or window

	pcall(function()
		window.Destroying:Connect(onGone)
	end)

	return gui, window, content
end

local function destroyGui(gui)
	if gui ~= nil and UI.isAlive(gui) then
		gui:Destroy()
	end
end

function ImageViewer.ImageSource(path)
	return sourceResolver(path)
end

function ImageViewer.SetImageSource(resolver)
	sourceResolver = resolver
end

function ImageViewer.BlocksInput()
	return activeViewer ~= nil or os.clock() - viewerClosedAt < 0.1
end

function ImageViewer.Open(ctx)
	if activeViewer ~= nil then
		activeViewer.close()
	end

	local state = {
		zoom = 1,
		panX = 0,
		panY = 0,
		rotation = 0,
		background = 1,
		tint = 1,
		opacity = 1,
	}

	local handle = {}
	local closed = false
	local connections = {}

	local gui, window, content

	local function cleanup()
		if closed then
			return false
		end

		closed = true

		for _, connection in ipairs(connections) do
			pcall(function()
				connection:Disconnect()
			end)
		end

		if activeViewer == handle then
			activeViewer = nil
		end

		viewerClosedAt = os.clock()

		return true
	end

	local function close()
		cleanup()

		destroyGui(gui)
	end

	local function windowGone()
		cleanup()

		destroyGui(gui)
	end

	handle.close = close
	activeViewer = handle

	gui, window, content = createWindow(ctx.Name, windowGone)

	if closed then
		destroyGui(gui)

		return
	end

	local canvas = UI.create("Frame", {
		Position = UDim2.fromOffset(8, 20),
		Size = UDim2.new(1, -16, 1, -68),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Active = true,
	}, content)

	canvas.BackgroundTransparency = 1

	UI.corner(canvas, tokens.radius.sm)

	local image = UI.image(canvas, ImageViewer.ImageSource(ctx.Path), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 1))

	pcall(function()
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.ScaleType = Enum.ScaleType.Fit
		image.BackgroundTransparency = 1
	end)

	local status =
		UI.label(content, "", UDim2.new(0, 10, 1, -26), UDim2.new(1, -20, 0, 18), tokens.type.small, tokens.color.muted)

	local function refreshStatus()
		local opacity = math.floor((1 - viewerOpacities[state.opacity]) * 100 + 0.5)

		status.Text = string.format(
			"Zoom %d%%    Rotation %d    Tint %s    Opacity %d%%    Background %s",
			math.floor(state.zoom * 100 + 0.5),
			state.rotation % 360,
			viewerTints[state.tint].name,
			opacity,
			viewerBackgrounds[state.background].name
		)
	end

	local function apply(animated)
		local size = UDim2.fromScale(state.zoom, state.zoom)
		local position = UDim2.new(0.5, state.panX, 0.5, state.panY)

		pcall(function()
			canvas.BackgroundColor3 = viewerBackgrounds[state.background].color
		end)

		pcall(function()
			image.ImageColor3 = viewerTints[state.tint].color
		end)

		pcall(function()
			image.ImageTransparency = viewerOpacities[state.opacity]
		end)

		if animated then
			tween(image, { Size = size, Position = position, Rotation = state.rotation }, 0.15)
		else
			pcall(function()
				image.Size = size
				image.Position = position
				image.Rotation = state.rotation
			end)
		end

		refreshStatus()
	end

	local function save()
		local fileType = ctx.Type

		if fileType == nil or fileType.onSave == nil then
			toastMessage("error", "Nothing to save with", "No onSave callback is registered for this file type.")
			return
		end

		local ok, err = pcall(fileType.onSave, ctx, {
			zoom = state.zoom,
			rotation = state.rotation % 360,
			tint = viewerTints[state.tint].name,
			tintColor = viewerTints[state.tint].color,
			opacity = 1 - viewerOpacities[state.opacity],
			background = viewerBackgrounds[state.background].name,
		})

		if ok then
			toastMessage("success", "Saved", ctx.Name)
		else
			toastMessage("error", "Save failed", tostring(err))
		end
	end

	local panning = nil

	canvas.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			panning = {
				x = input.Position.X,
				y = input.Position.Y,
				panX = state.panX,
				panY = state.panY,
			}
		end
	end)

	connections[#connections + 1] = UserInputService.InputChanged:Connect(function(input)
		if not UI.isAlive(window) then
			windowGone()
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseMovement and panning ~= nil then
			state.panX = panning.panX + (input.Position.X - panning.x)
			state.panY = panning.panY + (input.Position.Y - panning.y)

			apply(false)

			return
		end

		if input.UserInputType == Enum.UserInputType.MouseWheel and mouseOver(canvas) then
			local factor = input.Position.Z > 0 and 1.1 or 1 / 1.1

			state.zoom = math.clamp(state.zoom * factor, 0.1, 16)

			apply(false)
		end
	end)

	connections[#connections + 1] = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			panning = nil
		end
	end)

	connections[#connections + 1] = UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Escape then
			close()
		end
	end)

	apply(false)
end

return ImageViewer

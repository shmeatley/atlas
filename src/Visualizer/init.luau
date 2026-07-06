--!strict
--!native
--!optimize 2

local AssetService = game:GetService("AssetService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Presets = require(script.Presets)

local clamp = math.clamp
local floor = math.floor
local writeu32 = buffer.writeu32

local TITLE_HEIGHT = 28
local MAX_DIMENSION = 1024
local VECTOR2_ZERO = Vector2.zero

local windowIndex = 0

export type PixelCallback = Presets.PixelCallback
export type DrawCallback = Presets.DrawCallback

--[=[
	@interface VisualizerOptions
	@within Visualizer
	.width number? -- Image width in pixels, at most 1024. Defaults to 256.
	.height number? -- Image height in pixels, at most 1024. Defaults to 256.
	.parent Instance? -- Where to parent the window. Defaults to the local player's PlayerGui.
	.title string? -- Window title. Defaults to "Atlas".
	.pixelScale number? -- On-screen magnification of the image. Defaults to 1.
]=]
export type VisualizerOptions = {
	width: number?,
	height: number?,
	parent: Instance?,
	title: string?,
	pixelScale: number?,
}

--[=[
	@class Visualizer

	A draggable on-screen window backed by an `EditableImage`, for eyeballing
	noise fields, curves, and point sets while you tune them. Rendering runs
	through a single reused pixel buffer, so re-rendering every frame is cheap.

	```lua
	local viz = Atlas.Visualizer.new({ width = 256, height = 256, title = "fBm" })
	viz:render(function(x, y)
		local v = simplex:sample2D(x * 0.02, y * 0.02) * 0.5 + 0.5
		return v, v, v
	end)
	```
]=]
local Visualizer = {}
Visualizer.__index = Visualizer

--[=[
	@prop Presets Presets
	@within Visualizer
	@readonly
	Built-in pixel and draw callbacks for noise, curves, and point sets.
]=]
Visualizer.Presets = Presets

type VisualizerProps = {
	_image: EditableImage,
	_buffer: buffer,
	_width: number,
	_height: number,
	_size: Vector2,
	_gui: ScreenGui,
	_dragConnection: RBXScriptConnection,
	_destroyed: boolean,
}

export type Visualizer = typeof(setmetatable({} :: VisualizerProps, Visualizer))

--[=[
	Creates a visualizer window. On the server (or in other headless contexts)
	`options.parent` must be provided, since there is no local PlayerGui.

	@function new
	@within Visualizer
	@param options VisualizerOptions?
	@return Visualizer
]=]
function Visualizer.new(options: VisualizerOptions?): Visualizer
	local width = if options then options.width or 256 else 256
	local height = if options then options.height or 256 else 256
	local pixelScale = if options then options.pixelScale or 1 else 1
	local title = if options then options.title or "Atlas" else "Atlas"
	local parent = if options then options.parent else nil

	if width < 1 or height < 1 or width > MAX_DIMENSION or height > MAX_DIMENSION then
		error(`Visualizer dimensions must be within 1-{MAX_DIMENSION} pixels`, 2)
	end

	if not parent then
		local localPlayer = Players.LocalPlayer
		parent = localPlayer and localPlayer:FindFirstChildOfClass("PlayerGui")
		if not parent then
			error("Visualizer.new requires options.parent outside a client context", 2)
		end
	end

	local size = Vector2.new(width, height)
	local image: EditableImage? = AssetService:CreateEditableImage({ Size = size })
	if not image then
		error("Visualizer.new failed to create an EditableImage (editable memory budget exhausted)", 2)
	end

	windowIndex += 1
	local cascade = 36 * ((windowIndex - 1) % 8)

	local gui = Instance.new("ScreenGui")
	gui.Name = "AtlasVisualizer"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 100

	local window = Instance.new("Frame")
	window.Name = "Window"
	window.Size = UDim2.fromOffset(width * pixelScale, height * pixelScale + TITLE_HEIGHT)
	window.Position = UDim2.fromOffset(48 + cascade, 48 + cascade)
	window.BackgroundColor3 = Color3.fromRGB(24, 25, 31)
	window.BorderSizePixel = 0
	window.Active = true
	window.Parent = gui

	local titleBar = Instance.new("TextLabel")
	titleBar.Name = "TitleBar"
	titleBar.Size = UDim2.new(1, -TITLE_HEIGHT, 0, TITLE_HEIGHT)
	titleBar.BackgroundColor3 = Color3.fromRGB(36, 38, 46)
	titleBar.BorderSizePixel = 0
	titleBar.Font = Enum.Font.Code
	titleBar.Text = " " .. title
	titleBar.TextSize = 13
	titleBar.TextColor3 = Color3.fromRGB(220, 222, 228)
	titleBar.TextXAlignment = Enum.TextXAlignment.Left
	titleBar.Parent = window

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "Close"
	closeButton.Size = UDim2.fromOffset(TITLE_HEIGHT, TITLE_HEIGHT)
	closeButton.Position = UDim2.new(1, -TITLE_HEIGHT, 0, 0)
	closeButton.BackgroundColor3 = Color3.fromRGB(36, 38, 46)
	closeButton.BorderSizePixel = 0
	closeButton.Font = Enum.Font.Code
	closeButton.Text = "x"
	closeButton.TextSize = 13
	closeButton.TextColor3 = Color3.fromRGB(232, 116, 116)
	closeButton.Parent = window

	local canvas = Instance.new("ImageLabel")
	canvas.Name = "Canvas"
	canvas.Size = UDim2.fromOffset(width * pixelScale, height * pixelScale)
	canvas.Position = UDim2.fromOffset(0, TITLE_HEIGHT)
	canvas.BackgroundTransparency = 1
	canvas.ResampleMode = Enum.ResamplerMode.Pixelated
	canvas.ImageContent = Content.fromObject(image)
	canvas.Parent = window

	local dragging = false
	local dragStart = VECTOR2_ZERO
	local startOffsetX = 0
	local startOffsetY = 0

	titleBar.InputBegan:Connect(function(input)
		local inputType = input.UserInputType
		if inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = Vector2.new(input.Position.X, input.Position.Y)
			startOffsetX = window.Position.X.Offset
			startOffsetY = window.Position.Y.Offset
		end
	end)

	titleBar.InputEnded:Connect(function(input)
		local inputType = input.UserInputType
		if inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	local dragConnection = UserInputService.InputChanged:Connect(function(input: InputObject)
		if not dragging then
			return
		end
		local inputType = input.UserInputType
		if inputType == Enum.UserInputType.MouseMovement or inputType == Enum.UserInputType.Touch then
			local deltaX = input.Position.X - dragStart.X
			local deltaY = input.Position.Y - dragStart.Y
			window.Position = UDim2.fromOffset(startOffsetX + deltaX, startOffsetY + deltaY)
		end
	end)

	local self = setmetatable({
		_image = image,
		_buffer = buffer.create(width * height * 4),
		_width = width,
		_height = height,
		_size = size,
		_gui = gui,
		_dragConnection = dragConnection,
		_destroyed = false,
	}, Visualizer)

	closeButton.MouseButton1Click:Connect(function()
		self:destroy()
	end)

	gui.Parent = parent
	return self
end

--[=[
	Renders the image by calling `callback` once per pixel. Returned channels
	are clamped to [0, 1].

	@method render
	@within Visualizer
	@param callback PixelCallback
]=]
function Visualizer.render(self: Visualizer, callback: PixelCallback)
	if self._destroyed then
		error("Visualizer has been destroyed", 2)
	end

	local buf = self._buffer
	local width = self._width
	local height = self._height
	local offset = 0

	for y = 0, height - 1 do
		for x = 0, width - 1 do
			local r, g, b = callback(x, y)
			writeu32(
				buf,
				offset,
				floor(clamp(r, 0, 1) * 255 + 0.5)
					+ floor(clamp(g, 0, 1) * 255 + 0.5) * 0x100
					+ floor(clamp(b, 0, 1) * 255 + 0.5) * 0x10000
					+ 0xFF000000
			)
			offset += 4
		end
	end

	self._image:WritePixelsBuffer(VECTOR2_ZERO, self._size, buf)
end

--[=[
	Hands the raw RGBA buffer to `callback` for direct writes, then uploads it.
	Faster than [Visualizer:render] when the callback can batch its own work,
	and the natural fit for [Presets.curve] and [Presets.points].

	@method draw
	@within Visualizer
	@param callback DrawCallback
]=]
function Visualizer.draw(self: Visualizer, callback: DrawCallback)
	if self._destroyed then
		error("Visualizer has been destroyed", 2)
	end

	callback(self._buffer, self._width, self._height)
	self._image:WritePixelsBuffer(VECTOR2_ZERO, self._size, self._buffer)
end

--[=[
	Closes the window and releases the EditableImage. Safe to call twice.

	@method destroy
	@within Visualizer
]=]
function Visualizer.destroy(self: Visualizer)
	if self._destroyed then
		return
	end
	self._destroyed = true
	self._dragConnection:Disconnect()
	self._gui:Destroy()
	self._image:Destroy()
end

return Visualizer

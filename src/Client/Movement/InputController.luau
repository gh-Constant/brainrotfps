--!strict
--[[
    InputController
    Provides unified cross-platform input handling for movement actions.
    Supports PC (keyboard), Mobile (touch buttons), and Console (gamepad).
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local InputController = {}
InputController.__index = InputController

export type InputController = typeof(setmetatable({} :: {
    _platform: string, -- "PC" | "Mobile" | "Console"
    _slideButton: ImageButton?,
    _slideButtonFrame: Frame?,
    _connections: { RBXScriptConnection },
    _isSlideHeld: boolean,
    SlidePressed: BindableEvent,
    SlideReleased: BindableEvent,
}, InputController))

-- Input mappings
local SLIDE_KEY = Enum.KeyCode.LeftShift
local SLIDE_GAMEPAD_BUTTON = Enum.KeyCode.ButtonB
local SLIDE_GAMEPAD_ALT = Enum.KeyCode.ButtonR1 -- RB/R1 as alternative

-- Mobile button settings
local BUTTON_SIZE = UDim2.new(0, 70, 0, 70)
local BUTTON_POSITION = UDim2.new(1, -90, 1, -180) -- Above jump button area
local BUTTON_IMAGE = "rbxassetid://6035047409" -- Crouch/slide icon
local BUTTON_BG_COLOR = Color3.fromRGB(30, 30, 30)
local BUTTON_BG_TRANSPARENCY = 0.3

type Platform = "PC" | "Mobile" | "Console"

local function detectPlatform(): Platform
    -- Check for console first (gamepad enabled and no touch/keyboard)
    if GuiService:IsTenFootInterface() then
        return "Console"
    end
    
    -- Check for mobile (touch enabled)
    if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
        return "Mobile"
    end
    
    -- Check for gamepad
    if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
        return "Console"
    end
    
    -- Default to PC
    return "PC"
end

function InputController.new(): InputController
    local self = setmetatable({}, InputController)
    
    self._platform = detectPlatform()
    self._connections = {}
    self._isSlideHeld = false
    self._slideButton = nil
    self._slideButtonFrame = nil
    
    -- Create bindable events for slide actions
    self.SlidePressed = Instance.new("BindableEvent")
    self.SlideReleased = Instance.new("BindableEvent")
    
    -- Setup input based on platform
    self:_setupInput()
    
    print("[InputController] Platform detected:", self._platform)
    
    return self :: InputController
end

function InputController._setupInput(self: InputController)
    -- Always setup keyboard/gamepad input (works on all platforms)
    self:_setupKeyboardInput()
    self:_setupGamepadInput()
    
    -- Setup mobile button if on touch device
    if UserInputService.TouchEnabled then
        self:_setupMobileInput()
    end
    
    -- Listen for input type changes (player might plug in controller)
    local lastInputConnection = UserInputService.LastInputTypeChanged:Connect(function(inputType)
        if inputType == Enum.UserInputType.Touch then
            if not self._slideButtonFrame then
                self:_setupMobileInput()
            end
        elseif inputType == Enum.UserInputType.Gamepad1 then
            self._platform = "Console"
        elseif inputType == Enum.UserInputType.Keyboard or inputType == Enum.UserInputType.MouseMovement then
            self._platform = "PC"
        end
    end)
    table.insert(self._connections, lastInputConnection)
end

function InputController._setupKeyboardInput(self: InputController)
    local inputBeganConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        
        if input.KeyCode == SLIDE_KEY then
            self:_onSlidePressed()
        end
    end)
    table.insert(self._connections, inputBeganConnection)
    
    local inputEndedConnection = UserInputService.InputEnded:Connect(function(input, _gameProcessed)
        if input.KeyCode == SLIDE_KEY then
            self:_onSlideReleased()
        end
    end)
    table.insert(self._connections, inputEndedConnection)
end

function InputController._setupGamepadInput(self: InputController)
    local inputBeganConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        
        if input.KeyCode == SLIDE_GAMEPAD_BUTTON or input.KeyCode == SLIDE_GAMEPAD_ALT then
            self:_onSlidePressed()
        end
    end)
    table.insert(self._connections, inputBeganConnection)
    
    local inputEndedConnection = UserInputService.InputEnded:Connect(function(input, _gameProcessed)
        if input.KeyCode == SLIDE_GAMEPAD_BUTTON or input.KeyCode == SLIDE_GAMEPAD_ALT then
            self:_onSlideReleased()
        end
    end)
    table.insert(self._connections, inputEndedConnection)
end

function InputController._setupMobileInput(self: InputController)
    local player = Players.LocalPlayer
    if not player then return end
    
    local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
    
    -- Create a ScreenGui for the slide button
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "SlideButtonGui"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = playerGui
    
    -- Create container frame
    local frame = Instance.new("Frame")
    frame.Name = "SlideButtonFrame"
    frame.Size = BUTTON_SIZE
    frame.Position = BUTTON_POSITION
    frame.AnchorPoint = Vector2.new(1, 1)
    frame.BackgroundColor3 = BUTTON_BG_COLOR
    frame.BackgroundTransparency = BUTTON_BG_TRANSPARENCY
    frame.BorderSizePixel = 0
    frame.Parent = screenGui
    
    -- Make it circular
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0.5, 0)
    corner.Parent = frame
    
    -- Add stroke for visibility
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 255, 255)
    stroke.Thickness = 2
    stroke.Transparency = 0.5
    stroke.Parent = frame
    
    -- Create the button
    local button = Instance.new("ImageButton")
    button.Name = "SlideButton"
    button.Size = UDim2.new(1, -10, 1, -10)
    button.Position = UDim2.new(0.5, 0, 0.5, 0)
    button.AnchorPoint = Vector2.new(0.5, 0.5)
    button.BackgroundTransparency = 1
    button.Image = BUTTON_IMAGE
    button.ImageColor3 = Color3.fromRGB(255, 255, 255)
    button.ImageTransparency = 0.1
    button.Parent = frame
    
    -- Add text label for clarity
    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.Size = UDim2.new(1, 0, 0.3, 0)
    label.Position = UDim2.new(0, 0, 0.7, 0)
    label.BackgroundTransparency = 1
    label.Text = "SLIDE"
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.Parent = frame
    
    -- Connect touch events
    local touchStartConnection = button.MouseButton1Down:Connect(function()
        self:_onSlidePressed()
        frame.BackgroundTransparency = 0.1 -- Visual feedback
    end)
    table.insert(self._connections, touchStartConnection)
    
    local touchEndConnection = button.MouseButton1Up:Connect(function()
        self:_onSlideReleased()
        frame.BackgroundTransparency = BUTTON_BG_TRANSPARENCY
    end)
    table.insert(self._connections, touchEndConnection)
    
    -- Also handle when touch leaves the button
    local leaveConnection = button.MouseLeave:Connect(function()
        if self._isSlideHeld then
            self:_onSlideReleased()
            frame.BackgroundTransparency = BUTTON_BG_TRANSPARENCY
        end
    end)
    table.insert(self._connections, leaveConnection)
    
    self._slideButton = button
    self._slideButtonFrame = frame
    
    print("[InputController] Mobile slide button created")
end

function InputController._onSlidePressed(self: InputController)
    if self._isSlideHeld then return end
    self._isSlideHeld = true
    self.SlidePressed:Fire()
end

function InputController._onSlideReleased(self: InputController)
    if not self._isSlideHeld then return end
    self._isSlideHeld = false
    self.SlideReleased:Fire()
end

function InputController.IsSlideHeld(self: InputController): boolean
    return self._isSlideHeld
end

function InputController.GetPlatform(self: InputController): string
    return self._platform
end

function InputController.Destroy(self: InputController)
    for _, connection in self._connections do
        connection:Disconnect()
    end
    self._connections = {}
    
    if self._slideButtonFrame then
        local parent = self._slideButtonFrame.Parent
        if parent then
            parent:Destroy()
        end
        self._slideButtonFrame = nil
        self._slideButton = nil
    end
    
    self.SlidePressed:Destroy()
    self.SlideReleased:Destroy()
end

return InputController

--!strict
--[[
    DeathScreen
    GTA-style "WASTED" death screen with cartoonish styling.
    
    Shows a dark overlay with "WASTED" text when the player dies,
    then fades out before respawn.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Configuration
local FADE_IN_TIME = 0.3
local HOLD_TIME = 1.0
local FADE_OUT_TIME = 0.5

-- Module
local DeathScreen = {}

-- UI References
local screenGui: ScreenGui? = nil
local overlay: Frame? = nil
local wastedLabel: TextLabel? = nil

--[[
    Creates the death screen UI elements.
]]
local function createUI()
    -- Main ScreenGui
    local gui = Instance.new("ScreenGui")
    gui.Name = "DeathScreen"
    gui.DisplayOrder = 100 -- Above most UI
    gui.IgnoreGuiInset = true
    gui.Enabled = false
    gui.ResetOnSpawn = false
    gui.Parent = playerGui
    
    -- Dark overlay
    local overlayFrame = Instance.new("Frame")
    overlayFrame.Name = "Overlay"
    overlayFrame.Size = UDim2.fromScale(1, 1)
    overlayFrame.Position = UDim2.fromScale(0, 0)
    overlayFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    overlayFrame.BackgroundTransparency = 1 -- Start invisible
    overlayFrame.BorderSizePixel = 0
    overlayFrame.Parent = gui
    
    -- WASTED text with cartoonish styling
    local wasted = Instance.new("TextLabel")
    wasted.Name = "WastedText"
    wasted.Size = UDim2.fromScale(1, 0.2)
    wasted.Position = UDim2.fromScale(0, 0.4)
    wasted.BackgroundTransparency = 1
    wasted.Text = "WASTED"
    wasted.TextColor3 = Color3.fromRGB(255, 50, 50) -- Bright red
    wasted.Font = Enum.Font.GothamBlack
    wasted.TextSize = 120
    wasted.TextTransparency = 1 -- Start invisible
    wasted.TextScaled = false
    wasted.Parent = gui
    
    -- Add UIStroke for cartoonish outline
    local stroke = Instance.new("UIStroke")
    stroke.Name = "Outline"
    stroke.Color = Color3.fromRGB(80, 0, 0) -- Dark red outline
    stroke.Thickness = 4
    stroke.Transparency = 1 -- Start invisible
    stroke.Parent = wasted
    
    -- Add shadow text for depth
    local shadow = Instance.new("TextLabel")
    shadow.Name = "Shadow"
    shadow.Size = UDim2.fromScale(1, 1)
    shadow.Position = UDim2.fromOffset(6, 6)
    shadow.BackgroundTransparency = 1
    shadow.Text = "WASTED"
    shadow.TextColor3 = Color3.fromRGB(30, 0, 0)
    shadow.Font = Enum.Font.GothamBlack
    shadow.TextSize = 120
    shadow.TextTransparency = 1
    shadow.ZIndex = -1
    shadow.Parent = wasted
    
    -- Store references
    screenGui = gui
    overlay = overlayFrame
    wastedLabel = wasted
end

--[[
    Plays the death sound effect.
]]
local function playDeathSound()
    local config = ReplicatedStorage:FindFirstChild("Config")
    if not config then return end
    
    local playerFolder = config:FindFirstChild("Player")
    if not playerFolder then return end
    
    local audiosFolder = playerFolder:FindFirstChild("Audios")
    if not audiosFolder then return end
    
    local deathSound = audiosFolder:FindFirstChild("Death")
    
    -- Clone and play the sound (so it doesn't interfere with the original)
    local soundClone = deathSound:Clone()
    soundClone.Parent = SoundService
    soundClone:Play()
    
    -- Cleanup after playing
    soundClone.Ended:Connect(function()
        soundClone:Destroy()
    end)
end

--[[
    Shows the death screen with fade-in animation.
]]
function DeathScreen.Show()
    if not screenGui then
        createUI()
    end
    
    if not screenGui or not overlay or not wastedLabel then return end
    
    screenGui.Enabled = true
    
    -- Play death sound
    playDeathSound()
    
    local stroke = wastedLabel:FindFirstChild("Outline") :: UIStroke?
    local shadow = wastedLabel:FindFirstChild("Shadow") :: TextLabel?
    
    -- Fade in overlay (to 0.6 transparency = 40% darkening)
    local overlayTween = TweenService:Create(
        overlay,
        TweenInfo.new(FADE_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {BackgroundTransparency = 0.5}
    )
    
    -- Fade in WASTED text
    local textTween = TweenService:Create(
        wastedLabel,
        TweenInfo.new(FADE_IN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {TextTransparency = 0, TextSize = 140} -- Slight scale up for impact
    )
    
    overlayTween:Play()
    textTween:Play()
    
    -- Fade in stroke
    if stroke then
        TweenService:Create(
            stroke,
            TweenInfo.new(FADE_IN_TIME),
            {Transparency = 0}
        ):Play()
    end
    
    -- Fade in shadow
    if shadow then
        TweenService:Create(
            shadow,
            TweenInfo.new(FADE_IN_TIME),
            {TextTransparency = 0.3, TextSize = 140}
        ):Play()
    end
end

--[[
    Hides the death screen with fade-out animation.
]]
function DeathScreen.Hide()
    if not screenGui or not overlay or not wastedLabel then return end
    
    local stroke = wastedLabel:FindFirstChild("Outline") :: UIStroke?
    local shadow = wastedLabel:FindFirstChild("Shadow") :: TextLabel?
    
    -- Fade out everything
    local overlayTween = TweenService:Create(
        overlay,
        TweenInfo.new(FADE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        {BackgroundTransparency = 1}
    )
    
    local textTween = TweenService:Create(
        wastedLabel,
        TweenInfo.new(FADE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        {TextTransparency = 1}
    )
    
    overlayTween:Play()
    textTween:Play()
    
    if stroke then
        TweenService:Create(
            stroke,
            TweenInfo.new(FADE_OUT_TIME),
            {Transparency = 1}
        ):Play()
    end
    
    if shadow then
        TweenService:Create(
            shadow,
            TweenInfo.new(FADE_OUT_TIME),
            {TextTransparency = 1}
        ):Play()
    end
    
    -- Disable after fade
    task.delay(FADE_OUT_TIME, function()
        if screenGui then
            screenGui.Enabled = false
            -- Reset text size for next show
            if wastedLabel then
                wastedLabel.TextSize = 120
            end
            if shadow then
                shadow.TextSize = 120
            end
        end
    end)
end

--[[
    Play the full death sequence (show, hold, hide).
]]
function DeathScreen.PlaySequence(holdTime: number?)
    DeathScreen.Show()
    
    task.delay(FADE_IN_TIME + (holdTime or HOLD_TIME), function()
        DeathScreen.Hide()
    end)
end

--[[
    Initialize death screen with ByteNet packet listener.
]]
function DeathScreen.Init()
    createUI()
    
    -- Import ByteNet packets
    local Rojo = ReplicatedStorage:WaitForChild("Rojo")
    local Shared = Rojo:WaitForChild("Shared")
    local packets = require(Shared:WaitForChild("Packets"))
    
    -- Listen for death packet from server
    packets.playerDeath.listen(function()
        DeathScreen.PlaySequence()
    end)
    
    print("[DeathScreen] Initialized with ByteNet!")
end

-- Auto-initialize
task.spawn(DeathScreen.Init)

return DeathScreen

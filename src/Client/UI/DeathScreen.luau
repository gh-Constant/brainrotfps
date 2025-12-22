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
local FADE_OUT_TIME = 0.5

-- Module
local DeathScreen = {}

-- UI References
local screenGui: ScreenGui? = nil
local overlay: Frame? = nil
local wastedLabel: TextLabel? = nil
local respawnButton: TextButton? = nil

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
    
    -- Respawn button
    local button = Instance.new("TextButton")
    button.Name = "RespawnButton"
    button.Size = UDim2.fromOffset(200, 60)
    button.Position = UDim2.new(0.5, -100, 0.65, 0)
    button.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
    button.BackgroundTransparency = 1 -- Start invisible
    button.Text = "RESPAWN"
    button.TextColor3 = Color3.fromRGB(255, 255, 255)
    button.Font = Enum.Font.GothamBold
    button.TextSize = 24
    button.TextTransparency = 1 -- Start invisible
    button.BorderSizePixel = 0
    button.AutoButtonColor = false
    button.Parent = gui
    
    -- Button styling (rounded corners)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = button
    
    -- Button stroke
    local buttonStroke = Instance.new("UIStroke")
    buttonStroke.Color = Color3.fromRGB(150, 0, 0)
    buttonStroke.Thickness = 3
    buttonStroke.Transparency = 1 -- Start invisible
    buttonStroke.Parent = button
    
    -- Store references
    screenGui = gui
    overlay = overlayFrame
    wastedLabel = wasted
    respawnButton = button
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
    
    -- Fade in respawn button after a short delay
    if respawnButton then
        local buttonStroke = respawnButton:FindFirstChild("UIStroke") :: UIStroke?
        
        task.wait(FADE_IN_TIME + 0.5) -- Wait for death animation
        
        TweenService:Create(
            respawnButton,
            TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            {BackgroundTransparency = 0, TextTransparency = 0}
        ):Play()
        
        if buttonStroke then
            TweenService:Create(
                buttonStroke,
                TweenInfo.new(0.4),
                {Transparency = 0}
            ):Play()
        end
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
    
    -- Fade out respawn button
    if respawnButton then
        local buttonStroke = respawnButton:FindFirstChild("UIStroke") :: UIStroke?
        
        TweenService:Create(
            respawnButton,
            TweenInfo.new(FADE_OUT_TIME),
            {BackgroundTransparency = 1, TextTransparency = 1}
        ):Play()
        
        if buttonStroke then
            TweenService:Create(
                buttonStroke,
                TweenInfo.new(FADE_OUT_TIME),
                {Transparency = 1}
            ):Play()
        end
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
    Play the full death sequence (show until manual respawn).
]]
function DeathScreen.PlaySequence()
    DeathScreen.Show()
    -- Note: No auto-hide, player must click respawn button
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
    
    -- Setup respawn button click handler
    if respawnButton then
        respawnButton.MouseButton1Click:Connect(function()
            -- Send respawn request to server
            packets.playerRespawn.send({})
            
            -- Hide death screen
            DeathScreen.Hide()
        end)
        
        -- Add hover effects
        respawnButton.MouseEnter:Connect(function()
            if respawnButton then
                TweenService:Create(
                    respawnButton,
                    TweenInfo.new(0.2),
                    {BackgroundColor3 = Color3.fromRGB(255, 80, 80)}
                ):Play()
            end
        end)
        
        respawnButton.MouseLeave:Connect(function()
            if respawnButton then
                TweenService:Create(
                    respawnButton,
                    TweenInfo.new(0.2),
                    {BackgroundColor3 = Color3.fromRGB(255, 50, 50)}
                ):Play()
            end
        end)
    end
    
    print("[DeathScreen] Initialized with ByteNet!")
end

-- Auto-initialize
task.spawn(DeathScreen.Init)

return DeathScreen

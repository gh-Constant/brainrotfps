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
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Configuration
local FADE_IN_TIME = 0.3
local FADE_OUT_TIME = 0.5

-- Module
local DeathScreen = {}

-- State
local canRespawn = false

-- UI References
local screenGui: ScreenGui? = nil
local overlay: Frame? = nil
local wastedLabel: TextLabel? = nil
local respawnButton: TextButton? = nil

--[[
    Finds the death screen UI elements from PlayerGui (copied from StarterGui).
    Resets all elements to hidden state so tweens can animate them in.
]]
local function findUI()
    -- Wait for existing DeathScreen in PlayerGui (from StarterGui)
    local gui = playerGui:WaitForChild("DeathScreen", 5) :: ScreenGui?
    if not gui then
        warn("[DeathScreen] DeathScreen ScreenGui not found in PlayerGui! Make sure it's in StarterGui.")
        return
    end
    
    -- Find overlay
    local overlayFrame = gui:FindFirstChild("Overlay") :: Frame?
    if not overlayFrame then
        warn("[DeathScreen] Overlay frame not found in DeathScreen!")
    end
    
    -- Find WASTED text
    local wasted = gui:FindFirstChild("WastedText") :: TextLabel?
    if not wasted then
        warn("[DeathScreen] WastedText label not found in DeathScreen!")
    end
    
    -- Find respawn button
    local button = gui:FindFirstChild("RespawnButton") :: TextButton?
    if not button then
        warn("[DeathScreen] RespawnButton not found in DeathScreen!")
    end
    
    -- Store references
    screenGui = gui
    overlay = overlayFrame
    wastedLabel = wasted
    respawnButton = button
    
    -- === RESET TO DEFAULT HIDDEN STATE FOR TWEENS ===
    -- You can design the UI visible in Studio, this code will hide it on load
    
    if screenGui then
        screenGui.Enabled = false
    end
    
    if overlay then
        overlay.BackgroundTransparency = 1
    end
    
    if wastedLabel then
        wastedLabel.TextTransparency = 1
        wastedLabel.TextSize = 120 -- Default size before scale-up tween
        
        local stroke = wastedLabel:FindFirstChild("Outline") :: UIStroke?
        if stroke then
            stroke.Transparency = 1
        end
        
        local shadow = wastedLabel:FindFirstChild("Shadow") :: TextLabel?
        if shadow then
            shadow.TextTransparency = 1
            shadow.TextSize = 120
        end
    end
    
    if respawnButton then
        respawnButton.BackgroundTransparency = 1
        respawnButton.TextTransparency = 1
        
        local buttonStroke = respawnButton:FindFirstChild("UIStroke") :: UIStroke?
        if buttonStroke then
            buttonStroke.Transparency = 1
        end
    end
    
    print("[DeathScreen] Found existing UI from StarterGui! Reset to hidden state.")
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
        findUI()
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
        
        -- Enable respawn input
        canRespawn = true
    end
end

--[[
    Hides the death screen with fade-out animation.
]]
function DeathScreen.Hide()
    if not screenGui or not overlay or not wastedLabel then return end
    
    -- Disable respawn input
    canRespawn = false
    
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
    findUI()
    
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
    
    -- Setup spacebar respawn listener
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if not canRespawn then return end
        
        if input.KeyCode == Enum.KeyCode.Space then
            -- Send respawn request to server
            packets.playerRespawn.send({})
            
            -- Hide death screen
            DeathScreen.Hide()
        end
    end)
    
    print("[DeathScreen] Initialized with ByteNet!")
end

-- Auto-initialize
task.spawn(DeathScreen.Init)

return DeathScreen

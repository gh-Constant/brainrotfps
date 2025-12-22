--!strict
--[[
    ValueHandler
    Client-side script that handles Health and XP progress bar updates.
    
    Expected UI Structure:
    - Bottom/HP/Current (Fill frame)
    - Bottom/HP/CurrentHP (TextLabel)
    - Bottom/XP/Current (Fill frame)
    - Bottom/XP/CurrentLevel (TextLabel)
    - Bottom/XP/CurrentXP (TextLabel)
]]

local Players = game:GetService("Players")

-- Get ProgressBar module (same folder)
local ProgressBar = require(script.Parent.ProgressBar)

local player = Players.LocalPlayer

-- Module for external access
local ValueHandler = {}

-- Progress bar references (set during Init)
local healthBar: any = nil
local xpBar: any = nil

--[[
    Updates the health bar based on character attributes.
]]
local function updateHealth()
    if not healthBar then return end
    
    local character = player.Character
    if not character then return end
    
    -- Use attributes from Custom Health System
    local currentHP = character:GetAttribute("Health") or 100
    local maxHP = character:GetAttribute("MaxHealth") or 100
    
    healthBar:SetValue(currentHP, maxHP)
end

--[[
    Updates the XP bar based on leaderstats.
]]
local function updateXP()
    if not xpBar then return end
    
    local leaderstats = player:FindFirstChild("leaderstats")
    if not leaderstats then return end
    
    local levelValue = leaderstats:FindFirstChild("Level")
    local xpValueObj = leaderstats:FindFirstChild("XP")
    
    local level = levelValue and levelValue.Value or 1
    local totalXP = xpValueObj and xpValueObj.Value or 0
    
    -- Update level label
    xpBar:SetSecondaryLabel("Lv. " .. tostring(level))
    
    -- Simple XP formula: level * 100 (level 1 = 100, level 2 = 200, level 4 = 400, etc.)
    local requiredXP = level * 100
    
    -- Calculate XP progress within current level
    -- Total XP needed to reach current level = sum of all previous levels = 100 * (level-1) * level / 2
    local xpToReachCurrentLevel = 100 * (level - 1) * level / 2
    local currentXP = totalXP - xpToReachCurrentLevel
    
    -- Clamp to valid range
    currentXP = math.clamp(currentXP, 0, requiredXP)
    
    xpBar:SetValue(currentXP, requiredXP)
end

--[[
    Sets up health tracking for a character.
]]
local function onCharacterAdded(character: Model)
    -- Initial update
    updateHealth()
    
    -- Listen for health attribute changes (Custom Health System)
    character:GetAttributeChangedSignal("Health"):Connect(updateHealth)
    character:GetAttributeChangedSignal("MaxHealth"):Connect(updateHealth)
end

--[[
    Initializes the ValueHandler with the given client context.
    @param context - ClientContext with Player, PlayerGui, Character, etc.
]]
function ValueHandler.Init(context: any)
    local player = context.Player
    local playerGui = context.PlayerGui
    
    -- Wait for UI with timeout
    local baseGui = playerGui:WaitForChild("Base", 10)
    if not baseGui then
        warn("[ValueHandler] Base UI not found in PlayerGui!")
        return
    end
    
    local bottom = baseGui:WaitForChild("Bottom", 5)
    if not bottom then
        warn("[ValueHandler] Bottom frame not found!")
        return
    end
    
    -- HP Bar Elements
    local hpFrame = bottom:WaitForChild("HP", 5)
    local hpFill = hpFrame and hpFrame:WaitForChild("Current", 5)
    local hpLabel = hpFrame and hpFrame:WaitForChild("CurrentHP", 5) :: TextLabel?
    
    -- XP Bar Elements
    local xpFrame = bottom:WaitForChild("XP", 5)
    local xpFill = xpFrame and xpFrame:WaitForChild("Current", 5)
    local levelLabel = xpFrame and xpFrame:WaitForChild("CurrentLevel", 5) :: TextLabel?
    local xpLabel = xpFrame and xpFrame:WaitForChild("CurrentXP", 5) :: TextLabel?
    
    -- Create progress bar controllers only if UI exists
    if hpFrame and hpFill and hpLabel then
        healthBar = ProgressBar.new({
            Container = hpFrame,
            Fill = hpFill,
            ValueLabel = hpLabel,
            TweenDuration = 0.2,
            ValueFormat = "%d",  -- Just show current HP
        })
        ValueHandler.HealthBar = healthBar
    else
        warn("[ValueHandler] HP bar UI elements not found!")
    end
    
    if xpFrame and xpFill and xpLabel and levelLabel then
        xpBar = ProgressBar.new({
            Container = xpFrame,
            Fill = xpFill,
            ValueLabel = xpLabel,
            SecondaryLabel = levelLabel,
            TweenDuration = 0.3,
            ValueFormat = "%d / %d XP",
        })
        ValueHandler.XPBar = xpBar
    else
        warn("[ValueHandler] XP bar UI elements not found!")
    end
    
    -- Setup health tracking for current character
    task.spawn(onCharacterAdded, context.Character)
    
    -- Setup future character handling
    player.CharacterAdded:Connect(onCharacterAdded)
    
    -- Setup XP tracking (in background to not block)
    task.spawn(function()
        local leaderstats = player:WaitForChild("leaderstats", 10)
        if not leaderstats then
            warn("[ValueHandler] leaderstats not found!")
            return
        end
        
        local levelValue = leaderstats:WaitForChild("Level", 5)
        local xpValueObj = leaderstats:WaitForChild("XP", 5)
        
        if not levelValue or not xpValueObj then
            warn("[ValueHandler] Level or XP value not found in leaderstats!")
            return
        end
        
        -- Initial update
        updateXP()
        
        -- Listen for changes
        levelValue:GetPropertyChangedSignal("Value"):Connect(updateXP)
        xpValueObj:GetPropertyChangedSignal("Value"):Connect(updateXP)
    end)
    
    print("[ValueHandler] Initialized!")
end

return ValueHandler

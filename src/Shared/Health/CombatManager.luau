--!strict
--[[
    CombatManager.luau
    Handles combat state and timers for players.
]]

local RunService = game:GetService("RunService")

local CombatManager = {}

-- Constants
local COMBAT_DURATION = 13 -- seconds
local ATTR_IN_COMBAT = "InCombat"
local ATTR_COMBAT_COUNTDOWN = "CombatCountdown"

--[[
    Put a character into combat state with countdown timer.
    Only runs on server.
    
    OPTIMIZED: Instead of spawning a new countdown thread on each hit,
    we just reset the countdown value. A single persistent thread per character
    handles the countdown, preventing thread spam from rapid hits.
]]
function CombatManager.EnterCombat(character: Model)
    if not RunService:IsServer() then return end
    if not character then return end
    
    -- Reset countdown to full duration
    character:SetAttribute(ATTR_COMBAT_COUNTDOWN, COMBAT_DURATION)
    
    -- If already in combat, just reset the timer - don't spawn a new thread
    if character:GetAttribute(ATTR_IN_COMBAT) then
        return
    end
    
    -- Set combat state (first time entering combat)
    character:SetAttribute(ATTR_IN_COMBAT, true)
    
    -- Start a single countdown loop for this combat session
    task.spawn(function()
        while character and character.Parent do
            local countdown = character:GetAttribute(ATTR_COMBAT_COUNTDOWN) :: number?
            
            if not countdown or countdown <= 0 then
                -- Combat ended
                character:SetAttribute(ATTR_IN_COMBAT, false)
                character:SetAttribute(ATTR_COMBAT_COUNTDOWN, nil)
                break
            end
            
            task.wait(1)
            
            -- Decrement countdown (check if still valid)
            if character and character.Parent then
                local currentCountdown = character:GetAttribute(ATTR_COMBAT_COUNTDOWN) :: number?
                if currentCountdown and currentCountdown > 0 then
                    character:SetAttribute(ATTR_COMBAT_COUNTDOWN, currentCountdown - 1)
                end
            end
        end
    end)
end

--[[
    Check if a character is currently in combat.
]]
function CombatManager.IsInCombat(character: Model): boolean
    if not character then return false end
    return character:GetAttribute(ATTR_IN_COMBAT) == true
end

--[[
    Get remaining combat time for a character.
]]
function CombatManager.GetCombatTimeRemaining(character: Model): number
    if not character then return 0 end
    return (character:GetAttribute(ATTR_COMBAT_COUNTDOWN) :: number?) or 0
end

--[[
    Force exit combat state immediately.
    Only runs on server.
]]
function CombatManager.ExitCombat(character: Model)
    if not RunService:IsServer() then return end
    if not character then return end
    
    -- Set countdown to 0 so the loop exits on next tick
    character:SetAttribute(ATTR_COMBAT_COUNTDOWN, 0)
end

return CombatManager

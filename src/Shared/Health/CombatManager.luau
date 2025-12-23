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
local ATTR_COMBAT_TIMER = "_CombatTimer"
local ATTR_COMBAT_COUNTDOWN = "CombatCountdown"

--[[
    Put a character into combat state with countdown timer.
    Only runs on server.
]]
function CombatManager.EnterCombat(character: Model)
    if not RunService:IsServer() then return end
    if not character then return end
    
    -- Set combat state
    character:SetAttribute(ATTR_IN_COMBAT, true)
    
    -- Increment timer ID to invalidate previous timers
    local currentTimer = (character:GetAttribute(ATTR_COMBAT_TIMER) :: number?) or 0
    local newTimerId = currentTimer + 1
    character:SetAttribute(ATTR_COMBAT_TIMER, newTimerId)
    character:SetAttribute(ATTR_COMBAT_COUNTDOWN, COMBAT_DURATION)
    
    -- Start countdown
    task.spawn(function()
        for i = COMBAT_DURATION, 0, -1 do
            -- Check if this timer is still valid
            if not character or not character.Parent then
                break
            end
            if character:GetAttribute(ATTR_COMBAT_TIMER) ~= newTimerId then
                break
            end
            
            character:SetAttribute(ATTR_COMBAT_COUNTDOWN, i)
            
            if i == 0 then
                character:SetAttribute(ATTR_IN_COMBAT, false)
                character:SetAttribute(ATTR_COMBAT_COUNTDOWN, nil)
            else
                task.wait(1)
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
    
    -- Increment timer to invalidate any running countdown
    local currentTimer = (character:GetAttribute(ATTR_COMBAT_TIMER) :: number?) or 0
    character:SetAttribute(ATTR_COMBAT_TIMER, currentTimer + 1)
    character:SetAttribute(ATTR_IN_COMBAT, false)
    character:SetAttribute(ATTR_COMBAT_COUNTDOWN, nil)
end

return CombatManager

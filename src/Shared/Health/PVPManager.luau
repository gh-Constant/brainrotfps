--!strict
--[[
    PVPManager.luau
    Handles PVP (Player vs Player) checks and validation.
]]

local Players = game:GetService("Players")

local PVPManager = {}

-- Attribute names
local ATTR_PVP_ENABLED = "IsPvPEnabled"

--[[
    Check if an attacker can damage a target.
    Returns true if damage is allowed, false if blocked by PVP settings.
    
    Rules:
    - If attacker is not a player (nil or NPC), allow damage
    - If target is not a player character (NPC/mob), allow damage
    - If BOTH attacker AND target are players, BOTH must have PVP enabled
]]
function PVPManager.CanDamage(attacker: Player?, targetInstance: Instance): boolean
    -- If no attacker specified (environment damage, NPC, etc), allow damage
    if not attacker then
        return true
    end
    
    -- Check if target is a player character
    local targetPlayer: Player? = nil
    if targetInstance:IsA("Model") then
        targetPlayer = Players:GetPlayerFromCharacter(targetInstance)
    end
    
    -- If target is not a player (NPC/mob), allow damage
    if not targetPlayer then
        return true
    end
    
    -- Both are players - check PVP settings for BOTH
    local attackerChar = attacker.Character
    if not attackerChar then
        return false
    end
    
    local attackerPvPEnabled = attackerChar:GetAttribute(ATTR_PVP_ENABLED)
    local targetPvPEnabled = targetInstance:GetAttribute(ATTR_PVP_ENABLED)
    
    -- BOTH players must have PVP enabled for damage to occur
    if not attackerPvPEnabled or not targetPvPEnabled then
        return false
    end
    
    return true
end

--[[
    Check if a player has PVP enabled.
]]
function PVPManager.IsPvPEnabled(player: Player): boolean
    local character = player.Character
    if not character then
        return false
    end
    return character:GetAttribute(ATTR_PVP_ENABLED) == true
end

--[[
    Get the target player from an instance (if it's a player character).
]]
function PVPManager.GetPlayerFromInstance(instance: Instance): Player?
    if instance:IsA("Model") then
        return Players:GetPlayerFromCharacter(instance)
    end
    return nil
end

return PVPManager

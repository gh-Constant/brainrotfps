--!strict
--[[
    Shared Player Module
    Re-exports all shared player utilities.
]]

local PlayerData = require(script.PlayerData)
local RagdollUtils = require(script.RagdollUtils)

export type PlayerData = PlayerData.PlayerData
export type Player = PlayerData.Player

return {
    -- Classes
    PlayerData = PlayerData,
    
    -- Utilities
    RagdollUtils = RagdollUtils,
    
    -- Re-export constructors for convenience
    new = PlayerData.new,
    GetDefaultData = PlayerData.GetDefaultData,
}

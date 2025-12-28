--!strict
--[[
    Shared Rarity Module
    Re-exports rarity configuration and visual utilities.
]]

local RarityConfig = require(script.RarityConfig)
-- RarityVisual was replaced by ColorSystem, redirecting for backward compatibility
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Rojo"):WaitForChild("Shared")
local ColorSystem = require(Shared:WaitForChild("Inventory"):WaitForChild("ColorSystem"))

-- Re-export types
export type RarityVisualConfig = RarityConfig.RarityVisualConfig

return {
    -- Modules
    Config = RarityConfig,
    Visual = ColorSystem,
    
    -- Convenience re-exports
    GetColor = RarityConfig.GetColor,
    GetConfig = RarityConfig.GetConfig,
    IsAnimated = RarityConfig.IsAnimated,
    ApplyToFrame = ColorSystem.ApplyToFrame,
    ApplyToHighlight = ColorSystem.ApplyToHighlight,
    CreateHighlight = ColorSystem.CreateHighlight,
    StopAnimation = ColorSystem.StopAnimation,
}

--!strict
--[[
    Shared Rarity Module
    Re-exports rarity configuration and visual utilities.
]]

local RarityConfig = require(script.RarityConfig)
local RarityVisual = require(script.RarityVisual)

-- Re-export types
export type RarityVisualConfig = RarityConfig.RarityVisualConfig

return {
    -- Modules
    Config = RarityConfig,
    Visual = RarityVisual,
    
    -- Convenience re-exports
    GetColor = RarityConfig.GetColor,
    GetConfig = RarityConfig.GetConfig,
    IsAnimated = RarityConfig.IsAnimated,
    ApplyToFrame = RarityVisual.ApplyToFrame,
    ApplyToHighlight = RarityVisual.ApplyToHighlight,
    CreateHighlight = RarityVisual.CreateHighlight,
    StopAnimation = RarityVisual.StopAnimation,
}

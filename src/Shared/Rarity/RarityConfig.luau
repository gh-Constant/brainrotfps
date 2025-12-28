--!strict
--[[
    Rarity Configuration
    Defines available rarities and maps them to visual styles in ColorSystem.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ColorSystem = require(ReplicatedStorage:WaitForChild("Rojo"):WaitForChild("Shared"):WaitForChild("Inventory"):WaitForChild("ColorSystem"))

type ColorVisualConfig = ColorSystem.ColorVisualConfig

--[[
    Map rarities to ColorSystem styles.
]]
local RarityToStyle = {
    Common = "BasicGray",
    Uncommon = "VibrantGreen",
    Epic = "AmethystVoid",
    Legendary = "SolarFlare",
    Mythic = "NeonMagenta",
    Secret = "MonochromeCycle",
    God = "RainbowFlow",
}

--[[
    Gets the configuration for a rarity.
    
    @param rarityName - Name of the rarity
    @return ColorVisualConfig? - Config or nil if not found
]]
local function GetConfig(rarityName: string): ColorVisualConfig?
    local style = RarityToStyle[rarityName]
    if style then
        return ColorSystem.GetColorConfig(style)
    end
    return nil
end

--[[
    Gets just the base color for a rarity.
    
    @param rarityName - Name of the rarity
    @return Color3 - The color (white if not found)
]]
local function GetColor(rarityName: string): Color3
    local config = GetConfig(rarityName)
    if config then
        return config.Color
    end
    return Color3.fromRGB(255, 255, 255)
end

--[[
    Checks if a rarity has animation.
]]
local function IsAnimated(rarityName: string): boolean
    local config = GetConfig(rarityName)
    return config ~= nil and config.Animated == true
end

return {
    -- Export the underlying mapping for reference if needed
    RarityToStyle = RarityToStyle,
    

    -- API (Backward compatible)
    GetConfig = GetConfig,
    GetColor = GetColor,
    IsAnimated = IsAnimated,
}

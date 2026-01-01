--!strict
--[[
    Rarity Configuration
    Defines available rarities and maps them to visual styles in ColorSystem.
    Each rarity has separate BackgroundColor and TextColor that can link to 
    different or same styles in ColorSystem.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ColorSystem = require(ReplicatedStorage:WaitForChild("Rojo"):WaitForChild("Shared"):WaitForChild("Inventory"):WaitForChild("ColorSystem"))

type ColorVisualConfig = ColorSystem.ColorVisualConfig

--[[
    Rarity visual mapping type.
    BackgroundStyle: ColorSystem style name for background visuals
    TextStyle: ColorSystem style name for text visuals
]]
export type RarityVisuals = {
    BackgroundStyle: string,
    TextStyle: string,
}

--[[
    Map rarities to background and text ColorSystem styles.
    These can be the same style or different ones.
]]
local RarityStyles: {[string]: RarityVisuals} = {
    Common = {
        BackgroundStyle = "VibrantGreen",
        TextStyle = "VibrantGreen",
    },
    Rare = {
        BackgroundStyle = "Rarity_Rare",
        TextStyle = "Rarity_Rare",
    },
    Epic = {
        BackgroundStyle = "Rarity_Epic",
        TextStyle = "AmethystVoid",
    },
    Legendary = {
        BackgroundStyle = "Rarity_Legendary",
        TextStyle = "SolarFlare",
    },
    Mythic = {
        BackgroundStyle = "Rarity_Mythic",
        TextStyle = "NeonMagenta",
    },
    God = {
        BackgroundStyle = "Rarity_God",
        TextStyle = "RainbowFlow",
    },
    Secret = {
        BackgroundStyle = "Rarity_Secret",
        TextStyle = "Zebra",
    },
}

-- Ordered list of rarities from least rare (index 1) to most rare (last index)
-- Used for sorting items - higher index = rarer
local RarityOrder: {string} = {
    "Common",

    "Rare",
    "Epic",
    "Legendary",
    "Mythic",
    "God",
    "Secret",
}

--[[
    Gets the visuals mapping for a rarity.
    
    @param rarityName - Name of the rarity
    @return RarityVisuals? - The background/text style mapping or nil
]]
local function GetRarityVisuals(rarityName: string): RarityVisuals?
    return RarityStyles[rarityName]
end

--[[
    Gets the background config for a rarity.
    
    @param rarityName - Name of the rarity
    @return ColorVisualConfig? - Config or nil if not found
]]
local function GetBackgroundConfig(rarityName: string): ColorVisualConfig?
    local visuals = RarityStyles[rarityName]
    if visuals then
        return ColorSystem.GetColorConfig(visuals.BackgroundStyle)
    end
    return nil
end

--[[
    Gets the text config for a rarity.
    
    @param rarityName - Name of the rarity
    @return ColorVisualConfig? - Config or nil if not found
]]
local function GetTextConfig(rarityName: string): ColorVisualConfig?
    local visuals = RarityStyles[rarityName]
    if visuals then
        return ColorSystem.GetColorConfig(visuals.TextStyle)
    end
    return nil
end

--[[
    Gets the configuration for a rarity (legacy - uses background style).
    
    @param rarityName - Name of the rarity
    @return ColorVisualConfig? - Config or nil if not found
]]
local function GetConfig(rarityName: string): ColorVisualConfig?
    return GetBackgroundConfig(rarityName)
end

--[[
    Gets just the base color for a rarity (from background style).
    
    @param rarityName - Name of the rarity
    @return Color3 - The color (white if not found)
]]
local function GetColor(rarityName: string): Color3
    local config = GetBackgroundConfig(rarityName)
    if config then
        return config.Color
    end
    return Color3.fromRGB(255, 255, 255)
end

--[[
    Gets the background style name for a rarity.
]]
local function GetBackgroundStyle(rarityName: string): string?
    local visuals = RarityStyles[rarityName]
    return visuals and visuals.BackgroundStyle
end

--[[
    Gets the text style name for a rarity.
]]
local function GetTextStyle(rarityName: string): string?
    local visuals = RarityStyles[rarityName]
    return visuals and visuals.TextStyle
end

--[[
    Checks if a rarity's background has animation.
]]
local function IsBackgroundAnimated(rarityName: string): boolean
    local config = GetBackgroundConfig(rarityName)
    return config ~= nil and config.Animated == true
end

--[[
    Checks if a rarity's text has animation.
]]
local function IsTextAnimated(rarityName: string): boolean
    local config = GetTextConfig(rarityName)
    return config ~= nil and config.Animated == true
end

--[[
    Checks if a rarity has animation (legacy - checks background).
]]
local function IsAnimated(rarityName: string): boolean
    return IsBackgroundAnimated(rarityName)
end

--[[
    Gets the rarity name based on event count.
    2 Events: Common
    4 Events: Rare
    6 Events: Epic
    8 Events: Legendary
    10 Events: God
    12+ Events: Secret
]]
local function GetEventRarity(eventCount: number): string
    if eventCount >= 12 then
        return "Secret"
    elseif eventCount >= 10 then
        return "God"
    elseif eventCount >= 8 then
        return "Legendary"
    elseif eventCount >= 6 then
        return "Epic"
    elseif eventCount >= 4 then
        return "Rare"
    else
        return "Common"
    end
end

return {
    -- Export the underlying mapping for reference if needed
    RarityStyles = RarityStyles,
    RarityOrder = RarityOrder, -- Ordered list from least rare to most rare
    
    -- New API
    GetRarityVisuals = GetRarityVisuals,
    GetBackgroundConfig = GetBackgroundConfig,
    GetTextConfig = GetTextConfig,
    GetBackgroundStyle = GetBackgroundStyle,
    GetTextStyle = GetTextStyle,
    IsBackgroundAnimated = IsBackgroundAnimated,
    IsTextAnimated = IsTextAnimated,

    -- Legacy API (Backward compatible)
    GetConfig = GetConfig,
    GetColor = GetColor,
    IsAnimated = IsAnimated,
    GetEventRarity = GetEventRarity,
}

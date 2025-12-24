--!strict
--[[
    Rarity Configuration
    Defines colors and visual properties for each rarity tier.
    
    EASY TO MODIFY:
    - Static colors: Just change the Color3 values
    - Gradients: Use ColorSequence for multi-color effects
    - Animated: Set Animated = true and provide animation properties
    
    For non-coders:
    - Colors use RGB values from 0-255
    - Gradients use ColorSequence (can be created in Studio)
]]

export type RarityVisualConfig = {
    -- Basic color (required)
    Color: Color3,
    
    -- Optional: Gradient for more complex visuals
    Gradient: ColorSequence?,
    GradientRotation: number?, -- Degrees, default 0
    
    -- Optional: Animation settings
    Animated: boolean?,
    AnimationType: ("Pulse" | "Rainbow" | "Cycle")?,
    AnimationSpeed: number?, -- Cycles per second
    AnimationColors: {Color3}?, -- For "Cycle" type
}

export type RarityConfigMap = {[string]: RarityVisualConfig}

--[[
    Default rarity configurations.
    Modify these values to change how rarities look in-game.
]]
local RarityConfig: RarityConfigMap = {
    -- Common: Gray, simple
    Common = {
        Color = Color3.fromRGB(180, 180, 180),
    },
    
    -- Uncommon: Green
    Uncommon = {
        Color = Color3.fromRGB(30, 255, 0),
    },
    
    -- Epic: Purple
    Epic = {
        Color = Color3.fromRGB(163, 53, 238),
    },
    
    -- Legendary: Orange/Gold
    Legendary = {
        Color = Color3.fromRGB(255, 165, 0),
        Gradient = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 0)),
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 140, 0)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 200, 0)),
        }),
    },
    
    -- Mythic: Pink/Magenta
    Mythic = {
        Color = Color3.fromRGB(255, 0, 128),
        Gradient = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 128)),
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 100, 200)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 128)),
        }),
        Animated = true,
        AnimationType = "Pulse",
        AnimationSpeed = 1,
    },
    
    -- Secret: Rainbow cycling
    Secret = {
        Color = Color3.fromRGB(0, 255, 255), -- Fallback
        Animated = true,
        AnimationType = "Rainbow",
        AnimationSpeed = 0.5,
    },
    
    -- God: Gold with intense animation
    God = {
        Color = Color3.fromRGB(255, 215, 0),
        Gradient = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 150)),
            ColorSequenceKeypoint.new(0.3, Color3.fromRGB(255, 215, 0)),
            ColorSequenceKeypoint.new(0.6, Color3.fromRGB(255, 180, 0)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 150)),
        }),
        Animated = true,
        AnimationType = "Cycle",
        AnimationSpeed = 2,
        AnimationColors = {
            Color3.fromRGB(255, 255, 150),
            Color3.fromRGB(255, 215, 0),
            Color3.fromRGB(255, 180, 0),
            Color3.fromRGB(255, 200, 50),
        },
    },
}

--[[
    Gets the configuration for a rarity.
    
    @param rarityName - Name of the rarity
    @return RarityVisualConfig? - Config or nil if not found
]]
local function GetConfig(rarityName: string): RarityVisualConfig?
    return RarityConfig[rarityName]
end

--[[
    Gets just the base color for a rarity.
    
    @param rarityName - Name of the rarity
    @return Color3 - The color (white if not found)
]]
local function GetColor(rarityName: string): Color3
    local config = RarityConfig[rarityName]
    if config then
        return config.Color
    end
    return Color3.fromRGB(255, 255, 255)
end

--[[
    Checks if a rarity has animation.
]]
local function IsAnimated(rarityName: string): boolean
    local config = RarityConfig[rarityName]
    return config ~= nil and config.Animated == true
end

return {
    Config = RarityConfig,
    GetConfig = GetConfig,
    GetColor = GetColor,
    IsAnimated = IsAnimated,
}

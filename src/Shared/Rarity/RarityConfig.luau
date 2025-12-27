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
    AnimationType: ("Pulse" | "Rainbow" | "Cycle" | "RotatingGradient")?,
    AnimationSpeed: number?, -- Cycles per second
    AnimationColors: {Color3}?, -- For "Cycle" type
    LightColor: Color3?, -- For "RotatingGradient" type (the lighter line color)
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
    
    -- Epic: Dark purple with rotating lighter lines
    Epic = {
        Color = Color3.fromRGB(90, 30, 130), -- Dark purple base
        LightColor = Color3.fromRGB(230, 180, 255), -- Bright, almost white purple for the lines
        Animated = true,
        AnimationType = "RotatingGradient",
        AnimationSpeed = 0.3, -- Slow rotation (0.3 rotations per second)
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
    
    -- Secret: Black and white pulse
    Secret = {
        Color = Color3.fromRGB(255, 255, 255), -- White base
        Animated = true,
        AnimationType = "Cycle",
        AnimationSpeed = 1.5,
        AnimationColors = {
            Color3.fromRGB(0, 0, 0),       -- Black
            Color3.fromRGB(255, 255, 255), -- White
        },
    },
    
    -- God: Rainbow cycling
    God = {
        Color = Color3.fromRGB(255, 215, 0), -- Gold fallback
        Animated = true,
        AnimationType = "Rainbow",
        AnimationSpeed = 0.5,
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

--!strict
--[[
    Color System (Visual Styles) - OPTIMIZED WITH ezVisuals
    Defines all visual styles for items, including colors, gradients, and animations.
    
    PERFORMANCE OPTIMIZATIONS:
    - Uses ezVisuals library (preserves original visual styles)
    - Tracks all effects for global PauseAll/ResumeAll when inventory closes
    - Proper cleanup to prevent memory leaks
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Packages = Rojo:WaitForChild("Packages")

-- Require ezVisuals
local ezVisuals = require(Packages:WaitForChild("ezvisualz"))

-- Custom synced effects for synchronized animations
local ZebraSynced = require(script.Parent.ZebraSynced)
local RainbowSynced = require(script.Parent.RainbowSynced)

export type ColorVisualConfig = {
    -- Basic color (required)
    Color: Color3,
    
    -- ezVisuals Mappings
    BackgroundPreset: string?, -- e.g. "Gold", "Zebra"
    StrokePreset: string?,     -- e.g. "GoldStroke"
    TextPreset: string?,       -- e.g. "Gold" (mapped to text gradient)
    
    -- Animation flag
    Animated: boolean?,
    
    -- Gradient (New support)
    Gradient: ColorSequence?,
    GradientRotation: number?,

    -- Legacy/Fallback or Custom params
    Speed: number?,
    Size: number?,
    
    -- Keep Gradient/LightColor for custom fallback if needed, or for passed params
    LightColor: Color3?, 
}

export type ColorSystemMap = {[string]: ColorVisualConfig}

--[[
    Load External Styles from Config
]]
local function loadExternalStyles(stylesMap: ColorSystemMap)
    local config = ReplicatedStorage:FindFirstChild("Config")
    if not config then return end
    
    local inventory = config:FindFirstChild("Inventory")
    if not inventory then return end
    
    -- Check for RarityGradient folder (User request)
    local rarityGradient = inventory:FindFirstChild("RarityGradient")
    if rarityGradient then
        for _, child in rarityGradient:GetChildren() do
            if child:IsA("UIGradient") then
                stylesMap[child.Name] = {
                    Color = child.Color.Keypoints[1].Value, -- Fallback color from start of gradient
                    Gradient = child.Color,
                    GradientRotation = child.Rotation,
                }
            end
        end
    end
end


--[[
    Defined Styles
]]
local Styles: ColorSystemMap = {
    -- Default / Common: Gray
    BasicGray = {
        Color = Color3.fromRGB(180, 180, 180),
        StrokePreset = "SilverStroke", -- Fallback/Simple
        BackgroundPreset = "Silver",
    },
    
    -- New Rarity Styles (Gradient Based)
    Rarity_Common = {
        Color = Color3.fromRGB(25, 255, 0), -- Fallback
        Gradient = ColorSequence.new({
             ColorSequenceKeypoint.new(0.000, Color3.new(0.220, 0.220, 0.220)),
             ColorSequenceKeypoint.new(1.000, Color3.new(0.102, 1.000, 0.000))
        }),
        GradientRotation = -90,
        StrokePreset = "SilverStroke", 
    },
    
    Rarity_Rare = {
        Color = Color3.fromRGB(0, 145, 255), -- Fallback
        Gradient = ColorSequence.new({
             ColorSequenceKeypoint.new(0.000, Color3.new(0.220, 0.220, 0.220)),
             ColorSequenceKeypoint.new(1.000, Color3.new(0.000, 0.569, 1.000))
        }),
        GradientRotation = -90,
        StrokePreset = "GreenOutline", 
    },

    Rarity_Epic = {
        Color = Color3.fromRGB(200, 0, 255), -- Fallback
        Gradient = ColorSequence.new({
             ColorSequenceKeypoint.new(0.000, Color3.new(0.220, 0.220, 0.220)),
             ColorSequenceKeypoint.new(1.000, Color3.new(0.784, 0.000, 1.000))
        }),
        GradientRotation = -90,
        StrokePreset = "DeathStroke", 
    },

    Rarity_Legendary = {
        Color = Color3.fromRGB(255, 190, 0), -- Fallback
        Gradient = ColorSequence.new({
             ColorSequenceKeypoint.new(0.000, Color3.new(0.220, 0.220, 0.220)),
             ColorSequenceKeypoint.new(1.000, Color3.new(1.000, 0.749, 0.000))
        }),
        GradientRotation = -90,
        StrokePreset = "GoldStroke",
    },

    Rarity_Mythic = {
        Color = Color3.fromRGB(255, 0, 4), -- Fallback
        Gradient = ColorSequence.new({
             ColorSequenceKeypoint.new(0.000, Color3.new(0.220, 0.220, 0.220)),
             ColorSequenceKeypoint.new(1.000, Color3.new(1.000, 0.000, 0.016))
        }),
        GradientRotation = -90,
        StrokePreset = "ChromeStroke",
    },

    Rarity_God = {
        Color = Color3.fromRGB(255, 0, 255), -- Fallback
        Gradient = ColorSequence.new({
             ColorSequenceKeypoint.new(0.000, Color3.new(0.000, 0.000, 0.000)),
             ColorSequenceKeypoint.new(0.090, Color3.new(0.122, 0.094, 0.094)),
             ColorSequenceKeypoint.new(0.408, Color3.new(1.000, 0.227, 0.239)),
             ColorSequenceKeypoint.new(0.652, Color3.new(0.949, 0.000, 0.933)),
             ColorSequenceKeypoint.new(0.925, Color3.new(0.103, 0.000, 0.997)),
             ColorSequenceKeypoint.new(1.000, Color3.new(0.067, 0.000, 1.000))
        }),
        GradientRotation = -45,
        StrokePreset = "RainbowStroke",
    },

    Rarity_Secret = {
        Color = Color3.fromRGB(255, 255, 255), -- Fallback
        Gradient = ColorSequence.new({
             ColorSequenceKeypoint.new(0.000, Color3.new(0.220, 0.220, 0.220)),
             ColorSequenceKeypoint.new(1.000, Color3.new(1.000, 1.000, 1.000))
        }),
        GradientRotation = -90,
        StrokePreset = nil,
    },
    
    -- Epic: Dark purple
    AmethystVoid = {
        Color = Color3.fromRGB(180, 80, 255), -- Brighter purple for visibility
        StrokePreset = "DeathStroke",
    },
    
    -- Legenday: Yellow/Gold
    SolarFlare = {
        Color = Color3.fromRGB(255, 240, 100), -- Lighter yellow/gold
        BackgroundPreset = "Gold",
        StrokePreset = "GoldStroke",
        Speed = 0.2,
    },
    
    -- Mythic: Pink/Magenta
    NeonMagenta = {
        Color = Color3.fromRGB(255, 0, 128),
        BackgroundPreset = "Shine", 
        StrokePreset = "ChromeStroke",
        Speed = 0.3,
    },
    
    -- Zebra animated (for text effects)
    Zebra = {
        Color = Color3.fromRGB(255, 255, 255),
        BackgroundPreset = "Zebra",
        TextPreset = "Zebra",
        StrokePreset = nil,
        Speed = 0.4,
        Animated = true,
    },
    
    -- Zebra static (black/white non-animated for backgrounds)
    ZebraStatic = {
        Color = Color3.fromRGB(40, 40, 40),
        LightColor = Color3.fromRGB(255, 255, 255),
        BackgroundPreset = nil,
        StrokePreset = nil,
        Animated = false,
    },
    
    -- Legacy: Keep MonochromeCycle for backward compatibility
    MonochromeCycle = {
        Color = Color3.fromRGB(255, 255, 255),
        BackgroundPreset = "Zebra",
        StrokePreset = nil, 
        Speed = 0.4,
    },
    
    -- God: Rainbow
    RainbowFlow = {
        Color = Color3.fromRGB(255, 255, 255), -- White base for rainbow tint
        BackgroundPreset = "Rainbow",
        TextPreset = "Rainbow", -- Explicitly set text preset
        StrokePreset = "RainbowStroke",
        Speed = 0.5, -- Standard speed
    },
    
    -- Custom Example: Fire
    Fire = {
        Color = Color3.fromRGB(255, 50, 0),
        BackgroundPreset = "Lava",
        StrokePreset = "FireStroke",
        Speed = 0.3,
    },
    
    -- Custom Example: Ice
    Ice = {
        Color = Color3.fromRGB(0, 255, 255),
        BackgroundPreset = "IceStroke",
        StrokePreset = "IceStroke",
        Speed = 0.3,
    },

    -- Custom: Green Pulse
    GreenPulse = {
        Color = Color3.fromRGB(50, 255, 50),
        StrokePreset = "GreenOutline",
        Speed = 0.2,
    },
    
    -- ===========================================
    -- VIBRANT COLOR STYLES (for potions/custom items)
    -- ===========================================
    
    -- Vibrant Red
    VibrantRed = {
        Color = Color3.fromRGB(255, 50, 50),
        Gradient = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(60, 15, 15)),
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(200, 30, 30)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 80))
        }),
        GradientRotation = -90,
    },
    
    -- Vibrant Green
    VibrantGreen = {
        Color = Color3.fromRGB(50, 255, 80),
        Gradient = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(15, 60, 20)),
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(30, 200, 60)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 255, 130))
        }),
        GradientRotation = -90,
    },
    
    -- Vibrant Blue
    VibrantBlue = {
        Color = Color3.fromRGB(50, 150, 255),
        Gradient = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(15, 30, 80)),
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(40, 120, 220)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 180, 255))
        }),
        GradientRotation = -90,
    },
    
    -- Vibrant Yellow
    VibrantYellow = {
        Color = Color3.fromRGB(255, 230, 50),
        Gradient = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(80, 60, 10)),
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(230, 180, 30)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 240, 120))
        }),
        GradientRotation = -90,
    },
}

-- Load dynamic styles from Config
loadExternalStyles(Styles)

--[[
    Gets the configuration for a style name.
]]
local function GetColorConfig(styleName: string?): ColorVisualConfig?
    if not styleName then return nil end
    return Styles[styleName]
end

-- ==========================================================
-- VISUAL APPLICATION LOGIC (With Performance Tracking)
-- ==========================================================

-- Store active effects to allow cleanup and pause/resume: {[Instance]: {[EffectType]: EffectObject}}
local activeEffects: {[Instance]: {[string]: any}} = {}

local function StopAnimation(instance: Instance, specificType: string?)
    local effects = activeEffects[instance]
    if effects then
        if specificType then
            if effects[specificType] then
                effects[specificType]:Destroy()
                effects[specificType] = nil
            end
        else
            -- Stop all
            for _, effect in pairs(effects) do
                effect:Destroy()
            end
            activeEffects[instance] = nil
        end
    end
end

local function RegisterEffect(instance: Instance, effectType: string, effectObject: any)
    if not activeEffects[instance] then
        activeEffects[instance] = {}
    end
    -- Clean existing of same type
    if activeEffects[instance][effectType] then
        activeEffects[instance][effectType]:Destroy()
    end
    activeEffects[instance][effectType] = effectObject
end

--[[
    PERFORMANCE: Pause all registered effects (call when inventory closes)
]]
local function PauseAll()
    for instance, effects in pairs(activeEffects) do
        for _, effect in pairs(effects) do
            if effect.Pause then
                effect:Pause()
            end
        end
    end
end

--[[
    PERFORMANCE: Resume all registered effects (call when inventory opens)
]]
local function ResumeAll()
    for instance, effects in pairs(activeEffects) do
        -- Skip if instance destroyed
        if not instance.Parent then
            continue
        end
        for _, effect in pairs(effects) do
            if effect.Resume then
                effect:Resume()
            end
        end
    end
end

--[[
    Applies style to a Frame (UIStroke).
]]
local function ApplyToFrame(frame: Frame, styleName: string?, options: {StrokeThickness: number?}?)
    StopAnimation(frame, "Stroke")
    
    -- Reset basic stroke if no style
    if not styleName then
        local stroke = frame:FindFirstChild("RarityStroke") :: UIStroke?
        if stroke then stroke:Destroy() end
        return
    end

    local config = GetColorConfig(styleName)
    if not config then return end
    
    if config.StrokePreset then
        -- ezVisuals.new(uiInstance, effectType, speed, size, saveInstanceObjects, customColor)
        local effect = ezVisuals.new(frame, config.StrokePreset, config.Speed, config.Size, false, config.Color)
        RegisterEffect(frame, "Stroke", effect)
    else
         -- Fallback to basic color if no preset
         local stroke = frame:FindFirstChild("RarityStroke") :: UIStroke?
         if not stroke then
            stroke = Instance.new("UIStroke")
            stroke.Name = "RarityStroke"
            stroke.Parent = frame
         end
         stroke.Color = config.Color
         stroke.Thickness = (options and options.StrokeThickness) or 2
    end
end

--[[
    Applies style to a Frame's Background (UIGradient).
]]
local function ApplyToBackground(frame: Frame, styleName: string?)
    StopAnimation(frame, "Background")
    
    if not styleName then
        -- Reset to default dark background for empty slots
        frame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
        
        local gradient = frame:FindFirstChild("RarityGradient")
        if gradient then gradient:Destroy() end
        
        return 
    end

    local config = GetColorConfig(styleName)
    if not config then return end
    
    -- Set to white so gradients/presets show correctly
    frame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    frame.BackgroundTransparency = 0
    
    if config.Gradient then
         local gradient = frame:FindFirstChild("RarityGradient") :: UIGradient?
         if not gradient then
             gradient = Instance.new("UIGradient")
             gradient.Name = "RarityGradient"
             gradient.Parent = frame
         end
         gradient.Color = config.Gradient
         gradient.Rotation = config.GradientRotation or -90
    elseif config.BackgroundPreset then
        -- Use ezVisuals for animated presets
        local effect = ezVisuals.new(frame, config.BackgroundPreset, config.Speed, config.Size, false, config.Color)
        RegisterEffect(frame, "Background", effect)
    else
        -- Fallback to solid color
        frame.BackgroundColor3 = config.Color
    end
end

--[[
    Applies style to TextLabel.
]]
local function ApplyToText(textLabel: TextLabel, styleName: string?)
    StopAnimation(textLabel, "Text")
    
    if not styleName then
        textLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
        return
    end
    
    local config = GetColorConfig(styleName)
    if not config then return end
    
    textLabel.TextColor3 = config.Color
    
    -- Ensure base stroke exists
    local stroke = textLabel:FindFirstChild("UIStroke")
    if not stroke then
        stroke = Instance.new("UIStroke")
        stroke.Name = "UIStroke"
        stroke.Parent = textLabel
        stroke.Thickness = 2
        stroke.Color = Color3.fromRGB(0, 0, 0)
    end

    if config.TextPreset or config.BackgroundPreset then
        -- Many gradient presets work on TextLabels too
        local preset = config.TextPreset or config.BackgroundPreset
        
        -- Use custom synced effects to ensure all animated rarity texts animate in sync
        if preset == "Zebra" then
            local effect = ZebraSynced(textLabel, config.Speed, config.Size)
            RegisterEffect(textLabel, "Text", effect)
        elseif preset == "Rainbow" then
            local effect = RainbowSynced(textLabel, config.Speed, config.Size)
            RegisterEffect(textLabel, "Text", effect)
        else
            local effect = ezVisuals.new(textLabel, preset, config.Speed, config.Size, false, config.Color)
            RegisterEffect(textLabel, "Text", effect)
        end
    end
end

--[[
    Applies style to Highlight.
    NOTE: ezVisuals ONLY supports GuiObjects. We must use custom logic for Highlights (3D).
]]
local function ApplyToHighlight(highlight: Highlight, styleName: string?)
     local config = GetColorConfig(styleName)
     if not config then
        highlight.FillColor = Color3.fromRGB(100, 100, 100)
        return
     end
     
     -- Check if config has Color property
     if not config.Color then
        highlight.FillColor = Color3.fromRGB(100, 100, 100)
        return
     end
     
     highlight.FillColor = config.Color
     highlight.OutlineColor = config.Color
end

local function CreateHighlight(styleName: string?): Highlight
    local highlight = Instance.new("Highlight")
    highlight.DepthMode = Enum.HighlightDepthMode.Occluded
    ApplyToHighlight(highlight, styleName)
    return highlight
end

--[[
    Get active effect count (for debugging)
]]
local function GetAnimationCount(): number
    local count = 0
    for _, effects in pairs(activeEffects) do
        for _ in pairs(effects) do
            count = count + 1
        end
    end
    return count
end

return {
    Styles = Styles,
    GetColorConfig = GetColorConfig,
    
    -- Visual Application
    ApplyToFrame = ApplyToFrame,
    ApplyToBackground = ApplyToBackground,
    ApplyToText = ApplyToText,
    ApplyToHighlight = ApplyToHighlight,
    CreateHighlight = CreateHighlight,
    StopAnimation = function(inst) StopAnimation(inst) end,
    
    -- Performance Controls
    PauseAll = PauseAll,
    ResumeAll = ResumeAll,
    GetAnimationCount = GetAnimationCount,
}

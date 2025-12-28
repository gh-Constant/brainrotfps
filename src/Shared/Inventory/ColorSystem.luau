--!strict
--[[
    Color System (Visual Styles)
    Defines all visual styles for items, including colors, gradients, and animations.
    Decoupled from Rarity logic to allow custom item colors.
]]

export type ColorVisualConfig = {
    -- Basic color (required)
    Color: Color3,
    
    -- Optional: Gradient for more complex visuals
    Gradient: ColorSequence?,
    GradientRotation: number?, -- Degrees, default 0
    
    -- Optional: Animation settings
    Animated: boolean?,
    AnimationType: ("Pulse" | "Rainbow" | "Cycle" | "RotatingGradient" | "GradientFlow")?,
    AnimationSpeed: number?, -- Cycles per second
    AnimationColors: {Color3}?, -- For "Cycle" type
    LightColor: Color3?, -- For "RotatingGradient" type (the lighter line color)
}

export type ColorSystemMap = {[string]: ColorVisualConfig}

--[[
    Defined Styles
]]
local Styles: ColorSystemMap = {
    -- Default / Common: Gray
    BasicGray = {
        Color = Color3.fromRGB(180, 180, 180),
    },
    
    -- Uncommon: Green
    VibrantGreen = {
        Color = Color3.fromRGB(30, 255, 0),
    },
    
    -- Epic: Dark purple with rotating lighter lines
    AmethystVoid = {
        Color = Color3.fromRGB(90, 30, 130), -- Dark purple base
        LightColor = Color3.fromRGB(230, 180, 255), -- Bright, almost white purple for the lines
        Animated = true,
        AnimationType = "RotatingGradient",
        AnimationSpeed = 0.3,
    },
    
    -- Legendary: Orange/Gold
    SolarFlare = {
        Color = Color3.fromRGB(255, 165, 0),
        Gradient = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 0)),
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 140, 0)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 200, 0)),
        }),
    },
    
    -- Mythic: Pink/Magenta
    NeonMagenta = {
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
    MonochromeCycle = {
        Color = Color3.fromRGB(255, 255, 255), -- White base
        Animated = true,
        AnimationType = "Cycle",
        AnimationSpeed = 1.5,
        AnimationColors = {
            Color3.fromRGB(0, 0, 0),       -- Black
            Color3.fromRGB(255, 255, 255), -- White
        },
    },
    
    -- God: Red/Blue Long with Widened Black/Pink
    RainbowFlow = {
        Color = Color3.fromRGB(25, 25, 25), -- Dark Grey Base
        Animated = true,
        AnimationType = "GradientFlow",
        AnimationSpeed = 0.5, 
        Gradient = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),     -- Red (Start)
            ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 0, 0)),  -- Red (End Solid)
            ColorSequenceKeypoint.new(0.40, Color3.fromRGB(0, 0, 0)),    -- Black (Start)
            ColorSequenceKeypoint.new(0.45, Color3.fromRGB(0, 0, 0)),    -- Black (End)
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 0, 255)),   -- Blue (Start Solid)
            ColorSequenceKeypoint.new(0.85, Color3.fromRGB(0, 0, 255)),  -- Blue (End Solid)
            ColorSequenceKeypoint.new(0.90, Color3.fromRGB(255, 0, 255)),-- Pink (Start)
            ColorSequenceKeypoint.new(0.95, Color3.fromRGB(255, 0, 255)),-- Pink (End)
            ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),     -- Red (Loop)
        }),
    },
    
    -- Custom Example: Fire
    Fire = {
        Color = Color3.fromRGB(255, 50, 0),
        Gradient = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 0)),
        }),
        Animated = true,
        AnimationType = "Pulse",
        AnimationSpeed = 2, 
    },
    
    -- Custom Example: Ice
    Ice = {
        Color = Color3.fromRGB(0, 255, 255),
        LightColor = Color3.fromRGB(200, 255, 255),
        Animated = true,
        AnimationType = "RotatingGradient",
        AnimationSpeed = 0.5,
    },

    -- Custom: Green Pulse
    GreenPulse = {
        Color = Color3.fromRGB(50, 255, 50),
        Animated = true,
        AnimationType = "Pulse",
        AnimationSpeed = 1,
    },
}

--[[
    Gets the configuration for a style name.
    
    @param styleName - Name of the style (e.g. "Legendary", "Fire")
    @return ColorVisualConfig? - Config or nil if not found
]]
local function GetColorConfig(styleName: string?): ColorVisualConfig?
    if not styleName then return nil end
    return Styles[styleName]
end

-- ==========================================================
-- VISUAL APPLICATION LOGIC
-- ==========================================================

local RunService = game:GetService("RunService")
local activeAnimations: {[Instance]: RBXScriptConnection} = {}

local function StopAnimation(instance: Instance)
    local conn = activeAnimations[instance]
    if conn then
        conn:Disconnect()
        activeAnimations[instance] = nil
    end
end

local function hueToColor(hue: number): Color3
    return Color3.fromHSV(hue % 1, 0.8, 1)
end

--[[
    Applies style to a Frame (UIStroke + UIGradient).
]]
local function ApplyToFrame(frame: Frame, styleName: string?, options: {StrokeThickness: number?}?)
    local stroke = frame:FindFirstChild("RarityStroke") :: UIStroke?
    if not stroke then
        local newStroke = Instance.new("UIStroke")
        newStroke.Name = "RarityStroke"
        newStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        newStroke.Parent = frame
        stroke = newStroke
    end
    local strokeInstance = stroke :: UIStroke
    StopAnimation(strokeInstance)
    
    local thickness = if options and options.StrokeThickness then options.StrokeThickness else 2
    strokeInstance.Thickness = thickness
    
    local config = GetColorConfig(styleName)
    
    if not config then
        strokeInstance.Color = Color3.fromRGB(80, 80, 90)
        strokeInstance.Transparency = 0.5
        -- Cleanup
        local g1 = strokeInstance:FindFirstChild("RarityGradient")
        if g1 then g1:Destroy() end
        local g2 = strokeInstance:FindFirstChild("RotatingGradient")
        if g2 then g2:Destroy() end
        return
    end
    
    strokeInstance.Transparency = 0
    strokeInstance.Color = config.Color
    
    -- Gradient
    if config.Gradient then
        local gradient = strokeInstance:FindFirstChild("RarityGradient") :: UIGradient?
        local gradientInstance: UIGradient
        if not gradient then
            gradientInstance = Instance.new("UIGradient")
            gradientInstance.Name = "RarityGradient"
            gradientInstance.Parent = strokeInstance
        else
            gradientInstance = gradient
        end
        gradientInstance.Color = config.Gradient
        gradientInstance.Rotation = config.GradientRotation or 0
    else
        local g = strokeInstance:FindFirstChild("RarityGradient")
        if g then g:Destroy() end
    end
    
    -- Animation
    if config.Animated then
        local animType = config.AnimationType or "Pulse"
        local speed = config.AnimationSpeed or 1
        
        if animType == "Pulse" then
            local conn = RunService.Heartbeat:Connect(function()
                local t = os.clock() * speed * math.pi * 2
                local pulse = (math.sin(t) + 1) / 2
                strokeInstance.Thickness = thickness + pulse * 2
            end)
            activeAnimations[strokeInstance] = conn
            
        elseif animType == "Rainbow" then
            local conn = RunService.Heartbeat:Connect(function()
                local hue = (os.clock() * speed) % 1
                strokeInstance.Color = hueToColor(hue)
            end)
            activeAnimations[strokeInstance] = conn
            
        elseif animType == "Cycle" and config.AnimationColors then
            local colors = config.AnimationColors
            local conn = RunService.Heartbeat:Connect(function()
                local t = (os.clock() * speed) % #colors
                local index = math.floor(t) + 1
                local nextIndex = (index % #colors) + 1
                local alpha = t % 1
                strokeInstance.Color = colors[index]:Lerp(colors[nextIndex], alpha)
            end)
            activeAnimations[strokeInstance] = conn
            
        elseif animType == "RotatingGradient" then
             local baseColor = config.Color
            local lightColor = config.LightColor or Color3.fromRGB(
                math.min(255, baseColor.R * 255 + 80),
                math.min(255, baseColor.G * 255 + 80),
                math.min(255, baseColor.B * 255 + 80)
            )
            
            local gradient = strokeInstance:FindFirstChild("RotatingGradient") :: UIGradient?
            local gradientInstance: UIGradient
            if not gradient then
                gradientInstance = Instance.new("UIGradient")
                gradientInstance.Name = "RotatingGradient"
                gradientInstance.Parent = strokeInstance
            else
                gradientInstance = gradient
            end
            
            gradientInstance.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, lightColor),
                ColorSequenceKeypoint.new(0.15, lightColor),
                ColorSequenceKeypoint.new(0.25, baseColor),
                ColorSequenceKeypoint.new(0.45, baseColor),
                ColorSequenceKeypoint.new(0.5, lightColor),
                ColorSequenceKeypoint.new(0.65, lightColor),
                ColorSequenceKeypoint.new(0.75, baseColor),
                ColorSequenceKeypoint.new(1, baseColor),
            })
            
            local conn = RunService.Heartbeat:Connect(function()
                local rotation = (os.clock() * speed * 360) % 360
                gradientInstance.Rotation = rotation
            end)
            activeAnimations[strokeInstance] = conn -- Use stroke as key (container for gradient)
            
        elseif animType == "GradientFlow" then
             local gradient = strokeInstance:FindFirstChild("RarityGradient") :: UIGradient?
             local gradientInstance = gradient
             if not gradientInstance then return end 
             
             gradientInstance.Rotation = 0 -- Enforce horizontal
             
             local conn = RunService.Heartbeat:Connect(function()
                -- Oscillate or pan? User said "go from left to right"
                -- Simple pan saw-tooth
                local phase = (os.clock() * speed) % 2 - 1 -- -1 to 1
                gradientInstance.Offset = Vector2.new(phase, 0)
            end)
            activeAnimations[strokeInstance] = conn
        end
    else
        local g = strokeInstance:FindFirstChild("RotatingGradient")
        if g then g:Destroy() end
    end
end

--[[
    Applies style to TextLabel.
]]
local function ApplyToText(textLabel: TextLabel, styleName: string?)
    StopAnimation(textLabel)
    local config = GetColorConfig(styleName)
    
    if not config then
        textLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
         local g = textLabel:FindFirstChild("RarityTextGradient")
        if g then g:Destroy() end
        return
    end
    
    textLabel.TextColor3 = config.Color
    
    if config.Animated then
         local animType = config.AnimationType or "Pulse"
        local speed = config.AnimationSpeed or 1
        
        if animType == "Rainbow" then
            local conn = RunService.Heartbeat:Connect(function()
                local hue = (os.clock() * speed) % 1
                textLabel.TextColor3 = hueToColor(hue)
            end)
            activeAnimations[textLabel] = conn
            
        elseif animType == "Cycle" and config.AnimationColors then
            local colors = config.AnimationColors
            local conn = RunService.Heartbeat:Connect(function()
                local t = (os.clock() * speed) % #colors
                local index = math.floor(t) + 1
                local nextIndex = (index % #colors) + 1
                local alpha = t % 1
                textLabel.TextColor3 = colors[index]:Lerp(colors[nextIndex], alpha)
            end)
            activeAnimations[textLabel] = conn
        elseif animType == "RotatingGradient" then
             -- Use config gradient if available, otherwise generate default
            if not config.Gradient then
                 local lightColor = config.LightColor or config.Color
                local baseColor = config.Color
                
                local gradient = textLabel:FindFirstChild("RarityTextGradient") :: UIGradient?
                 local gradientInstance: UIGradient
                if not gradient then
                    gradientInstance = Instance.new("UIGradient")
                    gradientInstance.Name = "RarityTextGradient"
                    gradientInstance.Parent = textLabel
                else
                    gradientInstance = gradient
                end
                
                 gradientInstance.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, lightColor),
                    ColorSequenceKeypoint.new(0.15, lightColor),
                    ColorSequenceKeypoint.new(0.25, baseColor),
                    ColorSequenceKeypoint.new(0.45, baseColor),
                    ColorSequenceKeypoint.new(0.5, lightColor),
                    ColorSequenceKeypoint.new(0.65, lightColor),
                    ColorSequenceKeypoint.new(0.75, baseColor),
                    ColorSequenceKeypoint.new(1, baseColor),
                })
            end
             -- If config.Gradient exists, it was handled in ApplyToText earlier (not fully shown in snippet but assuming structure holds, actually ApplyToText doesn't apply Gradient by default like ApplyToBg. Let's fix that assumption or just handle rotation here).
             -- Wait, ApplyToText lines 280-292 only sets TextColor3. It DOES NOT apply config.Gradient generally.
             -- So I should actually APPLY the gradient here if it exists.
             
             local gradient = textLabel:FindFirstChild("RarityTextGradient") :: UIGradient?
             local gradientInstance = gradient or Instance.new("UIGradient")
             gradientInstance.Name = "RarityTextGradient"
             gradientInstance.Parent = textLabel
             
             if config.Gradient then
                 gradientInstance.Color = config.Gradient
             end

            local conn = RunService.Heartbeat:Connect(function()
                local rotation = (os.clock() * speed * 360) % 360
                gradientInstance.Rotation = rotation
            end)
            activeAnimations[textLabel] = conn
            
        elseif animType == "GradientFlow" then
             local gradient = textLabel:FindFirstChild("RarityTextGradient") :: UIGradient?
             local gradientInstance = gradient or Instance.new("UIGradient")
             gradientInstance.Name = "RarityTextGradient"
             gradientInstance.Parent = textLabel
             
             if config.Gradient then
                 gradientInstance.Color = config.Gradient
             end
             gradientInstance.Rotation = 0
             
            local conn = RunService.Heartbeat:Connect(function()
                local phase = (os.clock() * speed) % 2 - 1
                gradientInstance.Offset = Vector2.new(phase, 0)
            end)
            activeAnimations[textLabel] = conn
        end
    else
         local g = textLabel:FindFirstChild("RarityTextGradient")
        if g then g:Destroy() end
    end
end

--[[
    Applies style to Highlight.
]]
local function ApplyToHighlight(highlight: Highlight, styleName: string?)
    StopAnimation(highlight)
    local config = GetColorConfig(styleName)
    
    if not config then
        highlight.FillColor = Color3.fromRGB(100, 100, 100)
        highlight.FillTransparency = 0.8
        highlight.OutlineColor = Color3.fromRGB(150, 150, 150)
        highlight.OutlineTransparency = 0.5
        return
    end
    
    highlight.FillColor = config.Color
    highlight.FillTransparency = 0.7
    highlight.OutlineColor = config.Color
    highlight.OutlineTransparency = 0
    
    if config.Animated then
        local animType = config.AnimationType or "Pulse"
        local speed = config.AnimationSpeed or 1
        
        if animType == "Pulse" then
            local conn = RunService.Heartbeat:Connect(function()
                local t = os.clock() * speed * math.pi * 2
                local pulse = (math.sin(t) + 1) / 2
                highlight.FillTransparency = 0.5 + pulse * 0.4
            end)
            activeAnimations[highlight] = conn
            
        elseif animType == "Rainbow" then
            local conn = RunService.Heartbeat:Connect(function()
                local hue = (os.clock() * speed) % 1
                local color = hueToColor(hue)
                highlight.FillColor = color
                highlight.OutlineColor = color
            end)
            activeAnimations[highlight] = conn
            
        elseif animType == "Cycle" and config.AnimationColors then
            local colors = config.AnimationColors
            local conn = RunService.Heartbeat:Connect(function()
                local t = (os.clock() * speed) % #colors
                local index = math.floor(t) + 1
                local nextIndex = (index % #colors) + 1
                local alpha = t % 1
                local color = colors[index]:Lerp(colors[nextIndex], alpha)
                highlight.FillColor = color
                highlight.OutlineColor = color
            end)
            activeAnimations[highlight] = conn
        end
    end
end

--[[
    Applies style to a Frame's Background (UIGradient).
]]
local function ApplyToBackground(frame: Frame, styleName: string?)
    local config = GetColorConfig(styleName)
    
    local gradient = frame:FindFirstChild("UIGradient") :: UIGradient?
    if not gradient then
         -- Create if missing
         local newGradient = Instance.new("UIGradient")
         newGradient.Parent = frame
         gradient = newGradient
    end
    local gradientInstance = gradient :: UIGradient
    
    StopAnimation(gradientInstance)
    
    if not config then
        -- Reset to default (dark gray/transparent usually handled by frame props, but here we reset gradient)
        gradientInstance.Color = ColorSequence.new(Color3.fromRGB(25, 25, 25)) -- Default dark gray
        gradientInstance.Rotation = 0
        -- Remove extra gradients
        local g2 = frame:FindFirstChild("RotatingGradient")
        if g2 then g2:Destroy() end
        return
    end
    
    if config.Gradient then
        gradientInstance.Color = config.Gradient
        gradientInstance.Rotation = config.GradientRotation or 0
    else
        gradientInstance.Color = ColorSequence.new(config.Color)
        gradientInstance.Rotation = 0
    end
    
    -- Animation (similar logic to ApplyToFrame, but targeting the Gradient/Frame props)
    if config.Animated then
        local animType = config.AnimationType or "Pulse"
        local speed = config.AnimationSpeed or 1
        
        if animType == "Pulse" then
             -- Not implemented for background
             
        elseif animType == "Rainbow" then
            local conn = RunService.Heartbeat:Connect(function()
                local hue = (os.clock() * speed) % 1
                gradientInstance.Color = ColorSequence.new(hueToColor(hue))
            end)
            activeAnimations[gradientInstance] = conn
            
        elseif animType == "Cycle" and config.AnimationColors then
            local colors = config.AnimationColors
            local conn = RunService.Heartbeat:Connect(function()
                local t = (os.clock() * speed) % #colors
                local index = math.floor(t) + 1
                local nextIndex = (index % #colors) + 1
                local alpha = t % 1
                gradientInstance.Color = ColorSequence.new(colors[index]:Lerp(colors[nextIndex], alpha))
            end)
            activeAnimations[gradientInstance] = conn
            
        elseif animType == "RotatingGradient" then
             -- Only overwrite gradient if NO custom gradient provided
             if not config.Gradient then
                 local baseColor = config.Color
                local lightColor = config.LightColor or Color3.fromRGB(
                    math.min(255, baseColor.R * 255 + 80),
                    math.min(255, baseColor.G * 255 + 80),
                    math.min(255, baseColor.B * 255 + 80)
                )
                
                -- Recreate gradient for rotation
                 gradientInstance.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, lightColor),
                    ColorSequenceKeypoint.new(0.15, lightColor),
                    ColorSequenceKeypoint.new(0.25, baseColor),
                    ColorSequenceKeypoint.new(0.45, baseColor),
                    ColorSequenceKeypoint.new(0.5, lightColor),
                    ColorSequenceKeypoint.new(0.65, lightColor),
                    ColorSequenceKeypoint.new(0.75, baseColor),
                    ColorSequenceKeypoint.new(1, baseColor),
                })
             end
             -- If config.Gradient was provided, it was applied in lines 435-441, so we just rotate.
            
            local conn = RunService.Heartbeat:Connect(function()
                local rotation = (os.clock() * speed * 360) % 360
                gradientInstance.Rotation = rotation
            end)
            activeAnimations[gradientInstance] = conn
            
        elseif animType == "GradientFlow" then
             -- Gradient should already be set by config.Gradient
             gradientInstance.Rotation = 0
             
             local conn = RunService.Heartbeat:Connect(function()
                local phase = (os.clock() * speed) % 2 - 1
                gradientInstance.Offset = Vector2.new(phase, 0)
            end)
            activeAnimations[gradientInstance] = conn
        end
    end
end

local function CreateHighlight(styleName: string?): Highlight
    local highlight = Instance.new("Highlight")
    highlight.DepthMode = Enum.HighlightDepthMode.Occluded
    ApplyToHighlight(highlight, styleName)
    return highlight
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
    StopAnimation = StopAnimation,
}

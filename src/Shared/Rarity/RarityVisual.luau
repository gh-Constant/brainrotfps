--!strict
--[[
    Rarity Visual
    Applies rarity visuals to UI elements and 3D models.
    
    Handles:
    - Applying colors to frames (UIStroke, background)
    - Applying gradients (UIGradient)
    - Animating colors (pulse, rainbow, cycle)
    - Applying Highlight to 3D models
]]

local RunService = game:GetService("RunService")
local _TweenService = game:GetService("TweenService") -- Prefixed for future use

local RarityConfig = require(script.Parent.RarityConfig)

type RarityVisualConfig = RarityConfig.RarityVisualConfig

-- Active animations tracking
local activeAnimations: {[Instance]: RBXScriptConnection} = {}

local RarityVisual = {}

--[[
    Stops any active animation on an instance.
]]
function RarityVisual.StopAnimation(instance: Instance)
    local conn = activeAnimations[instance]
    if conn then
        conn:Disconnect()
        activeAnimations[instance] = nil
    end
end

--[[
    Calculates rainbow color from hue (0-1).
]]
local function hueToColor(hue: number): Color3
    return Color3.fromHSV(hue % 1, 0.8, 1)
end

--[[
    Applies rarity visual to a Frame (for inventory slots).
    Creates/updates UIStroke and optional UIGradient.
    
    @param frame - The frame to style
    @param rarityName - Name of the rarity (or nil for no rarity)
    @param options - Optional settings { StrokeThickness: number }
]]
function RarityVisual.ApplyToFrame(
    frame: Frame,
    rarityName: string?,
    options: {StrokeThickness: number?}?
)
    -- Stop existing animation
    RarityVisual.StopAnimation(frame)
    
    -- Find or create UIStroke
    local stroke = frame:FindFirstChild("RarityStroke") :: UIStroke?
    if not stroke then
        local newStroke = Instance.new("UIStroke")
        newStroke.Name = "RarityStroke"
        newStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        newStroke.Parent = frame
        stroke = newStroke
    end
    
    -- At this point stroke is guaranteed to exist
    local strokeInstance = stroke :: UIStroke
    
    local thickness = if options then options.StrokeThickness or 2 else 2
    strokeInstance.Thickness = thickness
    
    -- No rarity = no visual
    if not rarityName then
        strokeInstance.Color = Color3.fromRGB(80, 80, 90)
        strokeInstance.Transparency = 0.5
        return
    end
    
    local config = RarityConfig.GetConfig(rarityName)
    if not config then
        strokeInstance.Color = Color3.fromRGB(80, 80, 90)
        return
    end
    
    strokeInstance.Transparency = 0
    strokeInstance.Color = config.Color
    
    -- Apply gradient if exists
    if config.Gradient then
        local gradient = frame:FindFirstChild("RarityGradient") :: UIGradient?
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
    end
    
    -- Apply animation if needed
    if config.Animated then
        local animType = config.AnimationType or "Pulse"
        local speed = config.AnimationSpeed or 1
        
        if animType == "Pulse" then
            -- Pulsing transparency/brightness
            local conn = RunService.Heartbeat:Connect(function()
                local t = os.clock() * speed * math.pi * 2
                local pulse = (math.sin(t) + 1) / 2 -- 0 to 1
                strokeInstance.Thickness = thickness + pulse * 2
            end)
            activeAnimations[frame] = conn
            
        elseif animType == "Rainbow" then
            -- Rainbow hue cycling
            local conn = RunService.Heartbeat:Connect(function()
                local hue = (os.clock() * speed) % 1
                strokeInstance.Color = hueToColor(hue)
            end)
            activeAnimations[frame] = conn
            
        elseif animType == "Cycle" and config.AnimationColors then
            -- Cycle through specific colors
            local colors = config.AnimationColors
            local conn = RunService.Heartbeat:Connect(function()
                local t = (os.clock() * speed) % #colors
                local index = math.floor(t) + 1
                local nextIndex = (index % #colors) + 1
                local alpha = t % 1
                strokeInstance.Color = colors[index]:Lerp(colors[nextIndex], alpha)
            end)
            activeAnimations[frame] = conn
        end
    end
end

--[[
    Applies rarity visual to a Highlight (for 3D models).
    
    @param highlight - The Highlight instance
    @param rarityName - Name of the rarity (or nil for no rarity)
]]
function RarityVisual.ApplyToHighlight(
    highlight: Highlight,
    rarityName: string?
)
    -- Stop existing animation
    RarityVisual.StopAnimation(highlight)
    
    -- No rarity = subtle gray
    if not rarityName then
        highlight.FillColor = Color3.fromRGB(100, 100, 100)
        highlight.FillTransparency = 0.8
        highlight.OutlineColor = Color3.fromRGB(150, 150, 150)
        highlight.OutlineTransparency = 0.5
        return
    end
    
    local config = RarityConfig.GetConfig(rarityName)
    if not config then
        highlight.FillColor = Color3.fromRGB(100, 100, 100)
        highlight.OutlineColor = Color3.fromRGB(150, 150, 150)
        return
    end
    
    highlight.FillColor = config.Color
    highlight.FillTransparency = 0.7
    highlight.OutlineColor = config.Color
    highlight.OutlineTransparency = 0
    
    -- Apply animation if needed
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
    Creates a configured Highlight for a model.
    
    @param rarityName - The rarity to apply
    @return Highlight - The configured highlight
]]
function RarityVisual.CreateHighlight(rarityName: string?): Highlight
    local highlight = Instance.new("Highlight")
    highlight.DepthMode = Enum.HighlightDepthMode.Occluded
    RarityVisual.ApplyToHighlight(highlight, rarityName)
    return highlight
end

--[[
    Gets the base color for a rarity.
]]
function RarityVisual.GetColor(rarityName: string): Color3
    return RarityConfig.GetColor(rarityName)
end

return RarityVisual

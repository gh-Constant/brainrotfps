--!strict
--[[
    ProgressBar
    A reusable module for animating progress bar UIs.
    
    Usage:
        local ProgressBar = require(path.to.ProgressBar)
        
        local healthBar = ProgressBar.new({
            Container = hpFrame,           -- The outer frame
            Fill = hpFrame.Current,        -- The inner fill frame
            ValueLabel = hpFrame.CurrentHP, -- Optional: text label for value
        })
        
        healthBar:SetProgress(0.75)  -- 75%
        healthBar:SetValue(75, 100)  -- current, max
]]

local TweenService = game:GetService("TweenService")

-- Types
export type ProgressBarConfig = {
    Container: GuiObject,
    Fill: GuiObject,
    ValueLabel: TextLabel?,
    SecondaryLabel: TextLabel?,
    TweenDuration: number?,
    TweenStyle: Enum.EasingStyle?,
    ValueFormat: string?,
    Formatter: ((number) -> string)?,
}

export type ProgressBar = {
    SetProgress: (self: ProgressBar, progress: number, animate: boolean?) -> (),
    SetValue: (self: ProgressBar, current: number, max: number, animate: boolean?) -> (),
    SetLabel: (self: ProgressBar, text: string) -> (),
    SetSecondaryLabel: (self: ProgressBar, text: string) -> (),
    GetProgress: (self: ProgressBar) -> number,
    Destroy: (self: ProgressBar) -> (),
}

-- Constants
local DEFAULT_TWEEN_DURATION = 0.3
local DEFAULT_TWEEN_STYLE = Enum.EasingStyle.Quad

-- Module
local ProgressBarModule = {}

--[[
    Creates a new ProgressBar controller.
    
    @param config - Configuration for the progress bar
    @return ProgressBar - The progress bar controller
]]
function ProgressBarModule.new(config: ProgressBarConfig): ProgressBar
    local self = {}
    
    -- Store config
    local _container = config.Container -- Stored for future use
    local fill = config.Fill
    local valueLabel = config.ValueLabel
    local secondaryLabel = config.SecondaryLabel
    local tweenDuration = config.TweenDuration or DEFAULT_TWEEN_DURATION
    local tweenStyle = config.TweenStyle or DEFAULT_TWEEN_STYLE
    local valueFormat = config.ValueFormat or "%d / %d"
    local formatter = config.Formatter
    
    -- State
    local currentProgress = 0
    local currentTween: Tween? = nil
    local destroyed = false
    
    -- Tween info
    local tweenInfo = TweenInfo.new(
        tweenDuration,
        tweenStyle,
        Enum.EasingDirection.Out
    )
    
    --[[
        Sets the progress directly (0-1).
        
        @param progress - Value between 0 and 1
        @param animate - Whether to animate the change (default: true)
    ]]
    function self:SetProgress(progress: number, animate: boolean?)
        if destroyed then return end
        if animate == nil then animate = true end
        
        -- Clamp progress
        progress = math.clamp(progress, 0, 1)
        currentProgress = progress
        
        -- Cancel existing tween
        if currentTween then
            currentTween:Cancel()
            currentTween = nil
        end
        
        -- Calculate target size
        local targetSize = UDim2.new(progress, 0, 1, 0)
        
        if animate and tweenDuration > 0 then
            local tween = TweenService:Create(fill, tweenInfo, {
                Size = targetSize
            })
            currentTween = tween
            tween:Play()
        else
            fill.Size = targetSize
        end
    end
    
    --[[
        Sets progress from current/max values.
        
        @param current - Current value
        @param max - Maximum value
        @param animate - Whether to animate (default: true)
    ]]
    function self:SetValue(current: number, max: number, animate: boolean?)
        if destroyed then return end
        
        local progress = max > 0 and (current / max) or 0
        self:SetProgress(progress, animate)
        
        -- Update value label if present
        if valueLabel then
            if formatter then
                -- Single value or dual value support depends on formatter
                -- Here we assume formatter handles single numbers, so we format current/max individually if needed
                -- But wait, valueFormat might be "%d / %d".
                -- Let's stick to simple logic: if formatter exists, use it on current and max
                -- But custom formats like "%s / %s" might be needed.
                -- User requested "format" for health/xp.
                -- Let's try to detect if format string has 2 placeholders
                if valueFormat:match("%%.+%%") then
                     valueLabel.Text = string.format(valueFormat, formatter(current), formatter(max))
                else
                     valueLabel.Text = formatter(current)
                end
            else
                valueLabel.Text = string.format(valueFormat, math.floor(current), math.floor(max))
            end
        end
    end
    
    --[[
        Sets the main label text directly.
        
        @param text - Text to display
    ]]
    function self:SetLabel(text: string)
        if destroyed then return end
        if valueLabel then
            valueLabel.Text = text
        end
    end
    
    --[[
        Sets the secondary label text (e.g., level number).
        
        @param text - Text to display
    ]]
    function self:SetSecondaryLabel(text: string)
        if destroyed then return end
        if secondaryLabel then
            secondaryLabel.Text = text
        end
    end
    
    --[[
        Gets the current progress (0-1).
        
        @return number - Current progress
    ]]
    function self:GetProgress(): number
        return currentProgress
    end
    
    --[[
        Destroys the controller and stops any active tweens.
    ]]
    function self:Destroy()
        if destroyed then return end
        destroyed = true
        
        if currentTween then
            currentTween:Cancel()
            currentTween = nil
        end
    end
    
    return self :: any
end

return ProgressBarModule

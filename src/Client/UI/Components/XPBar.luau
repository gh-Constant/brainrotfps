--!strict
--[[
    XPBar
    Handles the XP bar and level display.
    
    Expected UI Structure:
    - Base/Bottom/XP/Current (Fill frame)
    - Base/Bottom/XP/ImageLabel/CurrentLevel (TextLabel)
    - Base/Bottom/XP/CurrentXP (TextLabel)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local MoneyLib = require(Rojo:WaitForChild("Shared"):WaitForChild("MoneyLib"))

local ProgressBar = require(script.Parent.Parent.ProgressBar)

local player = Players.LocalPlayer

local XPBar = {}

local xpBar: any = nil

local function formatNumber(value: number): string
    return MoneyLib.HandleMoney(value)
end

local function updateXP()
    if not xpBar then return end
    
    local leaderstats = player:FindFirstChild("leaderstats")
    if not leaderstats then return end
    
    local levelValue = leaderstats:FindFirstChild("Level")
    local xpValueObj = leaderstats:FindFirstChild("XP")
    
    local level = levelValue and levelValue.Value or 1
    local currentXP = xpValueObj and xpValueObj.Value or 0
    
    -- Update level label
    xpBar:SetSecondaryLabel(tostring(level))
    
    -- XP to level up = level * 100
    local requiredXP = level * 100
    currentXP = math.clamp(currentXP, 0, requiredXP)
    
    xpBar:SetValue(currentXP, requiredXP)
end

function XPBar.Init(context: any)
    local bottomFrame = context.BottomFrame
    if not bottomFrame then return end
    
    local xpFrame = bottomFrame:FindFirstChild("XP")
    if not xpFrame then
        warn("[XPBar] XP frame not found!")
        return
    end
    
    local xpFill = xpFrame:FindFirstChild("Current")
    local imageLabel = xpFrame:FindFirstChild("ImageLabel")
    local levelLabel = imageLabel and imageLabel:FindFirstChild("CurrentLevel") :: TextLabel?
    local xpLabel = xpFrame:FindFirstChild("CurrentXP") :: TextLabel?
    
    if xpFill and xpLabel and levelLabel then
        xpBar = ProgressBar.new({
            Container = xpFrame,
            Fill = xpFill,
            ValueLabel = xpLabel,
            SecondaryLabel = levelLabel,
            TweenDuration = 0.3,
            ValueFormat = "%s / %s",
            Formatter = formatNumber,
        })
        XPBar.Bar = xpBar
    else
        warn("[XPBar] XP bar UI elements not found!")
    end
    
    -- Setup XP tracking
    task.spawn(function()
        local leaderstats = player:WaitForChild("leaderstats", 10)
        if not leaderstats then
            warn("[XPBar] leaderstats not found!")
            return
        end
        
        local levelValue = leaderstats:WaitForChild("Level", 5)
        local xpValueObj = leaderstats:WaitForChild("XP", 5)
        
        updateXP()
        
        if levelValue then levelValue.Changed:Connect(updateXP) end
        if xpValueObj then xpValueObj.Changed:Connect(updateXP) end
    end)
    
    print("[XPBar] Initialized!")
end

return XPBar

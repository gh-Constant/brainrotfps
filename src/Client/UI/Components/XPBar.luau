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
local Packages = Rojo:WaitForChild("Packages")
local Janitor = require(Packages:WaitForChild("janitor"))
local Promise = require(Packages:WaitForChild("promise"))
local MoneyLib = require(Rojo:WaitForChild("Shared"):WaitForChild("MoneyLib"))

local ProgressBar = require(script.Parent.Parent.ProgressBar)

local player = Players.LocalPlayer

local XPBar = {}

local xpBar: any = nil
local valueJanitor = Janitor.new()

local function formatNumber(value: number): string
    return MoneyLib.HandleMoney(value)
end

local function updateXP()
    if not xpBar then return end
    
    local internalStats = player:FindFirstChild("InternalStats")
    if not internalStats then return end
    
    local levelValue = internalStats:FindFirstChild("Level")
    local xpValueObj = internalStats:FindFirstChild("XP")
    
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
    
    -- Setup XP tracking with Promise
    Promise.try(function()
        local internalStats = player:WaitForChild("InternalStats", 10)
        if not internalStats then
            error("InternalStats not found")
        end
        return internalStats
    end):andThen(function(internalStats)
        local levelValue = internalStats:WaitForChild("Level", 5)
        local xpValueObj = internalStats:WaitForChild("XP", 5)
        
        updateXP()
        
        -- Use Janitor for value connections
        if levelValue then valueJanitor:Add(levelValue.Changed:Connect(updateXP)) end
        if xpValueObj then valueJanitor:Add(xpValueObj.Changed:Connect(updateXP)) end
        
        -- Link to internalStats for automatic cleanup
        valueJanitor:LinkToInstance(internalStats)
    end):catch(function(err)
        warn("[XPBar] Failed to setup tracking:", err)
    end)
    
    print("[XPBar] Initialized with Janitor and Promise!")
end

return XPBar


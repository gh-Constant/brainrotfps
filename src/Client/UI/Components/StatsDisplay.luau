--!strict
--[[
    StatsDisplay
    Handles the stats text labels (Coins, Credits, Damage).
    
    Expected UI Structure:
    - Base/Left/Infos/Coins/TextLabel
    - Base/Left/Infos/Credits/TextLabel
    - Base/Left/Infos/Damage/TextLabel
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local MoneyLib = require(Rojo:WaitForChild("Shared"):WaitForChild("MoneyLib"))

local player = Players.LocalPlayer

local StatsDisplay = {}

local coinsLabel: TextLabel? = nil
local creditsLabel: TextLabel? = nil
local damageLabel: TextLabel? = nil

local function formatNumber(value: number): string
    return MoneyLib.HandleMoney(value)
end

local function updateStats()
    local leaderstats = player:FindFirstChild("leaderstats")
    if not leaderstats then return end
    
    local levelValue = leaderstats:FindFirstChild("Level")
    local level = levelValue and levelValue.Value or 1
    
    -- Update Coins
    if coinsLabel then
        local coins = leaderstats:FindFirstChild("Gold")
        local coinsValue = coins and coins.Value or 0
        coinsLabel.Text = "Coins: " .. formatNumber(coinsValue)
    end
    
    -- Update Credits
    if creditsLabel then
        local credits = leaderstats:FindFirstChild("Credits")
        local creditsValue = credits and credits.Value or 0
        creditsLabel.Text = "Credits: " .. formatNumber(creditsValue)
    end
    
    -- Update Damage (3x Level)
    if damageLabel then
        local damage = level * 3
        damageLabel.Text = "Damage: " .. formatNumber(damage)
    end
end

function StatsDisplay.Init(context: any)
    local leftFrame = context.LeftFrame
    if not leftFrame then return end
    
    local infos = leftFrame:FindFirstChild("Infos")
    if not infos then
        warn("[StatsDisplay] Infos frame not found!")
        return
    end
    
    local coinsFrame = infos:FindFirstChild("Coins")
    local creditsFrame = infos:FindFirstChild("Credits")
    local damageFrame = infos:FindFirstChild("Damage")
    
    coinsLabel = coinsFrame and coinsFrame:FindFirstChild("TextLabel") :: TextLabel?
    creditsLabel = creditsFrame and creditsFrame:FindFirstChild("TextLabel") :: TextLabel?
    damageLabel = damageFrame and damageFrame:FindFirstChild("TextLabel") :: TextLabel?
    
    -- Setup stats tracking
    task.spawn(function()
        local leaderstats = player:WaitForChild("leaderstats", 10)
        if not leaderstats then
            warn("[StatsDisplay] leaderstats not found!")
            return
        end
        
        local levelValue = leaderstats:WaitForChild("Level", 5)
        local goldValue = leaderstats:WaitForChild("Gold", 5)
        local creditsValue = leaderstats:WaitForChild("Credits", 5)
        
        updateStats()
        
        if levelValue then levelValue.Changed:Connect(updateStats) end
        if goldValue then goldValue.Changed:Connect(updateStats) end
        if creditsValue then creditsValue.Changed:Connect(updateStats) end
    end)
    
    print("[StatsDisplay] Initialized!")
end

return StatsDisplay

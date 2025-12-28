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
local Packages = Rojo:WaitForChild("Packages")
local Janitor = require(Packages:WaitForChild("janitor"))
local Promise = require(Packages:WaitForChild("promise"))
local MoneyLib = require(Rojo:WaitForChild("Shared"):WaitForChild("MoneyLib"))

local player = Players.LocalPlayer

local StatsDisplay = {}

local coinsLabel: TextLabel? = nil
local creditsLabel: TextLabel? = nil
local damageLabel: TextLabel? = nil
local valueJanitor = Janitor.new()

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
    
    -- Update Damage (3x Level * Multiplier)
    if damageLabel then
        local multiplierValue = leaderstats:FindFirstChild("DamageMultiplier")
        local multiplier = multiplierValue and multiplierValue.Value or 1
        local damage = level * 3 * multiplier
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
    
    -- Setup stats tracking with Promise
    Promise.try(function()
        local leaderstats = player:WaitForChild("leaderstats", 10)
        if not leaderstats then
            error("leaderstats not found")
        end
        return leaderstats
    end):andThen(function(leaderstats)
        -- Wait for critical values
        local levelValue = leaderstats:WaitForChild("Level", 10)
        local goldValue = leaderstats:WaitForChild("Gold", 10)
        local creditsValue = leaderstats:WaitForChild("Credits", 10)
        local damageMultiplierValue = leaderstats:WaitForChild("DamageMultiplier", 10)
        
        -- Initial Update
        updateStats()
        
        -- Use Janitor for value connections
        if levelValue then valueJanitor:Add(levelValue.Changed:Connect(updateStats)) end
        if goldValue then valueJanitor:Add(goldValue.Changed:Connect(updateStats)) end
        if creditsValue then valueJanitor:Add(creditsValue.Changed:Connect(updateStats)) end
        if damageMultiplierValue then valueJanitor:Add(damageMultiplierValue.Changed:Connect(updateStats)) end
        
        -- Link to leaderstats for automatic cleanup
        valueJanitor:LinkToInstance(leaderstats)
    end):catch(function(err)
        warn("[StatsDisplay] Failed to setup tracking:", err)
    end)
    
    print("[StatsDisplay] Initialized with Janitor and Promise!")
end 

return StatsDisplay


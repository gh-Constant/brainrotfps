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
    local internalStats = player:FindFirstChild("InternalStats")
    if not internalStats then return end
    
    local levelValue = internalStats:FindFirstChild("Level")
    local level = levelValue and levelValue.Value or 1
    
    -- Update Coins (from InternalStats for precision)
    if coinsLabel then
        local goldValue = internalStats:FindFirstChild("Gold")
        local coins = goldValue and goldValue.Value or 0
        coinsLabel.Text = "Coins: " .. formatNumber(coins)
    end
    
    -- Update Credits
    if creditsLabel then
        local credits = internalStats:FindFirstChild("Credits")
        local creditsValue = credits and credits.Value or 0
        creditsLabel.Text = "Credits: " .. formatNumber(creditsValue)
    end
    
    -- Update Damage (Base(9+Level) * GlobalMult * MutationMult)
    if damageLabel then
        local multiplierValue = internalStats:FindFirstChild("DamageMultiplier")
        local globalMultiplier = multiplierValue and multiplierValue.Value or 1
        
        local mutationDamageMult = 1
        
        local currentTool = player.Character and player.Character:FindFirstChildWhichIsA("Tool")
        local isGun = false
        local baseFirerate = 0
        local bullets = 1
        
        if currentTool then
            -- Check for weapon stats directly on tool
            baseFirerate = currentTool:GetAttribute("rateOfFire")
            bullets = currentTool:GetAttribute("raysPerShot") or 1
            
            if baseFirerate and baseFirerate > 0 then
                isGun = true
            end
        end

        local totalDamage = (9 + level * 5) * globalMultiplier * mutationDamageMult
        
        if isGun then
            local shotsPerSecond = baseFirerate / 60
            local dps = math.floor(totalDamage * shotsPerSecond * bullets)
            damageLabel.Text = "DPS: " .. formatNumber(dps)
        else
            damageLabel.Text = "DPS: 0"
        end
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
        local internalStats = player:WaitForChild("InternalStats", 10)
        if not internalStats then
            error("InternalStats not found")
        end
        return internalStats
    end):andThen(function(internalStats)
        -- Wait for critical values
        local levelValue = internalStats:WaitForChild("Level", 10)
        local goldValue = internalStats:WaitForChild("Gold", 10)
        local creditsValue = internalStats:WaitForChild("Credits", 10)
        local damageMultiplierValue = internalStats:WaitForChild("DamageMultiplier", 10)
        
        -- Initial Update
        updateStats()
        
        -- Use Janitor for value connections
        if levelValue then valueJanitor:Add(levelValue.Changed:Connect(updateStats)) end
        if goldValue then valueJanitor:Add(goldValue.Changed:Connect(updateStats)) end
        if creditsValue then valueJanitor:Add(creditsValue.Changed:Connect(updateStats)) end
        if damageMultiplierValue then valueJanitor:Add(damageMultiplierValue.Changed:Connect(updateStats)) end
        
        -- Link to internalStats for automatic cleanup
        valueJanitor:LinkToInstance(internalStats)
    end):catch(function(err)
        warn("[StatsDisplay] Failed to setup tracking:", err)
    end)
    
    print("[StatsDisplay] Initialized with Janitor and Promise!")
    
    -- Character/Tool tracking
    local charJanitor = Janitor.new()
    
    local function setupCharacter(char)
        charJanitor:Cleanup()
        
        charJanitor:Add(char.ChildAdded:Connect(function(child)
            if child:IsA("Tool") then
                updateStats()
                -- Listen for mutation changes on the tool
                charJanitor:Add(child:GetAttributeChangedSignal("Mutations"):Connect(updateStats), "Disconnect")
            end
        end))
        
        charJanitor:Add(char.ChildRemoved:Connect(function(child)
            if child:IsA("Tool") then
                updateStats()
            end
        end))
        
        -- Check start tool if any
        local tool = char:FindFirstChildWhichIsA("Tool")
        if tool then
             charJanitor:Add(tool:GetAttributeChangedSignal("Mutations"):Connect(updateStats), "Disconnect")
        end
        updateStats()
    end
    
    player.CharacterAdded:Connect(setupCharacter)
    if player.Character then
        setupCharacter(player.Character)
    end
    player.CharacterRemoving:Connect(function()
        charJanitor:Cleanup()
    end)
end 

return StatsDisplay


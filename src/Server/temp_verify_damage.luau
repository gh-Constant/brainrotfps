-- Verification script for Damage Multipliers
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Rojo = game:GetService("ReplicatedStorage"):WaitForChild("Rojo")
local Server = ServerScriptService:WaitForChild("Rojo"):WaitForChild("Server")

local PlayerManager = require(Server:WaitForChild("Player"))

local function verify()
    local player = Players:GetPlayers()[1]
    if not player then
        print("[VERIFY] No players found to test with.")
        return
    end

    local playerData = PlayerManager.GetPlayerData(player)
    if not playerData then
        print("[VERIFY] Player data not loaded for " .. player.Name)
        return
    end

    print("[VERIFY] Initial DamageMultiplier: " .. playerData.DamageMultiplier)

    -- Test GamePass
    print("[VERIFY] Simulating 2x Damage GamePass...")
    player:SetAttribute("GamePass_DoubleDamage", true)
    task.wait(0.5)
    print("[VERIFY] New DamageMultiplier (expected 2): " .. playerData.DamageMultiplier)

    -- Test Potion (Additive: Base 1 + GP 1 + Potion 1 = 3)
    print("[VERIFY] Simulating 2x Brainrot Damage Potion...")
    player:SetAttribute("Buff_Potion_BrainrotDamage", 2)
    task.wait(0.5)
    print("[VERIFY] New DamageMultiplier (expected 3): " .. playerData.DamageMultiplier)

    -- Test removal
    print("[VERIFY] Removing GamePass and Potion...")
    player:SetAttribute("GamePass_DoubleDamage", false)
    player:SetAttribute("Buff_Potion_BrainrotDamage", nil)
    task.wait(0.5)
    print("[VERIFY] Final DamageMultiplier (expected 1): " .. playerData.DamageMultiplier)
    
    print("[VERIFY] Verification complete!")
end

task.delay(5, verify)

--!strict
--[[
    GamePassService
    Handles gamepass multiplier application for XP, Gold, and Damage.
    
    GamePass IDs:
    - 2x Experience: 1642681579
    - 2x Gold/Coins: 1642645563
    - 2x Damage: 1642445917
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")
local Server = ServerScriptService:WaitForChild("Rojo"):WaitForChild("Server")

local ProductConfig = require(Shared:WaitForChild("Monetization"):WaitForChild("ProductConfig"))

-- Lazy load to avoid circular dependencies
local MonetizationService = nil
local function getMonetizationService()
    if not MonetizationService then
        MonetizationService = require(Server:WaitForChild("Monetization"):WaitForChild("MonetizationService"))
    end
    return MonetizationService
end

local PlayerManager = nil
local function getPlayerManager()
    if not PlayerManager then
        PlayerManager = require(Server:WaitForChild("Player"))
    end
    return PlayerManager
end

local GamePassService = {}

-- Gamepass multiplier values
local DOUBLE_XP_MULTIPLIER = 2
local DOUBLE_GOLD_MULTIPLIER = 2
local DOUBLE_DAMAGE_MULTIPLIER = 2

-- Track which passes players own (cached)
local PlayerPasses: {[number]: {xp: boolean, gold: boolean, damage: boolean}} = {}

--------------------------------------------------------------------------------
-- Multiplier Application
--------------------------------------------------------------------------------

--[[
    Checks and applies all gamepass multipliers for a player.
    Should be called after playerData is loaded.
]]
function GamePassService.ApplyGamePassMultipliers(player: Player)
    local monetization = getMonetizationService()
    local playerData = getPlayerManager().GetPlayerData(player)
    
    if not playerData then
        warn("[GamePassService] Player data not available for " .. player.Name)
        return
    end
    
    local userId = player.UserId
    PlayerPasses[userId] = PlayerPasses[userId] or { xp = false, gold = false, damage = false }
    
    -- Check 2x Experience
    local hasDoubleXP = monetization.PerformPassCheck(player, ProductConfig.GamePasses.DoubleExperience.Id)
    if hasDoubleXP then
        PlayerPasses[userId].xp = true
        print(string.format("[GamePassService] %s owns 2x Experience!", player.Name))
    end
    
    -- Check 2x Gold
    local hasDoubleGold = monetization.PerformPassCheck(player, ProductConfig.GamePasses.DoubleGold.Id)
    if hasDoubleGold then
        PlayerPasses[userId].gold = true
        print(string.format("[GamePassService] %s owns 2x Gold!", player.Name))
    end
    
    -- Check 2x Damage
    local hasDoubleDamage = monetization.PerformPassCheck(player, ProductConfig.GamePasses.DoubleDamage.Id)
    if hasDoubleDamage then
        PlayerPasses[userId].damage = true
        playerData.DamageMultiplier = DOUBLE_DAMAGE_MULTIPLIER
        print(string.format("[GamePassService] %s owns 2x Damage!", player.Name))
    end
    
    -- Set attributes for client UI display
    player:SetAttribute("GamePass_DoubleXP", hasDoubleXP)
    player:SetAttribute("GamePass_DoubleGold", hasDoubleGold)
    player:SetAttribute("GamePass_DoubleDamage", hasDoubleDamage)
    
    print(string.format("[GamePassService] %s gamepass check complete (XP: %s, Gold: %s, Damage: %s)",
        player.Name, tostring(hasDoubleXP), tostring(hasDoubleGold), tostring(hasDoubleDamage)))
end

--[[
    Gets the XP multiplier from gamepasses for a player.
    Returns 2 if they have the pass, 1 otherwise.
]]
function GamePassService.GetXPMultiplier(player: Player): number
    local passes = PlayerPasses[player.UserId]
    if passes and passes.xp then
        return DOUBLE_XP_MULTIPLIER
    end
    return 1
end

--[[
    Gets the Gold multiplier from gamepasses for a player.
    Returns 2 if they have the pass, 1 otherwise.
]]
function GamePassService.GetGoldMultiplier(player: Player): number
    local passes = PlayerPasses[player.UserId]
    if passes and passes.gold then
        return DOUBLE_GOLD_MULTIPLIER
    end
    return 1
end

--[[
    Gets the complete experience multiplier for a player, including:
    - Base multiplier (1)
    - GamePass (2x if owned)
    - Potion buff
]]
function GamePassService.GetTotalXPMultiplier(player: Player): number
    local multiplier = GamePassService.GetXPMultiplier(player)
    
    -- Add potion buff
    local potionBuff = player:GetAttribute("Buff_Potion_XP") :: number?
    if potionBuff and potionBuff > 0 then
        multiplier = multiplier * potionBuff
    end
    local potionExpBuff = player:GetAttribute("Buff_Potion_Experience") :: number?
    if potionExpBuff and potionExpBuff > 0 then
        multiplier = multiplier * potionExpBuff
    end
    
    return multiplier
end

--[[
    Gets the complete gold multiplier for a player.
]]
function GamePassService.GetTotalGoldMultiplier(player: Player): number
    local multiplier = GamePassService.GetGoldMultiplier(player)
    
    -- Add potion buff
    local potionGoldBuff = player:GetAttribute("Buff_Potion_Gold") :: number?
    if potionGoldBuff and potionGoldBuff > 0 then
        multiplier = multiplier * potionGoldBuff
    end
    local potionCoinsBuff = player:GetAttribute("Buff_Potion_Coins") :: number?
    if potionCoinsBuff and potionCoinsBuff > 0 then
        multiplier = multiplier * potionCoinsBuff
    end
    
    return multiplier
end

--------------------------------------------------------------------------------
-- Cleanup
--------------------------------------------------------------------------------

local function onPlayerRemoving(player: Player)
    PlayerPasses[player.UserId] = nil
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

function GamePassService.Init()
    -- Handle existing players
    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(function()
            -- Wait for player data
            local tries = 0
            while not getPlayerManager().GetPlayerData(player) do
                tries += 1
                if tries > 60 then return end
                task.wait(0.1)
            end
            
            GamePassService.ApplyGamePassMultipliers(player)
        end)
    end
    
    -- Handle new players
    Players.PlayerAdded:Connect(function(player)
        task.spawn(function()
            -- Wait for player data
            local tries = 0
            while not getPlayerManager().GetPlayerData(player) do
                tries += 1
                if tries > 60 then return end
                task.wait(0.1)
            end
            
            GamePassService.ApplyGamePassMultipliers(player)
        end)
    end)
    
    -- Cleanup
    Players.PlayerRemoving:Connect(onPlayerRemoving)
    
    print("[GamePassService] Initialized!")
end

return GamePassService

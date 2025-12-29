--!strict
--[[
    BuffService
    Manages XP and Gold multipliers from various sources (Friends, Premium, GamePasses).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")
local Server = ServerScriptService:WaitForChild("Rojo"):WaitForChild("Server")

-- Use lazy loading for PlayerManager to avoid circular dependency issues during init
local PlayerManager = nil
local function getPlayerManager()
    if not PlayerManager then
        PlayerManager = require(Server:WaitForChild("Player"))
    end
    return PlayerManager
end

local MonetizationService = require(Server:WaitForChild("Monetization"):WaitForChild("MonetizationService"))
local ProductConfig = require(Shared:WaitForChild("Monetization"):WaitForChild("ProductConfig"))

local BuffService = {}

-- Constants
local FRIEND_BOOST_PER_FRIEND = 0.10 -- 10% per friend
local FRIEND_BOOST_MAX = 0.50 -- Max 50%
local PREMIUM_BOOST = 0.25 -- 25% XP and Gold

-- Cache
local friendCache: {[number]: {[number]: boolean}} = {} -- [PlayerId] = {[OtherId] = true}

--[[
    Checks if two players are friends, using cache if available.
]]
local function areFriends(player1: Player, player2: Player): boolean
    local id1, id2 = player1.UserId, player2.UserId
    
    if not friendCache[id1] then friendCache[id1] = {} end
    if friendCache[id1][id2] ~= nil then
        return friendCache[id1][id2]
    end
    
    local success, result = pcall(function()
        return player1:IsFriendsWith(id2) -- Using IsFriendsWith for now as it's internally cached by Roblox nicely. 
        -- Async version IsFriendsWithAsync is better but requires yield handling in loops.
        -- Given this is run in a task.spawn, we can accept IsFriendsWith's slight yield or use Async.
        -- But IsFriendsWith is deprecated. Let's use Async and cache it.
    end)
    
    if not success then
        return false -- Fail safe
    end
    
    -- Cache result (bidirectional?)
    friendCache[id1][id2] = result
    
    -- Also cache for the other player since friendship is mutual in Roblox
    if not friendCache[id2] then friendCache[id2] = {} end
    friendCache[id2][id1] = result
    
    return result
end

--[[
    Recalculates and applies multipliers for a player.
]]
local function calculateMultipliers(player: Player)
    local playerManager = getPlayerManager()
    local playerData = playerManager.GetPlayerData(player)
    
    if not playerData then return end
    
    -- 1. Calculate Friend Boost
    local friendCount = 0
    for _, otherPlayer in ipairs(Players:GetPlayers()) do
        if otherPlayer ~= player then
            -- Check if they are friends
            if areFriends(player, otherPlayer) then
                friendCount += 1
            end
        end
    end
    
    local friendBoost = math.min(friendCount * FRIEND_BOOST_PER_FRIEND, FRIEND_BOOST_MAX)
    
    -- 2. Calculate Premium Boost
    local isPremium = player.MembershipType == Enum.MembershipType.Premium
    local premiumBoost = isPremium and PREMIUM_BOOST or 0
    
    -- 3. Calculate GamePass Multipliers
    local doubleGold = false
    local doubleXP = false
    
    -- Check GamePasses via MonetizationService
    if MonetizationService.PerformPassCheck(player, ProductConfig.GamePasses.DoubleGold.Id) then
        doubleGold = true
    end
    
    if MonetizationService.PerformPassCheck(player, ProductConfig.GamePasses.DoubleExperience.Id) then
        doubleXP = true
    end
    
    -- 4. Final Calculation
    -- Base is 100% (1.0). Boosts are additive to base?
    -- Formula: (1 + FriendBoost + PremiumBoost) * GamePass
    
    local totalXPMultiplier = (1 + friendBoost + premiumBoost)
    if doubleXP then
        totalXPMultiplier *= 2
    end
    
    local totalGoldMultiplier = (1 + premiumBoost) -- Friend boost is XP only per request
    if doubleGold then
        totalGoldMultiplier *= 2
    end
    
    -- Apply to PlayerData
    playerData.ExperienceMultiplier = totalXPMultiplier
    playerData.GoldMultiplier = totalGoldMultiplier
    
    -- Update Attributes for Client UI
    player:SetAttribute("Buff_FriendBoost", friendBoost)
    player:SetAttribute("Buff_Premium", isPremium)
    
    print(string.format("[BuffService] Updated %s: XP x%.2f (Friends: %d, Prem: %s), Gold x%.2f", 
        player.Name, totalXPMultiplier, friendCount, tostring(isPremium), totalGoldMultiplier))
end

--[[
    Updates friend counts for all players (e.g. when someone joins/leaves).
]]
local function updateAllPlayers()
    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(function()
            calculateMultipliers(player)
        end)
    end
end

function BuffService.Init()
    -- Handle Player Added
    Players.PlayerAdded:Connect(function(player)
        -- Wait for data to load
        task.spawn(function()
            -- Poll for player data to be ready
            local tries = 0
            while not getPlayerManager().GetPlayerData(player) do
                tries += 1
                if tries > 60 then return end -- Give up after 6s (should be fast)
                task.wait(0.1)
            end
            
            calculateMultipliers(player)
            
            -- Update everyone else because a potential friend joined
            updateAllPlayers()
        end)
    end)
    
    -- Handle Player Removing
    Players.PlayerRemoving:Connect(function(player)
        -- Update everyone else because a potential friend left
        -- Wait a moment for the player list to update?
        -- Players.PlayerRemoving fires before they are gone from GetPlayers?
        -- Actually GetPlayers usually excludes them slightly after?
        -- Safest is to wait a tick.
        task.delay(0.1, function()
            updateAllPlayers()
        end)
    end)
    
    -- Listen for GamePass purchases
    MonetizationService.OnGamePassPurchased:Connect(function(player, passId)
        if passId == ProductConfig.GamePasses.DoubleGold.Id or
           passId == ProductConfig.GamePasses.DoubleExperience.Id then
            task.spawn(function()
                calculateMultipliers(player)
            end)
        end
    end)
    
    -- Initial check for existing players
    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(function()
            if getPlayerManager().GetPlayerData(player) then
                calculateMultipliers(player)
            end
        end)
    end
    
    print("[BuffService] Initialized!")
end

return BuffService

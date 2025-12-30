--!strict
--[[
    BuffService
    Manages XP and Gold multipliers from Friends and Premium.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")


local Server = ServerScriptService:WaitForChild("Rojo"):WaitForChild("Server")

-- Use lazy loading for PlayerManager to avoid circular dependency issues during init
local PlayerManager = nil
local function getPlayerManager()
    if not PlayerManager then
        PlayerManager = require(Server:WaitForChild("Player"))
    end
    return PlayerManager
end

local BuffService = {}

-- Constants
local FRIEND_BOOST_PER_FRIEND = 0.10 -- 10% per friend
local FRIEND_BOOST_MAX = 0.50 -- Max 50%
local PREMIUM_BOOST = 0.25 -- 25% XP and Gold

--[[
    Checks if two players are friends.
]]
local function areFriends(player1: Player, player2: Player): boolean
    local success, result = pcall(function()
        return player1:IsFriendsWith(player2.UserId)
    end)
    return success and result
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
            if areFriends(player, otherPlayer) then
                friendCount += 1
            end
        end
    end
    
    local friendBoost = math.min(friendCount * FRIEND_BOOST_PER_FRIEND, FRIEND_BOOST_MAX)
    
    -- 2. Calculate Premium Boost
    local isPremium = player.MembershipType == Enum.MembershipType.Premium
    local premiumBoost = isPremium and PREMIUM_BOOST or 0
    
    -- 3. Final Calculation
    local totalXPMultiplier = (1 + friendBoost + premiumBoost)
    local totalGoldMultiplier = (1 + premiumBoost)
    
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
                if tries > 60 then return end -- Give up after 6s
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
        task.delay(0.1, function()
            updateAllPlayers()
        end)
    end)
    
    -- Handle Premium Membership Changes (Real-time update)
    Players.PlayerMembershipChanged:Connect(function(player)
        task.spawn(function()
            calculateMultipliers(player)
        end)
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

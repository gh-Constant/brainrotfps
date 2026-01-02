--!strict
--[[
    BuffService
    Manages XP and Gold multipliers from Friends and Premium.
]]

local Players = game:GetService("Players")
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
        return player1:IsFriendsWithAsync(player2.UserId)
    end)
    return success and result
end

--[[
    Recalculates and applies multipliers for a player.
]]
--[[
    Recalculates and applies multipliers for a player.
    Formula: Base(1) + FriendBonus + PremiumBonus + GamePassBonus + PotionBonus
    where GamePassBonus = (2x - 1) = 1
    and PotionBonus = (Nx - 1)
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
    
    -- 3. Gamepass Bonus (Additive)
    -- If owned, adds 100% (so +1.0)
    local xpGamePassBonus = player:GetAttribute("GamePass_DoubleXP") and 1.0 or 0
    local goldGamePassBonus = player:GetAttribute("GamePass_DoubleGold") and 1.0 or 0
    local damageGamePassBonus = player:GetAttribute("GamePass_DoubleDamage") and 1.0 or 0
    
    -- 4. Potion Bonus (Additive)
    -- Potion 2x means +1.0 bonus. Potion 3x means +2.0 bonus.
    -- Formula: (Multiplier - 1)
    local potionXPVal = player:GetAttribute("Buff_Potion_XP") :: number or 1
    local potionExpVal = player:GetAttribute("Buff_Potion_Experience") :: number or 1
    local maxPotionXP = math.max(potionXPVal, potionExpVal)
    local potionXPBonus = math.max(0, maxPotionXP - 1)
    
    local potionGoldVal = player:GetAttribute("Buff_Potion_Gold") :: number or 1
    local potionCoinsVal = player:GetAttribute("Buff_Potion_Coins") :: number or 1
    local maxPotionGold = math.max(potionGoldVal, potionCoinsVal)
    local potionGoldBonus = math.max(0, maxPotionGold - 1)

    local potionDamageVal = player:GetAttribute("Buff_Potion_BrainrotDamage") :: number or 1
    local potionMobDamageVal = player:GetAttribute("Buff_Potion_MobDamage") :: number or 1
    local maxPotionDamage = math.max(potionDamageVal, potionMobDamageVal)
    local potionDamageBonus = math.max(0, maxPotionDamage - 1)
    
    -- 5. Final Calculation (Additive)
    -- Base (1.0) + All Bonuses
    local totalXPMultiplier = 1.0 + friendBoost + premiumBoost + xpGamePassBonus + potionXPBonus
    local totalGoldMultiplier = 1.0 + premiumBoost + goldGamePassBonus + potionGoldBonus
    local totalDamageMultiplier = 1.0 + damageGamePassBonus + potionDamageBonus
    
    -- Apply to PlayerData
    playerData.ExperienceMultiplier = totalXPMultiplier
    playerData.GoldMultiplier = totalGoldMultiplier
    playerData:SetDamageMultiplier(totalDamageMultiplier)
    
    -- Update Attributes for Client UI
    player:SetAttribute("Buff_FriendBoost", friendBoost)
    player:SetAttribute("Buff_Premium", isPremium)
    
    -- Debug print for verification
    print(string.format("[BuffService] Updated %s: XP x%.2f, Gold x%.2f, Damage x%.2f (GP: %.1f, Pot: %.1f)", 
        player.Name, totalXPMultiplier, totalGoldMultiplier, totalDamageMultiplier, damageGamePassBonus, potionDamageBonus))
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
        
        -- GamePass Attributes (set by GamePassService)
        player:GetAttributeChangedSignal("GamePass_DoubleXP"):Connect(function() calculateMultipliers(player) end)
        player:GetAttributeChangedSignal("GamePass_DoubleGold"):Connect(function() calculateMultipliers(player) end)
        
        -- Potion Attributes (set by PotionService)
        player:GetAttributeChangedSignal("Buff_Potion_XP"):Connect(function() calculateMultipliers(player) end)
        player:GetAttributeChangedSignal("Buff_Potion_Experience"):Connect(function() calculateMultipliers(player) end)
        player:GetAttributeChangedSignal("Buff_Potion_Gold"):Connect(function() calculateMultipliers(player) end)
        player:GetAttributeChangedSignal("Buff_Potion_Coins"):Connect(function() calculateMultipliers(player) end)
        player:GetAttributeChangedSignal("Buff_Potion_BrainrotDamage"):Connect(function() calculateMultipliers(player) end)
        player:GetAttributeChangedSignal("Buff_Potion_MobDamage"):Connect(function() calculateMultipliers(player) end)
        
        -- GamePass Damage Change
        player:GetAttributeChangedSignal("GamePass_DoubleDamage"):Connect(function() calculateMultipliers(player) end)
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

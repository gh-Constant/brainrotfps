--!strict
--[[
    DailyRewardsService
    Server-side service for managing daily login rewards.
    
    Handles:
    - Tracking claim times and streak
    - Validating claim requests (24-hour cooldown)
    - Distributing rewards (coins, XP, items)
    - Sending reward state to clients
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")

local Packets = require(Shared:WaitForChild("Packets"))
local DailyRewardsConfig = require(Shared:WaitForChild("Rewards"):WaitForChild("DailyRewardsConfig"))


-- Lazy require to avoid circular dependencies
local PlayerManager = nil
local function getPlayerManager()
    if not PlayerManager then
        PlayerManager = require(script.Parent.Parent.Player)
    end
    return PlayerManager
end

local InventoryManager = nil
local function getInventoryManager()
    if not InventoryManager then
        InventoryManager = require(script.Parent.Parent.Inventory)
    end
    return InventoryManager
end

local DailyRewardsService = {}

-- Rate limiting
local LastRequest: {[number]: number} = {}
local REQUEST_COOLDOWN = 0.5

--[[
    Gets the current server time as a Unix timestamp.
]]
local function getCurrentTime(): number
    return os.time()
end

--[[
    Calculates which days have been claimed in the current cycle.
    Since streak advances after claim, claimed days are 1 to (streak - 1).
]]
local function getClaimedDays(streak: number, _canClaimToday: boolean): {number}
    local claimed = {}
    -- All days before current streak day were claimed
    -- If streak is 1, no days claimed yet.
    -- If streak is 2, Day 1 was claimed.
    for day = 1, streak - 1 do
        table.insert(claimed, day)
    end
    return claimed
end

--[[
    Determines if a player can claim their daily reward.
    
    @param lastClaim - Unix timestamp of last claim
    @return (canClaim: boolean, timeUntilNext: number)
]]
local function canClaimReward(lastClaim: number): (boolean, number)
    local currentTime = getCurrentTime()
    local timeSinceClaim = currentTime - lastClaim
    
    if lastClaim == 0 then
        -- Never claimed before = can claim
        return true, 0
    end
    
    if timeSinceClaim >= DailyRewardsConfig.ClaimCooldown then
        return true, 0
    end
    
    local timeUntilNext = DailyRewardsConfig.ClaimCooldown - timeSinceClaim
    return false, timeUntilNext
end

--[[
    Calculates the next day in the streak, handling resets.
    
    @param lastClaim - Unix timestamp of last claim
    @param currentStreak - Current streak day (1-7)
    @return number - The day number player should claim
]]
local function calculateCurrentDay(lastClaim: number, currentStreak: number): number
    local currentTime = getCurrentTime()
    local timeSinceClaim = currentTime - lastClaim
    
    -- If player hasn't claimed in too long, reset streak
    if lastClaim > 0 and timeSinceClaim > DailyRewardsConfig.StreakResetTime then
        return 1
    end
    
    -- If streak is beyond 7, wrap around
    if currentStreak > 7 then
        return 1
    end
    
    return currentStreak
end

--[[
    Sends the current daily rewards state to a player.
]]
function DailyRewardsService.SendRewardsState(player: Player)
    local playerData = getPlayerManager().GetPlayerData(player)
    if not playerData then return end
    
    local lastClaim = playerData.LastDailyRewardClaim
    local streak = playerData.DailyRewardStreak
    
    local currentDay = calculateCurrentDay(lastClaim, streak)
    local canClaim, timeUntilNext = canClaimReward(lastClaim)
    local claimedDays = getClaimedDays(currentDay, canClaim)
    
    Packets.dailyRewardsData.sendTo({
        currentDay = currentDay,
        claimedDays = claimedDays,
        canClaim = canClaim,
        timeUntilNextClaim = timeUntilNext,
    }, player)
end

--[[
    Attempts to claim a daily reward for a player.
    
    @param player - The player claiming
    @param day - The day they're trying to claim
    @return boolean - Success
]]
function DailyRewardsService.ClaimReward(player: Player, day: number): boolean
    local playerData = getPlayerManager().GetPlayerData(player)
    if not playerData then
        Packets.dailyRewardClaimed.sendTo({
            success = false,
            day = day,
        }, player)
        return false
    end
    
    local lastClaim = playerData.LastDailyRewardClaim
    local streak = playerData.DailyRewardStreak
    
    local currentDay = calculateCurrentDay(lastClaim, streak)
    local canClaim, _ = canClaimReward(lastClaim)
    
    -- Validate claim
    if not canClaim then
        print(string.format("[DailyRewardsService] %s cannot claim yet (cooldown)", player.Name))
        Packets.dailyRewardClaimed.sendTo({
            success = false,
            day = day,
        }, player)
        return false
    end
    
    if day ~= currentDay then
        print(string.format("[DailyRewardsService] %s tried to claim day %d but should claim day %d", player.Name, day, currentDay))
        Packets.dailyRewardClaimed.sendTo({
            success = false,
            day = day,
        }, player)
        return false
    end
    
    -- Get reward config
    local rewardConfig = DailyRewardsConfig.GetReward(day)
    if not rewardConfig then
        warn(string.format("[DailyRewardsService] No reward config for day %d", day))
        Packets.dailyRewardClaimed.sendTo({
            success = false,
            day = day,
        }, player)
        return false
    end
    
    -- Distribute rewards
    local coinsGiven = 0
    local xpGiven = 0
    local itemGiven = nil
    
    -- Add coins
    if rewardConfig.Coins and rewardConfig.Coins > 0 then
        playerData:AddGold(rewardConfig.Coins)
        coinsGiven = rewardConfig.Coins
        print(string.format("[DailyRewardsService] Gave %s %d coins", player.Name, coinsGiven))
    end
    
    -- Add XP
    if rewardConfig.XP and rewardConfig.XP > 0 then
        playerData:AddExperience(rewardConfig.XP)
        xpGiven = rewardConfig.XP
        print(string.format("[DailyRewardsService] Gave %s %d XP", player.Name, xpGiven))
    end
    
    -- Add items (Day 7 special)
    if rewardConfig.Items then
        local invManager = getInventoryManager()
        for _, itemReward in ipairs(rewardConfig.Items) do
            local newItem = invManager.AddItem(
                player,
                itemReward.TemplateId
            )
            if newItem then
                itemGiven = itemReward.TemplateId
                print(string.format("[DailyRewardsService] Gave %s item: %s", player.Name, itemReward.TemplateId))
            end
        end
    end
    
    -- Update player data
    playerData.LastDailyRewardClaim = getCurrentTime()
    
    -- Advance streak (wrap at 7)
    if currentDay >= 7 then
        playerData.DailyRewardStreak = 1
    else
        playerData.DailyRewardStreak = currentDay + 1
    end
    
    print(string.format("[DailyRewardsService] %s claimed day %d, next streak: %d", player.Name, day, playerData.DailyRewardStreak))
    
    -- Send confirmation
    Packets.dailyRewardClaimed.sendTo({
        success = true,
        day = day,
        coins = if coinsGiven > 0 then coinsGiven else nil,
        xp = if xpGiven > 0 then xpGiven else nil,
        itemTemplateId = itemGiven,
    }, player)
    
    -- Send updated state
    DailyRewardsService.SendRewardsState(player)
    
    return true
end

--[[
    Initializes the Daily Rewards Service.
]]
function DailyRewardsService.Init()
    -- Listen for state requests
    Packets.requestDailyRewards.listen(function(_, player: Player?)
        if not player then return end
        local userId = player.UserId
        local now = os.clock()
        
        -- Rate limit
        if LastRequest[userId] and (now - LastRequest[userId]) < REQUEST_COOLDOWN then
            return
        end
        LastRequest[userId] = now
        
        DailyRewardsService.SendRewardsState(player)
    end)
    
    -- Listen for claim requests
    Packets.claimDailyReward.listen(function(data, player: Player?)
        if not player or not data then return end
        local userId = player.UserId
        local now = os.clock()
        
        -- Rate limit
        if LastRequest[userId] and (now - LastRequest[userId]) < REQUEST_COOLDOWN then
            return
        end
        LastRequest[userId] = now
        
        DailyRewardsService.ClaimReward(player, data.day)
    end)
    
    print("[DailyRewardsService] Initialized!")
end

return DailyRewardsService

--!strict
--[[
    HourlyRewardsService
    Tracks player playtime and handles hourly reward claims.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")

local Packets = require(Shared:WaitForChild("Packets"))
local HourlyRewardsConfig = require(Shared:WaitForChild("Rewards"):WaitForChild("HourlyRewardsConfig"))


local HourlyRewardsService = {}

-- Session tracking
local PlayerStartTimes: {[number]: number} = {}
local ClaimedRewards: {[number]: {number}} = {}

-- Constants
local SYNC_INTERVAL = 30 -- Sync with client every 30s

-- Internal: Get inventory manager (lazy load to avoid circular deps)
local function getInventoryManager()
    return require(script.Parent.Parent.Inventory)
end


--[[
    Get current playtime in seconds for a player.
]]
local function getPlaytime(player: Player): number
    local startTime = PlayerStartTimes[player.UserId]
    if not startTime then return 0 end
    return os.time() - startTime
end

--[[
    Sends current hourly rewards state to client.
]]
function HourlyRewardsService.SendState(player: Player)
    local userId = player.UserId
    local playtime = getPlaytime(player)
    local claimed = ClaimedRewards[userId] or {}
    
    Packets.hourlyRewardsData.sendTo({
        claimedIds = claimed,
        playtimeSeconds = playtime,
    }, player)
end

--[[
    Handles claiming an hourly reward.
]]
function HourlyRewardsService.ClaimReward(player: Player, rewardId: number)
    local userId = player.UserId
    local playtime = getPlaytime(player)
    local reward = HourlyRewardsConfig.GetReward(rewardId)
    
    if not reward then return end
    
    -- Check if already claimed
    local claimed = ClaimedRewards[userId] or {}
    for _, id in ipairs(claimed) do
        if id == rewardId then
            warn(`[HourlyRewardsService] {player.Name} already claimed reward {rewardId}`)
            return
        end
    end
    
    -- Check if time requirement met
    if playtime < reward.TimeRequired then
        warn(`[HourlyRewardsService] {player.Name} hasn't reached playtime for reward {rewardId}`)
        return
    end
    
    -- Grant reward
    local invManager = getInventoryManager()
    
    local newItem = invManager.AddItem(
        player,
        reward.TemplateId
    )
    
    if newItem then
        table.insert(claimed, rewardId)
        ClaimedRewards[userId] = claimed
        
        Packets.hourlyRewardClaimed.sendTo({
            success = true,
            rewardId = rewardId,
            itemTemplateId = reward.TemplateId,
        }, player)
        
        print(`[HourlyRewardsService] {player.Name} claimed hourly reward {rewardId}: {reward.TemplateId}`)
        
        -- Update state
        HourlyRewardsService.SendState(player)
    else
        warn(`[HourlyRewardsService] Failed to give reward {rewardId} to {player.Name}`)
    end
end

--[[
    Adds playtime (in seconds) to a player's session.
]]
function HourlyRewardsService.AddPlaytime(player: Player, seconds: number)
    local current = PlayerStartTimes[player.UserId]
    if not current then return end
    PlayerStartTimes[player.UserId] = current - seconds
    HourlyRewardsService.SendState(player)
end

--[[
    Resets hourly reward session for a player.
]]
function HourlyRewardsService.ResetSession(player: Player)
    PlayerStartTimes[player.UserId] = os.time()
    ClaimedRewards[player.UserId] = {}
    HourlyRewardsService.SendState(player)
end

--[[
    Initializes the service.
]]
function HourlyRewardsService.Init()
    -- Handle player joins
    -- Handle player join logic
    local function onPlayerAdded(player)
        if PlayerStartTimes[player.UserId] then return end -- Already initialized
        
        PlayerStartTimes[player.UserId] = os.time()
        ClaimedRewards[player.UserId] = {}
        
        -- Initial sync
        task.delay(1, function()
            if player.Parent then
                HourlyRewardsService.SendState(player)
            end
        end)
    end

    -- Handle player joins
    Players.PlayerAdded:Connect(onPlayerAdded)
    
    -- Handle existing players
    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(function() onPlayerAdded(player) end)
    end
    
    -- Handle player leaves
    Players.PlayerRemoving:Connect(function(player)
        PlayerStartTimes[player.UserId] = nil
        ClaimedRewards[player.UserId] = nil
    end)
    
    -- Periodic sync loop
    task.spawn(function()
        while true do
            task.wait(SYNC_INTERVAL)
            for _, player in ipairs(Players:GetPlayers()) do
                HourlyRewardsService.SendState(player)
            end
        end
    end)
    
    -- Listen for packets
    Packets.requestHourlyRewards.listen(function(_, player: Player?)
        if not player then return end
        HourlyRewardsService.SendState(player)
    end)
    
    Packets.claimHourlyReward.listen(function(data, player: Player?)
        if not player or not data then return end
        HourlyRewardsService.ClaimReward(player, data.rewardId)
    end)
end

return HourlyRewardsService

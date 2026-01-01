--!strict
--[[
    LeaderboardService
    Server-side service managing OrderedDataStores for leaderboards.
    
    Supports Daily, Weekly, Monthly, and AllTime leaderboards.
    Uses UTC time for consistent reset periods across all players.
    
    Usage:
        LeaderboardService.Init()
        LeaderboardService.RegisterLeaderboard("TotalXP", { DisplayName = "Total XP" })
        LeaderboardService.UpdateScore(player, "TotalXP", 1000)
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")
local Packages = Rojo:WaitForChild("Packages")

local Promise = require(Packages:WaitForChild("promise"))
local _Signal = require(Packages:WaitForChild("signal")) -- Reserved for future use
local Packets = require(Shared:WaitForChild("Packets"))
local LeaderboardModule = require(Shared:WaitForChild("Leaderboard"))
local Constants = LeaderboardModule.Constants

type LeaderboardEntry = LeaderboardModule.LeaderboardEntry
type LeaderboardPage = LeaderboardModule.LeaderboardPage
type LeaderboardOptions = LeaderboardModule.LeaderboardOptions
type LeaderboardPeriod = LeaderboardModule.LeaderboardPeriod

local LeaderboardService = {}

-- Registered leaderboards: { [valueName]: LeaderboardOptions }
local registeredLeaderboards: {[string]: LeaderboardOptions} = {}

-- Cache: { [cacheKey]: { data: LeaderboardPage, timestamp: number } }
local cache: {[string]: { data: LeaderboardPage, timestamp: number }} = {}

-- Player info cache: { [userId]: { Username: string, DisplayName: string } }
local playerInfoCache: {[number]: { Username: string, DisplayName: string }} = {}

--------------------------------------------------------------------------------
-- Time Period Helpers
--------------------------------------------------------------------------------

--[[
    Gets the current date key for a period (UTC-based).
]]
local function getDateKey(period: LeaderboardPeriod): string
    local utcTime = os.time()
    
    if period == "Daily" then
        return os.date("!%Y%m%d", utcTime) :: string
    elseif period == "Weekly" then
        -- Use standard ISO week number
        return os.date("!%Y-W%W", utcTime) :: string
    elseif period == "Monthly" then
        return os.date("!%Y%m", utcTime) :: string
    else
        return "AllTime"
    end
end

--[[
    Gets the OrderedDataStore name for a leaderboard.
]]
local function getDataStoreName(valueName: string, period: LeaderboardPeriod): string
    local dateKey = getDateKey(period)
    if period == "AllTime" then
        return string.format("%s_%s_AllTime", Constants.DATASTORE_PREFIX, valueName)
    else
        return string.format("%s_%s_%s_%s", Constants.DATASTORE_PREFIX, valueName, period, dateKey)
    end
end

--[[
    Gets or creates an OrderedDataStore for the given leaderboard.
]]
local function getDataStore(valueName: string, period: LeaderboardPeriod): OrderedDataStore
    local name = getDataStoreName(valueName, period)
    return DataStoreService:GetOrderedDataStore(name)
end

--[[
    Gets a cache key for the given leaderboard and page.
]]
local function getCacheKey(valueName: string, period: LeaderboardPeriod, page: number): string
    return string.format("%s_%s_%s_%d", valueName, period, getDateKey(period), page)
end

--------------------------------------------------------------------------------
-- Display Name Fetching
--------------------------------------------------------------------------------

--[[
    Gets player info for a userId (cached).
]]
local function getPlayerInfo(userId: number): { Username: string, DisplayName: string }
    if playerInfoCache[userId] then
        return playerInfoCache[userId]
    end
    
    -- Check if player is in server
    local player = Players:GetPlayerByUserId(userId)
    if player then
        local info = { Username = player.Name, DisplayName = player.DisplayName }
        playerInfoCache[userId] = info
        return info
    end
    
    -- Fetch from API (wrapped in pcall)
    -- UserService gives us both names
    local UserService = game:GetService("UserService")
    local success, result = pcall(function()
        return UserService:GetUserInfosByUserIdsAsync({userId})
    end)
    
    if success and result and #result > 0 then
        local entry = result[1]
        local info = { Username = entry.Username, DisplayName = entry.DisplayName }
        playerInfoCache[userId] = info
        return info
    end
    
    -- Fallback
    local fallback = { Username = "Unknown", DisplayName = "Unknown" }
    -- Try just username as last resort
    local nameSuccess, name = pcall(function()
        return Players:GetNameFromUserIdAsync(userId)
    end)
    
    if nameSuccess and name then
        fallback.Username = name
        fallback.DisplayName = name
    end
    
    playerInfoCache[userId] = fallback
    return fallback
end

--------------------------------------------------------------------------------
-- Core Functions
--------------------------------------------------------------------------------

--[[
    Registers a new leaderboard type.
    
    @param valueName - Unique identifier for this leaderboard (e.g., "TotalXP")
    @param options - Configuration options
]]
function LeaderboardService.RegisterLeaderboard(valueName: string, options: LeaderboardOptions?)
    registeredLeaderboards[valueName] = options or {}
    print(string.format("[LeaderboardService] Registered leaderboard: %s", valueName))
end

--[[
    Updates a player's score on all period leaderboards.
    
    @param player - The player
    @param valueName - The leaderboard name
    @param score - The new score (absolute value, not delta)
]]
function LeaderboardService.UpdateScore(player: Player, valueName: string, score: number)
    if not registeredLeaderboards[valueName] then
        warn(string.format("[LeaderboardService] Leaderboard '%s' not registered!", valueName))
        return
    end
    
    local userId = player.UserId
    local key = tostring(userId)
    
    -- Update player info cache
    playerInfoCache[userId] = { Username = player.Name, DisplayName = player.DisplayName }
    
    -- Update all periods
    local periods: {LeaderboardPeriod} = {"Daily", "Weekly", "Monthly", "AllTime"}
    
    for _, period in periods do
        task.spawn(function()
            local dataStore = getDataStore(valueName, period)
            local success, err = pcall(function()
                dataStore:SetAsync(key, score)
            end)
            
            if not success then
                warn(string.format("[LeaderboardService] Failed to update %s/%s for %s: %s", 
                    valueName, period, player.Name, tostring(err)))
            end
        end)
    end
end

--[[
    Increments a player's score on all period leaderboards.
    
    @param player - The player
    @param valueName - The leaderboard name
    @param delta - The amount to add
]]
function LeaderboardService.IncrementScore(player: Player, valueName: string, delta: number)
    if not registeredLeaderboards[valueName] then
        warn(string.format("[LeaderboardService] Leaderboard '%s' not registered!", valueName))
        return
    end
    
    local userId = player.UserId
    local key = tostring(userId)
    
    -- Update player info cache
    playerInfoCache[userId] = { Username = player.Name, DisplayName = player.DisplayName }
    
    -- Increment all periods
    local periods: {LeaderboardPeriod} = {"Daily", "Weekly", "Monthly", "AllTime"}
    
    for _, period in periods do
        task.spawn(function()
            local dataStore = getDataStore(valueName, period)
            local success, err = pcall(function()
                dataStore:UpdateAsync(key, function(oldValue)
                    return (oldValue or 0) + delta
                end)
            end)
            
            if not success then
                warn(string.format("[LeaderboardService] Failed to increment %s/%s for %s: %s", 
                    valueName, period, player.Name, tostring(err)))
            end
        end)
    end
end

--[[
    Gets a page of leaderboard data.
    
    @param valueName - The leaderboard name
    @param period - The time period
    @param pageNumber - Page number (1-indexed)
    @return Promise<LeaderboardPage>
]]
function LeaderboardService.GetPage(valueName: string, period: LeaderboardPeriod, pageNumber: number)
    return Promise.new(function(resolve, reject)
        -- Validate inputs
        if not registeredLeaderboards[valueName] then
            reject(string.format("Leaderboard '%s' not registered", valueName))
            return
        end
        
        pageNumber = math.clamp(pageNumber, 1, Constants.TOTAL_PAGES)
        
        -- Check cache
        local cacheKey = getCacheKey(valueName, period, pageNumber)
        local cached = cache[cacheKey]
        if cached and (os.time() - cached.timestamp) < Constants.CACHE_DURATION then
            resolve(cached.data)
            return
        end
        
        -- Fetch from DataStore
        local dataStore = getDataStore(valueName, period)
        local startIndex = (pageNumber - 1) * Constants.ENTRIES_PER_PAGE + 1
        
        local success, pages = pcall(function()
            return dataStore:GetSortedAsync(false, Constants.ENTRIES_PER_PAGE, nil, nil)
        end)
        
        if not success then
            reject(string.format("Failed to fetch leaderboard: %s", tostring(pages)))
            return
        end
        
        -- We need to paginate through the OrderedDataStore pages
        local entries: {LeaderboardEntry} = {}
        local currentRank = 1
        local targetStartRank = startIndex
        local targetEndRank = startIndex + Constants.ENTRIES_PER_PAGE - 1
        
        -- Skip to the right page
        local currentPage = pages
        while currentPage do
            local pageData = currentPage:GetCurrentPage()
            
            for _, entry in pageData do
                if currentRank >= targetStartRank and currentRank <= targetEndRank then
                    local userId = tonumber(entry.key) or 0
                    local info = getPlayerInfo(userId)
                    table.insert(entries, {
                        Rank = currentRank,
                        UserId = userId,
                        DisplayName = info.DisplayName,
                        Username = info.Username,
                        Value = entry.value,
                    })
                end
                
                currentRank += 1
                
                -- Stop if we've collected enough entries
                if currentRank > targetEndRank then
                    break
                end
            end
            
            -- Move to next page if needed and available
            if currentRank > targetEndRank or not currentPage.IsFinished then
                break
            end
            
            if not currentPage.IsFinished then
                local nextSuccess, _nextErr = pcall(function()
                    currentPage:AdvanceToNextPageAsync()
                end)
                if not nextSuccess then
                    break
                end
            else
                break
            end
        end
        
        -- Calculate total pages based on entries found
        local totalEntries = math.min(currentRank - 1, Constants.MAX_ENTRIES)
        local totalPages = math.max(1, math.ceil(totalEntries / Constants.ENTRIES_PER_PAGE))
        
        local result: LeaderboardPage = {
            ValueName = valueName,
            Period = period,
            PageNumber = pageNumber,
            TotalPages = totalPages,
            Entries = entries,
        }
        
        -- Cache result
        cache[cacheKey] = {
            data = result,
            timestamp = os.time(),
        }
        
        resolve(result)
    end)
end

--[[
    Gets a player's rank on a leaderboard.
    
    @param player - The player
    @param valueName - The leaderboard name
    @param period - The time period
    @return Promise<{rank: number, value: number}?>
]]
function LeaderboardService.GetPlayerRank(player: Player, valueName: string, period: LeaderboardPeriod)
    return Promise.new(function(resolve, reject)
        local dataStore = getDataStore(valueName, period)
        local key = tostring(player.UserId)
        
        local success, result = pcall(function()
            return dataStore:GetAsync(key)
        end)
        
        if not success then
            reject(tostring(result))
            return
        end
        
        if result == nil then
            resolve(nil :: {rank: number?, value: number}?)
            return
        end
        
        -- To get rank, we need to count how many have higher scores
        -- This is expensive, so we estimate based on sorted pages
        local rankSuccess, rank = pcall(function(): number?
            local pages = dataStore:GetSortedAsync(false, 100)
            local currentRank = 1
            
            while pages do
                local pageData = pages:GetCurrentPage()
                for _, entry in pageData do
                    if entry.key == key then
                        return currentRank
                    end
                    currentRank += 1
                end
                
                if pages.IsFinished then
                    break
                end
                
                pages:AdvanceToNextPageAsync()
            end
            
            return nil
        end)
        
        if rankSuccess and rank then
            resolve({ rank = rank :: number, value = result :: number })
        else
            resolve({ rank = nil :: number?, value = result :: number })
        end
    end)
end

--------------------------------------------------------------------------------
-- Network Handlers
--------------------------------------------------------------------------------

local function setupNetworkListeners()
    Packets.requestLeaderboard.listen(function(data, player)
        local _requestPlayer = player :: Player
        LeaderboardService.GetPage(data.valueName, data.period :: LeaderboardPeriod, data.page)
            :andThen(function(pageData)
                -- Convert entries for packet
                local packetEntries = {}
                for _, entry in pageData.Entries do
                    table.insert(packetEntries, {
                        rank = entry.Rank,
                        userId = entry.UserId,
                        displayName = entry.DisplayName,
                        username = entry.Username,
                        value = entry.Value,
                    })
                end
                
                Packets.leaderboardData.sendTo({
                    valueName = pageData.ValueName,
                    period = pageData.Period,
                    page = pageData.PageNumber,
                    totalPages = pageData.TotalPages,
                    entries = packetEntries,
                }, player :: Player)
            end)
            :catch(function(err)
                warn(string.format("[LeaderboardService] Failed to get page for %s: %s", 
                    (player :: Player).Name, tostring(err)))
            end)
    end)
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

function LeaderboardService.Init()
    setupNetworkListeners()
    
    -- Cache info for all current players
    for _, player in Players:GetPlayers() do
        playerInfoCache[player.UserId] = { Username = player.Name, DisplayName = player.DisplayName }
    end
    
    Players.PlayerAdded:Connect(function(player)
        playerInfoCache[player.UserId] = { Username = player.Name, DisplayName = player.DisplayName }
    end)
    
    print("[LeaderboardService] Initialized!")
end

return LeaderboardService

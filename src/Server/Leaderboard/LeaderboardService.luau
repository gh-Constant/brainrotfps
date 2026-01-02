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

-- Write Buffer: { [bufferKey]: { [userId]: score } }
local scoreBuffer: {[string]: {[number]: number}} = {}
local FLUSH_INTERVAL = 60 -- Seconds between DataStore flushes

-- Player Score Cache: Stores loaded DataStore scores per player/valueName/period
-- Format: { [userId]: { ["TotalXP_Daily"]: 1500, ["BrainrotKills_AllTime"]: 42 } }
local playerScoreCache: {[number]: {[string]: number}} = {}

-- Logging helper (checks Config.Leaderboard.Logging attribute)
local function log(message: string)
    local config = ReplicatedStorage:FindFirstChild("Config")
    local lbConfig = config and config:FindFirstChild("Leaderboard")
    if lbConfig and lbConfig:GetAttribute("Logging") == true then
        print(message)
    end
end

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

-- Use a high multiplier to preserve precision in log space
-- This allows us to store values up to 10^9,000,000 within a 64-bit integer
local LOG_MULTIPLIER = 1e12

local function encodeScore(score: number): number
    if score <= 0 then return 0 end
    return math.floor(math.log10(score) * LOG_MULTIPLIER)
end

local function decodeScore(encoded: number): number
    if encoded <= 0 then return 0 end
    return 10 ^ (encoded / LOG_MULTIPLIER)
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
    
    -- Update periods
    local periods: {LeaderboardPeriod} = {"Daily", "Weekly", "Monthly", "AllTime"}
    
    -- If this is a "Level" leaderboard, only track All-Time
    if valueName == "Level" then
        periods = {"AllTime"}
    end
    
    local userId = player.UserId
    
    -- Update player info cache
    playerInfoCache[userId] = { Username = player.Name, DisplayName = player.DisplayName }

    -- Buffer the score for each period
    for _, period in periods do
        local bufferKey = valueName .. "_" .. period
        if not scoreBuffer[bufferKey] then
            scoreBuffer[bufferKey] = {}
        end
        scoreBuffer[bufferKey][userId] = score
    end
    
    log(string.format("[Leaderboard] UpdateScore: %s -> %s = %d", player.Name, valueName, score))
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
    
    -- Update player info cache
    playerInfoCache[userId] = { Username = player.Name, DisplayName = player.DisplayName }
    
    -- Increment periods
    local periods: {LeaderboardPeriod} = {"Daily", "Weekly", "Monthly", "AllTime"}
    
    -- If this is a "Level" leaderboard, only track All-Time
    if valueName == "Level" then
        periods = {"AllTime"}
    end
    
    for _, period in periods do
        local bufferKey = valueName .. "_" .. period
        if not scoreBuffer[bufferKey] then
            scoreBuffer[bufferKey] = {}
        end
        
        -- Get cached DataStore value (loaded on player join) or current buffer value
        local cachedScore = 0
        if playerScoreCache[userId] and playerScoreCache[userId][bufferKey] then
            cachedScore = playerScoreCache[userId][bufferKey]
        end
        local currentBufferValue = scoreBuffer[bufferKey][userId] or cachedScore
        
        -- Update with delta
        local newScore = currentBufferValue + delta
        scoreBuffer[bufferKey][userId] = newScore
        
        -- Also update the cache so subsequent increments use the new value
        if playerScoreCache[userId] then
            playerScoreCache[userId][bufferKey] = newScore
        end
        
        -- Log only for AllTime period to avoid spam
        if period == "AllTime" then
            log(string.format("[Leaderboard] IncrementScore: %s -> %s +%d = %d (cached: %d)", 
                player.Name, valueName, delta, newScore, cachedScore))
        end
    end
end

--[[
    Loads existing scores from DataStore for a player.
    Returns a Promise that resolves when all scores are loaded.
    
    @param player - The player
    @return Promise that resolves when loading is complete
]]
function LeaderboardService.LoadPlayerScores(player: Player)
    local userId = player.UserId
    
    -- Initialize cache for this player
    if not playerScoreCache[userId] then
        playerScoreCache[userId] = {}
    end
    
    local promises = {}
    
    -- Load scores for each registered leaderboard
    for valueName, _ in pairs(registeredLeaderboards) do
        local periods: {LeaderboardPeriod} = {"Daily", "Weekly", "Monthly", "AllTime"}
        if valueName == "Level" then
            periods = {"AllTime"}
        end
        
        for _, period in periods do
            local bufferKey = valueName .. "_" .. period
            local dataStore = getDataStore(valueName, period :: LeaderboardPeriod)
            local key = tostring(userId)
            
            local promise = Promise.new(function(resolve)
                local success, result = pcall(function()
                    return dataStore:GetAsync(key)
                end)
                
                if success and result then
                    local decodedScore = decodeScore(result)
                    playerScoreCache[userId] = playerScoreCache[userId] or {}
                    playerScoreCache[userId][bufferKey] = decodedScore
                    
                    -- Log only AllTime to avoid spam
                    if period == "AllTime" then
                        log(string.format("[Leaderboard] Loaded %s for %s: %d", valueName, player.Name, decodedScore))
                    end
                elseif not success then
                    warn(string.format("[LeaderboardService] Failed to load %s for %s: %s", 
                        bufferKey, player.Name, tostring(result)))
                end
                resolve()
            end)
            
            table.insert(promises, promise)
        end
    end
    
    return Promise.all(promises)
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
                    local entryUserId = tonumber(entry.key) or 0
                    local info = getPlayerInfo(entryUserId)
                    table.insert(entries, {
                        Rank = currentRank,
                        UserId = entryUserId,
                        DisplayName = info.DisplayName,
                        Username = info.Username,
                        Value = decodeScore(entry.value),
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
            return (dataStore :: any):GetAsync(key)
        end)
        
        if not success then
            reject(tostring(result))
            return
        end
        
        local numericResult = result :: number?
        
        if numericResult == nil then
            resolve(nil)
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
            resolve({ rank = rank :: number, value = numericResult :: number })
        else
            resolve({ rank = nil, value = numericResult :: number } :: any)
        end
    end)
end

--------------------------------------------------------------------------------
-- Network Handlers
--------------------------------------------------------------------------------

local function flushBuffer()
    local currentBuffer = scoreBuffer
    scoreBuffer = {} -- Swap buffers immediately to avoid race conditions during async calls

    for bufferKey, entries in currentBuffer do
        local split = string.split(bufferKey, "_")
        local valueName = split[1]
        local period = split[2] :: LeaderboardPeriod
        
        local dataStore = getDataStore(valueName, period)
        
        for entryUserId, score in entries do
            task.spawn(function()
                local key = tostring(entryUserId)
                local success, err = pcall(function()
                    dataStore:UpdateAsync(key, function(oldEncoded)
                        -- For simplicity, we treat buffered values as 
                        -- "the most recent known score" to keep it robust.
                        return encodeScore(score)
                    end)
                end)
                
                if not success then
                    warn(string.format("[LeaderboardService] Buffer flush failed for %s/%s/ID:%d: %s", 
                        valueName, tostring(period), entryUserId, tostring(err)))
                end
            end)
        end
    end
end

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
    
    -- Cache info for all current players and load their scores
    for _, player in Players:GetPlayers() do
        playerInfoCache[player.UserId] = { Username = player.Name, DisplayName = player.DisplayName }
        LeaderboardService.LoadPlayerScores(player):await()
    end
    
    Players.PlayerAdded:Connect(function(player)
        playerInfoCache[player.UserId] = { Username = player.Name, DisplayName = player.DisplayName }
        
        -- Wait for scores to load before player can act
        LeaderboardService.LoadPlayerScores(player):await()
    end)

    Players.PlayerRemoving:Connect(function(player)
        -- Flush this player's buffer immediately to ensure data saves
        local userId = player.UserId
        
        -- Force flush any buffered scores for this player
        for bufferKey, entries in pairs(scoreBuffer) do
            if entries[userId] then
                local split = string.split(bufferKey, "_")
                local valueName = split[1]
                local period = split[2] :: LeaderboardPeriod
                local dataStore = getDataStore(valueName, period)
                local key = tostring(userId)
                local score = entries[userId]
                
                task.spawn(function()
                    local success, err = pcall(function()
                        dataStore:UpdateAsync(key, function(_oldEncoded)
                            return encodeScore(score)
                        end)
                    end)
                    if not success then
                        warn(string.format("[LeaderboardService] Failed to save score on leave for %s: %s", player.Name, tostring(err)))
                    end
                end)
                
                entries[userId] = nil
            end
        end
        
        -- Clear player score cache
        playerScoreCache[userId] = nil
    end)
    
    -- Start buffer flush loop
    task.spawn(function()
        while true do
            task.wait(FLUSH_INTERVAL)
            flushBuffer()
        end
    end)
    
    print("[LeaderboardService] Initialized with Write Buffer!")
end

return LeaderboardService

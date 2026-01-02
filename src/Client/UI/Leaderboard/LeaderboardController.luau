--!strict
--[[
    LeaderboardController
    Client-side controller managing leaderboard state and network requests.
    
    Usage:
        local controller = require(LeaderboardController)
        controller.Init()
        controller.RequestPage("TotalXP", "Daily", 1)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local _Players = game:GetService("Players") -- Reserved for future use

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")
local Packages = Rojo:WaitForChild("Packages")

local Signal = require(Packages:WaitForChild("signal"))
local Packets = require(Shared:WaitForChild("Packets"))
local LeaderboardModule = require(Shared:WaitForChild("Leaderboard"))
local _Constants = LeaderboardModule.Constants -- Reserved for future use

type LeaderboardEntry = LeaderboardModule.LeaderboardEntry
type LeaderboardPage = LeaderboardModule.LeaderboardPage
type LeaderboardPeriod = LeaderboardModule.LeaderboardPeriod

local LeaderboardController = {
    Name = "LeaderboardController",
    Priority = 50
}

-- State per valueName
type BoardState = {
    valueName: string,
    period: LeaderboardPeriod,
    pageNumber: number,
    totalPages: number,
    entries: {LeaderboardEntry},
    isLoading: boolean,
}

local states: {[string]: BoardState} = {}

-- Cache for received data: { [cacheKey]: LeaderboardPage }
local pageCache: {[string]: LeaderboardPage} = {}

-- Signals (first argument is always valueName)
local OnDataReceived = Signal.new()
local OnPeriodChanged = Signal.new()
local OnPageChanged = Signal.new()
local OnLoadingChanged = Signal.new()

--------------------------------------------------------------------------------
-- Internal Helpers
--------------------------------------------------------------------------------

local function getCacheKey(valueName: string, period: LeaderboardPeriod, page: number): string
    return string.format("%s_%s_%d", valueName, period, page)
end

local function getState(valueName: string): BoardState
    if not states[valueName] then
        states[valueName] = {
            valueName = valueName,
            period = "AllTime",
            pageNumber = 1,
            totalPages = 1,
            entries = {},
            isLoading = false,
        }
    end
    return states[valueName]
end

local function setLoading(valueName: string, loading: boolean)
    local state = getState(valueName)
    if state.isLoading ~= loading then
        state.isLoading = loading
        OnLoadingChanged:Fire(valueName, loading)
    end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--[[
    Requests a specific page of leaderboard data.
]]
function LeaderboardController.RequestPage(valueName: string, period: LeaderboardPeriod, pageNumber: number, force: boolean?)
    -- Validate inputs
    if not valueName or valueName == "" then
        warn("[LeaderboardController] RequestPage called with nil/empty valueName!")
        return
    end
    if not period or period == "" then
        warn("[LeaderboardController] RequestPage called with nil/empty period!")
        return
    end
    
    local state = getState(valueName)
    local periodStr = tostring(period)
    
    -- Check cache first
    local cacheKey = getCacheKey(valueName, period, pageNumber)
    local cached = pageCache[cacheKey]
    if cached and not force then
        state.period = period
        state.pageNumber = cached.PageNumber
        state.totalPages = cached.TotalPages
        state.entries = cached.Entries
        OnDataReceived:Fire(valueName, cached)
        return
    end
    
    -- Request from server
    setLoading(valueName, true)
    
    print(string.format("[LeaderboardController] Requesting page %d of %s/%s", pageNumber, valueName, periodStr))
    
    Packets.requestLeaderboard.send({
        valueName = valueName,
        period = periodStr,
        page = math.clamp(pageNumber, 1, 255),
    })
end

--[[
    Gets the current leaderboard data for a specific valueName.
]]
function LeaderboardController.GetCurrentData(valueName: string): BoardState?
    return states[valueName]
end

--[[
    Changes the current time period and requests page 1.
]]
function LeaderboardController.SetPeriod(valueName: string, period: LeaderboardPeriod)
    local state = getState(valueName)
    if state.period ~= period then
        state.period = period
        OnPeriodChanged:Fire(valueName, period)
        LeaderboardController.RequestPage(valueName, period, 1)
    end
end

--[[
    Refreshes the current leaderboard data by bypassing the cache.
]]
function LeaderboardController.Refresh(valueName: string)
    local state = getState(valueName)
    if state.valueName then
        -- Clear current page from cache to force refresh
        local cacheKey = getCacheKey(state.valueName, state.period, state.pageNumber)
        pageCache[cacheKey] = nil
        
        LeaderboardController.RequestPage(
            state.valueName,
            state.period,
            state.pageNumber,
            true
        )
    end
end

--[[
    Navigates to the next page.
]]
function LeaderboardController.NextPage(valueName: string)
    local state = getState(valueName)
    if state.pageNumber < state.totalPages then
        LeaderboardController.RequestPage(
            state.valueName,
            state.period,
            state.pageNumber + 1
        )
    end
end

--[[
    Navigates to the previous page.
]]
function LeaderboardController.PrevPage(valueName: string)
    local state = getState(valueName)
    if state.pageNumber > 1 then
        LeaderboardController.RequestPage(
            state.valueName,
            state.period,
            state.pageNumber - 1
        )
    end
end

--[[
    Navigates to a specific page.
]]
function LeaderboardController.GoToPage(valueName: string, page: number)
    local state = getState(valueName)
    local clampedPage = math.clamp(page, 1, state.totalPages)
    if clampedPage ~= state.pageNumber then
        LeaderboardController.RequestPage(
            state.valueName,
            state.period,
            clampedPage
        )
    end
end

--[[
    Gets the available periods.
]]
function LeaderboardController.GetPeriods(): {string}
    return {"Daily", "Weekly", "Monthly", "AllTime"}
end

--------------------------------------------------------------------------------
-- Signals (Public)
--------------------------------------------------------------------------------

LeaderboardController.OnDataReceived = OnDataReceived
LeaderboardController.OnPeriodChanged = OnPeriodChanged
LeaderboardController.OnPageChanged = OnPageChanged
LeaderboardController.OnLoadingChanged = OnLoadingChanged

--------------------------------------------------------------------------------
-- Network Handlers
--------------------------------------------------------------------------------

local function setupNetworkListeners()
    Packets.leaderboardData.listen(function(data)
        setLoading(data.valueName, false)
        
        -- Convert packet entries to typed entries
        local entries: {LeaderboardEntry} = {}
        for _, entry in data.entries do
            table.insert(entries, {
                Rank = entry.rank,
                UserId = math.floor(entry.userId),
                DisplayName = entry.displayName,
                Username = entry.username,
                Value = math.floor(entry.value),
            })
        end
        
        local page: LeaderboardPage = {
            ValueName = data.valueName,
            Period = data.period :: LeaderboardPeriod,
            PageNumber = data.page,
            TotalPages = data.totalPages,
            Entries = entries,
        }
        
        -- Cache the data
        local cacheKey = getCacheKey(data.valueName, data.period :: LeaderboardPeriod, data.page)
        pageCache[cacheKey] = page
        
        -- Update state
        local state = getState(data.valueName)
        state.period = page.Period
        state.pageNumber = page.PageNumber
        state.totalPages = page.TotalPages
        state.entries = page.Entries
        
        OnDataReceived:Fire(data.valueName, page)
        OnPageChanged:Fire(data.valueName, page.PageNumber, page.TotalPages)
    end)
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

function LeaderboardController.Init(_context: any)
    setupNetworkListeners()
    print("[LeaderboardController] Initialized!")
end

return LeaderboardController

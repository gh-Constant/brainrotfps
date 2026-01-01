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

-- Current state
local currentState: {
    valueName: string?,
    period: LeaderboardPeriod,
    pageNumber: number,
    totalPages: number,
    entries: {LeaderboardEntry},
    isLoading: boolean,
} = {
    valueName = nil,
    period = "AllTime",
    pageNumber = 1,
    totalPages = 1,
    entries = {},
    isLoading = false,
}

-- Cache for received data: { [cacheKey]: LeaderboardPage }
local pageCache: {[string]: LeaderboardPage} = {}

-- Signals
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

local function setLoading(loading: boolean)
    if currentState.isLoading ~= loading then
        currentState.isLoading = loading
        OnLoadingChanged:Fire(loading)
    end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--[[
    Requests a specific page of leaderboard data.
    
    @param valueName - The leaderboard identifier
    @param period - The time period
    @param pageNumber - Page number (1-indexed)
]]
function LeaderboardController.RequestPage(valueName: string, period: LeaderboardPeriod, pageNumber: number)
    -- Validate inputs
    if not valueName or valueName == "" then
        warn("[LeaderboardController] RequestPage called with nil/empty valueName!")
        return
    end
    if not period or period == "" then
        warn("[LeaderboardController] RequestPage called with nil/empty period!")
        return
    end
    
    -- Ensure period is a valid string
    local periodStr = tostring(period)
    
    -- Check cache first
    local cacheKey = getCacheKey(valueName, period, pageNumber)
    local cached = pageCache[cacheKey]
    if cached then
        currentState.valueName = valueName
        currentState.period = period
        currentState.pageNumber = cached.PageNumber
        currentState.totalPages = cached.TotalPages
        currentState.entries = cached.Entries
        OnDataReceived:Fire(cached)
        return
    end
    
    -- Request from server
    setLoading(true)
    
    print(string.format("[LeaderboardController] Requesting page %d of %s/%s", pageNumber, valueName, periodStr))
    
    Packets.requestLeaderboard.send({
        valueName = valueName,
        period = periodStr,
        page = math.clamp(pageNumber, 1, 255), -- uint8 limit
    })
end

--[[
    Gets the current leaderboard data.
]]
function LeaderboardController.GetCurrentData(): {
    valueName: string?,
    period: LeaderboardPeriod,
    pageNumber: number,
    totalPages: number,
    entries: {LeaderboardEntry},
    isLoading: boolean,
}
    return currentState
end

--[[
    Changes the current time period and requests page 1.
]]
function LeaderboardController.SetPeriod(period: LeaderboardPeriod)
    if currentState.period ~= period then
        currentState.period = period
        OnPeriodChanged:Fire(period)
        
        if currentState.valueName then
            LeaderboardController.RequestPage(currentState.valueName, period, 1)
        end
    end
end

--[[
    Navigates to the next page.
]]
function LeaderboardController.NextPage()
    if currentState.pageNumber < currentState.totalPages and currentState.valueName then
        LeaderboardController.RequestPage(
            currentState.valueName,
            currentState.period,
            currentState.pageNumber + 1
        )
    end
end

--[[
    Navigates to the previous page.
]]
function LeaderboardController.PrevPage()
    if currentState.pageNumber > 1 and currentState.valueName then
        LeaderboardController.RequestPage(
            currentState.valueName,
            currentState.period,
            currentState.pageNumber - 1
        )
    end
end

--[[
    Navigates to a specific page.
]]
function LeaderboardController.GoToPage(page: number)
    if currentState.valueName then
        local clampedPage = math.clamp(page, 1, currentState.totalPages)
        if clampedPage ~= currentState.pageNumber then
            LeaderboardController.RequestPage(
                currentState.valueName,
                currentState.period,
                clampedPage
            )
        end
    end
end

--[[
    Gets the available periods.
]]
function LeaderboardController.GetPeriods(): {string}
    return {"Daily", "Weekly", "Monthly", "AllTime"}
end

--[[
    Checks if currently on first page.
]]
function LeaderboardController.IsFirstPage(): boolean
    return currentState.pageNumber <= 1
end

--[[
    Checks if currently on last page.
]]
function LeaderboardController.IsLastPage(): boolean
    return currentState.pageNumber >= currentState.totalPages
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
        setLoading(false)
        
        -- Convert packet entries to typed entries
        local entries: {LeaderboardEntry} = {}
        for _, entry in data.entries do
            table.insert(entries, {
                Rank = entry.rank,
                UserId = math.floor(entry.userId), -- Convert float64 back to int
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
        currentState.valueName = page.ValueName
        currentState.period = page.Period
        currentState.pageNumber = page.PageNumber
        currentState.totalPages = page.TotalPages
        currentState.entries = page.Entries
        
        OnDataReceived:Fire(page)
        OnPageChanged:Fire(page.PageNumber, page.TotalPages)
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

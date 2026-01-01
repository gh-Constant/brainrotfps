--!strict
--[[
    LeaderboardInit
    Initializes the TotalXP All-Time leaderboard on the Screen part.
    
    Location: workspace.LeaderBoard.NormalLeaderboard.Screen
]]

-- Require from the same folder (script.Parent is the Leaderboard folder)
local LeaderboardController = require(script.Parent:WaitForChild("LeaderboardController"))
local LeaderboardExample = require(script.Parent:WaitForChild("LeaderboardExample"))

-- Initialize the controller
LeaderboardController.Init()

-- Wait for the leaderboard part
local leaderboardFolder = workspace:WaitForChild("LeaderBoard", 30)
if not leaderboardFolder then
    warn("[LeaderboardInit] Could not find workspace.LeaderBoard!")
    return
end

local normalLeaderboard = leaderboardFolder:WaitForChild("NormalLeaderBoard", 10)
if not normalLeaderboard then
    warn("[LeaderboardInit] Could not find LeaderBoard.NormalLeaderBoard!")
    return
end

local screenPart = normalLeaderboard:WaitForChild("Screen", 10) :: BasePart?
if not screenPart or not screenPart:IsA("BasePart") then
    warn("[LeaderboardInit] Could not find NormalLeaderboard.Screen or it's not a BasePart!")
    return
end

-- Create the All-Time Level leaderboard
local _displayLevel = LeaderboardExample.CreateDisplay({
    Part = screenPart,
    Face = Enum.NormalId.Front,
    ValueName = "Level",
    Period = "AllTime",
    PixelsPerStud = 50,
    AutoRefresh = true,
    RefreshInterval = 30,
    ShowPeriodTabs = false,
    Title = "🏆 TOP LEVEL 🏆",
})

print("[LeaderboardInit] Level All-Time leaderboard initialized on", screenPart:GetFullName())

-- initialize Daily XP Leaderboard
local dailyFolder = leaderboardFolder:WaitForChild("Daily", 5)
if dailyFolder then
    local dailyScreen = dailyFolder:WaitForChild("Screen", 5) :: BasePart?
    if dailyScreen and dailyScreen:IsA("BasePart") then
        LeaderboardExample.CreateDisplay({
            Part = dailyScreen,
            Face = Enum.NormalId.Front,
            ValueName = "TotalXP",
            Period = "Daily",
            PixelsPerStud = 50,
            AutoRefresh = true,
            RefreshInterval = 60, -- Refresh daily slightly less often
            ShowPeriodTabs = false, -- Fixed to Daily
            Title = "📅 DAILY XP 📅",
        })
        print("[LeaderboardInit] Daily XP leaderboard initialized")
    else
        warn("[LeaderboardInit] Could not find Daily.Screen")
    end
end

-- Initialize Weekly XP Leaderboard
local weeklyFolder = leaderboardFolder:WaitForChild("Weekly", 5)
if weeklyFolder then
    local weeklyScreen = weeklyFolder:WaitForChild("Screen", 5) :: BasePart?
    if weeklyScreen and weeklyScreen:IsA("BasePart") then
        LeaderboardExample.CreateDisplay({
            Part = weeklyScreen,
            Face = Enum.NormalId.Front,
            ValueName = "TotalXP",
            Period = "Weekly",
            PixelsPerStud = 50,
            AutoRefresh = true,
            RefreshInterval = 60,
            ShowPeriodTabs = false, -- Fixed to Weekly
            Title = "📅 WEEKLY XP 📅",
        })
        print("[LeaderboardInit] Weekly XP leaderboard initialized")
    else
        warn("[LeaderboardInit] Could not find Weekly.Screen")
    end
end

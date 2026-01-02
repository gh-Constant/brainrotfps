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

-- Helper to safely initialize a leaderboard
local function initLeaderboard(name: string, valueName: string, period: any, title: string)
    local board = workspace:WaitForChild(name, 10)
    if not board then
        warn("[LeaderboardInit] Could not find workspace." .. name)
        return
    end

    local screen = board:WaitForChild("Screen", 5) :: BasePart?
    if not screen or not screen:IsA("BasePart") then
        warn("[LeaderboardInit] Could not find Screen part for " .. name)
        return
    end

    LeaderboardExample.CreateDisplay({
        Part = screen,
        Face = Enum.NormalId.Front,
        ValueName = valueName,
        Period = period,
        PixelsPerStud = 50,
        AutoRefresh = true,
        RefreshInterval = 300,
        ShowPeriodTabs = false,
        Title = title,
    })
    
    print("[LeaderboardInit] Initialized " .. name .. " (" .. valueName .. " " .. tostring(period) .. ")")
end

-- Initialize the specific leaderboards
initLeaderboard("TOP_LEVEL_LEADERBOARD", "Level", "AllTime", "🏆 TOP LEVEL 🏆")
initLeaderboard("DAILY_XP_LEADERBOARD", "TotalXP", "Daily", "📅 DAILY XP 📅")
initLeaderboard("WEEKLY_XP_LEADERBOARD", "TotalXP", "Weekly", "📅 WEEKLY XP 📅")

-- Statistics Leaderboards
initLeaderboard("TOP_BRAINROTS_KILLS_LEADERBOARD", "BrainrotKills", "AllTime", "🧟 BRAINROT KILLS 🧟")
initLeaderboard("TOP_DAMAGE_LEADERBOARD", "TotalDamage", "AllTime", "💥 TOTAL DAMAGE �")
initLeaderboard("TOP_PLAYER_KILLS_LEADERBOARD", "PlayerKills", "AllTime", "⚔️ PLAYER KILLS ⚔️")
initLeaderboard("PLAYER_KILL_DAILY_LEADERBOARD", "PlayerKills", "Daily", "⚔️ DAILY KILLS ⚔️")

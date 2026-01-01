--!strict
--[[
    Leaderboard Shared Module
    Re-exports types and constants for the leaderboard system.
]]

local Types = require(script.LeaderboardTypes)
local Constants = require(script.Constants)

export type LeaderboardPeriod = Types.LeaderboardPeriod
export type LeaderboardEntry = Types.LeaderboardEntry
export type LeaderboardPage = Types.LeaderboardPage
export type LeaderboardOptions = Types.LeaderboardOptions
export type LeaderboardConfig = Types.LeaderboardConfig

return {
    Types = Types,
    Constants = Constants,
}

--!strict
--[[
    LeaderboardTypes
    Shared type definitions for the leaderboard system.
]]

export type LeaderboardPeriod = "Daily" | "Weekly" | "Monthly" | "AllTime"

export type LeaderboardEntry = {
    Rank: number,
    UserId: number,
    DisplayName: string,
    Username: string,
    Value: number,
}

export type LeaderboardPage = {
    ValueName: string,
    Period: LeaderboardPeriod,
    PageNumber: number,
    TotalPages: number,
    Entries: {LeaderboardEntry},
}

export type LeaderboardOptions = {
    -- Display name for the leaderboard (e.g., "Total XP", "Level")
    DisplayName: string?,
    -- Whether to track this leaderboard for all time periods
    TrackAllPeriods: boolean?,
    -- Custom formatter for values (e.g., adding "XP" suffix)
    ValueFormatter: ((value: number) -> string)?,
}

export type LeaderboardConfig = {
    ValueName: string,
    Part: BasePart,
    Period: LeaderboardPeriod?,
    Face: Enum.NormalId?,
    Options: LeaderboardOptions?,
}

return nil

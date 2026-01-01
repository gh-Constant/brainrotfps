--!strict
--[[
    Leaderboard Constants
    Shared constants for the leaderboard system.
]]

local Constants = {}

-- Available time periods
Constants.Periods = {
    Daily = "Daily",
    Weekly = "Weekly",
    Monthly = "Monthly",
    AllTime = "AllTime",
}

-- Pagination settings
Constants.ENTRIES_PER_PAGE = 25
Constants.MAX_ENTRIES = 1000
Constants.TOTAL_PAGES = math.ceil(Constants.MAX_ENTRIES / Constants.ENTRIES_PER_PAGE) -- 40 pages

-- Cache settings
Constants.CACHE_DURATION = 60 -- Seconds to cache leaderboard data
Constants.REFRESH_INTERVAL = 30 -- Seconds between auto-refresh on client

-- Size tiers for UI rendering
-- Each tier defines: maxRank, height, fontSize, showIcon
export type SizeTier = {
    MaxRank: number,
    Height: number,
    FontSize: number,
    Icon: string?,
    GlowColor: Color3?,
}

local sizeTiers: {SizeTier} = {
    { MaxRank = 1, Height = 140, FontSize = 48, Icon = "👑", GlowColor = Color3.fromRGB(255, 215, 0) },   -- Gold
    { MaxRank = 2, Height = 100, FontSize = 36, Icon = "🥈", GlowColor = Color3.fromRGB(192, 192, 192) }, -- Silver
    { MaxRank = 3, Height = 80, FontSize = 28, Icon = "🥉", GlowColor = Color3.fromRGB(205, 127, 50) },  -- Bronze
    { MaxRank = 100, Height = 50, FontSize = 20, Icon = nil, GlowColor = nil },                          -- Medium
    { MaxRank = 1000, Height = 35, FontSize = 14, Icon = nil, GlowColor = nil },                         -- Small
}
Constants.SizeTiers = sizeTiers

-- UI Colors
Constants.Colors = {
    Background = Color3.fromRGB(20, 20, 30),
    Header = Color3.fromRGB(30, 30, 45),
    Entry = Color3.fromRGB(35, 35, 50),
    EntryAlt = Color3.fromRGB(40, 40, 55),
    Text = Color3.fromRGB(255, 255, 255),
    TextSecondary = Color3.fromRGB(180, 180, 180),
    Accent = Color3.fromRGB(100, 150, 255),
    Gold = Color3.fromRGB(255, 215, 0),
    Silver = Color3.fromRGB(192, 192, 192),
    Bronze = Color3.fromRGB(205, 127, 50),
    TabActive = Color3.fromRGB(80, 120, 200),
    TabInactive = Color3.fromRGB(50, 50, 70),
    PageButton = Color3.fromRGB(60, 80, 120),
    PageButtonHover = Color3.fromRGB(80, 100, 150),
}

-- Gradient colors for top 3
Constants.Gradients = {
    Gold = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 50)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 230, 100)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 180, 0)),
    }),
    Silver = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(180, 180, 200)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(220, 220, 230)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(160, 160, 180)),
    }),
    Bronze = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(180, 100, 30)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(220, 150, 80)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(160, 90, 20)),
    }),
}

-- DataStore key prefix
Constants.DATASTORE_PREFIX = "Leaderboard"

return Constants

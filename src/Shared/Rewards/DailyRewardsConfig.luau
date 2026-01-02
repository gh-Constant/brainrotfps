--!strict
--[[
    DailyRewardsConfig
    Centralized configuration for daily login rewards.
    
    Edit this file to easily modify reward amounts and items.
    
    Structure:
    - Days 1-6: ONE reward only (coins OR xp)
    - Day 7: Multiple rewards (coins + XP + item)
]]

export type ItemReward = {
    TemplateId: string, -- Rarity/ItemType comes from inventory config
}

export type DayReward = {
    Day: number,
    Coins: number?,
    XP: number?,
    Items: {ItemReward}?, -- For Day 7 or special days
}

local DailyRewardsConfig = {}

-- Reward definitions for each day
-- Days 1-6: ONE reward only (coins OR xp)
-- Day 7: Special day with multiple rewards
DailyRewardsConfig.Rewards = ({
    {
        Day = 1,
        Items = {
            {
                TemplateId = "2_BOOST_XP_BOTTLE",
            },
        },
    },
    {
        Day = 2,
        XP = 75, -- Only XP
    },
    {
        Day = 3,
        Coins = 200, -- Only coins
    },
    {
        Day = 4,
        XP = 150, -- Only XP
    },
    {
        Day = 5,
        Coins = 400, -- Only coins
    },
    {
        Day = 6,
        XP = 250, -- Only XP
    },
    {
        Day = 7,
        -- Day 7 is special: can have multiple rewards!
        Coins = 1000,
        XP = 500,
        Items = {
            {
                TemplateId = "2_BOOST_XP_BOTTLE", -- Uses inventory config for styling
            },
        },
    },
} :: {DayReward})

-- How long between claims (in seconds)
-- 24 hours = 86400 seconds
DailyRewardsConfig.ClaimCooldown = 86400

-- Grace period: if player misses a day by this much, don't reset streak
-- 48 hours = 172800 seconds (gives a 1-day buffer)
DailyRewardsConfig.StreakResetTime = 172800

--[[
    Gets the reward config for a specific day.
    
    @param day - Day number (1-7)
    @return DayReward? - The reward config or nil if invalid
]]
function DailyRewardsConfig.GetReward(day: number): DayReward?
    if day < 1 or day > 7 then
        return nil
    end
    return DailyRewardsConfig.Rewards[day]
end

--[[
    Gets the total number of days in the reward cycle.
    
    @return number - Number of days (7)
]]
function DailyRewardsConfig.GetTotalDays(): number
    return #DailyRewardsConfig.Rewards
end

return DailyRewardsConfig

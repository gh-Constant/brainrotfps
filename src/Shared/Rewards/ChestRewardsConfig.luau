--!strict
--[[
    ChestRewardsConfig
    Configuration for chest rewards.
]]

local ChestRewardsConfig = {}

ChestRewardsConfig.Rewards = {
    Group = {
        Coins = 500,
        XP = 250,
        Items = { "2_BOOST_LUCK_BOTTLE" }, -- Example item
        Cooldown = 86400, -- Daily
    },
    Premium = {
        Coins = 1000,
        XP = 500,
        Items = { "2_BOOST_COIN_BOTTLE" },
        Cooldown = 86400, -- Daily
    },
    Discord = {
        Coins = 250,
        XP = 100,
        Items = {},
        Cooldown = 86400, -- Daily
    }
}

return ChestRewardsConfig

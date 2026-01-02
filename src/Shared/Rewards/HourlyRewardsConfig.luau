--!strict
--[[
    HourlyRewardsConfig
    Configuration for playtime-based rewards.
]]

export type HourlyReward = {
    Id: number,
    TimeRequired: number, -- Seconds of playtime required
    TemplateId: string,   -- Item template ID
}

local HourlyRewardsConfig = {}

-- Reward definitions
-- Requirements: 5, 10, 15, 30, 45, 60, 75, 90, 110 minutes
HourlyRewardsConfig.Rewards = {
    { Id = 1, TimeRequired = 300,  TemplateId = "2_BOOST_XP_BOTTLE" },
    { Id = 2, TimeRequired = 600,  TemplateId = "2_BOOST_COIN_BOTTLE" },
    { Id = 3, TimeRequired = 900,  TemplateId = "2_BOOST_XP_BOTTLE" },
    { Id = 4, TimeRequired = 1800, TemplateId = "2_BOOST_COIN_BOTTLE" },
    { Id = 5, TimeRequired = 2700, TemplateId = "2_BOOST_LUCK_BOTTLE" },
    { Id = 6, TimeRequired = 3600, TemplateId = "2_BOOST_DAMAGE_BOTTLE" },
    { Id = 7, TimeRequired = 4500, TemplateId = "2_BOOST_XP_BOTTLE" },
    { Id = 8, TimeRequired = 5400, TemplateId = "2_BOOST_COIN_BOTTLE" },
    { Id = 9, TimeRequired = 6600, TemplateId = "2_BOOST_LUCK_BOTTLE" },
}

--[[
    Gets the reward config by ID.
]]
function HourlyRewardsConfig.GetReward(id: number): HourlyReward?
    for _, reward in ipairs(HourlyRewardsConfig.Rewards) do
        if reward.Id == id then
            return reward
        end
    end
    return nil
end

return HourlyRewardsConfig

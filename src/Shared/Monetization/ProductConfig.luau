--!strict
--[[
    ProductConfig
    Central configuration for all monetization products.
]]

export type ProductType = "GamePass" | "DevProduct"

export type ProductDefinition = {
    Id: number,
    Name: string,
    Type: ProductType,
    Description: string?,
}

local ProductConfig = {
    GamePasses = {
        DoubleGold = {
            Id = 1642645563,
            Name = "2x Gold",
            Type = "GamePass",
            Description = "Earn double the gold from all sources!",
        } :: ProductDefinition,
        
        DoubleExperience = {
            Id = 1642681579,
            Name = "2x Experience",
            Type = "GamePass",
            Description = "Earn double the experience from all sources!",
        } :: ProductDefinition,

        DoubleDamage = {
            Id = 1642445917,
            Name = "2x Damage",
            Type = "GamePass",
            Description = "Deal double damage!",
        } :: ProductDefinition,
    },
    
    DevProducts = {
        -- Add DevProducts here in the future
    },
}

return ProductConfig

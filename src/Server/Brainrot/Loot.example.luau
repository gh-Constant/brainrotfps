    --[[
        Loot Configuration Module
        Place this ModuleScript named "Loot" inside your mob model (in Config.Brainrots... or wherever your mob template is).
        
        Format:
        return {
            Items = {
                { Name = "ItemTemplateName", Chance = Number },
            }
        }
        
        Chance Logic:
        "1 in X chance".
        Chance = 10  -> 1 in 10 chance (10%)
        Chance = 100 -> 1 in 100 chance (1%)
        Chance = 1   -> 1 in 1 chance (100% Guaranteed)
    ]]

    return {
        Items = {
            -- Example: 1 in 10 chance to drop "MatteoGun"
            {
                Name = "MatteoGun",
                Chance = 10,
            },
            
            -- Example: 1 in 50 chance to drop "RayGun"
            {
                Name = "RayGun",
                Chance = 50,
            },
            
            -- Example: Guaranteed drop (1 in 1)
            {
            Name = "HealthPotion",
            Chance = 1,
            }
        }
    }

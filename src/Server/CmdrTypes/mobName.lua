-- Mob name type for spawnmob command autocomplete
local ReplicatedStorage = game:GetService("ReplicatedStorage")

return function(registry)
    local function getMobNamesForZone(zoneName)
        local mobNames = {}
        local config = ReplicatedStorage:FindFirstChild("Config")
        if config then
            local brainrots = config:FindFirstChild("Brainrots")
            if brainrots then
                local zones = brainrots:FindFirstChild("Zones")
                if zones then
                    local zone = zones:FindFirstChild(zoneName)
                    if zone then
                        for _, mob in zone:GetChildren() do
                            if mob:IsA("Model") then
                                table.insert(mobNames, mob.Name)
                            end
                        end
                    end
                end
            end
        end
        table.sort(mobNames)
        return mobNames
    end
    
    local function getAllMobNames()
        local mobNames = {}
        local seenNames = {}
        local config = ReplicatedStorage:FindFirstChild("Config")
        if config then
            local brainrots = config:FindFirstChild("Brainrots")
            if brainrots then
                local zones = brainrots:FindFirstChild("Zones")
                if zones then
                    for _, zone in zones:GetChildren() do
                        if zone:IsA("Folder") then
                            for _, mob in zone:GetChildren() do
                                if mob:IsA("Model") and not seenNames[mob.Name] then
                                    seenNames[mob.Name] = true
                                    table.insert(mobNames, mob.Name)
                                end
                            end
                        end
                    end
                end
            end
        end
        table.sort(mobNames)
        return mobNames
    end
    
    registry:RegisterType("mobName", {
        DisplayName = "Mob Name",
        
        Transform = function(text)
            return text
        end,
        
        Validate = function(text)
            local mobs = getAllMobNames()
            for _, mobName in ipairs(mobs) do
                if mobName:lower() == text:lower() then
                    return true
                end
            end
            return false, "Invalid mob name."
        end,
        
        Autocomplete = function(text, executor, args)
            -- Try to get zone-specific mobs if zone was provided
            local mobs
            if args and args[1] then
                local zoneName = tostring(args[1])
                mobs = getMobNamesForZone(zoneName)
            end
            
            -- Fallback to all mobs if no zone or empty
            if not mobs or #mobs == 0 then
                mobs = getAllMobNames()
            end
            
            local results = {}
            for _, mobName in ipairs(mobs) do
                if mobName:lower():sub(1, #text) == text:lower() then
                    table.insert(results, mobName)
                end
            end
            return results
        end,
        
        Parse = function(text)
            -- Return the properly cased mob name
            local mobs = getAllMobNames()
            for _, mobName in ipairs(mobs) do
                if mobName:lower() == text:lower() then
                    return mobName
                end
            end
            return text
        end,
    })
end

-- Zone name type for spawnmob command autocomplete
local ReplicatedStorage = game:GetService("ReplicatedStorage")

return function(registry)
    -- Cache for zone names
    local zoneNames = nil
    
    local function getZoneNames()
        if zoneNames then return zoneNames end
        
        zoneNames = {}
        local config = ReplicatedStorage:FindFirstChild("Config")
        if config then
            local brainrots = config:FindFirstChild("Brainrots")
            if brainrots then
                local zones = brainrots:FindFirstChild("Zones")
                if zones then
                    for _, zone in zones:GetChildren() do
                        if zone:IsA("Folder") then
                            table.insert(zoneNames, zone.Name)
                        end
                    end
                end
            end
        end
        table.sort(zoneNames)
        return zoneNames
    end
    
    registry:RegisterType("zoneName", {
        DisplayName = "Zone Name",
        
        Transform = function(text)
            return text
        end,
        
        Validate = function(text)
            local zones = getZoneNames()
            for _, zoneName in ipairs(zones) do
                if zoneName:lower() == text:lower() then
                    return true
                end
            end
            return false, "Invalid zone. Valid: " .. table.concat(zones, ", ")
        end,
        
        Autocomplete = function(text)
            local results = {}
            local zones = getZoneNames()
            for _, zoneName in ipairs(zones) do
                if zoneName:lower():sub(1, #text) == text:lower() then
                    table.insert(results, zoneName)
                end
            end
            return results
        end,
        
        Parse = function(text)
            -- Return the properly cased zone name
            local zones = getZoneNames()
            for _, zoneName in ipairs(zones) do
                if zoneName:lower() == text:lower() then
                    return zoneName
                end
            end
            return text
        end,
    })
end

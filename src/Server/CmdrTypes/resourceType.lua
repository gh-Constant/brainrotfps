-- ResourceType for give command autocomplete
local resourceTypes = {
    "level",
    "gold",
    "xp",
    "credits",
}

return function(registry)
    registry:RegisterType("resourceType", {
        DisplayName = "Resource Type",
        
        Transform = function(text)
            return text:lower()
        end,
        
        Validate = function(text)
            for _, resType in ipairs(resourceTypes) do
                if resType == text:lower() then
                    return true
                end
            end
            return false, "Invalid type. Valid: " .. table.concat(resourceTypes, ", ")
        end,
        
        Autocomplete = function(text)
            local results = {}
            for _, resType in ipairs(resourceTypes) do
                if resType:sub(1, #text) == text:lower() then
                    table.insert(results, resType)
                end
            end
            return results
        end,
        
        Parse = function(text)
            return text:lower()
        end,
    })
end

-- ItemName type for Cmdr autocomplete
-- Reads available items from ReplicatedStorage/Config/Items

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function getItemNames()
    local names = {}
    local config = ReplicatedStorage:FindFirstChild("Config")
    if config then
        local items = config:FindFirstChild("Items")
        if items then
            for _, item in ipairs(items:GetChildren()) do
                if item:IsA("Configuration") then
                    table.insert(names, item.Name)
                end
            end
        end
    end
    return names
end

return function(registry)
    registry:RegisterType("itemName", {
        DisplayName = "Item Name",
        
        Transform = function(text)
            return text
        end,
        
        Validate = function(text)
            local itemNames = getItemNames()
            for _, name in ipairs(itemNames) do
                if name:lower() == text:lower() then
                    return true
                end
            end
            if #itemNames == 0 then
                return false, "No items found in Config/Items. Create some in Studio first!"
            end
            return false, "Item not found. Available: " .. table.concat(itemNames, ", ")
        end,
        
        Autocomplete = function(text)
            local results = {}
            local itemNames = getItemNames()
            for _, name in ipairs(itemNames) do
                if name:lower():sub(1, #text) == text:lower() then
                    table.insert(results, name)
                end
            end
            return results
        end,
        
        Parse = function(text)
            -- Return the correct case from config
            local itemNames = getItemNames()
            for _, name in ipairs(itemNames) do
                if name:lower() == text:lower() then
                    return name
                end
            end
            return text
        end,
    })
end

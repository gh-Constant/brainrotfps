-- ItemName type for Cmdr autocomplete
-- Reads available items from ReplicatedStorage/Config/Items (supports nested folders)
-- Optimized for large item counts with caching and result limiting

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Configuration
local MAX_AUTOCOMPLETE_RESULTS = 15  -- Maximum suggestions to show
local MAX_ERROR_ITEMS = 10           -- Maximum items to show in error message
local CACHE_DURATION = 1             -- How long to cache names (in seconds)

-- Cache for item names
local cachedNames: {string}? = nil
local lastCacheTime = 0

local function getItemNames(): {string}
    -- Return cached names if still valid
    local now = os.clock()
    if cachedNames and (now - lastCacheTime) < CACHE_DURATION then
        return cachedNames
    end
    
    local names = {}
    local config = ReplicatedStorage:FindFirstChild("Config")
    if config then
        local items = config:FindFirstChild("Items")
        if items then
            -- Recursive search for Configuration elements in nested folders
            local function searchRecursive(parent)
                for _, child in parent:GetChildren() do
                    if child:IsA("Configuration") then
                        table.insert(names, child.Name)
                    elseif child:IsA("Folder") then
                        searchRecursive(child)
                    end
                end
            end
            searchRecursive(items)
        end
    end
    
    -- Sort names alphabetically for consistent autocomplete
    table.sort(names)
    
    -- Update cache
    cachedNames = names
    lastCacheTime = now
    
    return names
end

-- Force refresh cache (call after adding new items)
local function refreshCache()
    cachedNames = nil
    lastCacheTime = 0
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
            
            -- Limit error message to prevent huge outputs
            if #itemNames > MAX_ERROR_ITEMS then
                local preview = {}
                for i = 1, MAX_ERROR_ITEMS do
                    table.insert(preview, itemNames[i])
                end
                return false, string.format(
                    "Item not found. %d items available. Showing first %d: %s...",
                    #itemNames,
                    MAX_ERROR_ITEMS,
                    table.concat(preview, ", ")
                )
            end
            
            return false, "Item not found. Available: " .. table.concat(itemNames, ", ")
        end,
        
        Autocomplete = function(text)
            local results = {}
            local itemNames = getItemNames()
            local textLower = text:lower()
            local textLen = #text
            
            for _, name in ipairs(itemNames) do
                if name:lower():sub(1, textLen) == textLower then
                    table.insert(results, name)
                    -- Stop early once we have enough results
                    if #results >= MAX_AUTOCOMPLETE_RESULTS then
                        break
                    end
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
    
    -- Expose refresh function on the registry for manual cache invalidation
    registry.ItemNameRefreshCache = refreshCache
end


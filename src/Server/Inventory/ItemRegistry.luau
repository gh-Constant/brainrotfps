--!strict
--[[
    ItemRegistry
    Global datastore for tracking item ownership history.
    
    Uses DataStoreService directly (not ProfileStore) since this is
    global data that needs to be accessed across all servers without session locking.
    
    Each item's OriginalId is used as the key, storing:
    - TemplateId: What type of item
    - OriginalOwner: First owner's UserId
    - CreatedAt: Unix timestamp
    - OwnerHistory: Array of {UserId, Timestamp}
]]

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Packages = Rojo:WaitForChild("Packages")

local Promise = require(Packages:WaitForChild("promise"))
local Signal = require(Packages:WaitForChild("signal"))

-- Logging helper (checks Config.Inventory.Logging attribute)
local function log(message: string)
	local config = ReplicatedStorage:FindFirstChild("Config")
	if config then
		local invConfig = config:FindFirstChild("Inventory")
		if invConfig and invConfig:GetAttribute("Logging") == true then
			print(message)
		end
	end
end

-- Types
export type OwnerHistoryEntry = {
    UserId: number,
    Timestamp: number,
}

export type ItemRegistryRecord = {
    TemplateId: string,
    OriginalOwner: number,
    CreatedAt: number,
    OwnerHistory: {OwnerHistoryEntry},
}

-- Constants
local STORE_NAME = "ItemRegistry_v1"
local MAX_RETRIES = 3
local RETRY_DELAY = 1

-- DataStore
local ItemRegistryStore = DataStoreService:GetDataStore(STORE_NAME)

-- Module
local ItemRegistry = {}

-- Events
ItemRegistry.OnItemRegistered = Signal.new()
ItemRegistry.OnOwnershipTransferred = Signal.new()

-- Cache for recent lookups (reduces datastore calls)
local cache: {[string]: ItemRegistryRecord} = {}
local _CACHE_EXPIRY = 300 -- 5 minutes

--------------------------------------------------------------------------------
-- Private Helpers
--------------------------------------------------------------------------------

--[[
    Wraps a DataStore call in pcall with retry logic.
]]
local function retryAsync<T>(operation: () -> T, operationName: string): T?
    for attempt = 1, MAX_RETRIES do
        local success, result = pcall(operation)
        if success then
            return result
        end
        
        warn(string.format("[ItemRegistry] %s failed (attempt %d/%d): %s", 
            operationName, attempt, MAX_RETRIES, tostring(result)))
        
        if attempt < MAX_RETRIES then
            task.wait(RETRY_DELAY * attempt) -- Exponential backoff
        end
    end
    
    return nil
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--[[
    Registers a new item in the global registry.
    
    @param originalId - The item's unique ID
    @param ownerId - The first owner's UserId
    @param templateId - What type of item this is
    @return Promise<boolean> - True if registered successfully
]]
function ItemRegistry.RegisterItem(originalId: string, ownerId: number, templateId: string)
    return Promise.new(function(resolve, reject)
        local record: ItemRegistryRecord = {
            TemplateId = templateId,
            OriginalOwner = ownerId,
            CreatedAt = os.time(),
            OwnerHistory = {
                { UserId = ownerId, Timestamp = os.time() }
            },
        }
        
        local success = retryAsync(function()
            ItemRegistryStore:SetAsync(originalId, record)
            return true
        end, "RegisterItem")
        
        if success then
            cache[originalId] = record
            ItemRegistry.OnItemRegistered:Fire(originalId, record)
            log(string.format("[ItemRegistry] Registered item %s for user %d (%s)", 
                originalId:sub(1, 8), ownerId, templateId))
            resolve(true)
        else
            reject("Failed to register item after retries")
        end
    end)
end

--[[
    Gets the registry record for an item.
    
    @param originalId - The item's unique ID
    @return Promise<ItemRegistryRecord?> - The record or nil if not found
]]
function ItemRegistry.GetRecord(originalId: string)
    return Promise.new(function(resolve, _reject)
        -- Check cache first
        if cache[originalId] then
            resolve(cache[originalId])
            return
        end
        
        local record = retryAsync(function()
            return ItemRegistryStore:GetAsync(originalId)
        end, "GetRecord")
        
        if record then
            cache[originalId] = record :: ItemRegistryRecord
        end
        
        resolve(record :: ItemRegistryRecord?)
    end)
end

--[[
    Transfers ownership by adding new owner to history.
    
    @param originalId - The item's unique ID
    @param newOwnerId - The new owner's UserId
    @return Promise<boolean>
]]
function ItemRegistry.TransferOwnership(originalId: string, newOwnerId: number)
    return Promise.new(function(resolve, reject)
        local success = retryAsync(function()
            ItemRegistryStore:UpdateAsync(originalId, function(oldData)
                if not oldData then
                    -- Item not in registry - this shouldn't happen for legit items
                    warn(string.format("[ItemRegistry] TransferOwnership: Item %s not found in registry!", originalId))
                    return nil
                end
                
                local record = oldData :: ItemRegistryRecord
                table.insert(record.OwnerHistory, {
                    UserId = newOwnerId,
                    Timestamp = os.time(),
                })
                
                return record
            end)
            return true
        end, "TransferOwnership")
        
        if success then
            -- Invalidate cache
            cache[originalId] = nil
            ItemRegistry.OnOwnershipTransferred:Fire(originalId, newOwnerId)
            log(string.format("[ItemRegistry] Transferred item %s to user %d", 
                originalId:sub(1, 8), newOwnerId))
            resolve(true)
        else
            reject("Failed to transfer ownership after retries")
        end
    end)
end

--[[
    Checks if a user is a valid owner (exists in history).
    
    @param originalId - The item's unique ID
    @param userId - The UserId to check
    @return Promise<boolean>
]]
function ItemRegistry.IsValidOwner(originalId: string, userId: number)
    return ItemRegistry.GetRecord(originalId):andThen(function(record)
        if not record then
            -- Not in registry = suspicious (could be duped)
            return false
        end
        
        for _, entry in ipairs(record.OwnerHistory) do
            if entry.UserId == userId then
                return true
            end
        end
        
        return false
    end)
end

--[[
    Formats a registry record for display (for /iteminfo command).
    
    @param record - The registry record
    @return string - Formatted string
]]
function ItemRegistry.FormatRecord(record: ItemRegistryRecord?): string
    if not record then
        return "Item not found in registry (SUSPICIOUS - possible dupe)"
    end
    
    local lines = {
        "=== Item Registry Record ===",
        string.format("Template: %s", record.TemplateId),
        string.format("Original Owner: %d", record.OriginalOwner),
        string.format("Created: %s", os.date("%Y-%m-%d %H:%M:%S", record.CreatedAt)),
        "Owner History:",
    }
    
    for i, entry in ipairs(record.OwnerHistory) do
        table.insert(lines, string.format("  %d. User %d @ %s", 
            i, entry.UserId, os.date("%Y-%m-%d %H:%M:%S", entry.Timestamp)))
    end
    
    return table.concat(lines, "\n")
end

--[[
    Clears the in-memory cache (for testing).
]]
function ItemRegistry.ClearCache()
    cache = {}
end

return ItemRegistry

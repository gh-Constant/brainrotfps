--!strict
--[[
    Inventory Store
    Centralized state management for client-side inventory data.
    
    This module holds the authoritative client copy of inventory state
    and provides signals for reactive updates.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Packages = Rojo:WaitForChild("Packages")
local Shared = Rojo:WaitForChild("Shared")

local Signal = require(Packages:WaitForChild("signal"))
local Inventory = require(Shared:WaitForChild("Inventory"))
local Logger = require(Shared:WaitForChild("Inventory"):WaitForChild("Logger"))

-- Types
type InventoryItem = Inventory.InventoryItem

-- State
local inventoryData: {InventoryItem} = {}
local toolbarSlots: {[number]: string} = {}
local dupedItems: {[string]: boolean} = {}
local itemIndex: {[string]: InventoryItem} = {} -- O(1) lookup

-- Module table
local InventoryStore = {}

-- Signals (created at module level for simple access)
InventoryStore.OnSync = Signal.new() -- Full sync received
InventoryStore.OnUpdate = Signal.new() -- Single item add/remove
InventoryStore.OnToolbarUpdate = Signal.new() -- Toolbar slots changed

--------------------------------------------------------------------------------
-- Private Functions
--------------------------------------------------------------------------------

--[[
    Rebuilds the item index for O(1) lookups.
]]
local function rebuildIndex()
    itemIndex = {}
    for _, item in inventoryData do
        itemIndex[item.Id] = item
    end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--[[
    Gets the current inventory data.
    @return {InventoryItem}
]]
function InventoryStore.GetInventory(): {InventoryItem}
    return inventoryData
end

--[[
    Gets the current toolbar slot assignments.
    @return {[number]: string} - Slot number to item ID mapping
]]
function InventoryStore.GetToolbarSlots(): {[number]: string}
    return toolbarSlots
end

--[[
    Gets the duped items tracking table.
    @return {[string]: boolean}
]]
function InventoryStore.GetDupedItems(): {[string]: boolean}
    return dupedItems
end

--[[
    Finds an item by its unique ID.
    Uses indexed lookup for O(1) performance.
    
    @param itemId - The item ID to find
    @return InventoryItem? - The item or nil
]]
function InventoryStore.FindById(itemId: string): InventoryItem?
    return itemIndex[itemId]
end

--[[
    Checks if an item ID is in a toolbar slot.
    @param itemId - The item ID to check
    @return number? - The slot number (1-9) or nil if not equipped
]]
function InventoryStore.GetEquippedSlot(itemId: string): number?
    for slot, id in pairs(toolbarSlots) do
        if id == itemId then
            return slot
        end
    end
    return nil
end

--[[
    Handles full inventory sync from server.
    Called when inventorySync packet is received.
    
    @param data - The sync data from server
]]
function InventoryStore.HandleSync(data: any)
    inventoryData = {}
    toolbarSlots = {}
    dupedItems = {}
    
    -- Unpack grouped items from server
    for _, group in data.groupedItems do
        local templateId = group.templateId
        local itemType = group.itemType
        local rarity = if group.rarity ~= "" then group.rarity else nil
        local metadata = group.metadata
        
        for _, instance in group.instances do
            local item: InventoryItem = {
                Id = instance.id,
                TemplateId = templateId,
                Type = itemType :: any, -- Allow string from network
                Rarity = rarity :: any, -- Allow string from network
                Metadata = metadata,
            }
            table.insert(inventoryData, item)
        end
    end
    
    for slot, itemId in pairs(data.toolbarSlots) do
        toolbarSlots[slot] = itemId
    end
    
    rebuildIndex()
    Logger.log("InventoryStore", "Synced " .. #inventoryData .. " items")
    InventoryStore.OnSync:Fire(inventoryData, toolbarSlots)
end

--[[
    Handles inventory update from server (add/remove single item).
    Called when inventoryUpdate packet is received.
    
    @param data - The update data from server
]]
function InventoryStore.HandleUpdate(data: any)
    local action = data.action
    local itemData = data.item
    
    Logger.log("InventoryStore", "Update: " .. action .. " item: " .. (itemData and itemData.templateId or "nil"))
    
    if action == "Add" then
        local item: InventoryItem = {
            Id = itemData.id,
            TemplateId = itemData.templateId,
            Type = itemData.itemType :: any,
            Rarity = if itemData.rarity ~= "" then itemData.rarity :: any else nil,
            Metadata = itemData.metadata,
        }
        table.insert(inventoryData, item)
        itemIndex[item.Id] = item
        
        -- Track duped status
        if itemData.maybeDuped then
            dupedItems[itemData.id] = true
        end
        
    elseif action == "Remove" then
        for i, item in inventoryData do
            if item.Id == itemData.id then
                table.remove(inventoryData, i)
                itemIndex[itemData.id] = nil
                dupedItems[itemData.id] = nil
                break
            end
        end
    end
    
    InventoryStore.OnUpdate:Fire(action, itemData)
end

--[[
    Handles batch inventory update from server.
    Called when inventoryBatchUpdate packet is received.
]]
function InventoryStore.HandleBatchUpdate(data: any)
    local action = data.action
    local items = data.items
    
    Logger.log("InventoryStore", string.format("Batch Update: %s %d items", action, #items))
    
    if action == "Add" then
        for _, itemData in ipairs(items) do
            local item: InventoryItem = {
                Id = itemData.id,
                TemplateId = itemData.templateId,
                Type = itemData.itemType :: any,
                Rarity = if itemData.rarity ~= "" then itemData.rarity :: any else nil,
                Metadata = itemData.metadata,
            }
            table.insert(inventoryData, item)
            itemIndex[item.Id] = item
            
            -- Track duped status
            if itemData.maybeDuped then
                dupedItems[itemData.id] = true
            end
        end
        
    elseif action == "Remove" then
        -- Create set for O(1) checking
        local removeIds = {}
        for _, itemData in ipairs(items) do
            removeIds[itemData.id] = true
            itemIndex[itemData.id] = nil
            dupedItems[itemData.id] = nil
        end
        
        -- Filter in place
        local w = 1
        for r = 1, #inventoryData do
            if not removeIds[inventoryData[r].Id] then
                if r ~= w then
                    inventoryData[w] = inventoryData[r]
                end
                w += 1
            end
        end
        
        -- Clear remaining slots
        for r = w, #inventoryData do
            inventoryData[r] = nil
        end
    end
    
    -- Fire OnUpdate with "Batch" to trigger refresh
    InventoryStore.OnUpdate:Fire(action, {BatchCount = #items}) 
    -- Note: UI needs to handle this "fake" itemData or just generic refresh
end

--[[
    Handles toolbar update from server.
    Called when toolbarUpdate packet is received.
    
    @param data - The toolbar data from server
]]
function InventoryStore.HandleToolbarUpdate(data: any)
    toolbarSlots = {}
    for slot, itemId in pairs(data.toolbarSlots) do
        toolbarSlots[slot] = itemId
    end
    
    Logger.log("InventoryStore", "Toolbar updated")
    InventoryStore.OnToolbarUpdate:Fire(toolbarSlots)
end

return InventoryStore

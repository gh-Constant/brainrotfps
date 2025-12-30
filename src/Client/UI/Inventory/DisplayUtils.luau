--!strict
--[[
    DisplayUtils - Inventory display helpers for filtering, grouping, and sorting items.
    Extracted from init.luau to reduce code duplication and improve maintainability.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")

local Inventory = require(Shared:WaitForChild("Inventory"))
local RarityConfig = require(Shared:WaitForChild("Rarity"):WaitForChild("RarityConfig"))
local ItemUtils = require(Shared:WaitForChild("Inventory"):WaitForChild("ItemUtils"))

-- Slot display data structure
export type ItemSlotData = {
    TemplateId: string,
    Type: string,
    Rarity: string?,
    Count: number,
    ItemIds: {string},
    IsEquipped: boolean,
    EquippedSlot: number?,
    MaybeDuped: boolean,
    Metadata: {[string]: any}?,
}

local DisplayUtils = {}

--[[
    Gets the item type for a template ID using cached lookup.
]]
function DisplayUtils.GetItemType(templateId: string): string?
    return ItemUtils.GetItemType(templateId)
end

--[[
    Counts mutations in metadata.
]]
function DisplayUtils.GetMutationCount(metadata: any): number
    if metadata and metadata.Mutations then
        local count = 0
        for _ in pairs(metadata.Mutations) do
            count = count + 1
        end
        return count
    end
    return 0
end

--[[
    Creates a lookup table of equipped item IDs to their slot numbers.
]]
function DisplayUtils.GetEquippedLookup(toolbarSlots: {[number]: string}): {[string]: number}
    local equippedItemIds: {[string]: number} = {}
    for slot, itemId in pairs(toolbarSlots) do
        if itemId and itemId ~= "" then
            equippedItemIds[itemId] = slot
        end
    end
    return equippedItemIds
end

--[[
    Filters items by type.
    @param items - List of inventory items (any type to avoid cross-module conflicts)
    @param filter - "Unfiltered" shows all, otherwise matches ItemType
]]
function DisplayUtils.FilterByType(items: {any}, filter: string): {any}
    if filter == "Unfiltered" then
        return items
    end
    
    local filtered = {}
    for _, item in items do
        local itemType = DisplayUtils.GetItemType(item.TemplateId)
        if itemType == filter then
            table.insert(filtered, item)
        end
    end
    return filtered
end

--[[
    Separates items into stackable and non-stackable groups.
]]
function DisplayUtils.SeparateStackable(items: {any}): ({any}, {any})
    local stackable = {}
    local nonStackable = {}
    
    for _, item in items do
        if Inventory.IsStackable(item.TemplateId) then
            table.insert(stackable, item)
        else
            table.insert(nonStackable, item)
        end
    end
    
    return stackable, nonStackable
end

--[[
    Converts a stack (grouped stackable items) to slot display data.
]]
function DisplayUtils.StackToSlotData(
    stack: any,
    equippedLookup: {[string]: number},
    dupedItems: {[string]: boolean}
): ItemSlotData
    -- Check if any item in this stack is equipped
    local equippedSlot: number? = nil
    for _, stackItem in ipairs(stack.Items) do
        if equippedLookup[stackItem.Id] then
            equippedSlot = equippedLookup[stackItem.Id]
            break
        end
    end
    
    -- Collect all item IDs and check for duped
    local itemIds: {string} = {}
    local anyDuped = false
    for _, stackItem in ipairs(stack.Items) do
        table.insert(itemIds, stackItem.Id)
        if dupedItems[stackItem.Id] then
            anyDuped = true
        end
    end
    
    return {
        TemplateId = stack.TemplateId,
        Type = stack.Type :: string,
        Rarity = if stack.Rarity then stack.Rarity :: string else nil,
        Count = stack.Count,
        ItemIds = itemIds,
        IsEquipped = equippedSlot ~= nil,
        EquippedSlot = equippedSlot,
        MaybeDuped = anyDuped,
        Metadata = stack.Items[1].Metadata,
    }
end

--[[
    Converts a single non-stackable item to slot display data.
]]
function DisplayUtils.ItemToSlotData(
    item: any,
    equippedLookup: {[string]: number},
    dupedItems: {[string]: boolean}
): ItemSlotData
    local equippedSlot = equippedLookup[item.Id]
    return {
        TemplateId = item.TemplateId,
        Type = item.Type :: string,
        Rarity = if item.Rarity then item.Rarity :: string else nil,
        Count = 1,
        ItemIds = {item.Id},
        IsEquipped = equippedSlot ~= nil,
        EquippedSlot = equippedSlot,
        MaybeDuped = dupedItems[item.Id] or false,
        Metadata = item.Metadata,
    }
end

--[[
    Sorts slot data list by:
    1. Equipped items first (by slot number)
    2. Higher rarity
    3. More mutations
]]
function DisplayUtils.SortSlotData(slotDataList: {ItemSlotData}): {ItemSlotData}
    -- Build rarity order lookup
    local rarityOrder: {[string]: number} = {}
    for index, rarityName in ipairs(RarityConfig.RarityOrder) do
        rarityOrder[rarityName] = index
    end
    
    table.sort(slotDataList, function(a, b)
        -- Equipped items first
        local equippedA = a.IsEquipped or false
        local equippedB = b.IsEquipped or false
        if equippedA ~= equippedB then
            return equippedA
        end
        
        -- Sort by equipped slot if both are equipped
        if equippedA and equippedB then
            local slotA = a.EquippedSlot or 999
            local slotB = b.EquippedSlot or 999
            if slotA ~= slotB then
                return slotA < slotB
            end
        end
        
        local rarityA = rarityOrder[a.Rarity or "Common"] or 0
        local rarityB = rarityOrder[b.Rarity or "Common"] or 0
        
        -- Higher rarity first
        if rarityA ~= rarityB then
            return rarityA > rarityB
        end
        
        -- More mutations first
        local mutationsA = DisplayUtils.GetMutationCount(a.Metadata)
        local mutationsB = DisplayUtils.GetMutationCount(b.Metadata)
        return mutationsA > mutationsB
    end)
    
    return slotDataList
end

--[[
    Main function: Converts inventory items to sorted, filtered slot display data.
    @param inventoryData - Raw inventory items (any type to avoid cross-module conflicts)
    @param toolbarSlots - Slot number to item ID mapping
    @param dupedItems - Set of potentially duplicated item IDs
    @param filter - Type filter ("Unfiltered", "Gun", "Grenade", "Potion")
    @return Sorted list of ItemSlotData for display
]]
function DisplayUtils.GetItemsForDisplay(
    inventoryData: {any},
    toolbarSlots: {[number]: string},
    dupedItems: {[string]: boolean},
    filter: string
): {ItemSlotData}
    -- Build equipped lookup
    local equippedLookup = DisplayUtils.GetEquippedLookup(toolbarSlots)
    
    -- Filter by type
    local filteredItems = DisplayUtils.FilterByType(inventoryData, filter)
    
    -- Separate stackable and non-stackable
    local stackableItems, nonStackableItems = DisplayUtils.SeparateStackable(filteredItems)
    
    -- Build slot data list
    local slotDataList: {ItemSlotData} = {}
    
    -- Group stackable items into stacks and convert to slot data
    local stacks = Inventory.GroupIntoStacks(stackableItems)
    for _, stack in ipairs(stacks) do
        table.insert(slotDataList, DisplayUtils.StackToSlotData(stack, equippedLookup, dupedItems))
    end
    
    -- Convert non-stackable items to slot data
    for _, item in nonStackableItems do
        table.insert(slotDataList, DisplayUtils.ItemToSlotData(item, equippedLookup, dupedItems))
    end
    
    -- Sort and return
    return DisplayUtils.SortSlotData(slotDataList)
end

return DisplayUtils

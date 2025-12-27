--!strict
--[[
    Item Utilities
    Helper functions for creating and manipulating inventory items.
    
    Uses:
    - Creating new items with unique IDs
    - Checking if items can be stacked
    - Grouping items into stacks for display
]]

local HttpService = game:GetService("HttpService")

local Types = require(script.Parent.Types)

type InventoryItem = Types.InventoryItem
type ItemType = Types.ItemType
type RarityType = Types.RarityType
type StackInfo = Types.StackInfo

local ItemUtils = {}

--[[
    Generates a unique ID for an item.
    Uses HttpService:GenerateGUID for uniqueness.
]]
function ItemUtils.GenerateId(): string
    return HttpService:GenerateGUID(false)
end

--[[
    Creates a new inventory item.
    
    @param templateId - The template reference (e.g., tool name)
    @param itemType - The type of item
    @param rarity - Optional rarity tier
    @param metadata - Optional extra data
    @return InventoryItem - The new item instance
]]
function ItemUtils.CreateItem(
    templateId: string,
    itemType: ItemType,
    rarity: RarityType?,
    metadata: {[string]: any}?
): InventoryItem
    return {
        Id = ItemUtils.GenerateId(),
        TemplateId = templateId,
        Type = itemType,
        Rarity = rarity,
        Metadata = metadata,
    }
end

--[[
    Checks if two items are stackable (same template, type, rarity, AND template is marked stackable).
    
    @param item1 - First item
    @param item2 - Second item
    @return boolean - True if items can be stacked together
]]
function ItemUtils.AreItemsStackable(item1: InventoryItem, item2: InventoryItem): boolean
    return ItemUtils.IsStackable(item1.TemplateId)
        and item1.TemplateId == item2.TemplateId
        and item1.Type == item2.Type
        and item1.Rarity == item2.Rarity
end

--[[
    Recursively finds an item configuration by templateId in Config.Items.
    Searches through all folders and returns the first Configuration element with matching name.
    
    @param templateId - The template name to find
    @return Configuration? - The item configuration or nil
]]
function ItemUtils.FindItemConfig(templateId: string): Configuration?
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local config = ReplicatedStorage:FindFirstChild("Config")
    if not config then return nil end
    
    local items = config:FindFirstChild("Items")
    if not items then return nil end
    
    -- Recursive search function
    local function searchRecursive(parent: Instance): Configuration?
        for _, child in parent:GetChildren() do
            if child:IsA("Configuration") and child.Name == templateId then
                return child
            elseif child:IsA("Folder") then
                -- Recursively search folders
                local found = searchRecursive(child)
                if found then return found end
            end
        end
        return nil
    end
    
    return searchRecursive(items)
end

--[[
    Checks if an item template is marked as stackable.
    Looks up Config/Items for the template's Stackable attribute (supports nested folders).
    
    @param templateId - The template to check
    @return boolean - True if stackable
]]
function ItemUtils.IsStackable(templateId: string): boolean
    local itemConfig = ItemUtils.FindItemConfig(templateId)
    if not itemConfig then return false end
    
    local stackable = itemConfig:GetAttribute("Stackable")
    return stackable == true
end

--[[
    Generates a stack key for grouping items.
    Format: "TemplateId|Type|Rarity"
]]
function ItemUtils.GetStackKey(item: InventoryItem): string
    local rarityStr = item.Rarity or "None"
    return string.format("%s|%s|%s", item.TemplateId, item.Type, rarityStr)
end

--[[
    Groups items into stacks for display.
    Items with same TemplateId + Type + Rarity are grouped together.
    
    @param items - Array of inventory items
    @return {StackInfo} - Array of stack info for display
]]
function ItemUtils.GroupIntoStacks(items: {InventoryItem}): {StackInfo}
    local stackMap: {[string]: StackInfo} = {}
    local stackOrder: {string} = {} -- Preserve order of first occurrence
    
    for _, item in ipairs(items) do
        local key = ItemUtils.GetStackKey(item)
        
        if not stackMap[key] then
            stackMap[key] = {
                TemplateId = item.TemplateId,
                Type = item.Type,
                Rarity = item.Rarity,
                Count = 0,
                Items = {},
            }
            table.insert(stackOrder, key)
        end
        
        local stack = stackMap[key]
        stack.Count = stack.Count + 1
        table.insert(stack.Items, item)
    end
    
    -- Convert to ordered array
    local stacks: {StackInfo} = {}
    for _, key in ipairs(stackOrder) do
        table.insert(stacks, stackMap[key])
    end
    
    return stacks
end

--[[
    Counts items matching a template and optional rarity.
    
    @param items - Array of inventory items
    @param templateId - Template to match
    @param rarity - Optional rarity to match
    @return number - Count of matching items
]]
function ItemUtils.CountItems(
    items: {InventoryItem},
    templateId: string,
    rarity: RarityType?
): number
    local count = 0
    for _, item in ipairs(items) do
        if item.TemplateId == templateId then
            if rarity == nil or item.Rarity == rarity then
                count = count + 1
            end
        end
    end
    return count
end

--[[
    Finds an item by its unique ID.
    
    @param items - Array of inventory items
    @param itemId - The item ID to find
    @return InventoryItem? - The item or nil
]]
function ItemUtils.FindById(items: {InventoryItem}, itemId: string): InventoryItem?
    for _, item in ipairs(items) do
        if item.Id == itemId then
            return item
        end
    end
    return nil
end

--[[
    Finds the index of an item by its unique ID.
    
    @param items - Array of inventory items
    @param itemId - The item ID to find
    @return number? - The index or nil
]]
function ItemUtils.FindIndexById(items: {InventoryItem}, itemId: string): number?
    for i, item in ipairs(items) do
        if item.Id == itemId then
            return i
        end
    end
    return nil
end

return ItemUtils

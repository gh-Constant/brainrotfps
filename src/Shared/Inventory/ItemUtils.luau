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
    Also checks if Mutations match.
    
    @param item1 - First item
    @param item2 - Second item
    @return boolean - True if items can be stacked together
]]
function ItemUtils.AreItemsStackable(item1: InventoryItem, item2: InventoryItem): boolean
    if not (ItemUtils.IsStackable(item1.TemplateId)
        and item1.TemplateId == item2.TemplateId
        and item1.Type == item2.Type
        and item1.Rarity == item2.Rarity) then
        return false
    end
    
    -- Check mutations deep equality
    local mutations1 = item1.Metadata and item1.Metadata.Mutations
    local mutations2 = item2.Metadata and item2.Metadata.Mutations
    
    if mutations1 == mutations2 then return true end -- both nil or same ref
    if not mutations1 or not mutations2 then return false end -- one is nil
    
    -- Compare Mutation counts
    for k, v in pairs(mutations1) do
        if mutations2[k] ~= v then return false end
    end
    for k, v in pairs(mutations2) do
        if mutations1[k] ~= v then return false end
    end
    
    return true
end

--[[
    Recursively finds an item configuration by templateId in Config.Items.
    Searches through all folders and returns the first Configuration element with matching name.
    Results are cached for O(1) repeated lookups.
    
    @param templateId - The template name to find
    @return Configuration? - The item configuration or nil
]]
-- Cache for item configs
local itemConfigCache: {[string]: Configuration} = {}
local isCacheInitialized = false

--[[
    Builds the item config cache by recursively iterating through Config.Items.
    Called once on first lookup.
]]

--[[
    Builds the item config cache by recursively iterating through Config.Items.
    Called once on first lookup, or can be called explicitly to preload.
]]
function ItemUtils.PreloadCache()
    buildItemConfigCache()
end

--[[
    Builds the item config cache by recursively iterating through Config.Items.
    Called once on first lookup.
]]
function buildItemConfigCache()
    if isCacheInitialized then return end
    
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local config = ReplicatedStorage:FindFirstChild("Config")
    if not config then return end
    
    local items = config:FindFirstChild("Items")
    if not items then return end
    
    local function recurse(parent: Instance)
        for _, child in parent:GetChildren() do
            if child:IsA("Configuration") then
                -- Store by name (TemplateId)
                itemConfigCache[child.Name] = child
            elseif child:IsA("Folder") then
                recurse(child)
            end
        end
    end
    
    recurse(items)
    isCacheInitialized = true
    
    local count = 0
    for _ in pairs(itemConfigCache) do count += 1 end
    print("[ItemUtils] Item cache preloaded with " .. tostring(count) .. " items")
end

function ItemUtils.FindItemConfig(templateId: string): Configuration?
    -- Initialize cache on first use
    if not isCacheInitialized then
        buildItemConfigCache()
    end
    
    return itemConfigCache[templateId]
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
    Format: "TemplateId|Type|Rarity|MutationHash"
]]
function ItemUtils.GetStackKey(item: InventoryItem): string
    local rarityStr = item.Rarity or "None"
    
    -- Generate simple hash for mutations
    local mutationHash = ""
    if item.Metadata and item.Metadata.Mutations then
        local keys = {}
        for k in pairs(item.Metadata.Mutations) do
            table.insert(keys, k)
        end
        table.sort(keys)
        
        for _, k in ipairs(keys) do
            mutationHash = mutationHash .. k .. ":" .. tostring(item.Metadata.Mutations[k]) .. ";"
        end
    end
    
    return string.format("%s|%s|%s|%s", item.TemplateId, item.Type, rarityStr, mutationHash)
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

--[[
    Finds all items that belong to the same stack as the reference item.
    
    @param items - Array of inventory items
    @param referenceItem - The item to match against
    @return {InventoryItem} - List of matching items
]]
function ItemUtils.GetStackItems(items: {InventoryItem}, referenceItem: InventoryItem): {InventoryItem}
    local stack = {}
    for _, item in ipairs(items) do
        if ItemUtils.AreItemsStackable(referenceItem, item) then
            table.insert(stack, item)
        end
    end
    return stack
end

--------------------------------------------------------------------------------
-- UI Helper Functions (extracted from client scripts)
--------------------------------------------------------------------------------

--[[
    Gets the display name for an item.
    Checks Config for "DisplayName" attribute, falls back to templateId.
    
    @param templateId - The template ID
    @return string - The display name
]]
function ItemUtils.GetDisplayName(templateId: string): string
    local itemConfig = ItemUtils.FindItemConfig(templateId)
    if itemConfig then
        local displayName = itemConfig:GetAttribute("DisplayName") :: string?
        if displayName and displayName ~= "" then
            return displayName
        end
    end
    return templateId
end

--[[
    Gets the image/texture ID for an item.
    Priority: Config "Image" attribute > Tool.TextureId
    
    @param templateId - The template ID
    @return string - The image asset ID (with rbxassetid:// prefix)
]]
function ItemUtils.GetItemImage(templateId: string): string
    local itemConfig = ItemUtils.FindItemConfig(templateId)
    if not itemConfig then return "" end
    
    -- Check Image attribute first
    local image = itemConfig:GetAttribute("Image") :: string?
    if image and image ~= "" then
        if not string.find(image, "://") then
            image = "rbxassetid://" .. image
        end
        return image
    end
    
    -- Fallback to Tool's TextureId
    local tool = itemConfig:FindFirstChildWhichIsA("Tool") :: Tool?
    if tool then
        local textureId = tool.TextureId
        if textureId and textureId ~= "" then
            if not string.find(textureId, "://") then
                textureId = "rbxassetid://" .. textureId
            end
            return textureId
        end
    end
    
    return ""
end

--[[
    Gets the ItemType attribute from an item's configuration.
    
    @param templateId - The template ID
    @return string? - The item type ("Gun", "Grenade", "Potion", etc.) or nil
]]
function ItemUtils.GetItemType(templateId: string): string?
    local itemConfig = ItemUtils.FindItemConfig(templateId)
    if itemConfig then
        return itemConfig:GetAttribute("ItemType") :: string?
    end
    return nil
end

--[[
    Gets the Tool instance from inside a Configuration.
    
    @param templateId - The template ID
    @return Tool? - The tool or nil
]]
function ItemUtils.GetTool(templateId: string): Tool?
    local itemConfig = ItemUtils.FindItemConfig(templateId)
    if itemConfig then
        return itemConfig:FindFirstChildWhichIsA("Tool") :: Tool?
    end
    return nil
end

--[[
    Gets the custom color style from Config, or derives it from rarity.
    
    @param templateId - The template ID
    @param rarity - Optional rarity to fall back to
    @return string? - The style name for ColorSystem
]]
function ItemUtils.GetBackgroundStyle(templateId: string, rarity: string?): string?
    local itemConfig = ItemUtils.FindItemConfig(templateId)
    if itemConfig then
        local customColor = itemConfig:GetAttribute("CustomColor") :: string?
        if customColor and customColor ~= "" then
            return customColor
        end
    end
    
    -- Fall back to rarity-based style via RarityConfig
    -- Note: Caller should use RarityConfig.GetBackgroundStyle(rarity) if this returns nil
    return nil
end

--[[
    Gets the custom text color style from Config.
    
    @param templateId - The template ID
    @return string? - The style name for ColorSystem text, or nil
]]
function ItemUtils.GetTextStyle(templateId: string): string?
    local itemConfig = ItemUtils.FindItemConfig(templateId)
    if itemConfig then
        return itemConfig:GetAttribute("CustomTextColor") :: string?
    end
    return nil
end

--[[
    Finds the physical Tool instance for a given item ID.
    Checks Backpack and Character.
    
    @param player - The player to search
    @param itemId - The inventory item ID to match
    @return Tool? - The found tool or nil
]]
function ItemUtils.FindToolInstance(player: Player, itemId: string): Tool?
    local backpack = player:FindFirstChild("Backpack")
    local character = player.Character
    
    -- Check Backpack
    if backpack then
        for _, t in backpack:GetChildren() do
            if t:IsA("Tool") and t:GetAttribute("InventoryItemId") == itemId then
                return t
            end
        end
    end
    
    -- Check Character
    if character then
        for _, t in character:GetChildren() do
            if t:IsA("Tool") and t:GetAttribute("InventoryItemId") == itemId then
                return t
            end
        end
    end
    
    return nil
end

return ItemUtils


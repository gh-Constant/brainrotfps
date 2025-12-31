--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")

local Inventory = require(Shared:WaitForChild("Inventory"))
local Events = require(script.Parent.Events)
local Network = require(script.Parent.Network)
local ToolbarUtils = require(script.Parent.ToolbarUtils)
local ItemRegistry = require(script.Parent.Parent:WaitForChild("Inventory"):WaitForChild("ItemRegistry")) -- Assuming referencing the init's child, but init is script.Parent?
-- Actually ItemRegistry needs to be required from where it was. 
-- In init.luau: local ItemRegistry = require(script.ItemRegistry)
-- So here: script.Parent.ItemRegistry
local ItemRegistryModule = script.Parent:WaitForChild("ItemRegistry")
local ItemRegistry = require(ItemRegistryModule)

type InventoryItem = Inventory.InventoryItem
type ItemType = Inventory.ItemType
type RarityType = Inventory.RarityType

local Actions = {}

-- Helper log function
local function log(message: string)
    local config = ReplicatedStorage:FindFirstChild("Config")
    if config then
        local invConfig = config:FindFirstChild("Inventory")
        if invConfig and invConfig:GetAttribute("Logging") == true then
            print(message)
        end
    end
end

--[[
    Validates that a templateId exists in Config/Items.
]]
local function isValidTemplateId(templateId: string): boolean
    return Inventory.ItemUtils.FindItemConfig(templateId) ~= nil
end

--[[
    Adds an item to a player's inventory.
]]
--[[
    Adds an item to a player's inventory.
]]
function Actions.AddItem(
    player: Player,
    inventory: any,
    index: any?, -- Inventory index cache
    templateId: string,
    itemType: ItemType,
    rarity: RarityType?,
    metadata: {[string]: any}?,
    dupedItems: {[string]: boolean}
): InventoryItem?
    if not inventory then
        warn("[Actions] No inventory for player:", player.Name)
        return nil
    end
    
    -- Security: Check inventory size limit
    local maxSize = inventory.MaxSize or 100000000000
    if #inventory.Items >= maxSize then
        warn(string.format("[Actions] Inventory full for %s (%d/%d items)", player.Name, #inventory.Items, maxSize))
        return nil
    end
    
    -- Security: Validate templateId exists (for Tools)
    if itemType == "Tool" and not isValidTemplateId(templateId) then
        warn(string.format("[Actions] Invalid templateId '%s' for %s", templateId, player.Name))
        return nil
    end
    
    local item = Inventory.CreateItem(templateId, itemType, rarity, metadata)
    table.insert(inventory.Items, item)
    
    -- Update Index
    if index then
        index.ById[item.Id] = item
        if not index.ByTemplate[templateId] then
            index.ByTemplate[templateId] = {}
        end
        table.insert(index.ByTemplate[templateId], item)
    end
    
    -- Register in global ItemRegistry
    task.spawn(function()
        ItemRegistry.RegisterItem(item.Id, player.UserId, templateId):catch(function(err)
            warn("[Actions] Failed to register item:", err)
        end)
    end)
    
    -- Fire events
    Events.OnItemAdded:Fire(player, item)
    Events.OnInventoryChanged:Fire(player, "Add", item)
    
    -- Sync to client
    Network.SendInventoryUpdate(player, "Add", item, dupedItems)
    
    log(string.format("[Actions] Added %s (%s) to %s", templateId, itemType, player.Name))
    return item
end

--[[
    Adds multiple items to a player's inventory in a batch.
    Optimized to send a single network packet.
]]
function Actions.AddItems(
    player: Player,
    inventory: any,
    index: any?,
    templateId: string,
    itemType: ItemType,
    count: number,
    rarity: RarityType?,
    metadata: {[string]: any}?,
    dupedItems: {[string]: boolean}
): {InventoryItem}
    if not inventory then return {} end
    if count <= 0 then return {} end
    
    -- Security: Validate templateId exists (once)
    if itemType == "Tool" and not isValidTemplateId(templateId) then
        warn(string.format("[Actions] Invalid templateId '%s' for %s", templateId, player.Name))
        return {}
    end
    
    local addedItems = {}
    local maxSize = inventory.MaxSize or 100000000000
    
    -- Bulk create and insert
    for i = 1, count do
        if #inventory.Items >= maxSize then
             warn(string.format("[Actions] Inventory full for %s during batch add", player.Name))
             break
        end
        
        local item = Inventory.CreateItem(templateId, itemType, rarity, metadata)
        table.insert(inventory.Items, item)
        table.insert(addedItems, item)
        
        -- Update Index
        if index then
            index.ById[item.Id] = item
            if not index.ByTemplate[templateId] then
                index.ByTemplate[templateId] = {}
            end
            table.insert(index.ByTemplate[templateId], item)
        end
        
        -- Register in global ItemRegistry (spawn separately to not block)
        task.spawn(function()
            ItemRegistry.RegisterItem(item.Id, player.UserId, templateId):catch(function(err)
                warn("[Actions] Failed to register item:", err)
            end)
        end)
        
        -- Fire individual events (optional, but good for compatibility)
        Events.OnItemAdded:Fire(player, item)
        Events.OnInventoryChanged:Fire(player, "Add", item)
    end
    
    if #addedItems > 0 then
        -- Sync to client (BATCHED)
        Network.SendBatchInventoryUpdate(player, "Add", addedItems, dupedItems)
        
        log(string.format("[Actions] Batch added %d x %s (%s) to %s", #addedItems, templateId, itemType, player.Name))
    end
    
    return addedItems
end

--[[
    Removes an item from a player's inventory by ID.
    Handles toolbar desync if the item was equipped.
]]
function Actions.RemoveItem(
    player: Player,
    inventory: any,
    index: any?, -- Inventory index cache
    itemId: string,
    dupedItems: {[string]: boolean},
    removeFromToolbarCallback: (Player, number) -> boolean -- Callback to avoid circular dependency with ToolbarActions
): boolean
    if not inventory then return false end
    
    local item: InventoryItem?
    local arrayIndex: number?
    
    -- Optimized lookup
    if index and index.ById[itemId] then
        item = index.ById[itemId]
        arrayIndex = table.find(inventory.Items, item)
    else
        -- Fallback linear search
        arrayIndex = Inventory.ItemUtils.FindIndexById(inventory.Items, itemId)
        if arrayIndex then
            item = inventory.Items[arrayIndex]
        end
    end
    
    if not item or not arrayIndex then return false end
    
    local isStackable = Inventory.IsStackable(item.TemplateId)
    
    table.remove(inventory.Items, arrayIndex)
    
    -- Update Index
    if index then
        index.ById[itemId] = nil
        local tList = index.ByTemplate[item.TemplateId]
        if tList then
            local tIndex = table.find(tList, item)
            if tIndex then
                table.remove(tList, tIndex)
            end
        end
    end
    
    -- Handle toolbar update for stackable items
    if isStackable then
        local foundSlot: number? = nil
        
        -- Get remaining items in stack
        -- Optimized: Use index if available to narrow search
        local stackItems = {}
        if index and index.ByTemplate[item.TemplateId] then
             -- Filter from cache (much smaller list)
             for _, candidate in ipairs(index.ByTemplate[item.TemplateId]) do
                 if Inventory.ItemUtils.AreItemsStackable(item, candidate) then
                     table.insert(stackItems, candidate)
                 end
             end
        else
            -- Original scan
            stackItems = Inventory.ItemUtils.GetStackItems(inventory.Items, item)
        end
        
        local remainingCount = #stackItems
        local newReferenceItem = stackItems[1]
        
        -- Check toolbar
        -- Optimization: Quick check if we have any active toolbar slots
        local hasToolbarSlots = false
        for _, _ in pairs(inventory.ToolbarSlots) do hasToolbarSlots = true; break end
        
        if hasToolbarSlots then
            for slot, equippedId in pairs(inventory.ToolbarSlots) do
                if equippedId then
                    -- Optimization: Look up equip via index if possible
                    local equippedItem
                    if index and index.ById[equippedId] then
                        equippedItem = index.ById[equippedId]
                    else
                        equippedItem = Inventory.FindById(inventory.Items, equippedId)
                    end
                    
                    if equippedItem and Inventory.ItemUtils.AreItemsStackable(equippedItem, item) then
                        foundSlot = slot
                        break
                    elseif equippedId == itemId then
                        -- Should catch if the specific ID was there (though inconsistent if stackable)
                        foundSlot = slot
                        break
                    end
                end
            end
        end
        
        if foundSlot then
            if remainingCount > 0 then
                if newReferenceItem then
                    inventory.ToolbarSlots[foundSlot] = newReferenceItem.Id
                end
                
                -- Update stack count on tool
                local backpack = player:FindFirstChild("Backpack")
                local character = player.Character
                
                local function updateToolStackCount(container: Instance)
                    for _, tool in container:GetChildren() do
                        if tool:IsA("Tool") and tool:GetAttribute("StackTemplateId") == item.TemplateId then
                            tool:SetAttribute("StackCount", remainingCount)
                            if newReferenceItem then
                                tool:SetAttribute("InventoryItemId", newReferenceItem.Id)
                            end
                            return true
                        end
                    end
                    return false
                end
                
                if backpack then updateToolStackCount(backpack) end
                if character and not updateToolStackCount(character) then end
            else
                -- Remove from toolbar
                if removeFromToolbarCallback then
                    removeFromToolbarCallback(player, foundSlot)
                end
            end
        end
    else
        -- Non-stackable
        for slot, equippedId in pairs(inventory.ToolbarSlots) do
            if equippedId == itemId then
                if removeFromToolbarCallback then
                    removeFromToolbarCallback(player, slot)
                end
                break
            end
        end
    end
    
    -- Fire events
    Events.OnItemRemoved:Fire(player, item)
    Events.OnInventoryChanged:Fire(player, "Remove", item)
    
    -- Sync to client
    Network.SendInventoryUpdate(player, "Remove", item, dupedItems)
    Network.SendToolbarUpdate(player, inventory.ToolbarSlots)
    
    return true
end

return Actions

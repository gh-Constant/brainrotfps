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
function Actions.AddItem(
    player: Player,
    inventory: any,
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
    local maxSize = inventory.MaxSize or 50
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
    Removes an item from a player's inventory by ID.
    Handles toolbar desync if the item was equipped.
]]
function Actions.RemoveItem(
    player: Player,
    inventory: any,
    itemId: string,
    dupedItems: {[string]: boolean},
    removeFromToolbarCallback: (Player, number) -> boolean -- Callback to avoid circular dependency with ToolbarActions
): boolean
    if not inventory then return false end
    
    local index = Inventory.ItemUtils.FindIndexById(inventory.Items, itemId)
    if not index then return false end
    
    local item = inventory.Items[index]
    local isStackable = Inventory.IsStackable(item.TemplateId)
    
    table.remove(inventory.Items, index)
    
    -- Handle toolbar update for stackable items
    if isStackable then
        local foundSlot: number? = nil
        local remainingCount = 0
        
        -- Count remaining items
        for _, invItem in ipairs(inventory.Items) do
            if invItem.TemplateId == item.TemplateId 
                and invItem.Type == item.Type 
                and invItem.Rarity == item.Rarity then
                remainingCount = remainingCount + 1
            end
        end
        
        -- Check toolbar
        for slot, equippedId in pairs(inventory.ToolbarSlots) do
            if equippedId then
                local equippedItem = Inventory.FindById(inventory.Items, equippedId)
                if equippedItem and equippedItem.TemplateId == item.TemplateId 
                    and equippedItem.Type == item.Type 
                    and equippedItem.Rarity == item.Rarity then
                    foundSlot = slot
                    break
                elseif equippedId == itemId then
                    foundSlot = slot
                    break
                end
            end
        end
        
        if foundSlot then
            if remainingCount > 0 then
                -- Update reference
                local newReferenceItem: InventoryItem? = nil
                for _, invItem in ipairs(inventory.Items) do
                    if invItem.TemplateId == item.TemplateId 
                        and invItem.Type == item.Type 
                        and invItem.Rarity == item.Rarity then
                        newReferenceItem = invItem
                        break
                    end
                end
                
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

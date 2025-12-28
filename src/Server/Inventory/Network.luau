--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")

local Packets = require(Shared:WaitForChild("Packets"))
local Inventory = require(Shared:WaitForChild("Inventory"))

type InventoryItem = Inventory.InventoryItem

local Network = {}

--[[
    Syncs the full inventory to a client.
]]
function Network.SyncInventory(player: Player, inventory: any)
    if not inventory then return end
    
    -- Optimize: Group items to reduce network payload
    -- Uses Inventory.GroupIntoStacks which puts same TemplateId+Type+Rarity together
    
    local stacks = Inventory.GroupIntoStacks(inventory.Items)
    local groupedData = {}
    
    for _, stack in ipairs(stacks) do
        local instances = {}
        for _, item in ipairs(stack.Items) do
            table.insert(instances, {
                id = item.Id,
            })
        end
        
        table.insert(groupedData, {
            templateId = stack.TemplateId,
            itemType = stack.Type,
            rarity = stack.Rarity or "",
            metadata = stack.Items[1].Metadata, -- Use metadata from first item
            instances = instances,
        })
    end
    
    Packets.inventorySync.sendTo({
        groupedItems = groupedData,
        toolbarSlots = inventory.ToolbarSlots,
    }, player)
end

--[[
    Sends a lightweight toolbar update to a client.
]]
function Network.SendToolbarUpdate(player: Player, toolbarSlots: any)
    Packets.toolbarUpdate.sendTo({
        toolbarSlots = toolbarSlots,
    }, player)
end

--[[
    Sends an inventory update (add/remove) to a client.
]]
function Network.SendInventoryUpdate(player: Player, action: string, item: InventoryItem, dupedItems: {[string]: boolean})
    Packets.inventoryUpdate.sendTo({
        action = action,
        item = {
            id = item.Id,
            templateId = item.TemplateId,
            itemType = item.Type,
            rarity = item.Rarity or "",
            maybeDuped = dupedItems[item.Id] or false,
            metadata = item.Metadata,
        },
    }, player)
end

return Network

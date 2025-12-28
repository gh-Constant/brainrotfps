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
function Network.SyncInventory(player: Player, inventory: any, dupedItems: {[string]: boolean})
    if not inventory then return end
    
    -- Convert to packet format
    local itemsData = {}
    for _, item in ipairs(inventory.Items) do
        table.insert(itemsData, {
            id = item.Id,
            templateId = item.TemplateId,
            itemType = item.Type,
            rarity = item.Rarity or "",
            maybeDuped = dupedItems[item.Id] or false,
            metadata = item.Metadata,
        })
    end
    
    Packets.inventorySync.sendTo({
        items = itemsData,
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

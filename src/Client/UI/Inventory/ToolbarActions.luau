--!strict
--[[
    Toolbar Actions
    Centralized server communication for toolbar operations.
    
    Eliminates duplicate Packets.inventoryAction.send() calls
    from init.luau and InfoPanel.luau.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")

local Packets = require(Shared:WaitForChild("Packets"))
local Constants = require(Shared:WaitForChild("Inventory"):WaitForChild("Constants"))
local Logger = require(Shared:WaitForChild("Inventory"):WaitForChild("Logger"))

local ToolbarActions = {}

--[[
    Assigns an item to a toolbar slot.
    
    @param itemId - The inventory item ID
    @param slot - The toolbar slot number (1-9)
]]
function ToolbarActions.AssignToToolbar(itemId: string, slot: number)
    Logger.log("ToolbarActions", "Assigning item " .. itemId .. " to slot " .. slot)
    Packets.inventoryAction.send({
        action = Constants.ActionType.AssignToolbar,
        itemId = itemId,
        slot = slot,
    })
end

--[[
    Removes an item from a toolbar slot.
    
    @param slot - The toolbar slot number (1-9)
]]
function ToolbarActions.RemoveFromToolbar(slot: number)
    Logger.log("ToolbarActions", "Removing item from slot " .. slot)
    Packets.inventoryAction.send({
        action = Constants.ActionType.RemoveToolbar,
        itemId = "",
        slot = slot,
    })
end

--[[
    Swaps items between two toolbar slots.
    
    @param slot1 - First slot number
    @param slot2 - Second slot number
]]
function ToolbarActions.SwapToolbarSlots(slot1: number, slot2: number)
    Logger.log("ToolbarActions", "Swapping slots " .. slot1 .. " <-> " .. slot2)
    Packets.inventoryAction.send({
        action = Constants.ActionType.SwapToolbar,
        itemId = "",
        slot = slot1,
        slot2 = slot2,
    })
end

--[[
    Deletes an item from inventory.
    
    @param itemId - The inventory item ID to delete
]]
function ToolbarActions.DeleteItem(itemId: string)
    Logger.log("ToolbarActions", "Deleting item " .. itemId)
    Packets.inventoryAction.send({
        action = Constants.ActionType.DeleteItem,
        itemId = itemId,
    })
end

return ToolbarActions

--!strict
--[[
    Shared Inventory Module
    Re-exports all inventory utilities and types.
]]

local Types = require(script.Types)
local ItemUtils = require(script.ItemUtils)

-- Re-export types
export type ItemType = Types.ItemType
export type RarityType = Types.RarityType
export type InventoryItem = Types.InventoryItem
export type InventoryData = Types.InventoryData
export type InventoryChange = Types.InventoryChange
export type StackInfo = Types.StackInfo

return {
    -- Modules
    Types = Types,
    ItemUtils = ItemUtils,
    
    -- Convenience re-exports
    CreateItem = ItemUtils.CreateItem,
    AreItemsStackable = ItemUtils.AreItemsStackable,
    IsStackable = ItemUtils.IsStackable,
    GroupIntoStacks = ItemUtils.GroupIntoStacks,
    CountItems = ItemUtils.CountItems,
    FindById = ItemUtils.FindById,
    GenerateId = ItemUtils.GenerateId,
}


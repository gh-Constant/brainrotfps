--!strict
--[[
    Inventory Types
    Type definitions for the inventory system.
    
    Items can be:
    - Tools (equippable weapons with 3D models)
    - Consumables, Materials, Tickets, Boosts, etc. (non-equippable)
]]

export type ItemType = "Tool" | "Consumable" | "Material" | "Ticket" | "Boost" | "Cosmetic" | "Other"

export type RarityType = "Common" | "Uncommon" | "Epic" | "Legendary" | "Mythic" | "Secret" | "God"

--[[
    Represents a single item in the inventory.
    
    - Id: Unique identifier for this specific item instance (UUID)
    - TemplateId: Reference to the item template (e.g., tool name in ReplicatedStorage)
    - Type: Category of the item
    - Rarity: Optional rarity tier
    - Metadata: Optional extra data (e.g., custom stats, expiration)
]]
export type InventoryItem = {
    Id: string,
    TemplateId: string,
    Type: ItemType,
    Rarity: RarityType?,
    Metadata: {[string]: any}?,
}

--[[
    Serializable inventory data for ProfileStore.
    Array of items - stacking is handled at display level.
]]
export type InventoryData = {
    Items: {InventoryItem},
    ToolbarSlots: {[number]: string?}, -- Slot index -> Item Id
    MaxSize: number?, -- Max inventory slots (default 50, upgradeable)
}

--[[
    Inventory change event data.
]]
export type InventoryChange = {
    Action: "Add" | "Remove" | "Update",
    Item: InventoryItem,
}

--[[
    Stack display info for UI.
]]
export type StackInfo = {
    TemplateId: string,
    Type: ItemType,
    Rarity: RarityType?,
    Count: number,
    Items: {InventoryItem}, -- All items in this stack
}

return nil

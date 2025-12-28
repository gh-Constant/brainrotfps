--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")

local Inventory = require(Shared:WaitForChild("Inventory"))

local ToolbarUtils = {}

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
    Creates a new tool instance from an inventory item.
]]
function ToolbarUtils.CreateToolInstance(item: Inventory.InventoryItem, slot: number, stackCount: number?): Tool?
    if item.Type ~= "Tool" then return nil end

    local configItem = Inventory.ItemUtils.FindItemConfig(item.TemplateId)
    if not configItem then return nil end
    
    local template = configItem:FindFirstChildWhichIsA("Tool")
    if not template then return nil end
    
    local tool = template:Clone()
    
    -- Attributes
    tool:SetAttribute("InventoryItemId", item.Id)
    tool:SetAttribute("ToolbarSlot", slot)
    tool:SetAttribute("Rarity", item.Rarity)
    tool:SetAttribute("Type", item.Type)
    
    if item.Metadata and item.Metadata.CustomColor then
        tool:SetAttribute("CustomColor", item.Metadata.CustomColor)
    end
    
    -- Mutations
    if item.Metadata and item.Metadata.Mutations then
        for mutation, level in pairs(item.Metadata.Mutations) do
            tool:SetAttribute("Mutation", mutation) 
        end
    end
    
    local isStackable = Inventory.IsStackable(item.TemplateId)
    if isStackable then
        tool:SetAttribute("IsStackable", true)
        tool:SetAttribute("StackTemplateId", item.TemplateId)
        if stackCount and stackCount > 1 then
           tool:SetAttribute("StackCount", stackCount)
           tool.Name = string.format("%s (x%d)", item.TemplateId, stackCount)
        else
           tool:SetAttribute("StackCount", 1)
        end
    end
    
    return tool
end

--[[
    Spawns all toolbar tools for a player.
]]
function ToolbarUtils.SpawnToolbarTools(player: Player, inventory: any)
    if not inventory then return end
    
    local backpack = player:FindFirstChild("Backpack")
    if not backpack then return end
    
    local config = ReplicatedStorage:FindFirstChild("Config")
    if not config then return end
    
    local items = config:FindFirstChild("Items")
    if not items then return end
    
    -- Spawn each toolbar item
    local backpack = player:WaitForChild("Backpack")
    
    for slot, itemId in pairs(inventory.ToolbarSlots) do
        local item = Inventory.FindById(inventory.Items, itemId)
        if item then
             local isStackable = Inventory.IsStackable(item.TemplateId)
             local stackCount = nil
             
             if isStackable then
                 local stackItems = Inventory.ItemUtils.GetStackItems(inventory.Items, item)
                 stackCount = #stackItems
             end
             
             local tool = ToolbarUtils.CreateToolInstance(item, tonumber(slot) or 0, stackCount)
             if tool then
                 tool.Parent = backpack
             end
        end
    end
end

--[[
    Spawns a specific tool in a slot.
]]
function ToolbarUtils.SpawnToolInSlot(player: Player, item: Inventory.InventoryItem, slot: number, stackCount: number?)
    local backpack = player:FindFirstChild("Backpack")
    if not backpack then return end
    
    local tool = ToolbarUtils.CreateToolInstance(item, slot, stackCount)
    if tool then
        tool.Parent = backpack
    end
end

return ToolbarUtils

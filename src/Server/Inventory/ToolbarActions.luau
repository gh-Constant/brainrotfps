--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")

local Inventory = require(Shared:WaitForChild("Inventory"))
local Network = require(script.Parent.Network)
local ToolbarUtils = require(script.Parent.ToolbarUtils)

local ToolbarActions = {}

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
    Removes an item from the toolbar.
]]
function ToolbarActions.RemoveFromToolbar(player: Player, inventory: any, slot: number): boolean
    if slot < 1 or slot > 9 then return false end
    if not inventory then return false end
    
    -- Support both number and string keys
    local itemId = inventory.ToolbarSlots[slot] or inventory.ToolbarSlots[tostring(slot)] 
    
    if itemId then
        inventory.ToolbarSlots[slot] = nil
        inventory.ToolbarSlots[tostring(slot)] = nil
        
        -- Remove Tool from Backpack
        local backpack = player:FindFirstChild("Backpack")
        if backpack then
            for _, tool in backpack:GetChildren() do
                if tool:IsA("Tool") and tool:GetAttribute("InventoryItemId") == itemId then
                    tool:Destroy()
                    break
                end
            end
        end
        
        -- Remove Tool from Character
        local character = player.Character
        if character then
            for _, tool in character:GetChildren() do
                if tool:IsA("Tool") and tool:GetAttribute("InventoryItemId") == itemId then
                    tool:Destroy()
                    break
                end
            end
        end
        
        Network.SendToolbarUpdate(player, inventory.ToolbarSlots)
        return true
    end
    
    return false
end

--[[
    Assigns an item to a toolbar slot.
]]
function ToolbarActions.AssignToToolbar(player: Player, inventory: any, itemId: string, slot: number): boolean
    if slot < 1 or slot > 9 then return false end
    if not inventory then return false end
    
    local item = Inventory.FindById(inventory.Items, itemId)
    if not item then return false end
    
    if item.Type ~= "Tool" then return false end
    
    -- Stackable logic
    local isStackable = Inventory.IsStackable(item.TemplateId)
    local stackItemIds: {string} = {}
    if isStackable then
        for _, invItem in ipairs(inventory.Items) do
            if invItem.TemplateId == item.TemplateId 
                and invItem.Type == item.Type 
                and invItem.Rarity == item.Rarity then
                table.insert(stackItemIds, invItem.Id)
            end
        end
    else
        stackItemIds = {itemId}
    end
    
    -- Clear previous slot occurrences
    for s, slotData in pairs(inventory.ToolbarSlots) do
        if slotData then
            local shouldClear = false
            if isStackable then
                for _, stackId in ipairs(stackItemIds) do
                    if slotData == stackId then shouldClear = true; break end
                end
            else
                if slotData == itemId then shouldClear = true end
            end
            
            if shouldClear then
                inventory.ToolbarSlots[s] = nil
                -- Remove old tool
                local backpack = player:FindFirstChild("Backpack")
                if backpack then
                    for _, tool in backpack:GetChildren() do
                        if tool:IsA("Tool") and tool:GetAttribute("InventoryItemId") == slotData then
                            tool:Destroy()
                            break
                        end
                    end
                end
                break
            end
        end
    end
    
    -- Remove item in target slot if exists
    local existingItemId = inventory.ToolbarSlots[slot]
    if existingItemId and existingItemId ~= "" then
        local backpack = player:FindFirstChild("Backpack")
        if backpack then
            for _, tool in backpack:GetChildren() do
                if tool:IsA("Tool") and tool:GetAttribute("InventoryItemId") == existingItemId then
                    tool:Destroy()
                    break
                end
            end
        end
        local character = player.Character
        if character then
            for _, tool in character:GetChildren() do
                if tool:IsA("Tool") and tool:GetAttribute("InventoryItemId") == existingItemId then
                    tool:Destroy()
                    break
                end
            end
        end
    end
    
    -- Assign new
    inventory.ToolbarSlots[slot] = stackItemIds[1]
    
    -- Spawn tool
    local stackCount = if isStackable then #stackItemIds else nil
    ToolbarUtils.SpawnToolInSlot(player, item, slot, stackCount)
    
    log(string.format("[ToolbarActions] Spawned %s in %s's backpack (slot %d)", item.TemplateId, player.Name, slot))
    
    Network.SendToolbarUpdate(player, inventory.ToolbarSlots)
    
    return true
end

--[[
    Swaps items between two toolbar slots.
]]
function ToolbarActions.SwapToolbarSlots(player: Player, inventory: any, slot1: number, slot2: number): boolean
    if slot1 < 1 or slot1 > 9 or slot2 < 1 or slot2 > 9 then return false end
    if slot1 == slot2 then return false end
    if not inventory then return false end
    
    local itemId1 = inventory.ToolbarSlots[slot1]
    local itemId2 = inventory.ToolbarSlots[slot2]
    
    if not itemId1 and not itemId2 then return false end
    
    -- Helper to remove
    local function removeTool(itemId)
        local backpack = player:FindFirstChild("Backpack")
        if backpack then
            for _, tool in backpack:GetChildren() do
                if tool:IsA("Tool") and tool:GetAttribute("InventoryItemId") == itemId then
                    tool:Destroy()
                    break
                end
            end
        end
        local character = player.Character
        if character then
            for _, tool in character:GetChildren() do
                if tool:IsA("Tool") and tool:GetAttribute("InventoryItemId") == itemId then
                    tool:Destroy()
                    break
                end
            end
        end
    end
    
    if itemId1 then removeTool(itemId1) end
    if itemId2 then removeTool(itemId2) end
    
    -- Swap
    inventory.ToolbarSlots[slot1] = itemId2
    inventory.ToolbarSlots[slot2] = itemId1
    
    -- Respawn
    if itemId1 then
        local item = Inventory.FindById(inventory.Items, itemId1)
        if item then 
             -- Need Recalculate stack count? For swap assume stack untouched, just retrieve it
             -- Simplification: Just verify item exists and spawn
             local isStackable = Inventory.IsStackable(item.TemplateId)
             local count = nil
             if isStackable then
                 -- Count again to be safe
                 local c = 0
                 for _, invItem in ipairs(inventory.Items) do
                    if invItem.TemplateId == item.TemplateId 
                        and invItem.Type == item.Type 
                        and invItem.Rarity == item.Rarity then
                        c = c + 1
                    end
                end
                count = c
             end
             ToolbarUtils.SpawnToolInSlot(player, item, slot2, count)
        end
    end
    
    if itemId2 then
        local item = Inventory.FindById(inventory.Items, itemId2)
        if item then 
             local isStackable = Inventory.IsStackable(item.TemplateId)
             local count = nil
             if isStackable then
                 local c = 0
                 for _, invItem in ipairs(inventory.Items) do
                    if invItem.TemplateId == item.TemplateId 
                        and invItem.Type == item.Type 
                        and invItem.Rarity == item.Rarity then
                        c = c + 1
                    end
                end
                count = c
             end
             ToolbarUtils.SpawnToolInSlot(player, item, slot1, count)
        end
    end
    
    log(string.format("[ToolbarActions] Swapped %d <-> %d for %s", slot1, slot2, player.Name))
    
    Network.SendToolbarUpdate(player, inventory.ToolbarSlots)
    
    return true
end

return ToolbarActions

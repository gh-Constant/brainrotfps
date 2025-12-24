--!strict
--[[
    Inventory Manager
    Server-side inventory management with ProfileStore persistence.
    
    Handles:
    - Loading/saving inventory data (separate from player stats)
    - Adding/removing items
    - Toolbar slot management
    - Syncing with clients via ByteNet
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Packages = Rojo:WaitForChild("Packages")
local Shared = Rojo:WaitForChild("Shared")

local ProfileStore = require(Packages:WaitForChild("profilestore"))
local Signal = require(Packages:WaitForChild("signal"))
local Promise = require(Packages:WaitForChild("promise"))
local Janitor = require(Packages:WaitForChild("janitor"))

local Inventory = require(Shared:WaitForChild("Inventory"))
local Packets = require(Shared:WaitForChild("Packets"))

-- Types
type InventoryItem = Inventory.InventoryItem
type InventoryData = Inventory.InventoryData
type ItemType = Inventory.ItemType
type RarityType = Inventory.RarityType
type Signal = typeof(Signal.new())

-- ProfileStore configuration (separate from player data for modularity)
local STORE_NAME = "InventoryData_v2"
local DATA_TEMPLATE: InventoryData = {
    Items = {},
    ToolbarSlots = {},
}

-- Create ProfileStore
local InventoryProfileStore = ProfileStore.New(STORE_NAME, DATA_TEMPLATE)

-- Module
local InventoryManager = {}

-- Caches
local ActiveInventories: {[number]: InventoryData} = {}
local ActiveProfiles: {[number]: any} = {}
local PlayerJanitors: {[Player]: typeof(Janitor.new())} = {}

-- Events
InventoryManager.OnItemAdded = Signal.new()
InventoryManager.OnItemRemoved = Signal.new()
InventoryManager.OnInventoryChanged = Signal.new()

--------------------------------------------------------------------------------
-- Private Functions
--------------------------------------------------------------------------------

--[[
    Syncs the full inventory to a client.
]]
local function syncInventoryToClient(player: Player)
    local inventory = ActiveInventories[player.UserId]
    if not inventory then return end
    
    -- Convert to packet format
    local itemsData = {}
    for _, item in ipairs(inventory.Items) do
        table.insert(itemsData, {
            id = item.Id,
            templateId = item.TemplateId,
            itemType = item.Type,
            rarity = item.Rarity or "",
        })
    end
    
    Packets.inventorySync.sendTo({
        items = itemsData,
        toolbarSlots = inventory.ToolbarSlots,
    }, player)
end

--[[
    Sends an inventory update (add/remove) to a client.
]]
local function sendInventoryUpdate(player: Player, action: string, item: InventoryItem)
    Packets.inventoryUpdate.sendTo({
        action = action,
        item = {
            id = item.Id,
            templateId = item.TemplateId,
            itemType = item.Type,
            rarity = item.Rarity or "",
        },
    }, player)
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--[[
    Loads inventory for a player.
    Called by PlayerManager when player joins.
    
    @param player - The Roblox Player
    @return Promise<InventoryData>
]]
function InventoryManager.LoadInventory(player: Player)
    return Promise.new(function(resolve, reject)
        local userId = player.UserId
        local profileKey = "Inventory_" .. tostring(userId)
        
        local profile = InventoryProfileStore:StartSessionAsync(profileKey, {
            Cancel = function()
                return player.Parent ~= Players
            end
        })
        
        if profile == nil then
            reject("Failed to load inventory profile")
            return
        end
        
        if player.Parent ~= Players then
            profile:EndSession()
            reject("Player left during load")
            return
        end
        
        -- Setup profile
        profile:Reconcile()
        profile:AddUserId(userId)
        
        -- Handle session end
        profile.OnSessionEnd:Connect(function()
            ActiveInventories[userId] = nil
            ActiveProfiles[userId] = nil
        end)
        
        -- Store references
        ActiveInventories[userId] = profile.Data
        ActiveProfiles[userId] = profile
        
        -- Create janitor for this player
        local playerJanitor = Janitor.new()
        PlayerJanitors[player] = playerJanitor
        
        -- Sync to client
        syncInventoryToClient(player)
        
        -- Spawn toolbar tools in backpack (deferred to allow character to load)
        task.defer(function()
            InventoryManager.SpawnToolbarTools(player)
        end)
        
        resolve(profile.Data)
    end)
end

--[[
    Spawns all toolbar tools for a player.
    Called when player loads or respawns.
]]
function InventoryManager.SpawnToolbarTools(player: Player)
    local inventory = ActiveInventories[player.UserId]
    if not inventory then return end
    
    local backpack = player:FindFirstChild("Backpack")
    if not backpack then return end
    
    local config = ReplicatedStorage:FindFirstChild("Config")
    if not config then return end
    
    local items = config:FindFirstChild("Items")
    if not items then return end
    
    -- Spawn each toolbar item
    for slot, itemId in pairs(inventory.ToolbarSlots) do
        if not itemId then continue end
        local item = Inventory.FindById(inventory.Items, itemId :: string)
        if item and item.Type == "Tool" then
            -- Check if already spawned
            local alreadyExists = false
            for _, tool in backpack:GetChildren() do
                if tool:IsA("Tool") and tool:GetAttribute("InventoryItemId") == itemId then
                    alreadyExists = true
                    break
                end
            end
            
            if not alreadyExists then
                local itemConfig = items:FindFirstChild(item.TemplateId)
                if itemConfig then
                    local toolTemplate = itemConfig:FindFirstChildWhichIsA("Tool")
                    if toolTemplate then
                        local toolClone = toolTemplate:Clone()
                        toolClone:SetAttribute("InventoryItemId", itemId)
                        toolClone:SetAttribute("ToolbarSlot", slot)
                        toolClone.Parent = backpack
                        print(string.format("[InventoryManager] Spawned %s for %s (slot %d)", item.TemplateId, player.Name, slot))
                    end
                end
            end
        end
    end
end

--[[
    Unloads inventory for a player.
    Called by PlayerManager when player leaves.
]]
function InventoryManager.UnloadInventory(player: Player)
    local userId = player.UserId
    local profile = ActiveProfiles[userId]
    
    if profile then
        profile:EndSession()
    end
    
    -- Cleanup janitor
    local janitor = PlayerJanitors[player]
    if janitor then
        janitor:Destroy()
        PlayerJanitors[player] = nil
    end
    
    ActiveInventories[userId] = nil
    ActiveProfiles[userId] = nil
end

--[[
    Gets a player's inventory data.
    
    @param player - The Roblox Player
    @return InventoryData?
]]
function InventoryManager.GetInventory(player: Player): InventoryData?
    return ActiveInventories[player.UserId]
end

--[[
    Adds an item to a player's inventory.
    
    @param player - The Roblox Player
    @param templateId - Template reference (e.g., tool name)
    @param itemType - Type of item
    @param rarity - Optional rarity
    @param metadata - Optional extra data
    @return InventoryItem? - The created item or nil on failure
]]
function InventoryManager.AddItem(
    player: Player,
    templateId: string,
    itemType: ItemType,
    rarity: RarityType?,
    metadata: {[string]: any}?
): InventoryItem?
    local inventory = ActiveInventories[player.UserId]
    if not inventory then
        warn("[InventoryManager] No inventory for player:", player.Name)
        return nil
    end
    
    local item = Inventory.CreateItem(templateId, itemType, rarity, metadata)
    table.insert(inventory.Items, item)
    
    -- Fire events
    InventoryManager.OnItemAdded:Fire(player, item)
    InventoryManager.OnInventoryChanged:Fire(player, "Add", item)
    
    -- Sync to client
    sendInventoryUpdate(player, "Add", item)
    
    print(string.format("[InventoryManager] Added %s (%s) to %s", templateId, itemType, player.Name))
    return item
end

--[[
    Removes an item from a player's inventory by ID.
    
    @param player - The Roblox Player
    @param itemId - The item's unique ID
    @return boolean - True if removed
]]
function InventoryManager.RemoveItem(player: Player, itemId: string): boolean
    local inventory = ActiveInventories[player.UserId]
    if not inventory then return false end
    
    local index = Inventory.ItemUtils.FindIndexById(inventory.Items, itemId)
    if not index then return false end
    
    local item = inventory.Items[index]
    table.remove(inventory.Items, index)
    
    -- Remove from toolbar if equipped
    for slot, equippedId in pairs(inventory.ToolbarSlots) do
        if equippedId == itemId then
            inventory.ToolbarSlots[slot] = nil
            break
        end
    end
    
    -- Fire events
    InventoryManager.OnItemRemoved:Fire(player, item)
    InventoryManager.OnInventoryChanged:Fire(player, "Remove", item)
    
    -- Sync to client
    sendInventoryUpdate(player, "Remove", item)
    
    return true
end

--[[
    Assigns an item to a toolbar slot.
    Only Tools can be assigned to toolbar slots.
    
    @param player - The Roblox Player
    @param itemId - The item's unique ID
    @param slot - Slot number (1-9)
    @return boolean - True if successful
]]
function InventoryManager.AssignToToolbar(player: Player, itemId: string, slot: number): boolean
    if slot < 1 or slot > 9 then return false end
    
    local inventory = ActiveInventories[player.UserId]
    if not inventory then return false end
    
    local item = Inventory.FindById(inventory.Items, itemId)
    if not item then return false end
    
    -- Only Tools can be on toolbar
    if item.Type ~= "Tool" then
        return false
    end
    
    -- Remove from current slot if exists
    for s, id in pairs(inventory.ToolbarSlots) do
        if id == itemId then
            inventory.ToolbarSlots[s] = nil
            -- Remove old Tool from Backpack if it exists
            local backpack = player:FindFirstChild("Backpack")
            if backpack then
                for _, tool in backpack:GetChildren() do
                    if tool:IsA("Tool") and tool:GetAttribute("InventoryItemId") == id then
                        tool:Destroy()
                        break
                    end
                end
            end
            break
        end
    end
    
    -- Assign to new slot
    inventory.ToolbarSlots[slot] = itemId
    
    -- Spawn actual Tool in player's Backpack
    local backpack = player:FindFirstChild("Backpack")
    if backpack then
        -- Get tool config from Config/Items
        local config = ReplicatedStorage:FindFirstChild("Config")
        if config then
            local items = config:FindFirstChild("Items")
            if items then
                local itemConfig = items:FindFirstChild(item.TemplateId)
                if itemConfig then
                    -- Find the Tool child in the Configuration
                    local toolTemplate = itemConfig:FindFirstChildWhichIsA("Tool")
                    if toolTemplate then
                        local toolClone = toolTemplate:Clone()
                        toolClone:SetAttribute("InventoryItemId", itemId)
                        toolClone:SetAttribute("ToolbarSlot", slot)
                        toolClone.Parent = backpack
                        print(string.format("[InventoryManager] Spawned %s in %s's backpack (slot %d)", item.TemplateId, player.Name, slot))
                    end
                end
            end
        end
    end
    
    -- Sync to client
    syncInventoryToClient(player)
    
    return true
end

--[[
    Removes an item from the toolbar.
    
    @param player - The Roblox Player
    @param slot - Slot number (1-9)
    @return boolean - True if successful
]]
function InventoryManager.RemoveFromToolbar(player: Player, slot: number): boolean
    if slot < 1 or slot > 9 then return false end
    
    local inventory = ActiveInventories[player.UserId]
    if not inventory then return false end
    
    local itemId = inventory.ToolbarSlots[slot]
    if itemId then
        inventory.ToolbarSlots[slot] = nil
        
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
        
        -- Also check character (if tool is equipped)
        local character = player.Character
        if character then
            for _, tool in character:GetChildren() do
                if tool:IsA("Tool") and tool:GetAttribute("InventoryItemId") == itemId then
                    tool:Destroy()
                    break
                end
            end
        end
        
        syncInventoryToClient(player)
        return true
    end
    
    return false
end

--[[
    Gets the grouped stacks for UI display.
    
    @param player - The Roblox Player
    @return {StackInfo}
]]
function InventoryManager.GetStacks(player: Player): {Inventory.StackInfo}
    local inventory = ActiveInventories[player.UserId]
    if not inventory then return {} end
    
    return Inventory.GroupIntoStacks(inventory.Items)
end

--[[
    Checks if a player has a specific item.
    
    @param player - The Roblox Player
    @param templateId - Template to check
    @param rarity - Optional rarity to match
    @return boolean
]]
function InventoryManager.HasItem(player: Player, templateId: string, rarity: RarityType?): boolean
    local inventory = ActiveInventories[player.UserId]
    if not inventory then return false end
    
    return Inventory.CountItems(inventory.Items, templateId, rarity) > 0
end

--[[
    Forces a save for a player's inventory.
]]
function InventoryManager.SaveInventory(player: Player)
    local profile = ActiveProfiles[player.UserId]
    if profile and profile:IsActive() then
        profile:Save()
    end
end

--[[
    Initializes the InventoryManager.
    Sets up packet listeners.
]]
function InventoryManager.Init()
    -- Listen for inventory actions from clients
    Packets.inventoryAction.listen(function(data, player)
        if not player then return end
        local p = player :: Player
        local action = data.action
        local itemId = data.itemId
        local slot = data.slot
        
        if action == "AssignToolbar" and itemId and slot then
            InventoryManager.AssignToToolbar(p, itemId, slot)
        elseif action == "RemoveToolbar" and slot then
            InventoryManager.RemoveFromToolbar(p, slot)
        end
    end)
    
    print("[InventoryManager] Initialized!")
end

return InventoryManager

--!strict
--[[
    Inventory Manager
    Server-side inventory management.
    Refactored into modules v1.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Packages = Rojo:WaitForChild("Packages")
local Shared = Rojo:WaitForChild("Shared")

local ProfileStore = require(Packages:WaitForChild("profilestore"))
local Promise = require(Packages:WaitForChild("promise"))
local Janitor = require(Packages:WaitForChild("janitor"))

local Inventory = require(Shared:WaitForChild("Inventory"))
local Packets = require(Shared:WaitForChild("Packets"))
local Constants = require(Shared:WaitForChild("Inventory"):WaitForChild("Constants"))

-- Modules
local Events = require(script.Events)
local Network = require(script.Network)
local Actions = require(script.Actions)
local ToolbarActions = require(script.ToolbarActions)
local ToolbarUtils = require(script.ToolbarUtils)

-- ItemRegistry for global item tracking
local ItemRegistry = require(script.ItemRegistry)

-- Types
type InventoryItem = Inventory.InventoryItem
type InventoryData = Inventory.InventoryData
type ItemType = Inventory.ItemType
type RarityType = Inventory.RarityType

-- ProfileStore
local STORE_NAME = "InventoryDatae_eeEv5"
local DATA_TEMPLATE: InventoryData = {
    Items = {},
    ToolbarSlots = {},
    MaxSize = 100000000000,
}

local InventoryProfileStore = ProfileStore.New(STORE_NAME, DATA_TEMPLATE)

local InventoryManager = {}

-- State
local ActiveInventories: {[number]: InventoryData} = {}
local ActiveIndices: {[number]: {ById: {[string]: InventoryItem}, ByTemplate: {[string]: {InventoryItem}}}} = {}
local ActiveProfiles: {[number]: any} = {}
local DupedItems: {[string]: boolean} = {} 
local PlayerJanitors: {[Player]: typeof(Janitor.new())} = {}

-- Security
local SECURITY = {
    RateLimitWindow = 1.0, 
    MaxActionsPerWindow = 10,
}
local RateLimitState: {[number]: {LastReset: number, ActionCount: number}} = {}

-- Expose Events
InventoryManager.OnItemAdded = Events.OnItemAdded
InventoryManager.OnItemRemoved = Events.OnItemRemoved
InventoryManager.OnInventoryChanged = Events.OnInventoryChanged

--------------------------------------------------------------------------------
-- Private
--------------------------------------------------------------------------------

local function checkRateLimit(player: Player): boolean
    local userId = player.UserId
    local now = os.clock()
    local state = RateLimitState[userId]
    if not state then
        RateLimitState[userId] = { LastReset = now, ActionCount = 1 }
        return true
    end
    if now - state.LastReset >= SECURITY.RateLimitWindow then
        state.LastReset = now
        state.ActionCount = 1
        return true
    end
    if state.ActionCount < SECURITY.MaxActionsPerWindow then
        state.ActionCount = state.ActionCount + 1
        return true
    end
    warn(string.format("[InventoryManager] Rate limited player %s", player.Name))
    return false
end

-- internal dup detection from original code
function InventoryManager._detectDuplicates(player: Player, items: {InventoryItem})
    local seenIds = {}
    for _, item in ipairs(items) do
        if seenIds[item.Id] then
            DupedItems[item.Id] = true
            warn(string.format("[InventoryManager] Possible Duplicate: %s (%s) for %s", item.Id, item.TemplateId, player.Name))
        else
            seenIds[item.Id] = true
        end
    end
end

local function buildIndex(items: {InventoryItem})
    local byId = {}
    local byTemplate = {}
    
    for _, item in ipairs(items) do
        byId[item.Id] = item
        
        if not byTemplate[item.TemplateId] then
            byTemplate[item.TemplateId] = {}
        end
        table.insert(byTemplate[item.TemplateId], item)
    end
    
    return {
        ById = byId,
        ByTemplate = byTemplate,
    }
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function InventoryManager.GetItemRegistry()
    return ItemRegistry
end

function InventoryManager.LoadInventory(player: Player)
    return Promise.new(function(resolve, reject)
        local userId = player.UserId
        local profileKey = "Inventory_" .. tostring(userId)
        
        local profile = InventoryProfileStore:StartSessionAsync(profileKey, {
            Cancel = function() return player.Parent ~= Players end
        })
        
        if profile == nil then return reject("Failed to load inventory profile") end
        if player.Parent ~= Players then profile:EndSession(); return reject("Player left") end
        
        profile:Reconcile()
        profile:AddUserId(userId)
        
        -- Fix keys
        local fixedToolbarSlots = {}
        for k, v in pairs(profile.Data.ToolbarSlots) do
            local numKey = tonumber(k)
            if numKey then fixedToolbarSlots[numKey] = v end
        end
        profile.Data.ToolbarSlots = fixedToolbarSlots
        
        profile.OnSessionEnd:Connect(function()
            ActiveInventories[userId] = nil
            ActiveProfiles[userId] = nil
            ActiveIndices[userId] = nil
        end)
        
        ActiveInventories[userId] = profile.Data
        ActiveProfiles[userId] = profile
        ActiveIndices[userId] = buildIndex(profile.Data.Items)
        PlayerJanitors[player] = Janitor.new()
        
        -- Dup detect
        task.spawn(function()
             InventoryManager._detectDuplicates(player, profile.Data.Items)
        end)
        
        -- Initial Sync
        Network.SyncInventory(player, profile.Data)
        
        -- Spawn Tools
        task.defer(function()
            ToolbarUtils.SpawnToolbarTools(player, profile.Data)
        end)
        
        resolve(profile.Data)
    end)
end

function InventoryManager.UnloadInventory(player: Player)
    local userId = player.UserId
    local profile = ActiveProfiles[userId]
    if profile then profile:EndSession() end
    
    local janitor = PlayerJanitors[player]
    if janitor then janitor:Destroy(); PlayerJanitors[player] = nil end
    
    RateLimitState[userId] = nil
    ActiveInventories[userId] = nil
    ActiveProfiles[userId] = nil
    ActiveIndices[userId] = nil
end

--[[
    Returns raw inventory data for internal server use (no cloning).
    WARNING: Do not mutate directly - use AddItem/RemoveItem APIs.
]]
function InventoryManager.GetInventoryRaw(player: Player): InventoryData?
    return ActiveInventories[player.UserId]
end

--[[
    Returns a frozen copy of inventory for external module use.
    Only call this when you need to expose data to untrusted code.
]]
function InventoryManager.GetInventory(player: Player): InventoryData?
    local data = ActiveInventories[player.UserId]
    if not data then return nil end
    
    -- Create safe snapshot only when needed for external access
    local snapshot = table.clone(data)
    snapshot.Items = table.freeze(table.clone(data.Items))
    snapshot.ToolbarSlots = table.freeze(table.clone(data.ToolbarSlots))
    
    return table.freeze(snapshot)
end

function InventoryManager.AddItem(player: Player, templateId: string, itemType: ItemType, rarity: RarityType?, metadata: any): InventoryItem?
    local inventory = ActiveInventories[player.UserId]
    local index = ActiveIndices[player.UserId]
    return Actions.AddItem(player, inventory, index, templateId, itemType, rarity, metadata, DupedItems)
end

function InventoryManager.AddItems(player: Player, templateId: string, itemType: ItemType, count: number, rarity: RarityType?, metadata: any): {InventoryItem}
    local inventory = ActiveInventories[player.UserId]
    local index = ActiveIndices[player.UserId]
    return Actions.AddItems(player, inventory, index, templateId, itemType, count, rarity, metadata, DupedItems)
end

function InventoryManager.RemoveItem(player: Player, itemId: string): boolean
    local inventory = ActiveInventories[player.UserId]
    local index = ActiveIndices[player.UserId]
    return Actions.RemoveItem(player, inventory, index, itemId, DupedItems, function(p, s)
        return ToolbarActions.RemoveFromToolbar(p, inventory, s)
    end)
end

function InventoryManager.AssignToToolbar(player: Player, itemId: string, slot: number): boolean
    local inventory = ActiveInventories[player.UserId]
    return ToolbarActions.AssignToToolbar(player, inventory, itemId, slot)
end

function InventoryManager.RemoveFromToolbar(player: Player, slot: number): boolean
    local inventory = ActiveInventories[player.UserId]
    return ToolbarActions.RemoveFromToolbar(player, inventory, slot)
end

function InventoryManager.SwapToolbarSlots(player: Player, slot1: number, slot2: number): boolean
    local inventory = ActiveInventories[player.UserId]
    return ToolbarActions.SwapToolbarSlots(player, inventory, slot1, slot2)
end

function InventoryManager.GetStacks(player: Player): {Inventory.StackInfo}
    local inventory = ActiveInventories[player.UserId]
    if not inventory then return {} end
    return Inventory.GroupIntoStacks(inventory.Items)
end

function InventoryManager.HasItem(player: Player, templateId: string, rarity: RarityType?): boolean
    local inventory = ActiveInventories[player.UserId]
    if not inventory then return false end
    
    for _, item in ipairs(inventory.Items) do
        if item.TemplateId == templateId then
             if rarity then
                 if item.Rarity == rarity then return true end
             else
                 return true
             end
        end
    end
    return false
end

-- Init
function InventoryManager.Init()
    -- Packet Listeners
    Packets.inventoryAction.listen(function(data, player)
        if not checkRateLimit(player) then return end
        
        local action = data.action
        local itemId = data.itemId
        local slot = data.slot
        local slot2 = data.slot2
        
        if action == Constants.ActionType.AssignToolbar and itemId and slot then
            InventoryManager.AssignToToolbar(player, itemId, slot)
        elseif action == Constants.ActionType.RemoveToolbar and slot then
            InventoryManager.RemoveFromToolbar(player, slot)
        elseif action == Constants.ActionType.SwapToolbar and slot and slot2 then
            InventoryManager.SwapToolbarSlots(player, slot, slot2)
        elseif action == Constants.ActionType.DeleteItem and itemId then
            InventoryManager.RemoveItem(player, itemId)
        end
    end)
    
    -- Request Inventory Listener
    Packets.requestInventory.listen(function(_, player)
        if not checkRateLimit(player) then return end
        
        local inventory = ActiveInventories[player.UserId]
        if inventory then
            Network.SyncInventory(player, inventory)
            -- Also sync toolbar
            ToolbarUtils.SpawnToolbarTools(player, inventory)
            print(string.format("[InventoryManager] Resyncing inventory for %s upon request", player.Name))
        else
            warn(string.format("[InventoryManager] Received sync request from %s but no inventory loaded yet", player.Name))
        end
    end)
    
    -- Player Lifecycle
    -- Managed by PlayerManager (LoadInventory/UnloadInventory)
    
    -- Load for existing (only if not loaded by PlayerManager yet, useful for debugging/reload)
    -- Actually, if PlayerManager calls it, we don't need to do it here at all.
    -- Leaving it empty for now to avoid conflict.
    
    print("[InventoryManager] Initialized (Modular v1)")
end

return InventoryManager

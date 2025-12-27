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

-- ItemRegistry for global item tracking
local ItemRegistry = require(script.ItemRegistry)

-- Logging helper
local function log(message: string)
	local config = ReplicatedStorage:FindFirstChild("Config")
	if config then
		local invConfig = config:FindFirstChild("Inventory")
		if invConfig and invConfig:GetAttribute("Logging") == true then
			print(message)
		end
	end
end

-- Types
type InventoryItem = Inventory.InventoryItem
type InventoryData = Inventory.InventoryData
type ItemType = Inventory.ItemType
type RarityType = Inventory.RarityType
type Signal = typeof(Signal.new())

-- ProfileStore configuration (separate from player data for modularity)
local STORE_NAME = "InventoryData_v3"
local DATA_TEMPLATE: InventoryData = {
    Items = {},
    ToolbarSlots = {},
    MaxSize = 50, -- Default size
}

-- Create ProfileStore
local InventoryProfileStore = ProfileStore.New(STORE_NAME, DATA_TEMPLATE)

-- Module
local InventoryManager = {}

-- Caches
local ActiveInventories: {[number]: InventoryData} = {}
local ActiveProfiles: {[number]: any} = {}
local DupedItems: {[string]: boolean} = {} -- itemId -> isMaybeDuped (in-memory detection)
local PlayerJanitors: {[Player]: typeof(Janitor.new())} = {}

-- Security Configuration
local SECURITY = {
    RateLimitWindow = 1.0, -- Time window in seconds
    MaxActionsPerWindow = 10, -- Max actions per time window
}

-- Rate limiting state: userId -> {lastActionTime, actionCount}
local RateLimitState: {[number]: {LastReset: number, ActionCount: number}} = {}

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
            maybeDuped = DupedItems[item.Id] or false,
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
            maybeDuped = DupedItems[item.Id] or false,
        },
    }, player)
end

--[[
    Checks if a player is rate limited.
    Returns true if action should be allowed, false if rate limited.
]]
local function checkRateLimit(player: Player): boolean
    local userId = player.UserId
    local now = os.clock()
    
    local state = RateLimitState[userId]
    if not state then
        RateLimitState[userId] = { LastReset = now, ActionCount = 1 }
        return true
    end
    
    -- Reset window if enough time has passed
    if now - state.LastReset >= SECURITY.RateLimitWindow then
        state.LastReset = now
        state.ActionCount = 1
        return true
    end
    
    -- Check if under limit
    if state.ActionCount < SECURITY.MaxActionsPerWindow then
        state.ActionCount = state.ActionCount + 1
        return true
    end
    
    -- Rate limited
    warn(string.format("[InventoryManager] Rate limited player %s (%d actions in %.1fs)", 
        player.Name, state.ActionCount, SECURITY.RateLimitWindow))
    return false
end

--[[
    Validates that a templateId exists in Config/Items (supports nested folders).
]]
local function isValidTemplateId(templateId: string): boolean
    return Inventory.ItemUtils.FindItemConfig(templateId) ~= nil
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
        
        -- Detect duplicates (async, after profile loaded)
        task.spawn(function()
            InventoryManager._detectDuplicates(player, profile.Data.Items)
        end)
        
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
                local itemConfig = Inventory.ItemUtils.FindItemConfig(item.TemplateId)
                if itemConfig then
                    local toolTemplate = itemConfig:FindFirstChildWhichIsA("Tool")
                    if toolTemplate then
                        local toolClone = toolTemplate:Clone()
                        toolClone:SetAttribute("InventoryItemId", itemId)
                        toolClone:SetAttribute("ToolbarSlot", slot)
                        
                        -- Check if this is a stackable item and set stack attributes
                        local isStackable = Inventory.IsStackable(item.TemplateId)
                        if isStackable then
                            -- Count all items of same template in inventory
                            local stackCount = 0
                            for _, invItem in ipairs(inventory.Items) do
                                if invItem.TemplateId == item.TemplateId 
                                    and invItem.Type == item.Type 
                                    and invItem.Rarity == item.Rarity then
                                    stackCount = stackCount + 1
                                end
                            end
                            toolClone:SetAttribute("StackCount", stackCount)
                            toolClone:SetAttribute("StackTemplateId", item.TemplateId)
                            toolClone:SetAttribute("IsStackable", true)
                        end
                        
                        toolClone.Parent = backpack
                        log(string.format("[InventoryManager] Spawned %s for %s (slot %d)", item.TemplateId, player.Name, slot))
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
    
    -- Cleanup rate limit state
    RateLimitState[userId] = nil
    
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
    
    -- Security: Check inventory size limit
    local maxSize = inventory.MaxSize or 50 -- Fallback to default if nil (migrating old data)
    if #inventory.Items >= maxSize then
        warn(string.format("[InventoryManager] Inventory full for %s (%d/%d items)", player.Name, #inventory.Items, maxSize))
        return nil
    end
    
    -- Security: Validate templateId exists (for Tools)
    if itemType == "Tool" and not isValidTemplateId(templateId) then
        warn(string.format("[InventoryManager] Invalid templateId '%s' for %s", templateId, player.Name))
        return nil
    end
    
    local item = Inventory.CreateItem(templateId, itemType, rarity, metadata)
    table.insert(inventory.Items, item)
    
    -- Register in global ItemRegistry (async, don't block)
    task.spawn(function()
        ItemRegistry.RegisterItem(item.Id, player.UserId, templateId):catch(function(err)
            warn("[InventoryManager] Failed to register item:", err)
        end)
    end)
    
    -- Fire events
    InventoryManager.OnItemAdded:Fire(player, item)
    InventoryManager.OnInventoryChanged:Fire(player, "Add", item)
    
    -- Sync to client
    sendInventoryUpdate(player, "Add", item)
    
    log(string.format("[InventoryManager] Added %s (%s) to %s", templateId, itemType, player.Name))
    return item
end

--[[
    Removes an item from a player's inventory by ID.
    For stackable items in toolbar, updates the tool's StackCount.
    
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
    local isStackable = Inventory.IsStackable(item.TemplateId)
    
    table.remove(inventory.Items, index)
    
    -- Handle toolbar update for stackable items
    if isStackable then
        -- Find if this item's template is in a toolbar slot
        local foundSlot: number? = nil
        local remainingCount = 0
        
        -- Count remaining items of same template
        for _, invItem in ipairs(inventory.Items) do
            if invItem.TemplateId == item.TemplateId 
                and invItem.Type == item.Type 
                and invItem.Rarity == item.Rarity then
                remainingCount = remainingCount + 1
            end
        end
        
        -- Check if any item of this stack is in toolbar
        for slot, equippedId in pairs(inventory.ToolbarSlots) do
            if equippedId then
                local equippedItem = Inventory.FindById(inventory.Items, equippedId)
                if equippedItem and equippedItem.TemplateId == item.TemplateId 
                    and equippedItem.Type == item.Type 
                    and equippedItem.Rarity == item.Rarity then
                    foundSlot = slot
                    break
                elseif equippedId == itemId then
                    -- The removed item was the toolbar reference
                    foundSlot = slot
                    break
                end
            end
        end
        
        if foundSlot then
            if remainingCount > 0 then
                -- Update the toolbar slot to point to another item in stack
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
                
                -- Update the tool's StackCount attribute
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
                -- No items left in stack, remove from toolbar
                InventoryManager.RemoveFromToolbar(player, foundSlot)
            end
        end
    else
        -- Non-stackable: remove from toolbar if equipped
        for slot, equippedId in pairs(inventory.ToolbarSlots) do
            if equippedId == itemId then
                InventoryManager.RemoveFromToolbar(player, slot)
                break
            end
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
    For stackable items, the entire stack is assigned to the slot.
    
    @param player - The Roblox Player
    @param itemId - The item's unique ID (or any item from the stack)
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
    
    -- Check if this item is stackable
    local isStackable = Inventory.IsStackable(item.TemplateId)
    
    -- Get all item IDs for this stack (or just the one if not stackable)
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
    
    -- Remove all stack items from their current slot if any (moving from another slot)
    for s, slotData in pairs(inventory.ToolbarSlots) do
        if slotData then
            -- Check if this slot contains any of our stack items
            local shouldClear = false
            if isStackable then
                -- For stackable, check if slot is storing same template
                for _, stackId in ipairs(stackItemIds) do
                    if slotData == stackId then
                        shouldClear = true
                        break
                    end
                end
            else
                if slotData == itemId then
                    shouldClear = true
                end
            end
            
            if shouldClear then
                inventory.ToolbarSlots[s] = nil
                -- Remove old Tool from Backpack if it exists
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
    
    -- Remove existing item from target slot if occupied (swap scenario)
    local existingItemId = inventory.ToolbarSlots[slot]
    if existingItemId and existingItemId ~= "" then
        -- Remove the old tool from backpack
        local backpack = player:FindFirstChild("Backpack")
        if backpack then
            for _, tool in backpack:GetChildren() do
                if tool:IsA("Tool") and tool:GetAttribute("InventoryItemId") == existingItemId then
                    tool:Destroy()
                    break
                end
            end
        end
        -- Also check character for equipped tool
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
    
    -- Assign to new slot (use first item ID as the slot reference)
    inventory.ToolbarSlots[slot] = stackItemIds[1]
    
    -- Spawn actual Tool in player's Backpack
    local backpack = player:FindFirstChild("Backpack")
    if backpack then
        -- Get tool config from Config/Items
        local config = ReplicatedStorage:FindFirstChild("Config")
        if config then
            local items = config:FindFirstChild("Items")
            if items then
                local itemConfig = Inventory.ItemUtils.FindItemConfig(item.TemplateId)
                if itemConfig then
                    -- Find the Tool child in the Configuration
                    local toolTemplate = itemConfig:FindFirstChildWhichIsA("Tool")
                    if toolTemplate then
                        local toolClone = toolTemplate:Clone()
                        toolClone:SetAttribute("InventoryItemId", stackItemIds[1])
                        toolClone:SetAttribute("ToolbarSlot", slot)
                        -- For stackable items, add stack info
                        if isStackable then
                            toolClone:SetAttribute("StackCount", #stackItemIds)
                            toolClone:SetAttribute("StackTemplateId", item.TemplateId)
                            toolClone:SetAttribute("IsStackable", true)
                        end
                        toolClone.Parent = backpack
                        log(string.format("[InventoryManager] Spawned %s in %s's backpack (slot %d, stack: %d)", 
                            item.TemplateId, player.Name, slot, #stackItemIds))
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
    Swaps items between two toolbar slots.
    If one slot is empty, this acts as a move operation.
    
    @param player - The Roblox Player
    @param slot1 - First slot number (1-9)
    @param slot2 - Second slot number (1-9)
    @return boolean - True if successful
]]
function InventoryManager.SwapToolbarSlots(player: Player, slot1: number, slot2: number): boolean
    if slot1 < 1 or slot1 > 9 or slot2 < 1 or slot2 > 9 then return false end
    if slot1 == slot2 then return false end
    
    local inventory = ActiveInventories[player.UserId]
    if not inventory then return false end
    
    local itemId1 = inventory.ToolbarSlots[slot1]
    local itemId2 = inventory.ToolbarSlots[slot2]
    
    -- At least one slot must have an item
    if not itemId1 and not itemId2 then return false end
    
    -- Helper to destroy tool in backpack/character
    local function destroyToolForItem(itemId: string)
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
    
    -- Helper to spawn tool in slot
    local function spawnToolInSlot(itemId: string, slot: number)
        local item = Inventory.FindById(inventory.Items, itemId)
        if not item or item.Type ~= "Tool" then return end
        
        local backpack = player:FindFirstChild("Backpack")
        if not backpack then return end
        
        local config = ReplicatedStorage:FindFirstChild("Config")
        if not config then return end
        local items = config:FindFirstChild("Items")
        if not items then return end
        
        local itemConfig = Inventory.ItemUtils.FindItemConfig(item.TemplateId)
        if not itemConfig then return end
        
        local toolTemplate = itemConfig:FindFirstChildWhichIsA("Tool")
        if not toolTemplate then return end
        
        local toolClone = toolTemplate:Clone()
        toolClone:SetAttribute("InventoryItemId", itemId)
        toolClone:SetAttribute("ToolbarSlot", slot)
        toolClone.Parent = backpack
    end
    
    -- Destroy existing tools
    if itemId1 then destroyToolForItem(itemId1) end
    if itemId2 then destroyToolForItem(itemId2) end
    
    -- Swap slot assignments
    inventory.ToolbarSlots[slot1] = itemId2
    inventory.ToolbarSlots[slot2] = itemId1
    
    -- Respawn tools in new slots
    if itemId1 then spawnToolInSlot(itemId1, slot2) end
    if itemId2 then spawnToolInSlot(itemId2, slot1) end
    
    log(string.format("[InventoryManager] Swapped toolbar slots %d <-> %d for %s", slot1, slot2, player.Name))
    
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
    Upgrades a player's inventory size.
    
    @param player - The Roblox Player
    @param amount - Amount to increase (default 5, can be negative to decrease)
    @return boolean - True if successful
]]
function InventoryManager.UpgradeInventorySize(player: Player, amount: number): boolean
    local inventory = ActiveInventories[player.UserId]
    if not inventory then return false end
    
    local currentSize = inventory.MaxSize or 50
    inventory.MaxSize = currentSize + amount
    
    -- Save immediately
    InventoryManager.SaveInventory(player)
    

    log(string.format("[InventoryManager] Upgraded inventory size for %s: %d -> %d", player.Name, currentSize, inventory.MaxSize or 50))
    return true
end

--[[
    Detects duplicated items by checking against global ItemRegistry.
    Items not found in registry or with mismatched owner are flagged.
    
    @param player - The player whose inventory to check
    @param items - Array of inventory items
]]
function InventoryManager._detectDuplicates(player: Player, items: {InventoryItem})
    local userId = player.UserId
    local dupeCount = 0
    
    for _, item in ipairs(items) do
        ItemRegistry.IsValidOwner(item.Id, userId):andThen(function(isValid)
            if not isValid then
                DupedItems[item.Id] = true
                dupeCount = dupeCount + 1
                warn(string.format("[InventoryManager] Detected MAYBE DUPED item %s for %s", 
                    item.Id:sub(1, 8), player.Name))
            end
        end):catch(function(err)
            warn("[InventoryManager] Error checking item validity:", err)
        end)
    end
    
    -- Re-sync after detection completes (give some time for async checks)
    task.delay(2, function()
        if player.Parent == Players and dupeCount > 0 then
            syncInventoryToClient(player)
            log(string.format("[InventoryManager] Flagged %d potentially duped items for %s", 
                dupeCount, player.Name))
        end
    end)
end

--[[
    Duplicates an item WITHOUT registering in ItemRegistry.
    This simulates a duplication exploit for testing detection.
    
    @param player - The player to give the dupe to
    @param itemId - The item to duplicate
    @return InventoryItem? - The duplicated item
]]
function InventoryManager.DuplicateItem(player: Player, itemId: string): InventoryItem?
    local inventory = ActiveInventories[player.UserId]
    if not inventory then
        warn("[InventoryManager] No inventory for player:", player.Name)
        return nil
    end
    
    -- Find original item
    local originalItem = Inventory.FindById(inventory.Items, itemId)
    if not originalItem then
        warn("[InventoryManager] Item not found:", itemId)
        return nil
    end
    
    -- Security: Check inventory size limit
    local maxSize = inventory.MaxSize or 50
    if #inventory.Items >= maxSize then
        warn("[InventoryManager] Inventory full, cannot duplicate")
        return nil
    end
    
    -- Create a copy with NEW Id but same properties
    -- IMPORTANT: We do NOT register this in ItemRegistry - that's how detection catches it
    local dupedItem: InventoryItem = {
        Id = Inventory.ItemUtils.GenerateId(), -- New unique ID
        TemplateId = originalItem.TemplateId,
        Type = originalItem.Type,
        Rarity = originalItem.Rarity,
        Metadata = if originalItem.Metadata then table.clone(originalItem.Metadata) else nil,
    }
    
    table.insert(inventory.Items, dupedItem)
    
    -- Fire events
    InventoryManager.OnItemAdded:Fire(player, dupedItem)
    InventoryManager.OnInventoryChanged:Fire(player, "Add", dupedItem)
    
    -- Sync to client
    sendInventoryUpdate(player, "Add", dupedItem)
    
    log(string.format("[InventoryManager] DUPLICATED item %s -> %s (NOT registered in ItemRegistry)", 
        originalItem.Id:sub(1, 8), dupedItem.Id:sub(1, 8)))
    
    return dupedItem
end

--[[
    Gets the ItemRegistry module for external access (e.g., commands).
]]
function InventoryManager.GetItemRegistry()
    return ItemRegistry
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
        
        -- Security: Rate limit check
        if not checkRateLimit(p) then
            return -- Rate limited, ignore action
        end
        
        local action = data.action
        local itemId = data.itemId
        local slot = data.slot
        local slot2 = data.slot2
        
        if action == "AssignToolbar" and itemId and slot then
            InventoryManager.AssignToToolbar(p, itemId, slot)
        elseif action == "RemoveToolbar" and slot then
            InventoryManager.RemoveFromToolbar(p, slot)
        elseif action == "SwapToolbar" and slot and slot2 then
            InventoryManager.SwapToolbarSlots(p, slot, slot2)
        elseif action == "DeleteItem" and itemId then
            InventoryManager.RemoveItem(p, itemId)
        elseif action == "Consume" and itemId then
            -- Consume removes one item from inventory (for stackable consumables)
            InventoryManager.RemoveItem(p, itemId)
            log(string.format("[InventoryManager] Consumed item %s for %s", itemId:sub(1, 8), p.Name))
        end
    end)
    
    log("[InventoryManager] Initialized with ItemRegistry integration!")
end

return InventoryManager

--!strict
--[[
    Inventory UI Controller
    Manages the inventory panel UI.
    
    Features:
    - Grid layout of item slots with stacking
    - Toggle visibility from inventory button
    - Syncs with server via ByteNet
    - ViewportFrame 3D model display
    
    New UI Hierarchy:
    Inventory [ScreenGui]
    └── Hub [Frame]
        ├── ItemSlots [Frame]
        │   └── ListLayout [Frame] (Slot1..Slot9)
        ├── Base [Frame]
        │   ├── Close [ImageButton]
        │   ├── Panel [ScrollingFrame] (main inventory grid)
        │   └── NavBar, InfoPanel (not implemented yet)
        └── UIScale, UIAspectRatioConstraint
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Packages = Rojo:WaitForChild("Packages")
local Shared = Rojo:WaitForChild("Shared")

local Janitor = require(Packages:WaitForChild("janitor"))
local Signal = require(Packages:WaitForChild("signal"))

local Inventory = require(Shared:WaitForChild("Inventory"))
local Packets = require(Shared:WaitForChild("Packets"))
local RarityConfig = require(Shared:WaitForChild("Rarity"):WaitForChild("RarityConfig"))
local ColorSystem = require(Shared:WaitForChild("Inventory"):WaitForChild("ColorSystem"))
local ItemSlot = require(script.ItemSlot)
local DragDrop = require(script.DragDrop)

-- Logging helper (checks Config.Inventory.Logging attribute)
local function log(message: string)
	local config = ReplicatedStorage:FindFirstChild("Config")
	if config then
		local invConfig = config:FindFirstChild("Inventory")
		if invConfig and invConfig:GetAttribute("Logging") == true then
			print(message)
		end
	end
end

-- Get Toolbar module (for hide/show when inventory opens)
local Toolbar: any? = nil -- Will be set in Init to avoid circular dependency

-- Types
type Janitor = typeof(Janitor.new())
type InventoryItem = Inventory.InventoryItem
type StackInfo = Inventory.StackInfo
type ItemSlotData = ItemSlot.ItemSlotData

local _LocalPlayer = Players.LocalPlayer

-- Module
local InventoryUI = {}

-- State
local isOpen = false
local hubFrame: Frame? = nil
local slotsContainer: ScrollingFrame? = nil
local itemSlots: {ItemSlot.ItemSlot} = {}
local inventoryData: {InventoryItem} = {}
local toolbarSlots: {[number]: string} = {}
local dupedItems: {[string]: boolean} = {} -- itemId -> maybeDuped
local toolbarSlotFrames: {Frame} = {}
local screenGui: ScreenGui? = nil
local janitor: Janitor = Janitor.new()
local slotTemplate: GuiObject? = nil -- Slot template from Config
local infoPanel: any? = nil -- InfoPanel instance
local InfoPanel = require(script.InfoPanel)
local currentFilter: string = "Unfiltered" -- "Unfiltered", "Gun", "Grenade", "Potion"

-- Events
InventoryUI.OnItemClicked = Signal.new()
InventoryUI.OnToggled = Signal.new()

--------------------------------------------------------------------------------
-- Private Functions
--------------------------------------------------------------------------------

-- Forward declaration
local updateIntegratedToolbar 

--[[
    Gets the display name for an item.
    Checks Config for "DisplayName" attribute, falls back to templateId.
]]
local function _getDisplayName(templateId: string): string
    local config = ReplicatedStorage:FindFirstChild("Config")
    if config then
        local items = config:FindFirstChild("Items")
        if items then
            -- Recursive search for Configuration elements
            local function searchRecursive(parent: Instance): Configuration?
                for _, child in parent:GetChildren() do
                    if child:IsA("Configuration") and child.Name == templateId then
                        return child
                    elseif child:IsA("Folder") then
                        local found = searchRecursive(child)
                        if found then return found end
                    end
                end
                return nil
            end
            
            local itemConfig = searchRecursive(items)
            if itemConfig then
                local displayName = itemConfig:GetAttribute("DisplayName")
                if displayName and displayName ~= "" then
                    return displayName
                end
            end
        end
    end
    return templateId
end

-- Helper to get ItemType from item configuration
local function getItemType(templateId: string): string?
    local config = ReplicatedStorage:FindFirstChild("Config")
    if config then
        local items = config:FindFirstChild("Items")
        if items then
            local function searchRecursive(parent: Instance): Configuration?
                for _, child in parent:GetChildren() do
                    if child:IsA("Configuration") and child.Name == templateId then
                        return child
                    elseif child:IsA("Folder") then
                        local found = searchRecursive(child)
                        if found then return found end
                    end
                end
                return nil
            end
            
            local itemConfig = searchRecursive(items)
            if itemConfig then
                return itemConfig:GetAttribute("ItemType") :: string?
            end
        end
    end
    return nil
end

--[[
    Converts inventory items to slot display data.
    Stackable items are grouped together, non-stackable items shown individually.
    Filtered by currentFilter if not "Unfiltered".
]]
local function getItemsForDisplay(): {ItemSlotData}
    -- Create a set of item IDs that are in toolbar slots
    local equippedItemIds: {[string]: number} = {} -- itemId -> slot number
    for slot, itemId in pairs(toolbarSlots) do
        if itemId and itemId ~= "" then
            equippedItemIds[itemId] = slot
        end
    end
    
    local slotDataList: {ItemSlotData} = {}
    
    -- Separate stackable and non-stackable items, applying filter
    local stackableItems: {InventoryItem} = {}
    local nonStackableItems: {InventoryItem} = {}
    
    for _, item in inventoryData do
        -- Apply filter
        local passesFilter = true
        if currentFilter ~= "Unfiltered" then
            local itemType = getItemType(item.TemplateId)
            passesFilter = (itemType == currentFilter)
        end
        
        if passesFilter then
            if Inventory.IsStackable(item.TemplateId) then
                table.insert(stackableItems, item)
            else
                table.insert(nonStackableItems, item)
            end
        end
    end
    
    -- Group stackable items into stacks
    local stacks = Inventory.GroupIntoStacks(stackableItems)
    for _, stack in ipairs(stacks) do
        -- Check if any item in this stack is equipped
        local equippedSlot: number? = nil
        for _, stackItem in ipairs(stack.Items) do
            if equippedItemIds[stackItem.Id] then
                equippedSlot = equippedItemIds[stackItem.Id]
                break
            end
        end
        
        -- Collect all item IDs in the stack
        local itemIds: {string} = {}
        local anyDuped = false
        for _, stackItem in ipairs(stack.Items) do
            table.insert(itemIds, stackItem.Id)
            if dupedItems[stackItem.Id] then
                anyDuped = true
            end
        end
        
        table.insert(slotDataList, {
            TemplateId = stack.TemplateId,
            Type = stack.Type :: string,
            Rarity = if stack.Rarity then stack.Rarity :: string else nil,
            Count = stack.Count,
            ItemIds = itemIds,
            IsEquipped = equippedSlot ~= nil,
            EquippedSlot = equippedSlot,
            EquippedSlot = equippedSlot,
            MaybeDuped = anyDuped,
            Metadata = stack.Items[1].Metadata,
        })
    end
    
    -- Add non-stackable items individually
    for _, item in nonStackableItems do
        local equippedSlot = equippedItemIds[item.Id]
        table.insert(slotDataList, {
            TemplateId = item.TemplateId,
            Type = item.Type :: string,
            Rarity = if item.Rarity then item.Rarity :: string else nil,
            Count = 1,
            ItemIds = {item.Id},
            IsEquipped = equippedSlot ~= nil,
            EquippedSlot = equippedSlot,
            MaybeDuped = dupedItems[item.Id] or false,
            Metadata = item.Metadata,
        })
    end
    
    -- Sort by rarity (rarest first) and mutation count (most first)
    -- Build rarity order lookup from RarityConfig.RarityOrder (index = rarity value, higher = rarer)
    local rarityOrder: {[string]: number} = {}
    for index, rarityName in ipairs(RarityConfig.RarityOrder) do
        rarityOrder[rarityName] = index
    end
    
    local function getMutationCount(slotData: ItemSlotData): number
        if slotData.Metadata and slotData.Metadata.Mutations then
            local count = 0
            for _ in pairs(slotData.Metadata.Mutations) do
                count = count + 1
            end
            return count
        end
        return 0
    end
    
    table.sort(slotDataList, function(a, b)
        -- Equipped items first
        local equippedA = a.IsEquipped or false
        local equippedB = b.IsEquipped or false
        if equippedA ~= equippedB then
            return equippedA
        end
        
        -- Sort by equipped slot if both are equipped
        if equippedA and equippedB then
            local slotA = a.EquippedSlot or 999
            local slotB = b.EquippedSlot or 999
            if slotA ~= slotB then
                return slotA < slotB
            end
        end
        
        local rarityA = rarityOrder[a.Rarity or "Common"] or 0
        local rarityB = rarityOrder[b.Rarity or "Common"] or 0
        
        -- Higher rarity first
        if rarityA ~= rarityB then
            return rarityA > rarityB
        end
        
        -- More mutations first
        local mutationsA = getMutationCount(a)
        local mutationsB = getMutationCount(b)
        return mutationsA > mutationsB
    end)
    
    return slotDataList
end


--[[
    Updates the display with current inventory data.
]]
local function refreshDisplay()
    if not slotsContainer then 
        -- Can happen if packet arrives before Init
        return 
    end
    
    -- Get individual items for display (no stacking)
    local itemData = getItemsForDisplay()
    log("[InventoryUI] refreshDisplay: inventoryData count: " .. #inventoryData .. " displayItems count: " .. #itemData)
    
    -- Reuse or create slots
    local requiredSlots = #itemData
    
    -- Create more slots if needed
    while #itemSlots < requiredSlots do
        -- Pass the stored slotTemplate if available
        local slot = ItemSlot.new(slotsContainer, slotTemplate :: any)
        slot.Frame.LayoutOrder = #itemSlots + 1
        
        -- Click handler
        local index = #itemSlots + 1
        slot.Frame.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or
               input.UserInputType == Enum.UserInputType.Touch then
                local data = itemSlots[index] and itemSlots[index].Data
                if data then
                    InventoryUI.OnItemClicked:Fire(data)
                    if infoPanel then
                        -- Find full inventory item data to pass to InfoPanel
                        local fullItem = nil
                        for _, item in inventoryData do
                            if item.Id == data.ItemIds[1] then
                                fullItem = item
                                break
                            end
                        end
                         
                        -- If it's a stack, we might need to construct a robust item representation
                        if not fullItem then
                             -- Construct temporary item from slot data for display
                             fullItem = {
                                 Id = data.ItemIds[1] or "",
                                 TemplateId = data.TemplateId,
                                 Type = data.Type :: any,
                                 Rarity = data.Rarity :: any,
                                 Metadata = data.Metadata
                             }
                        end
                        
                        infoPanel:Update(fullItem)
                    end
                end
            end
        end)
        
        -- Delete handler
        slot.OnDeleteClicked:Connect(function(slotItemData)
            local itemId = slotItemData.ItemIds[1]
            if itemId then
                log("[InventoryUI] Deleting item: " .. itemId)
                Packets.inventoryAction.send({
                    action = "DeleteItem",
                    itemId = itemId,
                })
            end
        end)
        
        table.insert(itemSlots, slot)
        janitor:Add(slot, "Destroy")
    end
    
    -- Update slot data and make draggable
    for i, slot in itemSlots do
        if i <= requiredSlots then
            local newData = itemData[i]
            local currentData = slot.Data
            
            -- Smart Diff: Check if data actually changed to avoid expensive SetData
            local changed = true
            if currentData 
                and currentData.TemplateId == newData.TemplateId 
                and currentData.Count == newData.Count
                and currentData.IsEquipped == newData.IsEquipped
                and currentData.MaybeDuped == newData.MaybeDuped
                and #currentData.ItemIds == #newData.ItemIds
                and currentData.ItemIds[1] == newData.ItemIds[1] then
                 
                 changed = false
            end
            
            if changed then
                slot:SetData(newData)
                
                -- Make draggable (remove old detector first)
                local oldDetector = slot.Frame:FindFirstChild("ItemDragDetector")
                if oldDetector then
                    oldDetector:Destroy()
                end
                
                -- Add drag capability if we have a screenGui
                if screenGui and newData then
                    local itemId = newData.ItemIds[1] or ""
                    
                    local dragData: DragDrop.DragData = {
                        ItemId = itemId,
                        TemplateId = newData.TemplateId,
                        Type = newData.Type,
                        Rarity = newData.Rarity,
                        SourceSlot = slot.Frame,
                        SourceToolbarSlot = newData.EquippedSlot, -- Pass equipped slot for move operations
                    }
                    DragDrop.MakeDraggable(slot.Frame, dragData, screenGui)
                end
            end
            
            slot.Frame.Visible = true
        else
            slot:SetData(nil)
            slot.Frame.Visible = false
        end
    end
end

--[[
    Handles incoming inventory sync from server.
]]
local function onInventorySync(data: any)
    inventoryData = {}
    toolbarSlots = {}
    dupedItems = {} -- Reset duped tracking
    
    -- [OPTIMIZED] Unpack grouped items from server
    -- Server sends groups to save bandwidth, we expand them back to flat list for Client use
    for _, group in data.groupedItems do
        local templateId = group.templateId
        local itemType = group.itemType :: Inventory.ItemType
        local rarity = if group.rarity ~= "" then group.rarity :: Inventory.RarityType? else nil
        local metadata = group.metadata
        
        for _, instance in group.instances do
            local item: InventoryItem = {
                Id = instance.id,
                TemplateId = templateId,
                Type = itemType,
                Rarity = rarity,
                Metadata = metadata,
            }
            table.insert(inventoryData, item)
        end
    end
    
    for slot, itemId in pairs(data.toolbarSlots) do
        toolbarSlots[slot] = itemId
    end
    
    refreshDisplay()
    
    -- Sync integrated toolbar immediately
    updateIntegratedToolbar()
    
    -- Refresh main HUD toolbar
    if Toolbar and Toolbar.Refresh then
        Toolbar.Refresh()
    end
end

--[[
    Handles incoming inventory update (add/remove).
]]
local function onInventoryUpdate(data: any)
    local action = data.action
    local itemData = data.item
    
    log("[InventoryUI] onInventoryUpdate: " .. action .. " item: " .. (itemData and itemData.templateId or "nil"))
    
    if action == "Add" then
        local item: InventoryItem = {
            Id = itemData.id,
            TemplateId = itemData.templateId,
            Type = itemData.itemType :: Inventory.ItemType,
            Rarity = if itemData.rarity ~= "" then itemData.rarity :: Inventory.RarityType? else nil,
            Metadata = itemData.metadata,
        }
        table.insert(inventoryData, item)
        
        -- Track duped status
        if itemData.maybeDuped then
            dupedItems[itemData.id] = true
        end
        
        log("[InventoryUI] Added item: " .. item.TemplateId .. " total items: " .. #inventoryData)
    elseif action == "Remove" then
        for i, item in inventoryData do
            if item.Id == itemData.id then
                table.remove(inventoryData, i)
                break
            end
        end
    end
    
    refreshDisplay()
    
    -- Refresh hotbar to reflect changes (e.g. removed items)
    task.delay(0.2, function()
        updateIntegratedToolbar()
        if Toolbar and Toolbar.Refresh then
            Toolbar.Refresh()
        end
    end)
end

--[[
    Handles incoming toolbar update (lightweight).
]]
local function onToolbarUpdate(data: any)
    toolbarSlots = {}
    for slot, itemId in pairs(data.toolbarSlots) do
        toolbarSlots[slot] = itemId
    end
    
    log("[InventoryUI] Toolbar updated via lightweight packet")
    
    -- Refresh hotbar (integrated and HUD)
    updateIntegratedToolbar()
    if Toolbar and Toolbar.Refresh then
        Toolbar.Refresh()
    end
    
    -- Smart refresh of inventory grid (will mostly be skipped due to diffing)
    refreshDisplay()
    
    if infoPanel and infoPanel.Refresh then
        infoPanel:Refresh()
    end
end

--[[
    Updates the integrated toolbar display to match the actual toolbar state.
    Shows tools from both inventory system and regular backpack.
]]
updateIntegratedToolbar = function()
    if #toolbarSlotFrames == 0 then 
        -- Can happen before Init
        return 
    end
    
    -- Use local authoritative data from packet
    local toolbarData = {}
    for i = 1, 9 do
        local itemId = toolbarSlots[i]
        local data = {
            SlotIndex = i,
            InventoryItemId = itemId,
            Tool = nil,
        }
        
        -- Try to find the actual tool if it exists in character or backpack (for Icon/Texture)
        -- But relying mainly on inventory data for logic
        if itemId then
             -- Find item in inventory data to get TemplateId/Config
             local invItem = nil
             for _, item in inventoryData do
                 if item.Id == itemId then
                     invItem = item
                     break
                 end
             end
             
             if invItem then
                 -- We have the inventory item, that's enough for display even if tool isn't spawned yet
                 data.Tool = {
                     Name = invItem.TemplateId,
                     TextureId = "", -- Will be resolved via Config in the loop below
                     GetAttribute = function(self, attr) 
                        return nil -- Mock to prevent crashes if code expects tool instance
                     end
                 } :: any
                 
                 -- Try to find real tool for extra data if needed
                 local player = Players.LocalPlayer
                 if player then
                     local backpack = player:FindFirstChild("Backpack")
                     local character = player.Character
                     
                     if backpack then
                         for _, t in backpack:GetChildren() do
                             if t:IsA("Tool") and t:GetAttribute("InventoryItemId") == itemId then
                                 data.Tool = t
                                 break
                             end
                         end
                     end
                     if character and data.Tool == nil then -- Check character if not found in backpack
                         for _, t in character:GetChildren() do
                             if t:IsA("Tool") and t:GetAttribute("InventoryItemId") == itemId then
                                 data.Tool = t
                                 break
                             end
                         end
                     end
                 end
             end
        end
        
        table.insert(toolbarData, data)
    end
    
    -- Register toolbar contents with DragDrop for swap detection
    local slotContents: {[number]: string?} = {}
    for i = 1, 9 do
        local data = toolbarData[i]
        slotContents[i] = if data and data.InventoryItemId then data.InventoryItemId else nil
    end
    DragDrop.RegisterToolbarContents(slotContents)
    
    for i, slotFrame in ipairs(toolbarSlotFrames) do
        local data = toolbarData[i]
        
        -- All elements are directly on the slot frame now
        -- No "Background" child check needed as per user request
        
        -- Get sub-elements
        local toolIcon = slotFrame:FindFirstChild("ToolIcon") :: ImageLabel?
        local hotkeyLabel = slotFrame:FindFirstChild("HotkeyLabel") :: TextLabel?
        local quantityLabel = slotFrame:FindFirstChild("QuantityLabel") :: TextLabel?
        local nameLabel = slotFrame:FindFirstChild("ToolNameLabel") :: TextLabel?
        local eventsLabel = slotFrame:FindFirstChild("EventsLabel") :: TextLabel?
        
        if data and data.Tool then
            local tool = data.Tool
            
            -- 1. RESOLVE DATA (Rarity, TemplateId, Config)
            local rarity: string? = nil
            local customColor: string? = nil
            local invTemplateId: string? = nil
            
            -- Try to get data from inventory link
            if data.InventoryItemId then
                for _, invItem in inventoryData do
                    if invItem.Id == data.InventoryItemId then
                        rarity = invItem.Rarity :: string?
                        invTemplateId = invItem.TemplateId
                        break
                    end
                end
            end
            
            -- Fallback rarity
            if not rarity or rarity == "" then
                rarity = tool:GetAttribute("Rarity") :: string?
            end
            
            -- Resolve Config (iC)
            local tId = invTemplateId or tool:GetAttribute("TemplateId") or tool.Name
            local iC: Configuration? = nil
            
            local config = ReplicatedStorage:FindFirstChild("Config")
            if config then
                 local items = config:FindFirstChild("Items")
                 if items then
                     local function quickSearch(parent: Instance): Configuration?
                         for _, child in parent:GetChildren() do
                             if child.Name == tId and child:IsA("Configuration") then
                                 return child
                             elseif child:IsA("Folder") then
                                 local found = quickSearch(child)
                                 if found then return found end
                             end
                         end
                         return nil
                     end
                     iC = quickSearch(items)
                 end
            end
            
            -- Get Custom Colors from Config
            if iC then
                customColor = iC:GetAttribute("CustomColor") :: string?
            end
            
            -- Fallback CustomColor from Tool
            if not customColor or customColor == "" then
                customColor = tool:GetAttribute("CustomColor") :: string?
            end

            -- 2. UPDATE UI ELEMENTS
            
            -- Update icon
            if toolIcon then
                local textureId = ""
                
                -- Priority: Config "Image" > Tool "TextureId"
                if iC then
                     textureId = iC:GetAttribute("Image") :: string? or ""
                end
                
                if textureId == "" then
                     textureId = tool.TextureId
                end
                
                if textureId and textureId ~= "" and not string.find(textureId, "://") then
                    textureId = "rbxassetid://" .. textureId
                end
                toolIcon.Image = if textureId and textureId ~= "" then textureId else "rbxassetid://6031763426"
                toolIcon.Visible = true
            end
            
            -- Update name
            if nameLabel then
                local toolDisplayName = tool:GetAttribute("DisplayName")
                nameLabel.Text = if toolDisplayName and toolDisplayName ~= "" then toolDisplayName else tool.Name
                nameLabel.Visible = true
            end
            
            -- Show stack count
            if quantityLabel then
                local stackCount = tool:GetAttribute("StackCount")
                if stackCount and stackCount > 1 then
                    quantityLabel.Text = "x" .. tostring(stackCount)
                    quantityLabel.Visible = true
                else
                    quantityLabel.Text = ""
                    quantityLabel.Visible = false
                end
            end
            
             -- Update EventsLabel
            if eventsLabel then
                local foundMutations = nil
                
                -- Check inventory data first
                if data.InventoryItemId then
                    for _, invItem in inventoryData do
                        if invItem.Id == data.InventoryItemId then
                            if invItem.Metadata and invItem.Metadata.Mutations then
                                foundMutations = invItem.Metadata.Mutations
                            end
                            break
                        end
                    end
                end
                
                -- Fallback to tool attribute
                if not foundMutations then
                    local mutJson = tool:GetAttribute("Mutations") :: string?
                    if mutJson and mutJson ~= "" then
                         local HttpService = game:GetService("HttpService")
                         pcall(function()
                             foundMutations = HttpService:JSONDecode(mutJson)
                         end)
                    end
                end

                 if foundMutations then
                     local count = 0
                     for _ in pairs(foundMutations) do
                         count = count + 1
                     end
                     if count > 0 then
                        eventsLabel.Text = tostring(count) .. " " .. (count == 1 and "Event" or "Events")
                        eventsLabel.Visible = true
                     else
                        eventsLabel.Text = ""
                        eventsLabel.Visible = false
                     end
                 else
                     eventsLabel.Text = ""
                     eventsLabel.Visible = false
                 end
            end

            -- Update RarityLabel
            local rarityLabel = slotFrame:FindFirstChild("RarityLabel") :: TextLabel?
            if rarityLabel then
                rarityLabel.Text = rarity or "Common"
                rarityLabel.Visible = true
                
                local textStyle = nil
                if iC then
                     textStyle = iC:GetAttribute("CustomTextColor") :: string?
                end
                
                if not textStyle then
                     textStyle = tool:GetAttribute("CustomTextColor") :: string?
                end
                
                if not textStyle then
                     textStyle = RarityConfig.GetTextStyle(rarity or "Common")
                end
                
                ColorSystem.ApplyToText(rarityLabel, textStyle)
            end

            -- Apply Background visuals
            local style = customColor
            if not style or style == "" then
                style = RarityConfig.GetBackgroundStyle(rarity)
            end
            
            ColorSystem.ApplyToBackground(slotFrame, style)
            
            -- Make this toolbar slot draggable (to remove from toolbar) if from inventory
            if screenGui and data.InventoryItemId then
                DragDrop.MakeToolbarSlotDraggable(
                    slotFrame,
                    i,
                    data.InventoryItemId,
                    tool.Name,
                    screenGui
                )
            end
        else
            -- Empty slot
            if toolIcon then
                toolIcon.Image = ""
                toolIcon.Visible = false
            end
            if nameLabel then
                nameLabel.Text = ""
                nameLabel.Visible = false
            end
            if quantityLabel then
                quantityLabel.Text = ""
                quantityLabel.Visible = false
            end
            if eventsLabel then
                eventsLabel.Text = ""
                eventsLabel.Visible = false
            end
            
            local rarityLabel = slotFrame:FindFirstChild("RarityLabel") :: TextLabel?
            if rarityLabel then
                rarityLabel.Visible = false
            end
            
            ColorSystem.ApplyToBackground(slotFrame, nil)
            
            -- Remove drag detector if it exists
            local dragDetector = slotFrame:FindFirstChild("ToolbarDragDetector")
            if dragDetector then
                dragDetector:Destroy()
            end

        end
        
        -- Always show hotkey
        if hotkeyLabel then
            hotkeyLabel.Text = tostring(i)
            hotkeyLabel.Visible = true
        end
        

    end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--[[
    Toggles inventory visibility.
    
    @param open - True to open, false to close, nil to toggle
]]
function InventoryUI.Toggle(open: boolean?)
    if open == nil then
        open = not isOpen
    end
    
    isOpen = open
    
    if hubFrame then
        hubFrame.Visible = isOpen
    end
    
    -- Hide/show main toolbar when inventory opens/closes
    if Toolbar then
        Toolbar.SetVisible(not isOpen)
    end
    
    -- Update integrated toolbar display when opening
    if isOpen then
        updateIntegratedToolbar()
    end
    
    InventoryUI.OnToggled:Fire(isOpen)
end

--[[
    Returns whether inventory is open.
]]
function InventoryUI.IsOpen(): boolean
    return isOpen
end

--[[
    Gets the current inventory data.
]]
function InventoryUI.GetInventory(): {InventoryItem}
    return inventoryData
end

--[[
    Gets toolbar slot assignments.
]]
function InventoryUI.GetToolbarSlots(): {[number]: string}
    return toolbarSlots
end

--[[
    Sends a toolbar assignment action to server.
]]
function InventoryUI.AssignToToolbar(itemId: string, slot: number)
    Packets.inventoryAction.send({
        action = "AssignToolbar",
        itemId = itemId,
        slot = slot,
    })
end

--[[
    Sends a toolbar removal action to server.
]]
function InventoryUI.RemoveFromToolbar(slot: number)
    Packets.inventoryAction.send({
        action = "RemoveToolbar",
        itemId = "",
        slot = slot,
    })
end

--[[
    Sends a toolbar swap action to server.
]]
function InventoryUI.SwapToolbarSlots(slot1: number, slot2: number)
    Packets.inventoryAction.send({
        action = "SwapToolbar",
        itemId = "",
        slot = slot1,
        slot2 = slot2,
    })
end

--[[
    Initializes the inventory UI by binding to existing instances.
    
    New Hierarchy:
    Inventory [ScreenGui]
    └── Hub [Frame]
        ├── ItemSlots [Frame]
        │   └── ListLayout [Frame] (Slot1..Slot9)
        ├── Base [Frame]
        │   ├── Close [ImageButton]
        │   └── Panel [ScrollingFrame]
        └── UIScale
    
    @param context - ClientContext with PlayerGui
]]
function InventoryUI.Init(context: any)
    local playerGui = context.PlayerGui :: PlayerGui
    
    -- Find existing UI (new hierarchy: "Inventory" instead of "InventoryUI")
    local existingScreenGui = playerGui:WaitForChild("Inventory", 10)
    if not existingScreenGui then
        warn("[InventoryUI] Failed to find Inventory ScreenGui in PlayerGui")
        return
    end
    screenGui = existingScreenGui :: ScreenGui
    
    -- Hub is the main frame
    hubFrame = screenGui:WaitForChild("Hub") :: Frame
    hubFrame.Visible = false -- Start hidden
    
    -- Bind Panel (main inventory grid)
    local base = hubFrame:WaitForChild("Base") :: Frame
    slotsContainer = base:WaitForChild("Panel") :: ScrollingFrame
    
    -- Initialize InfoPanel
    local infoPanelFrame = base:WaitForChild("InfoPanel", 5)
    if infoPanelFrame then
        infoPanel = InfoPanel.new(infoPanelFrame)
        -- Set callback for getting toolbar slots
        InfoPanel.GetToolbarSlots = function()
            return toolbarSlots
        end
        -- Set callback for when equip state changes (refresh toolbar)
        InfoPanel.OnEquipChanged = function()
            updateIntegratedToolbar()
            refreshDisplay()
            if Toolbar and Toolbar.Refresh then
                Toolbar.Refresh()
            end
        end
    else
        warn("[InventoryUI] InfoPanel frame not found in Hub.Base")
    end
    
    -- Setup NavBar filter buttons
    local navBar = base:FindFirstChild("NavBar")
    if navBar then
        -- Map button names to filter values (ItemType attribute values)
        local filterMap = {
            ["Weapons"] = "Gun",
            ["Grenades"] = "Grenade",
            ["Potions"] = "Potion",
            ["Unfiltered"] = "Unfiltered",
        }
        
        for buttonName, filterValue in pairs(filterMap) do
            local button = navBar:FindFirstChild(buttonName)
            if button and (button:IsA("TextButton") or button:IsA("ImageButton")) then
                button.Activated:Connect(function()
                    currentFilter = filterValue
                    refreshDisplay()
                    log("[InventoryUI] Filter set to: " .. filterValue)
                    
                    -- Update button visual states (optional: highlight active filter)
                    for name, _ in pairs(filterMap) do
                            local btn = navBar:FindFirstChild(name)
                        if btn then
                            -- Set visual feedback - always white as requested (no green highlight)
                            if btn:IsA("TextButton") then
                                btn.TextColor3 = Color3.fromRGB(255, 255, 255)
                            elseif btn:IsA("ImageButton") then
                                btn.ImageColor3 = Color3.fromRGB(255, 255, 255)
                            end
                        end
                    end
                end)
            end
        end
        log("[InventoryUI] NavBar filter buttons connected")
    else
        log("[InventoryUI] NavBar not found in Hub.Base")
    end
    
    -- Load slot template from Config
    local Config = ReplicatedStorage:WaitForChild("Config", 5)
    if Config then
        local inventoryConfig = Config:WaitForChild("Inventory", 2)
        if inventoryConfig then
            local templates = inventoryConfig:WaitForChild("Templates", 2)
            if templates then
                local tmpl = templates:WaitForChild("ItemSlot", 2)
                if tmpl then
                    slotTemplate = tmpl
                    log("[InventoryUI] Loaded ItemSlot template from Config.Inventory.Templates")
                end
            end
        end
    end
    
    if not slotTemplate then
        warn("[InventoryUI] Failed to load ItemSlot template from Config! Checking Panel fallback...")
        -- Fallback: Check for slot template in Panel
        local existingTemplate = slotsContainer:FindFirstChild("Template") 
                              or slotsContainer:FindFirstChildWhichIsA("ImageLabel")
                              
        if existingTemplate and existingTemplate:IsA("ImageLabel") then
            log("[InventoryUI] Found slot template in Panel: " .. existingTemplate.Name)
            slotTemplate = existingTemplate:Clone()
            existingTemplate.Visible = false
        end
    end
    
    -- Clean up container (remove placeholders except Template)
    for _, child in slotsContainer:GetChildren() do
        if child:IsA("ImageLabel") and child.Name ~= "Template" then
            child:Destroy()
        elseif child:IsA("Frame") then
            child:Destroy()
        end
    end
    
    -- Bind Close Button (Base.Close)
    local closeBtn = base:FindFirstChild("Close") :: GuiButton?
    if closeBtn then
        closeBtn.Activated:Connect(function()
            InventoryUI.Toggle(false)
        end)
        log("[InventoryUI] Connected to Close button")
    else
        warn("[InventoryUI] Close button not found at Hub.Base.Close")
    end
    
    -- Bind Integrated Toolbar Area (ItemSlots.ListLayout)
    local itemSlotsArea = hubFrame:WaitForChild("ItemSlots") :: Frame
    local listLayout = itemSlotsArea:WaitForChild("ListLayout") :: Frame
    
    -- Load hotbar slot template from Config
    local hotbarSlotTemplate: GuiObject? = nil
    -- Config already loaded above
    if Config then
        local inventoryConfig = Config:WaitForChild("Inventory", 2)
        if inventoryConfig then
            local templates = inventoryConfig:WaitForChild("Templates", 2)
            if templates then
                local tmpl = templates:FindFirstChild("HOTBAR_SlotTemplate") 
                          or templates:FindFirstChild("ToolHotbarTemplate")
                if tmpl then
                    hotbarSlotTemplate = tmpl :: GuiObject
                    log("[InventoryUI] Loaded HOTBAR_SlotTemplate from Config.Inventory.Templates")
                end
            end
        end
    end
    
    if not hotbarSlotTemplate then
        warn("[InventoryUI] Failed to load HOTBAR_SlotTemplate from Config!")
    end
    
    -- Clone template 9 times into ListLayout
    toolbarSlotFrames = {}
    for i = 1, 9 do
        local slotClone: GuiObject
        
        if hotbarSlotTemplate then
            slotClone = hotbarSlotTemplate:Clone()
        else
            -- Fallback: create minimal frame
            slotClone = Instance.new("Frame")
            slotClone.Size = UDim2.fromOffset(80, 80)
            slotClone.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
        end
        
        slotClone.Name = "Slot" .. i
        slotClone.LayoutOrder = i
        slotClone.Parent = listLayout
        
        -- Everything is inside Background
        local background = slotClone:FindFirstChild("Background") :: GuiObject?
        if background then
            -- Set up hotkey label
            local hotkeyLabel = background:FindFirstChild("HotkeyLabel") :: TextLabel?
            if hotkeyLabel then
                hotkeyLabel.Text = tostring(i)
                hotkeyLabel.Visible = true
            end
            
            -- Clear initial icon/name
            local toolIcon = background:FindFirstChild("ToolIcon") :: ImageLabel?
            if toolIcon then
                toolIcon.Image = ""
                toolIcon.Visible = false
            end
            
            local nameLabel = background:FindFirstChild("ToolNameLabel") :: TextLabel?
            if nameLabel then
                nameLabel.Text = ""
                nameLabel.Visible = false
            end
            
            -- Reset background gradient to default
            local gradient = background:FindFirstChild("UIGradient") :: UIGradient?
            if gradient then
                gradient.Color = ColorSequence.new(Color3.fromRGB(40, 40, 50))
            end
            
            -- Reset border stroke to white
            local borderStroke = background:FindFirstChild("BorderStroke") :: UIStroke?
            if not borderStroke then
                borderStroke = background:FindFirstChildWhichIsA("UIStroke") :: UIStroke?
            end
            if borderStroke then
                borderStroke.Color = Color3.fromRGB(255, 255, 255)
            end
        end
        
        -- Add click handler to update InfoPanel when hotbar slot is clicked
        local slotIndex = i
        slotClone.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or
               input.UserInputType == Enum.UserInputType.Touch then
                -- Find item in this toolbar slot
                local itemId = toolbarSlots[slotIndex]
                if itemId and itemId ~= "" then
                    -- Find full inventory item data
                    local fullItem = nil
                    for _, item in inventoryData do
                        if item.Id == itemId then
                            fullItem = item
                            break
                        end
                    end
                    
                    if fullItem and infoPanel then
                        infoPanel:Update(fullItem)
                    end
                end
            end
        end)
        
        table.insert(toolbarSlotFrames, slotClone :: Frame)
    end
    
    if #toolbarSlotFrames > 0 then
        DragDrop.RegisterToolbarSlots(toolbarSlotFrames)
        log("[InventoryUI] Created and registered " .. #toolbarSlotFrames .. " toolbar slots from template")
    end
    
    -- Get Toolbar reference (from context if available, or require it)
    if context.Toolbar then
        Toolbar = context.Toolbar
    else
        -- Try to require Toolbar module
        local Client = script.Parent.Parent
        if Client:FindFirstChild("Toolbar") then
            Toolbar = require(Client.Toolbar)
        end
    end
    
    -- Setup packet listeners
    Packets.inventorySync.listen(onInventorySync)
    Packets.inventoryUpdate.listen(onInventoryUpdate)
    Packets.toolbarUpdate.listen(onToolbarUpdate)
    
    -- Handle drag & drop to toolbar
    janitor:Add(DragDrop.OnItemDropped:Connect(function(result: DragDrop.DropResult)
        if result.Success and result.ToolbarSlotIndex then
            -- Skip if dropping on the same slot (no-op)
            if result.ItemData.SourceToolbarSlot == result.ToolbarSlotIndex then
                log("[InventoryUI] Dropped on same slot, ignoring")
                return
            end
            
            -- If coming from another toolbar slot, remove it first
            if result.ItemData.SourceToolbarSlot then
                InventoryUI.RemoveFromToolbar(result.ItemData.SourceToolbarSlot)
            end
            -- Send assignment to server
            InventoryUI.AssignToToolbar(result.ItemData.ItemId, result.ToolbarSlotIndex)
            log("[InventoryUI] Assigned " .. result.ItemData.TemplateId .. " to toolbar slot " .. result.ToolbarSlotIndex)
            -- Refresh integrated toolbar display after a short delay (wait for server to process)
            task.delay(0.2, function()
                updateIntegratedToolbar()
            end)
        end
    end))
    
    -- Handle removing items from toolbar (dragged to inventory)
    janitor:Add(DragDrop.OnToolbarItemRemoved:Connect(function(slotIndex: number, _itemId: string)
        InventoryUI.RemoveFromToolbar(slotIndex)
        log("[InventoryUI] Removed tool from toolbar slot " .. slotIndex)
        -- Refresh display after removal
        task.delay(0.2, function()
            updateIntegratedToolbar()
        end)
    end))
    
    -- Handle swapping toolbar items
    janitor:Add(DragDrop.OnToolbarSwap:Connect(function(slot1: number, slot2: number)
        InventoryUI.SwapToolbarSlots(slot1, slot2)
        log("[InventoryUI] Swapped toolbar slots " .. slot1 .. " <-> " .. slot2)
        -- Refresh display after swap
        task.delay(0.2, function()
            updateIntegratedToolbar()
        end)
    end))
    
    -- Handle item selection (info panel disabled for now)
    janitor:Add(InventoryUI.OnItemClicked:Connect(function(itemData: ItemSlotData)
        log("[InventoryUI] Item clicked: " .. itemData.TemplateId)
        -- Info panel implementation removed for now
    end))
    
    -- Connect to inventory button (Async to avoid blocking Init)
    task.spawn(function()
        local baseUI = playerGui:WaitForChild("Base", 10)
        if not baseUI then
            warn("[InventoryUI] Base UI not found in PlayerGui")
            return
        end

        local hid = baseUI:WaitForChild("HID", 10)
        if not hid then return end
        
        local left = hid:WaitForChild("Left", 10)
        if not left then return end
        
        local buttons = left:WaitForChild("Buttons", 10)
        if not buttons then return end
        
        local inventoryButton = buttons:WaitForChild("Inventory", 10) :: GuiButton
        if inventoryButton then
            inventoryButton.Activated:Connect(function()
                log("[InventoryUI] Inventory button clicked")
                InventoryUI.Toggle()
            end)
            log("[InventoryUI] Connected to inventory button")
        else
            warn("[InventoryUI] Inventory button not found at Base.HID.Left.Buttons.Inventory")
        end
    end)
    
    log("[InventoryUI] Initialized with new Inventory/Hub hierarchy!")
end

--[[
    Cleanup.
]]
function InventoryUI.Destroy()
    DragDrop.Cleanup()
    janitor:Destroy()
    if hubFrame then
        hubFrame:Destroy()
    end
end

return InventoryUI

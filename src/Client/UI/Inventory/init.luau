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

local Inventory = require(Shared:WaitForChild("Inventory")) -- For types only, core logic moved to DisplayUtils
local Packets = require(Shared:WaitForChild("Packets"))
local _RarityConfig = require(Shared:WaitForChild("Rarity"):WaitForChild("RarityConfig")) -- Used in DisplayUtils
local ColorSystem = require(Shared:WaitForChild("Inventory"):WaitForChild("ColorSystem"))
local ItemUtils = require(Shared:WaitForChild("Inventory"):WaitForChild("ItemUtils"))
local Logger = require(Shared:WaitForChild("Inventory"):WaitForChild("Logger"))

local ItemSlot = require(script.ItemSlot)
local DragDrop = require(script.DragDrop)
local InventoryStore = require(script.InventoryStore)
local ToolbarActions = require(script.ToolbarActions)
local SlotRenderer = require(script.SlotRenderer)
local DisplayUtils = require(script.DisplayUtils)
local InventoryVisibilityManager = require(script.InventoryVisibilityManager)

-- Use Logger for all logging
local function log(message: string)
    Logger.log("InventoryUI", message)
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

-- Use ItemUtils for display name (replaces 30-line duplicate function)
local function _getDisplayName(templateId: string): string
    return ItemUtils.GetDisplayName(templateId)
end

-- getItemType moved to DisplayUtils.GetItemType()

--[[
    Converts inventory items to slot display data.
    Uses DisplayUtils for filtering, grouping, and sorting.
]]
local function getItemsForDisplay(): {ItemSlotData}
    return DisplayUtils.GetItemsForDisplay(
        inventoryData,
        toolbarSlots,
        dupedItems,
        currentFilter
    )
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
                ToolbarActions.DeleteItem(itemId)
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
                        SourceSlot = slot.Frame :: Frame, -- Fix type error
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
    Updates the integrated toolbar display to match the actual toolbar state.
    Shows tools from both inventory system and regular backpack.
]]
updateIntegratedToolbar = function()
    if #toolbarSlotFrames == 0 then 
        -- Can happen before Init
        return 
    end
    
    -- Register toolbar contents with DragDrop for swap detection
    local slotContents: {[number]: string?} = {}
    for i = 1, 9 do
        slotContents[i] = toolbarSlots[i]
    end
    DragDrop.RegisterToolbarContents(slotContents)
    
    for i, slotFrame in ipairs(toolbarSlotFrames) do
        local itemId = toolbarSlots[i]
        
        if itemId then
            -- Find item in inventory data using InventoryStore O(1) lookup
            local invItem = InventoryStore.FindById(itemId)
            
            if invItem then
                -- Build render data from inventory item
                local renderData: SlotRenderer.SlotRenderData = {
                    TemplateId = invItem.TemplateId,
                    Rarity = invItem.Rarity :: string?,
                    Count = 1, -- Toolbar slots don't show stacks
                    IsEquipped = true,
                    EquippedSlot = i,
                    Metadata = invItem.Metadata,
                }
                
                -- Try to get stack count from actual tool if spawned
                local player = Players.LocalPlayer
                if player then
                    local tool = ItemUtils.FindToolInstance(player, itemId)
                    
                    if tool then
                        local stackCount = tool:GetAttribute("StackCount") :: number?
                        if stackCount and stackCount > 1 then
                            renderData.Count = stackCount
                        end
                    end
                end
                
                -- Use SlotRenderer for all UI updates
                SlotRenderer.RenderSlot(slotFrame, renderData)
                
                -- Setup drag-drop for inventory items
                if screenGui then
                    DragDrop.MakeToolbarSlotDraggable(
                        slotFrame,
                        i,
                        itemId,
                        invItem.TemplateId,
                        screenGui
                    )
                end
            else
                -- Item ID but not in inventory (shouldn't happen but handle gracefully)
                SlotRenderer.ClearSlot(slotFrame)
            end
        else
            -- Empty slot
            SlotRenderer.ClearSlot(slotFrame)
            
            -- Remove drag detector if it exists
            local dragDetector = slotFrame:FindFirstChild("ToolbarDragDetector")
            if dragDetector then
                dragDetector:Destroy()
            end
        end
        
        -- Always show hotkey using SlotRenderer helper
        SlotRenderer.SetHotkey(slotFrame, i)
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
    
    -- PERFORMANCE: Pause/resume all animations based on visibility
    if isOpen then
        -- Resume animations when opening
        ColorSystem.ResumeAll()
        InventoryVisibilityManager.ResumeAll()
        updateIntegratedToolbar()
    else
        -- Pause animations when closing to save CPU
        ColorSystem.PauseAll()
        InventoryVisibilityManager.PauseAll()
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
    ToolbarActions.AssignToToolbar(itemId, slot)
end

--[[
    Sends a toolbar removal action to server.
]]
function InventoryUI.RemoveFromToolbar(slot: number)
    ToolbarActions.RemoveFromToolbar(slot)
end

--[[
    Sends a toolbar swap action to server.
]]
function InventoryUI.SwapToolbarSlots(slot1: number, slot2: number)
    ToolbarActions.SwapToolbarSlots(slot1, slot2)
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
    
    -- Get Toolbar reference (from context if available, or require it from same folder)
    if context.Toolbar then
        Toolbar = context.Toolbar
    else
        -- Toolbar is now in the same folder (Inventory)
        Toolbar = require(script.Toolbar)
    end
    
    -- Setup packet listeners (Delegation only)
    Packets.inventorySync.listen(function(data)
        InventoryStore.HandleSync(data)
    end)
    
    Packets.inventoryUpdate.listen(function(data)
        InventoryStore.HandleUpdate(data)
    end)
    
    Packets.inventoryBatchUpdate.listen(function(data)
        InventoryStore.HandleBatchUpdate(data)
    end)
    
    Packets.toolbarUpdate.listen(function(data)
        InventoryStore.HandleToolbarUpdate(data)
    end)
    
    -- Reactive UI Updates via Signals
    janitor:Add(InventoryStore.OnSync:Connect(function(newInventory, newToolbarSlots)
        log("[InventoryUI] OnSync received")
        inventoryData = newInventory
        toolbarSlots = newToolbarSlots
        dupedItems = InventoryStore.GetDupedItems()
        
        refreshDisplay()
        updateIntegratedToolbar()
        if Toolbar and Toolbar.Refresh then
            Toolbar.Refresh()
        end
    end))
    
    janitor:Add(InventoryStore.OnUpdate:Connect(function(action, itemData)
        log("[InventoryUI] OnUpdate received: " .. action)
        -- Update local state
        inventoryData = InventoryStore.GetInventory()
        dupedItems = InventoryStore.GetDupedItems()
        
        refreshDisplay()
        
        -- Also refresh toolbar in case an equipped item was removed/modified
        updateIntegratedToolbar()
        if Toolbar and Toolbar.Refresh then
            Toolbar.Refresh()
        end
    end))
    
    janitor:Add(InventoryStore.OnToolbarUpdate:Connect(function(newToolbarSlots)
        log("[InventoryUI] OnToolbarUpdate received")
        toolbarSlots = newToolbarSlots
        
        -- Optimized: Only refresh toolbar, skip full grid refresh
        updateIntegratedToolbar()
        refreshDisplay() -- Fix: Refresh grid to show/hide "1", "2", etc labels
        if Toolbar and Toolbar.Refresh then
            Toolbar.Refresh()
        end
        
        if infoPanel and infoPanel.Refresh then
            infoPanel:Refresh()
        end
    end))
    
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
            -- UI will update reactively when server sends ToolbarUpdate
        end
    end))
    
    -- Handle removing items from toolbar (dragged to inventory)
    janitor:Add(DragDrop.OnToolbarItemRemoved:Connect(function(slotIndex: number, _itemId: string)
        InventoryUI.RemoveFromToolbar(slotIndex)
        log("[InventoryUI] Removed tool from toolbar slot " .. slotIndex)
        -- UI will update reactively when server sends ToolbarUpdate
    end))
    
    -- Handle swapping toolbar items
    janitor:Add(DragDrop.OnToolbarSwap:Connect(function(slot1: number, slot2: number)
        InventoryUI.SwapToolbarSlots(slot1, slot2)
        log("[InventoryUI] Swapped toolbar slots " .. slot1 .. " <-> " .. slot2)
        -- UI will update reactively when server sends ToolbarUpdate
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
    
    -- Request initial inventory data
    log("[InventoryUI] Requesting initial inventory data...")
    Packets.requestInventory.send({})
    
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

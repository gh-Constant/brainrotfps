--!strict
--[[
    Inventory UI Controller
    Manages the inventory panel UI.
    
    Features:
    - Grid layout of item slots with stacking
    - Toggle visibility from inventory button
    - Syncs with server via ByteNet
    - ViewportFrame 3D model display
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
local ItemSlot = require(script.ItemSlot)
local DragDrop = require(script.DragDrop)

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
local inventoryFrame: Frame? = nil
local slotsContainer: ScrollingFrame? = nil
local itemSlots: {ItemSlot.ItemSlot} = {}
local inventoryData: {InventoryItem} = {}
local toolbarSlots: {[number]: string} = {}
local dupedItems: {[string]: boolean} = {} -- itemId -> maybeDuped
local toolbarSlotFrames: {Frame} = {}
local screenGui: ScreenGui? = nil
local janitor: Janitor = Janitor.new()
local slotTemplate: Frame? = nil -- Added slot template

-- Info Panel State
local infoTitle: TextLabel? = nil
local infoIcon: ImageLabel? = nil
local infoDesc: TextLabel? = nil
local infoItemId: TextLabel? = nil -- Item ID display
local consumeButton: GuiButton? = nil -- Consume button
local _infoStats: Frame? = nil
local _selectedItem: ItemSlotData? = nil

-- Events
InventoryUI.OnItemClicked = Signal.new()
InventoryUI.OnToggled = Signal.new()

-- UI Constants
-- (Removed as we are using existing UI)

--------------------------------------------------------------------------------
-- Private Functions
--------------------------------------------------------------------------------

-- Forward declaration
local updateIntegratedToolbar 

--[[
    Gets the display name for an item.
    Checks Config for "DisplayName" attribute, falls back to templateId.
]]
local function getDisplayName(templateId: string): string
    local config = ReplicatedStorage:FindFirstChild("Config")
    if config then
        local items = config:FindFirstChild("Items")
        if items then
            local itemConfig = items:FindFirstChild(templateId)
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

--[[
    Consumes an item (removes one from stack).
]]
local function consumeItem(itemData: ItemSlotData)
    local itemId = itemData.ItemIds[1]
    if not itemId then
        warn("[Inventory] Cannot consume item: no item ID")
        return
    end
    
    print(string.format("[Inventory] Consuming item: %s (ID: %s)", itemData.TemplateId, itemId))
    
    -- Send consume packet to server (removes one item from inventory)
    Packets.inventoryAction.send({ 
        action = "Consume", 
        itemId = itemId,
    })
end

--[[
    Updates the Info Panel with item details.
]]
local function updateInfoPanel(itemData: ItemSlotData?)
    if not infoTitle or not infoIcon or not infoDesc then return end
    
    if not itemData then
        -- Default/Empty State
        infoTitle.Text = "Select an Item"
        infoIcon.Image = "rbxassetid://6031763426" -- Default icon
        infoDesc.Text = "Click on an item to see more details."
        infoIcon.ImageTransparency = 0.5
        _selectedItem = nil
        return
    end
    
    -- Populate Data
    infoTitle.Text = getDisplayName(itemData.TemplateId)
    infoIcon.Image = "rbxassetid://6031763426" -- Placeholder
    infoIcon.ImageTransparency = 0
    
    -- Generate description based on type/rarity
    local desc = string.format("Type: <font color='#88ccff'>%s</font>\n", itemData.Type)
    desc = desc .. string.format("Rarity: <font color='#ccaaff'>%s</font>\n", itemData.Rarity or "Common")
    
    if itemData.Count > 1 then
        desc = desc .. string.format("Count: <b>%d</b>\n", itemData.Count)
    end
    
    infoDesc.Text = desc
    _selectedItem = itemData
    
    -- Update Item ID display
    if infoItemId then
        infoItemId.Text = itemData.ItemIds[1] or ""
    end
    
    -- Update Consume button visibility
    if consumeButton then
        consumeButton.Visible = (itemData.Type == "Consumable")
    end
end

--[[
    Converts inventory items to slot display data.
    Stackable items are grouped together, non-stackable items shown individually.
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
    
    -- Separate stackable and non-stackable items
    local stackableItems: {InventoryItem} = {}
    local nonStackableItems: {InventoryItem} = {}
    
    for _, item in inventoryData do
        if Inventory.IsStackable(item.TemplateId) then
            table.insert(stackableItems, item)
        else
            table.insert(nonStackableItems, item)
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
            MaybeDuped = anyDuped,
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
        })
    end
    
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
    print("[InventoryUI] refreshDisplay: inventoryData count:", #inventoryData, "displayItems count:", #itemData)
    
    -- Reuse or create slots
    local requiredSlots = #itemData
    
    -- Create more slots if needed
    while #itemSlots < requiredSlots do
        -- Pass the stored slotTemplate if available
        local slot = ItemSlot.new(slotsContainer, slotTemplate)
        slot.Frame.LayoutOrder = #itemSlots + 1
        
        -- Click handler
        local index = #itemSlots + 1
        slot.Frame.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or
               input.UserInputType == Enum.UserInputType.Touch then
                local data = itemSlots[index] and itemSlots[index].Data
                if data then
                    InventoryUI.OnItemClicked:Fire(data)
                end
            end
        end)
        
        -- Delete handler
        slot.OnDeleteClicked:Connect(function(itemData)
            local itemId = itemData.ItemIds[1]
            if itemId then
                print("[InventoryUI] Deleting item:", itemId)
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
            local data = itemData[i]
            slot:SetData(data)
            slot.Frame.Visible = true
            
            -- Make draggable (remove old detector first)
            local oldDetector = slot.Frame:FindFirstChild("ItemDragDetector")
            if oldDetector then
                oldDetector:Destroy()
            end
            
            -- Add drag capability if we have a screenGui
            if screenGui and data then
                -- Each slot now has exactly one item (no stacking)
                local itemId = data.ItemIds[1] or ""
                
                local dragData: DragDrop.DragData = {
                    ItemId = itemId,
                    TemplateId = data.TemplateId,
                    Type = data.Type,
                    Rarity = data.Rarity,
                    SourceSlot = slot.Frame,
                    SourceToolbarSlot = data.EquippedSlot, -- Pass equipped slot for move operations
                }
                DragDrop.MakeDraggable(slot.Frame, dragData, screenGui)
            end
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
    
    for _, itemData in data.items do
        local item: InventoryItem = {
            Id = itemData.id,
            TemplateId = itemData.templateId,
            Type = itemData.itemType :: Inventory.ItemType,
            Rarity = if itemData.rarity ~= "" then itemData.rarity :: Inventory.RarityType? else nil,
            Metadata = nil,
        }
        table.insert(inventoryData, item)
        
        -- Track duped status
        if itemData.maybeDuped then
            dupedItems[itemData.id] = true
        end
    end
    
    for slot, itemId in pairs(data.toolbarSlots) do
        toolbarSlots[slot] = itemId
    end
    
    refreshDisplay()
end

--[[
    Handles incoming inventory update (add/remove).
]]
local function onInventoryUpdate(data: any)
    local action = data.action
    local itemData = data.item
    
    print("[InventoryUI] onInventoryUpdate:", action, "item:", itemData and itemData.templateId or "nil")
    
    if action == "Add" then
        local item: InventoryItem = {
            Id = itemData.id,
            TemplateId = itemData.templateId,
            Type = itemData.itemType :: Inventory.ItemType,
            Rarity = if itemData.rarity ~= "" then itemData.rarity :: Inventory.RarityType? else nil,
            Metadata = nil,
        }
        table.insert(inventoryData, item)
        
        -- Track duped status
        if itemData.maybeDuped then
            dupedItems[itemData.id] = true
        end
        
        print("[InventoryUI] Added item:", item.TemplateId, "total items:", #inventoryData)
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
    end)
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
    
    -- Get toolbar data from Toolbar module if available
    local toolbarData = nil
    if Toolbar and Toolbar.GetToolbarData then
        toolbarData = Toolbar.GetToolbarData()
        print("[InventoryUI] Got toolbar data:", #toolbarData, "slots")
    else
        print("[InventoryUI] Toolbar module not available, checking backpack directly")
        -- Fallback: get tools directly from backpack
        local player = Players.LocalPlayer
        local backpack = player:FindFirstChild("Backpack")
        local character = player.Character
        
        -- Initialize all 9 slots as empty
        toolbarData = {}
        for i = 1, 9 do
            table.insert(toolbarData, {
                SlotIndex = i,
                Tool = nil,
                InventoryItemId = nil,
            })
        end
        
        -- Get tools from backpack and place them in their assigned slots
        if backpack then
            for _, tool in backpack:GetChildren() do
                if tool:IsA("Tool") then
                    local assignedSlot = tool:GetAttribute("ToolbarSlot")
                    if assignedSlot and assignedSlot >= 1 and assignedSlot <= 9 then
                        toolbarData[assignedSlot] = {
                            SlotIndex = assignedSlot,
                            Tool = tool,
                            InventoryItemId = tool:GetAttribute("InventoryItemId"),
                        }
                    end
                end
            end
        end
        
    -- Get equipped tool from character and place in assigned slot
        if character then
            for _, tool in character:GetChildren() do
                if tool:IsA("Tool") then
                    local assignedSlot = tool:GetAttribute("ToolbarSlot")
                    if assignedSlot and assignedSlot >= 1 and assignedSlot <= 9 then
                        toolbarData[assignedSlot] = {
                            SlotIndex = assignedSlot,
                            Tool = tool,
                            InventoryItemId = tool:GetAttribute("InventoryItemId"),
                        }
                    end
                end
            end
        end
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
        
        -- Clear existing content (except hotkey label and border/corner)
        -- We only clear specific types we created to avoid destroying user's layout elements?
        -- For now, sticking to the current logic but ensuring new elements are on TOP.
        for _, child in slotFrame:GetChildren() do
            if child.Name ~= "Hotkey" and not child:IsA("UICorner") and not child:IsA("UIStroke") and not child:IsA("UIGradient") then
                child:Destroy()
            end
        end
        
        if data and data.Tool then
            local tool = data.Tool
            
            -- Create icon for the tool
            local icon = Instance.new("ImageLabel")
            icon.Name = "ToolIcon"
            icon.Size = UDim2.fromScale(0.7, 0.7)
            icon.Position = UDim2.fromScale(0.5, 0.5)
            icon.AnchorPoint = Vector2.new(0.5, 0.5)
            icon.BackgroundTransparency = 1
            
            -- Handle TextureId
            local textureId = tool.TextureId
            if textureId and textureId ~= "" and not string.find(textureId, "://") then
                textureId = "rbxassetid://" .. textureId
            end
            icon.Image = if textureId and textureId ~= "" then textureId else "rbxassetid://6031763426"
            
            icon.ScaleType = Enum.ScaleType.Fit
            icon.ZIndex = 50 -- Ensure it renders above background
            icon.Parent = slotFrame
            
            -- Add tool name label (Tiny)
            local nameLabel = Instance.new("TextLabel")
            nameLabel.Name = "ToolName"
            nameLabel.Size = UDim2.fromScale(1, 0.2)
            nameLabel.Position = UDim2.fromScale(0.5, 0.85)
            nameLabel.AnchorPoint = Vector2.new(0.5, 0)
            nameLabel.BackgroundTransparency = 1
            nameLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
            nameLabel.TextScaled = true
            nameLabel.Font = Enum.Font.GothamBold
            
            -- Check for DisplayName attribute on the tool itself, fallback to Name
            local toolDisplayName = tool:GetAttribute("DisplayName")
            nameLabel.Text = if toolDisplayName and toolDisplayName ~= "" then toolDisplayName else tool.Name
            
            nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
            nameLabel.ZIndex = 51
            nameLabel.Parent = slotFrame
            
            -- Show stack count using existing QuantityLabel from template
            local quantityLabel = slotFrame:FindFirstChild("QuantityLabel") :: TextLabel?
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
            
            -- Mark if it's from inventory (green badge = can be moved)
            if data.InventoryItemId then
                local inventoryBadge = Instance.new("Frame")
                inventoryBadge.Name = "InventoryBadge"
                inventoryBadge.Size = UDim2.fromScale(0.15, 0.15)
                inventoryBadge.SizeConstraint = Enum.SizeConstraint.RelativeXX
                inventoryBadge.Position = UDim2.fromScale(0.85, 0.05)
                inventoryBadge.BackgroundColor3 = Color3.fromRGB(100, 255, 100)
                inventoryBadge.BorderSizePixel = 0
                inventoryBadge.ZIndex = 52
                inventoryBadge.Parent = slotFrame
                
                local badgeCorner = Instance.new("UICorner")
                badgeCorner.CornerRadius = UDim.new(1, 0)
                badgeCorner.Parent = inventoryBadge
                
                -- Make this toolbar slot draggable (to remove from toolbar)
                if screenGui then
                    DragDrop.MakeToolbarSlotDraggable(
                        slotFrame,
                        i,
                        data.InventoryItemId,
                        tool.Name,
                        screenGui
                    )
                end
            else
                -- Red badge = cannot be moved (not from inventory)
                local lockedBadge = Instance.new("Frame")
                lockedBadge.Name = "LockedBadge"
                lockedBadge.Size = UDim2.fromScale(0.15, 0.15)
                lockedBadge.SizeConstraint = Enum.SizeConstraint.RelativeXX
                lockedBadge.Position = UDim2.fromScale(0.85, 0.05)
                lockedBadge.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
                lockedBadge.BorderSizePixel = 0
                lockedBadge.ZIndex = 52
                lockedBadge.Parent = slotFrame
                
                local badgeCorner = Instance.new("UICorner")
                badgeCorner.CornerRadius = UDim.new(1, 0)
                badgeCorner.Parent = lockedBadge
            end
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
    
    if inventoryFrame then
        inventoryFrame.Visible = isOpen
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
    
    @param context - ClientContext with PlayerGui
]]
function InventoryUI.Init(context: any)
    local playerGui = context.PlayerGui :: PlayerGui
    
    -- Find existing UI
    local existingScreenGui = playerGui:WaitForChild("InventoryUI", 10)
    if not existingScreenGui then
        warn("[InventoryUI] Failed to find InventoryUI in PlayerGui")
        return
    end
    screenGui = existingScreenGui :: ScreenGui
    
    inventoryFrame = screenGui:WaitForChild("InventoryPanel") :: Frame
    inventoryFrame.Visible = false -- Start hidden
    
    -- Bind Content Area
    local contentArea = inventoryFrame:WaitForChild("ContentArea")
    slotsContainer = contentArea:WaitForChild("GridContainer") :: ScrollingFrame
    
    -- Load slot template from Config
    local Config = ReplicatedStorage:WaitForChild("Config", 5)
    if Config then
        local inventoryConfig = Config:WaitForChild("Inventory", 2)
        if inventoryConfig then
            local templates = inventoryConfig:WaitForChild("Templates", 2)
            if templates then
                local tmpl = templates:WaitForChild("ItemSlot", 2)
                if tmpl and tmpl:IsA("Frame") then
                    slotTemplate = tmpl
                    print("[InventoryUI] Loaded ItemSlot template from Config.Inventory.Templates")
                end
            end
        end
    end
    
    if not slotTemplate then
        warn("[InventoryUI] Failed to load ItemSlot template from Config! Checking Container fallback...")
        -- Fallback: Check for slot template in ScanList
        local existingTemplate = slotsContainer:FindFirstChild("ItemSlot") 
                              or slotsContainer:FindFirstChildWhichIsA("Frame")
                              
        if existingTemplate and existingTemplate:IsA("Frame") then
            print("[InventoryUI] Found slot template in container:", existingTemplate.Name)
            slotTemplate = existingTemplate:Clone()
        end
    end
    
    -- Clean up container (remove placeholders)
    for _, child in slotsContainer:GetChildren() do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end
    
    -- Bind Info Panel
    local infoPanel = contentArea:WaitForChild("InfoPanel")
    infoTitle = infoPanel:WaitForChild("ItemName") :: TextLabel
    infoDesc = infoPanel:WaitForChild("Description") :: TextLabel
    infoItemId = infoPanel:FindFirstChild("ItemID") :: TextLabel? -- Optional ItemID display
    
    local iconContainer = infoPanel:WaitForChild("IconContainer")
    infoIcon = iconContainer:WaitForChild("Icon") :: ImageLabel
    
    -- Bind Consume Button
    consumeButton = infoPanel:FindFirstChild("Consume") :: GuiButton?
    if consumeButton then
        consumeButton.Visible = false -- Start hidden
        consumeButton.Activated:Connect(function()
            if _selectedItem then
                consumeItem(_selectedItem)
            end
        end)
        print("[InventoryUI] Found Consume button")
    else
        warn("[InventoryUI] Consume button not found in InfoPanel")
    end
    
    -- Bind Close Button (New Path: Header.Close.CloseButton)
    local header = inventoryFrame:WaitForChild("Header")
    local closeContainer = header:FindFirstChild("Close") -- Look for "Close" container first
    local closeBtn
    
    if closeContainer then
        closeBtn = closeContainer:WaitForChild("TextButton") :: TextButton
    else
        -- Fallback if user didn't nest it yet or changed mind
        closeBtn = header:WaitForChild("CloseButton") :: TextButton
    end
    
    if closeBtn then
        closeBtn.MouseButton1Click:Connect(function()
            InventoryUI.Toggle(false)
        end)
    end
    
    -- Bind Toolbar Area
    local toolbarArea = inventoryFrame:WaitForChild("ToolbarArea")
    
    -- Find toolbar slots (TSlot1..TSlot9)
    -- Assuming they are direct children of ToolbarArea or in a container.
    -- If user cloned checking direct usage is safer if we loop
    toolbarSlotFrames = {}
    for i = 1, 9 do
        local slotName = "TSlot" .. i
        -- Check direct child first
        local slot = toolbarArea:FindFirstChild(slotName)
        if slot then
            table.insert(toolbarSlotFrames, slot)
        else
            warn("[InventoryUI] Toolbar slot not found:", slotName)
        end
    end
    
    if #toolbarSlotFrames > 0 then
        DragDrop.RegisterToolbarSlots(toolbarSlotFrames)
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
    
    -- Handle drag & drop to toolbar
    janitor:Add(DragDrop.OnItemDropped:Connect(function(result: DragDrop.DropResult)
        if result.Success and result.ToolbarSlotIndex then
            -- Skip if dropping on the same slot (no-op)
            if result.ItemData.SourceToolbarSlot == result.ToolbarSlotIndex then
                print("[InventoryUI] Dropped on same slot, ignoring")
                return
            end
            
            -- If coming from another toolbar slot, remove it first
            if result.ItemData.SourceToolbarSlot then
                InventoryUI.RemoveFromToolbar(result.ItemData.SourceToolbarSlot)
            end
            -- Send assignment to server
            InventoryUI.AssignToToolbar(result.ItemData.ItemId, result.ToolbarSlotIndex)
            print("[InventoryUI] Assigned", result.ItemData.TemplateId, "to toolbar slot", result.ToolbarSlotIndex)
            -- Refresh integrated toolbar display after a short delay (wait for server to process)
            task.delay(0.2, function()
                updateIntegratedToolbar()
            end)
        end
    end))
    
    -- Handle removing items from toolbar (dragged to inventory)
    janitor:Add(DragDrop.OnToolbarItemRemoved:Connect(function(slotIndex: number, _itemId: string)
        InventoryUI.RemoveFromToolbar(slotIndex)
        print("[InventoryUI] Removed tool from toolbar slot", slotIndex)
        -- Refresh display after removal
        task.delay(0.2, function()
            updateIntegratedToolbar()
        end)
    end))
    
    -- Handle swapping toolbar items
    janitor:Add(DragDrop.OnToolbarSwap:Connect(function(slot1: number, slot2: number)
        InventoryUI.SwapToolbarSlots(slot1, slot2)
        print("[InventoryUI] Swapped toolbar slots", slot1, "<->", slot2)
        -- Refresh display after swap
        task.delay(0.2, function()
            updateIntegratedToolbar()
        end)
    end))
    
    -- Handle item selection
    janitor:Add(InventoryUI.OnItemClicked:Connect(function(itemData: ItemSlotData)
        print("[InventoryUI] Item clicked:", itemData.TemplateId)
        updateInfoPanel(itemData)
    end))
    
    -- Connect to inventory button (Async to avoid blocking Init)
    task.spawn(function()
        local base = playerGui:WaitForChild("Base", 10)
        if not base then
            warn("[InventoryUI] Base UI not found in PlayerGui")
            return
        end

        local hid = base:WaitForChild("HID", 10)
        if not hid then return end
        
        local left = hid:WaitForChild("Left", 10)
        if not left then return end
        
        local buttons = left:WaitForChild("Buttons", 10)
        if not buttons then return end
        
        local inventoryButton = buttons:WaitForChild("Inventory", 10) :: GuiButton
        if inventoryButton then
            inventoryButton.Activated:Connect(function()
                print("[InventoryUI] Inventory button clicked")
                InventoryUI.Toggle()
            end)
            print("[InventoryUI] Connected to inventory button")
        else
            warn("[InventoryUI] Inventory button not found at Base.HID.Left.Buttons.Inventory")
        end
    end)
    
    print("[InventoryUI] Initialized (Existing UI)!")
end

--[[
    Cleanup.
]]
function InventoryUI.Destroy()
    DragDrop.Cleanup()
    janitor:Destroy()
    if inventoryFrame then
        inventoryFrame:Destroy()
    end
end

return InventoryUI

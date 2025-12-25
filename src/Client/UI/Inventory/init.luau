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
local toolbarSlotFrames: {Frame} = {}
local screenGui: ScreenGui? = nil
local janitor: Janitor = Janitor.new()

-- Events
InventoryUI.OnItemClicked = Signal.new()
InventoryUI.OnToggled = Signal.new()

-- UI Constants - Clean Modern Dark Theme
local UI_CONFIG = {
    -- Gradient colors
    BackgroundTop = Color3.fromRGB(24, 26, 36),
    BackgroundBottom = Color3.fromRGB(14, 16, 22),
    HeaderTop = Color3.fromRGB(38, 42, 58),
    HeaderBottom = Color3.fromRGB(28, 32, 44),
    
    -- Accents
    AccentPrimary = Color3.fromRGB(90, 170, 255), -- Cyan
    AccentSecondary = Color3.fromRGB(160, 130, 255), -- Purple
    AccentGold = Color3.fromRGB(255, 200, 80),
    
    -- Borders
    BorderColor = Color3.fromRGB(50, 55, 75),
    BorderGlow = Color3.fromRGB(90, 130, 180),
    
    -- Slots
    SlotColor = Color3.fromRGB(30, 34, 48),
    SlotBorder = Color3.fromRGB(50, 55, 75),
    
    -- Layout
    Columns = 4,
    HeaderHeight = 52,
    ToolbarHeight = 100,
    Padding = 12,
    ToolbarSlots = 9,
}

--------------------------------------------------------------------------------
-- Private Functions
--------------------------------------------------------------------------------

--[[
    Creates the inventory panel UI with clean modern styling.
]]
local function createInventoryUI(playerGui: PlayerGui): Frame
    -- Main container - responsive scaling
    local container = Instance.new("Frame")
    container.Name = "InventoryPanel"
    container.Size = UDim2.fromScale(0.32, 0.55) -- Smaller, more compact
    container.Position = UDim2.fromScale(0.5, 0.5)
    container.AnchorPoint = Vector2.new(0.5, 0.5)
    container.BackgroundColor3 = UI_CONFIG.BackgroundTop
    container.BorderSizePixel = 0
    container.Visible = false
    
    -- Size constraint - smaller max size
    local sizeConstraint = Instance.new("UISizeConstraint")
    sizeConstraint.MinSize = Vector2.new(340, 380)
    sizeConstraint.MaxSize = Vector2.new(480, 550)
    sizeConstraint.Parent = container
    
    -- Cartoon rounded corners
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 16)
    corner.Parent = container
    
    -- Subtle border
    local outerBorder = Instance.new("UIStroke")
    outerBorder.Name = "OuterBorder"
    outerBorder.Color = UI_CONFIG.BorderGlow
    outerBorder.Thickness = 1.5
    outerBorder.Transparency = 0.4
    outerBorder.Parent = container
    
    -- Gradient background
    local bgGradient = Instance.new("UIGradient")
    bgGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, UI_CONFIG.BackgroundTop),
        ColorSequenceKeypoint.new(1, UI_CONFIG.BackgroundBottom),
    })
    bgGradient.Rotation = 180
    bgGradient.Parent = container
    
    -- Header
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, UI_CONFIG.HeaderHeight)
    header.BackgroundColor3 = UI_CONFIG.HeaderTop
    header.BorderSizePixel = 0
    header.Parent = container
    
    local headerCorner = Instance.new("UICorner")
    headerCorner.CornerRadius = UDim.new(0, 12)
    headerCorner.Parent = header
    
    -- Header gradient
    local headerGradient = Instance.new("UIGradient")
    headerGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, UI_CONFIG.HeaderTop),
        ColorSequenceKeypoint.new(1, UI_CONFIG.HeaderBottom),
    })
    headerGradient.Rotation = 180
    headerGradient.Parent = header
    
    -- Header clip for bottom corners
    local headerClip = Instance.new("Frame")
    headerClip.Name = "HeaderClip"
    headerClip.Size = UDim2.new(1, 0, 0.5, 0)
    headerClip.Position = UDim2.fromScale(0, 0.5)
    headerClip.BackgroundColor3 = UI_CONFIG.HeaderBottom
    headerClip.BorderSizePixel = 0
    headerClip.Parent = header
    
    -- Accent line under header
    local accentLine = Instance.new("Frame")
    accentLine.Name = "AccentLine"
    accentLine.Size = UDim2.new(1, -24, 0, 2)
    accentLine.Position = UDim2.new(0, 12, 1, -2)
    accentLine.BackgroundColor3 = UI_CONFIG.AccentPrimary
    accentLine.BorderSizePixel = 0
    accentLine.Parent = header
    
    -- Gradient line
    local lineGradient = Instance.new("UIGradient")
    lineGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, UI_CONFIG.AccentPrimary),
        ColorSequenceKeypoint.new(0.5, UI_CONFIG.AccentSecondary),
        ColorSequenceKeypoint.new(1, UI_CONFIG.AccentPrimary),
    })
    lineGradient.Parent = accentLine
    
    local accentCorner = Instance.new("UICorner")
    accentCorner.CornerRadius = UDim.new(1, 0)
    accentCorner.Parent = accentLine
    
    -- Title with cartoon font style
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, -80, 1, -10)
    title.Position = UDim2.fromOffset(20, 5)
    title.BackgroundTransparency = 1
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextSize = 28
    title.Font = Enum.Font.FredokaOne -- Cartoon font
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = "⚔️ INVENTORY"
    title.ZIndex = 102
    title.Parent = header
    
    -- Title stroke for cartoon effect
    local titleStroke = Instance.new("UIStroke")
    titleStroke.Color = Color3.fromRGB(0, 0, 0)
    titleStroke.Thickness = 2
    titleStroke.Parent = title
    
    -- Close button with cartoon style
    local closeButton = Instance.new("TextButton")
    closeButton.Name = "CloseButton"
    closeButton.Size = UDim2.fromOffset(40, 40)
    closeButton.Position = UDim2.new(1, -50, 0.5, 0)
    closeButton.AnchorPoint = Vector2.new(0, 0.5)
    closeButton.BackgroundColor3 = Color3.fromRGB(220, 60, 80)
    closeButton.BorderSizePixel = 0
    closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeButton.TextSize = 24
    closeButton.Font = Enum.Font.FredokaOne
    closeButton.Text = "✕"
    closeButton.ZIndex = 102
    closeButton.Parent = header
    
    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(0, 10)
    closeCorner.Parent = closeButton
    
    local closeBorder = Instance.new("UIStroke")
    closeBorder.Color = Color3.fromRGB(150, 40, 60)
    closeBorder.Thickness = 3
    closeBorder.Parent = closeButton
    
    closeButton.MouseButton1Click:Connect(function()
        InventoryUI.Toggle(false)
    end)
    
    -- Toolbar section at bottom
    local toolbarSection = Instance.new("Frame")
    toolbarSection.Name = "ToolbarSection"
    toolbarSection.Size = UDim2.new(1, 0, 0, UI_CONFIG.ToolbarHeight)
    toolbarSection.Position = UDim2.new(0, 0, 1, -UI_CONFIG.ToolbarHeight)
    toolbarSection.BackgroundColor3 = UI_CONFIG.BackgroundBottom
    toolbarSection.BorderSizePixel = 0
    toolbarSection.Parent = container
    
    local toolbarCorner = Instance.new("UICorner")
    toolbarCorner.CornerRadius = UDim.new(0, 12)
    toolbarCorner.Parent = toolbarSection
    
    -- Toolbar top accent line
    local toolbarTopLine = Instance.new("Frame")
    toolbarTopLine.Name = "TopLine"
    toolbarTopLine.Size = UDim2.new(1, -24, 0, 2)
    toolbarTopLine.Position = UDim2.fromOffset(12, 0)
    toolbarTopLine.BackgroundColor3 = UI_CONFIG.AccentGold
    toolbarTopLine.BorderSizePixel = 0
    toolbarTopLine.Parent = toolbarSection
    
    local toolbarTitle = Instance.new("TextLabel")
    toolbarTitle.Name = "ToolbarTitle"
    toolbarTitle.Size = UDim2.new(1, 0, 0, 22)
    toolbarTitle.Position = UDim2.fromOffset(12, 6)
    toolbarTitle.BackgroundTransparency = 1
    toolbarTitle.TextColor3 = UI_CONFIG.AccentGold
    toolbarTitle.TextSize = 12
    toolbarTitle.Font = Enum.Font.GothamBold
    toolbarTitle.TextXAlignment = Enum.TextXAlignment.Left
    toolbarTitle.Text = "HOTBAR"
    toolbarTitle.Parent = toolbarSection
    
    -- Toolbar slots container
    local toolbarSlots = Instance.new("Frame")
    toolbarSlots.Name = "ToolbarSlots"
    toolbarSlots.Size = UDim2.new(1, -24, 1, -32)
    toolbarSlots.Position = UDim2.fromOffset(12, 28)
    toolbarSlots.BackgroundTransparency = 1
    toolbarSlots.Parent = toolbarSection
    
    local toolbarLayout = Instance.new("UIListLayout")
    toolbarLayout.FillDirection = Enum.FillDirection.Horizontal
    toolbarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    toolbarLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    toolbarLayout.Padding = UDim.new(0, 8)
    toolbarLayout.Parent = toolbarSlots
    
    -- Create 9 toolbar slots with cartoon style
    toolbarSlotFrames = {}
    for i = 1, UI_CONFIG.ToolbarSlots do
        local slot = Instance.new("Frame")
        slot.Name = "ToolbarSlot" .. i
        slot.Size = UDim2.fromOffset(72, 72)
        slot.BackgroundColor3 = UI_CONFIG.SlotColor
        slot.BorderSizePixel = 0
        slot.ZIndex = 103
        slot.Parent = toolbarSlots
        
        local slotCorner = Instance.new("UICorner")
        slotCorner.CornerRadius = UDim.new(0, 10)
        slotCorner.Parent = slot
        
        local slotBorder = Instance.new("UIStroke")
        slotBorder.Name = "BorderStroke"
        slotBorder.Color = UI_CONFIG.BorderColor
        slotBorder.Thickness = 2
        slotBorder.Parent = slot
        
        -- Hotkey badge
        local hotkeyLabel = Instance.new("TextLabel")
        hotkeyLabel.Name = "Hotkey"
        hotkeyLabel.Size = UDim2.fromOffset(16, 16)
        hotkeyLabel.Position = UDim2.fromOffset(2, 2)
        hotkeyLabel.BackgroundColor3 = UI_CONFIG.AccentPrimary
        hotkeyLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        hotkeyLabel.TextSize = 12
        hotkeyLabel.Font = Enum.Font.FredokaOne
        hotkeyLabel.Text = tostring(i)
        hotkeyLabel.ZIndex = 104
        hotkeyLabel.Parent = slot
        
        local hotkeyCorner = Instance.new("UICorner")
        hotkeyCorner.CornerRadius = UDim.new(0, 5)
        hotkeyCorner.Parent = hotkeyLabel
        
        table.insert(toolbarSlotFrames, slot)
    end
    
    -- Register toolbar slots for drag & drop
    DragDrop.RegisterToolbarSlots(toolbarSlotFrames)
    
    -- Scrolling frame for inventory slots
    local scrollFrame = Instance.new("ScrollingFrame")
    scrollFrame.Name = "SlotsContainer"
    scrollFrame.Size = UDim2.new(1, -UI_CONFIG.Padding * 2, 1, -UI_CONFIG.HeaderHeight - UI_CONFIG.ToolbarHeight - 8)
    scrollFrame.Position = UDim2.new(0, UI_CONFIG.Padding, 0, UI_CONFIG.HeaderHeight + 4)
    scrollFrame.BackgroundTransparency = 1
    scrollFrame.BorderSizePixel = 0
    scrollFrame.ScrollBarThickness = 4
    scrollFrame.ScrollBarImageColor3 = UI_CONFIG.AccentPrimary
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    scrollFrame.Parent = container
    
    -- Grid layout for inventory slots (fixed square size)
    local gridLayout = Instance.new("UIGridLayout")
    gridLayout.CellSize = UDim2.fromOffset(100, 100) -- Fixed square size
    gridLayout.CellPadding = UDim2.fromOffset(8, 8)
    gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
    gridLayout.FillDirectionMaxCells = UI_CONFIG.Columns
    gridLayout.Parent = scrollFrame
    
    -- Auto-size canvas
    gridLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        scrollFrame.CanvasSize = UDim2.fromOffset(0, gridLayout.AbsoluteContentSize.Y + UI_CONFIG.Padding)
    end)
    
    slotsContainer = scrollFrame
    
    -- Parent to ScreenGui (high display order to be on top)
    screenGui = playerGui:FindFirstChild("InventoryUI") :: ScreenGui?
    if not screenGui then
        screenGui = Instance.new("ScreenGui")
        screenGui.Name = "InventoryUI"
        screenGui.DisplayOrder = 100 -- On top of other UIs
        screenGui.ResetOnSpawn = false
        screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        screenGui.Parent = playerGui
    end
    
    container.Parent = screenGui
    
    return container
end

--[[
    Converts inventory items to individual slot display data.
    Shows all items individually (no stacking) with equipped indicator.
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
    
    -- Add each item individually (no stacking)
    for _, item in inventoryData do
        local equippedSlot = equippedItemIds[item.Id]
        table.insert(slotDataList, {
            TemplateId = item.TemplateId,
            Type = item.Type :: string,
            Rarity = if item.Rarity then item.Rarity :: string else nil,
            Count = 1, -- Always 1 since no stacking
            ItemIds = {item.Id},
            IsEquipped = equippedSlot ~= nil,
            EquippedSlot = equippedSlot,
        })
    end
    
    return slotDataList
end

--[[
    Updates the display with current inventory data.
]]
local function refreshDisplay()
    if not slotsContainer then 
        print("[InventoryUI] refreshDisplay: No slotsContainer!")
        return 
    end
    
    -- Get individual items for display (no stacking)
    local itemData = getItemsForDisplay()
    print("[InventoryUI] refreshDisplay: inventoryData count:", #inventoryData, "displayItems count:", #itemData)
    
    -- Reuse or create slots
    local requiredSlots = #itemData
    
    -- Create more slots if needed
    while #itemSlots < requiredSlots do
        local slot = ItemSlot.new(slotsContainer)
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
    
    for _, itemData in data.items do
        local item: InventoryItem = {
            Id = itemData.id,
            TemplateId = itemData.templateId,
            Type = itemData.itemType :: Inventory.ItemType,
            Rarity = if itemData.rarity ~= "" then itemData.rarity :: Inventory.RarityType? else nil,
            Metadata = nil,
        }
        table.insert(inventoryData, item)
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
end

--[[
    Updates the integrated toolbar display to match the actual toolbar state.
    Shows tools from both inventory system and regular backpack.
]]
local function updateIntegratedToolbar()
    if #toolbarSlotFrames == 0 then 
        print("[InventoryUI] No toolbar slot frames!")
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
        
        -- Clear existing content (except hotkey label and border)
        for _, child in slotFrame:GetChildren() do
            if child.Name ~= "Hotkey" and not child:IsA("UICorner") and not child:IsA("UIStroke") then
                child:Destroy()
            end
        end
        
        if data and data.Tool then
            local tool = data.Tool
            print("[InventoryUI] Showing tool in slot", i, ":", tool.Name)
            
            -- Create icon for the tool
            local icon = Instance.new("ImageLabel")
            icon.Name = "ToolIcon"
            icon.Size = UDim2.fromScale(0.7, 0.7)
            icon.Position = UDim2.fromScale(0.5, 0.5)
            icon.AnchorPoint = Vector2.new(0.5, 0.5)
            icon.BackgroundTransparency = 1
            icon.Image = if tool.TextureId ~= "" then tool.TextureId else "rbxassetid://6031763426"
            icon.Parent = slotFrame
            
            -- Add tool name label
            local nameLabel = Instance.new("TextLabel")
            nameLabel.Name = "ToolName"
            nameLabel.Size = UDim2.new(1, 0, 0.25, 0)
            nameLabel.Position = UDim2.new(0, 0, 1, -15)
            nameLabel.BackgroundTransparency = 1
            nameLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
            nameLabel.TextSize = 8
            nameLabel.Font = Enum.Font.GothamBold
            nameLabel.Text = tool.Name
            nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
            nameLabel.Parent = slotFrame
            
            -- Mark if it's from inventory (green badge = can be moved)
            if data.InventoryItemId then
                local inventoryBadge = Instance.new("Frame")
                inventoryBadge.Name = "InventoryBadge"
                inventoryBadge.Size = UDim2.fromOffset(8, 8)
                inventoryBadge.Position = UDim2.new(1, -10, 0, 2)
                inventoryBadge.BackgroundColor3 = Color3.fromRGB(100, 200, 100)
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
                lockedBadge.Size = UDim2.fromOffset(8, 8)
                lockedBadge.Position = UDim2.new(1, -10, 0, 2)
                lockedBadge.BackgroundColor3 = Color3.fromRGB(150, 80, 80)
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
    Initializes the inventory UI.
    
    @param context - ClientContext with PlayerGui
]]
function InventoryUI.Init(context: any)
    local playerGui = context.PlayerGui :: PlayerGui
    
    -- Create UI
    inventoryFrame = createInventoryUI(playerGui)
    
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
    
    -- Connect to inventory button
    local base = playerGui:WaitForChild("Base", 5)
    if base then
        local hid = base:FindFirstChild("HID")
        if hid then
            local left = hid:FindFirstChild("Left")
            if left then
                local buttons = left:FindFirstChild("Buttons")
                if buttons then
                    local inventoryButton = buttons:FindFirstChild("Inventory") :: TextButton?
                    if inventoryButton then
                        inventoryButton.MouseButton1Click:Connect(function()
                            InventoryUI.Toggle()
                        end)
                        print("[InventoryUI] Connected to inventory button")
                    else
                        warn("[InventoryUI] Inventory button not found at Base.HID.Left.Buttons.Inventory")
                    end
                end
            end
        end
    end
    
    print("[InventoryUI] Initialized!")
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

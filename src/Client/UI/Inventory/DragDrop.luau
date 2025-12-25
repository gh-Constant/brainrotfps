--!strict
--[[
    DragDropHandler Module
    Handles drag and drop functionality for inventory items and toolbar slots.
    Uses Roblox's native UIDragDetector for smooth dragging.
    
    Features:
    - Unified drag handling for both inventory and toolbar slots
    - Visual feedback during drag (ghost element, slot highlighting)
    - Drop detection on toolbar slots
    - Swap support when dropping on occupied slots
    - Snap-back if dropped outside valid area
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Packages = Rojo:WaitForChild("Packages")
local Janitor = require(Packages:WaitForChild("janitor"))
local Signal = require(Packages:WaitForChild("signal"))

-- Types
export type DragData = {
    ItemId: string,
    TemplateId: string,
    Type: string,
    Rarity: string?,
    SourceSlot: Frame,
    SourceToolbarSlot: number?, -- If dragged from toolbar, this is the slot index
}

export type DropResult = {
    Success: boolean,
    ToolbarSlotIndex: number?,
    ItemData: DragData,
    DisplacedItemId: string?, -- Item that was in the target slot (for swaps)
    SourceToolbarSlot: number?, -- Source slot if dragged from toolbar
}

-- Module
local DragDropHandler = {}
DragDropHandler.__index = DragDropHandler

-- Configuration
local CONFIG = {
    DragTransparency = 0.5,
    DragZIndex = 200,
    DropHighlightColor = Color3.fromRGB(100, 180, 100),
    InvalidDropColor = Color3.fromRGB(180, 100, 100),
    HoverScale = 1.1,
}

-- Signals
DragDropHandler.OnItemDropped = Signal.new() -- Fires when item dropped on toolbar slot
DragDropHandler.OnToolbarItemRemoved = Signal.new() -- Fires when item dragged from toolbar to empty area
DragDropHandler.OnToolbarSwap = Signal.new() -- Fires when two toolbar items should swap
DragDropHandler.OnDragStart = Signal.new()
DragDropHandler.OnDragEnd = Signal.new()

-- State
local currentDragData: DragData? = nil
local dragStartTime: number = 0
local isDragActive: boolean = false -- True only after threshold passed
local dragGhost: Frame? = nil
local toolbarSlots: {Frame} = {}
local toolbarContents: {[number]: string?} = {} -- slot index -> itemId (for swap detection)
local hoveredSlot: Frame? = nil
local janitor = Janitor.new()

--------------------------------------------------------------------------------
-- Private Functions
--------------------------------------------------------------------------------

--[[
    Creates a ghost/preview element that follows the mouse during drag.
]]
--[[
    Creates a ghost/preview element that follows the mouse during drag.
]]
local function createDragGhost(sourceFrame: Frame, screenGui: ScreenGui): Frame
    local ghost = sourceFrame:Clone()
    ghost.Name = "DragGhost"
    ghost.ZIndex = CONFIG.DragZIndex
    ghost.BackgroundTransparency = CONFIG.DragTransparency
    ghost.Parent = screenGui
    
    -- Convert scale size to absolute offset to prevent full-screen ghost
    ghost.Size = UDim2.fromOffset(sourceFrame.AbsoluteSize.X, sourceFrame.AbsoluteSize.Y)
    ghost.AnchorPoint = Vector2.new(0.5, 0.5) -- Center on mouse
    
    -- Remove interactivity
    ghost.Active = false
    -- Remove UIAspectRatioConstraint to prevent resizing issues during drag if container aspect differs
    local aspect = ghost:FindFirstChildWhichIsA("UIAspectRatioConstraint")
    if aspect then aspect:Destroy() end

    for _, child in ghost:GetDescendants() do
        if child:IsA("GuiButton") then
            child.Active = false
        end
        -- Also remove drag detectors from ghost
        if child:IsA("UIDragDetector") then
            child:Destroy()
        end
    end
    
    return ghost
end

--[[
    Updates ghost position to follow mouse.
]]
local function updateGhostPosition(ghost: Frame, mousePosition: Vector2)
    -- Just center on mouse since we set AnchorPoint to 0.5, 0.5
    ghost.Position = UDim2.fromOffset(mousePosition.X, mousePosition.Y)
end

--[[
    Checks if a point is inside a frame's bounds.
]]
local function isPointInFrame(point: Vector2, frame: Frame): boolean
    local pos = frame.AbsolutePosition
    local size = frame.AbsoluteSize
    return point.X >= pos.X and point.X <= pos.X + size.X
        and point.Y >= pos.Y and point.Y <= pos.Y + size.Y
end

--[[
    Finds which toolbar slot (if any) is under the mouse.
]]
local function findHoveredToolbarSlot(mousePosition: Vector2): (Frame?, number?)
    for i, slot in ipairs(toolbarSlots) do
        if isPointInFrame(mousePosition, slot) then
            return slot, i
        end
    end
    return nil, nil
end

--[[
    Highlights a slot during hover.
]]
local function highlightSlot(slot: Frame, highlight: boolean, valid: boolean?)
    local stroke = slot:FindFirstChildWhichIsA("UIStroke")
    if stroke then
        if highlight then
            stroke.Color = valid ~= false and CONFIG.DropHighlightColor or CONFIG.InvalidDropColor
            stroke.Thickness = 3
        else
            stroke.Color = Color3.fromRGB(70, 70, 80)
            stroke.Thickness = 1
        end
    end
end

--[[
    Cleans up current drag state.
]]
local function cleanupDrag()
    if dragGhost then
        dragGhost:Destroy()
        dragGhost = nil
    end
    if hoveredSlot then
        highlightSlot(hoveredSlot, false)
        hoveredSlot = nil
    end
    currentDragData = nil
    DragDropHandler.OnDragEnd:Fire()
end

--[[
    Handles drag start (unified for inventory and toolbar slots).
]]
--[[
    Handles drag start (unified for inventory and toolbar slots).
]]
local function onDragStart(slotFrame: Frame, itemData: DragData, screenGui: ScreenGui, inputPosition: Vector2)
    currentDragData = itemData
    dragStartTime = tick()
    isDragActive = false
    
    -- Defer ghost creation until threshold passed
end

--[[
    Handles drag continue (unified for inventory and toolbar slots).
]]
--[[
    Handles drag continue (unified for inventory and toolbar slots).
]]
local function onDragContinue(inputPosition: Vector2, slotFrame: Frame, screenGui: ScreenGui)
    if not currentDragData then return end
    
    -- Check threshold if not active yet
    if not isDragActive then
        if tick() - dragStartTime > 0.15 then
            -- Activate Drag
            isDragActive = true
            
            -- Create ghost
            dragGhost = createDragGhost(slotFrame, screenGui)
            updateGhostPosition(dragGhost :: Frame, inputPosition)
            
            -- Dim original
            slotFrame.BackgroundTransparency = 0.7
            
            DragDropHandler.OnDragStart:Fire(currentDragData)
        else
            return -- Wait for threshold
        end
    end

    if dragGhost then
        updateGhostPosition(dragGhost, inputPosition)
    end
    
    -- Check hover over toolbar slots
    local newHoveredSlot, _slotIdx = findHoveredToolbarSlot(inputPosition)
    
    if newHoveredSlot ~= hoveredSlot then
        -- Unhighlight old
        if hoveredSlot then
            highlightSlot(hoveredSlot, false)
        end
        
        -- Highlight new
        if newHoveredSlot and currentDragData then
            -- Only Tools can go in toolbar
            local isValid = currentDragData.Type == "Tool"
            highlightSlot(newHoveredSlot :: Frame, true, isValid)
        end
        
        hoveredSlot = newHoveredSlot
    end
end

--[[
    Handles drag end for INVENTORY slot drop.
]]
--[[
    Handles drag end for INVENTORY slot drop.
]]
local function onInventoryDragEnd(slotFrame: Frame, inputPosition: Vector2)
    slotFrame.BackgroundTransparency = 0
    
    if not isDragActive then
        cleanupDrag()
        return -- Was just a click
    end
    
    local droppedSlot, slotIndex = findHoveredToolbarSlot(inputPosition)
    
    if droppedSlot and currentDragData and currentDragData.Type == "Tool" and slotIndex then
        -- Get the item currently in the target slot (if any)
        local displacedItemId = toolbarContents[slotIndex]
        
        local result: DropResult = {
            Success = true,
            ToolbarSlotIndex = slotIndex,
            ItemData = currentDragData,
            DisplacedItemId = displacedItemId,
            SourceToolbarSlot = currentDragData.SourceToolbarSlot,
        }
        DragDropHandler.OnItemDropped:Fire(result)
        highlightSlot(droppedSlot, false)
    else
        -- Invalid drop - snap back
        if currentDragData then
            local result: DropResult = {
                Success = false,
                ToolbarSlotIndex = nil,
                ItemData = currentDragData,
            }
            DragDropHandler.OnItemDropped:Fire(result)
        end
    end
    
    cleanupDrag()
end

--[[
    Handles drag end for TOOLBAR slot drop.
]]
--[[
    Handles drag end for TOOLBAR slot drop.
]]
local function onToolbarDragEnd(slotFrame: Frame, sourceSlotIndex: number, inputPosition: Vector2)
    slotFrame.BackgroundTransparency = 0
    
    if not isDragActive then
        cleanupDrag()
        return -- Was just a click
    end
    
    local droppedSlot, targetSlotIndex = findHoveredToolbarSlot(inputPosition)
    
    if droppedSlot and currentDragData and targetSlotIndex then
        if targetSlotIndex == sourceSlotIndex then
            -- Dropped on same slot - no-op
            cleanupDrag()
            return
        end
        
        -- Check if target slot has an item (swap scenario)
        local targetItemId = toolbarContents[targetSlotIndex]
        
        if targetItemId and targetItemId ~= "" then
            -- Both slots have items - swap!
            DragDropHandler.OnToolbarSwap:Fire(sourceSlotIndex, targetSlotIndex)
        else
            -- Target is empty - move operation
            local result: DropResult = {
                Success = true,
                ToolbarSlotIndex = targetSlotIndex,
                ItemData = currentDragData,
                SourceToolbarSlot = sourceSlotIndex,
            }
            DragDropHandler.OnItemDropped:Fire(result)
        end
        
        highlightSlot(droppedSlot, false)
    else
        -- Dropped outside toolbar - remove from toolbar
        if currentDragData then
            DragDropHandler.OnToolbarItemRemoved:Fire(sourceSlotIndex, currentDragData.ItemId)
        end
    end
    
    cleanupDrag()
end

--------------------------------------------------------------------------------
-- Public Methods
--------------------------------------------------------------------------------

--[[
    Registers toolbar slots for drop detection.
    @param slots - Array of Frame references for the 9 toolbar slots
]]
function DragDropHandler.RegisterToolbarSlots(slots: {Frame})
    toolbarSlots = slots
end

--[[
    Updates the known contents of toolbar slots (for swap detection).
    @param contents - Map of slot index -> item ID (nil/empty string for empty slots)
]]
function DragDropHandler.RegisterToolbarContents(contents: {[number]: string?})
    toolbarContents = contents
end

--[[
    Makes an inventory slot draggable using UIDragDetector.
    @param slotFrame - The frame containing the inventory item
    @param itemData - Data about the item (id, templateId, type, rarity)
    @param screenGui - The ScreenGui for the drag ghost
]]
function DragDropHandler.MakeDraggable(slotFrame: Frame, itemData: DragData, screenGui: ScreenGui)
    -- Remove existing detector if any
    local existingDetector = slotFrame:FindFirstChild("ItemDragDetector")
    if existingDetector then
        existingDetector:Destroy()
    end
    
    local dragDetector = Instance.new("UIDragDetector")
    dragDetector.Name = "ItemDragDetector"
    dragDetector.DragStyle = Enum.UIDragDetectorDragStyle.TranslatePlane
    dragDetector.ResponseStyle = Enum.UIDragDetectorResponseStyle.CustomOffset
    dragDetector.Parent = slotFrame
    
    local slotJanitor = Janitor.new()
    
    slotJanitor:Add(dragDetector.DragStart:Connect(function(inputPosition: Vector2)
        local data: DragData = {
            ItemId = itemData.ItemId,
            TemplateId = itemData.TemplateId,
            Type = itemData.Type,
            Rarity = itemData.Rarity,
            SourceSlot = slotFrame,
            SourceToolbarSlot = itemData.SourceToolbarSlot,
        }
        onDragStart(slotFrame, data, screenGui, inputPosition)
    end))
    
    slotJanitor:Add(dragDetector.DragContinue:Connect(function(inputPosition: Vector2)
        onDragContinue(inputPosition, slotFrame, screenGui)
    end))
    
    slotJanitor:Add(dragDetector.DragEnd:Connect(function(inputPosition: Vector2)
        onInventoryDragEnd(slotFrame, inputPosition)
    end))
    
    slotJanitor:Add(slotFrame.Destroying:Connect(function()
        slotJanitor:Cleanup()
    end))
    
    janitor:Add(slotJanitor)
    
    return dragDetector
end

--[[
    Makes a toolbar slot draggable (for moving/swapping/removing items).
    @param slotFrame - The toolbar slot frame
    @param slotIndex - The toolbar slot index (1-9)
    @param itemId - The inventory item ID in this slot
    @param templateId - The template ID of the item
    @param screenGui - The ScreenGui for the drag ghost
]]
function DragDropHandler.MakeToolbarSlotDraggable(
    slotFrame: Frame, 
    slotIndex: number, 
    itemId: string, 
    templateId: string,
    screenGui: ScreenGui
)
    -- Remove existing detector if any
    local oldDetector = slotFrame:FindFirstChild("ToolbarDragDetector")
    if oldDetector then
        oldDetector:Destroy()
    end
    
    local dragDetector = Instance.new("UIDragDetector")
    dragDetector.Name = "ToolbarDragDetector"
    dragDetector.DragStyle = Enum.UIDragDetectorDragStyle.TranslatePlane
    dragDetector.ResponseStyle = Enum.UIDragDetectorResponseStyle.CustomOffset
    dragDetector.Parent = slotFrame
    
    local slotJanitor = Janitor.new()
    
    slotJanitor:Add(dragDetector.DragStart:Connect(function(inputPosition: Vector2)
        local data: DragData = {
            ItemId = itemId,
            TemplateId = templateId,
            Type = "Tool",
            Rarity = nil,
            SourceSlot = slotFrame,
            SourceToolbarSlot = slotIndex,
        }
        onDragStart(slotFrame, data, screenGui, inputPosition)
    end))
    
    slotJanitor:Add(dragDetector.DragContinue:Connect(function(inputPosition: Vector2)
        onDragContinue(inputPosition, slotFrame, screenGui)
    end))
    
    slotJanitor:Add(dragDetector.DragEnd:Connect(function(inputPosition: Vector2)
        onToolbarDragEnd(slotFrame, slotIndex, inputPosition)
    end))
    
    slotJanitor:Add(slotFrame.Destroying:Connect(function()
        slotJanitor:Cleanup()
    end))
    
    janitor:Add(slotJanitor)
    
    return dragDetector
end

--[[
    Cleans up all drag handlers.
]]
function DragDropHandler.Cleanup()
    janitor:Cleanup()
    toolbarSlots = {}
    toolbarContents = {}
    currentDragData = nil
    hoveredSlot = nil
    if dragGhost then
        dragGhost:Destroy()
        dragGhost = nil
    end
end

return DragDropHandler

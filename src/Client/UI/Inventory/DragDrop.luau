--!strict
--[[
    DragDropHandler Module
    Handles drag and drop functionality for inventory items to toolbar slots.
    Uses Roblox's native UIDragDetector for smooth dragging.
    
    Features:
    - Drag items from inventory grid to toolbar
    - Visual feedback during drag
    - Drop detection on toolbar slots
    - Snap-back if dropped outside valid area
]]

local _Players = game:GetService("Players")
local _RunService = game:GetService("RunService")

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
}

export type DropResult = {
    Success: boolean,
    ToolbarSlotIndex: number?,
    ItemData: DragData,
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
DragDropHandler.OnItemDropped = Signal.new() -- Fires when item dropped on toolbar
DragDropHandler.OnDragStart = Signal.new()
DragDropHandler.OnDragEnd = Signal.new()

-- State
local currentDragData: DragData? = nil
local dragGhost: Frame? = nil
local toolbarSlots: {Frame} = {}
local hoveredSlot: Frame? = nil
local janitor = Janitor.new()

--------------------------------------------------------------------------------
-- Private Functions
--------------------------------------------------------------------------------

--[[
    Creates a ghost/preview element that follows the mouse during drag.
]]
local function createDragGhost(sourceFrame: Frame, screenGui: ScreenGui): Frame
    local ghost = sourceFrame:Clone()
    ghost.Name = "DragGhost"
    ghost.ZIndex = CONFIG.DragZIndex
    ghost.BackgroundTransparency = CONFIG.DragTransparency
    ghost.Parent = screenGui
    
    -- Remove interactivity
    ghost.Active = false
    for _, child in ghost:GetDescendants() do
        if child:IsA("GuiButton") then
            child.Active = false
        end
    end
    
    return ghost
end

--[[
    Updates ghost position to follow mouse.
]]
local function updateGhostPosition(ghost: Frame, mousePosition: Vector2)
    ghost.Position = UDim2.fromOffset(
        mousePosition.X - ghost.AbsoluteSize.X / 2,
        mousePosition.Y - ghost.AbsoluteSize.Y / 2
    )
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
    Makes an inventory slot draggable using UIDragDetector.
    @param slotFrame - The frame containing the inventory item
    @param itemData - Data about the item (id, templateId, type, rarity)
    @param screenGui - The ScreenGui for the drag ghost
]]
function DragDropHandler.MakeDraggable(slotFrame: Frame, itemData: DragData, screenGui: ScreenGui)
    -- Create UIDragDetector for native drag support
    local dragDetector = Instance.new("UIDragDetector")
    dragDetector.Name = "ItemDragDetector"
    dragDetector.DragStyle = Enum.UIDragDetectorDragStyle.TranslatePlane
    dragDetector.ResponseStyle = Enum.UIDragDetectorResponseStyle.CustomOffset
    dragDetector.Parent = slotFrame
    
    local slotJanitor = Janitor.new()
    
    -- Store original position for snap-back
    local _originalPosition = slotFrame.Position
    
    -- Drag Start
    slotJanitor:Add(dragDetector.DragStart:Connect(function(inputPosition: Vector2)
        currentDragData = {
            ItemId = itemData.ItemId,
            TemplateId = itemData.TemplateId,
            Type = itemData.Type,
            Rarity = itemData.Rarity,
            SourceSlot = slotFrame,
        }
        
        -- Create ghost
        dragGhost = createDragGhost(slotFrame, screenGui)
        updateGhostPosition(dragGhost :: Frame, inputPosition)
        
        -- Dim original
        slotFrame.BackgroundTransparency = 0.7
        
        DragDropHandler.OnDragStart:Fire(currentDragData)
    end))
    
    -- Drag Continue (update ghost and check hover)
    slotJanitor:Add(dragDetector.DragContinue:Connect(function(inputPosition: Vector2)
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
    end))
    
    -- Drag End
    slotJanitor:Add(dragDetector.DragEnd:Connect(function(inputPosition: Vector2)
        -- Clean up ghost
        if dragGhost then
            dragGhost:Destroy()
            dragGhost = nil
        end
        
        -- Restore original
        slotFrame.BackgroundTransparency = 0
        
        -- Check if dropped on valid toolbar slot
        local droppedSlot, slotIndex = findHoveredToolbarSlot(inputPosition)
        
        if droppedSlot and currentDragData and currentDragData.Type == "Tool" and slotIndex then
            -- Valid drop!
            local result: DropResult = {
                Success = true,
                ToolbarSlotIndex = slotIndex,
                ItemData = currentDragData,
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
        
        -- Clear hover
        if hoveredSlot then
            highlightSlot(hoveredSlot, false)
            hoveredSlot = nil
        end
        
        -- Clear drag data
        currentDragData = nil
        DragDropHandler.OnDragEnd:Fire()
    end))
    
    -- Cleanup on slot removal
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
    currentDragData = nil
    hoveredSlot = nil
    if dragGhost then
        dragGhost:Destroy()
        dragGhost = nil
    end
end

return DragDropHandler

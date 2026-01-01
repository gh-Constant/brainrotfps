--!strict
--[[
    VirtualScrollManager - Virtual Scrolling (View Recycling) for Inventory
    
    The Pro Optimization: Only 18 physical slots exist regardless of inventory size.
    As the player scrolls, slots are recycled and updated with new data.
    
    How it works:
    1. Create a fixed pool of ~18+3 slots (visible + buffer)
    2. Track ScrollingFrame.CanvasPosition.Y
    3. Calculate which items should be visible: firstIndex = floor(scrollY / slotHeight)
    4. Recycle slots: reposition and call SetData() with new content
    
    Result: Zero lag even with 10,000 items
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Packages = Rojo:WaitForChild("Packages")
local Shared = Rojo:WaitForChild("Shared")

local Janitor = require(Packages:WaitForChild("janitor"))
local Signal = require(Packages:WaitForChild("signal"))
local Logger = require(Shared:WaitForChild("Inventory"):WaitForChild("Logger"))

local ItemSlot = require(script.Parent.ItemSlot)
local DragDrop = require(script.Parent.DragDrop)

-- Types
type Janitor = typeof(Janitor.new())
type ItemSlotData = ItemSlot.ItemSlotData

export type VirtualScrollManager = {
    SetData: (self: VirtualScrollManager, itemData: {ItemSlotData}) -> (),
    Refresh: (self: VirtualScrollManager) -> (),
    GetSlotAtIndex: (self: VirtualScrollManager, dataIndex: number) -> ItemSlot.ItemSlot?,
    Destroy: (self: VirtualScrollManager) -> (),
    
    OnItemClicked: any, -- Signal<ItemSlotData>
    OnItemDeleted: any, -- Signal<ItemSlotData>
}

-- Configuration
local COLUMNS = 6 -- Grid columns (6 per row)
local VISIBLE_ROWS = 4 -- Approx rows visible at once (1 / 0.3 = 3.33)
local BUFFER_ROWS = 1 -- Reduced buffer to minimize instance count
local POOL_SIZE = (VISIBLE_ROWS + BUFFER_ROWS) * COLUMNS -- 5 rows * 6 cols = 30 slots

-- UIGridLayout equivalent settings (Scale-based)
-- CellSize: {0.15, 0}, {0.3, 0}
-- CellPadding: {0.017, 0}, {0.05, 0}
local CELL_WIDTH_SCALE = 0.15
local CELL_HEIGHT_SCALE = 0.3
local PADDING_X_SCALE = 0.017
local PADDING_Y_SCALE = 0.05

local VirtualScrollManagerModule = {}
VirtualScrollManagerModule.__index = VirtualScrollManagerModule

local function log(message: string)
    Logger.log("VirtualScroll", message)
end

--[[
    Creates a new VirtualScrollManager.
]]
function VirtualScrollManagerModule.new(
    scrollingFrame: ScrollingFrame,
    slotTemplate: GuiObject,
    screenGui: ScreenGui
): VirtualScrollManager
    local self = setmetatable({}, VirtualScrollManagerModule) :: any
    
    self._janitor = Janitor.new()
    self._scrollingFrame = scrollingFrame
    self._slotTemplate = slotTemplate
    self._screenGui = screenGui
    
    -- Data state
    self._allItemData = {} :: {ItemSlotData} -- Full sorted/filtered list
    
    -- Slot pool
    self._slotPool = {} :: {ItemSlot.ItemSlot}
    
    -- Events
    self.OnItemClicked = Signal.new()
    self.OnItemDeleted = Signal.new()
    self._janitor:Add(self.OnItemClicked, "Destroy")
    self._janitor:Add(self.OnItemDeleted, "Destroy")
    
    -- Create slot pool
    self:_createSlotPool()
    
    -- Listen for scroll changes
    self._lastCanvasPosition = scrollingFrame.CanvasPosition.Y :: number
    self._janitor:Add(scrollingFrame:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
        self:_onScroll()
    end), "Disconnect")
    
    log("[VirtualScroll] Initialized with pool size " .. POOL_SIZE .. " (Modulo Algorithm)")
    
    return self :: any
end

--[[
    Creates the fixed pool of reusable slots.
]]
function VirtualScrollManagerModule:_createSlotPool()
    for i = 1, POOL_SIZE do
        local slot = ItemSlot.new(self._scrollingFrame, self._slotTemplate)
        slot.Frame.Name = "VirtualSlot_" .. i
        slot.Frame.Visible = false
        
        -- Connect click handler
        local clickConnection = slot.Frame.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or
               input.UserInputType == Enum.UserInputType.Touch then
                if slot.Data then
                    self.OnItemClicked:Fire(slot.Data)
                end
            end
        end)
        self._janitor:Add(clickConnection, "Disconnect")
        
        -- Connect delete handler
        local deleteConnection = slot.OnDeleteClicked:Connect(function(slotData)
            self.OnItemDeleted:Fire(slotData)
        end)
        self._janitor:Add(deleteConnection, "Disconnect")
        
        table.insert(self._slotPool, slot)
        self._janitor:Add(slot, "Destroy")
    end
end

--[[
    Sets full data and refreshes.
]]
function VirtualScrollManagerModule:SetData(itemData: {ItemSlotData})
    self._allItemData = itemData
    
    -- 1. Calculate Canvas Size
    local totalRows = math.ceil(#itemData / COLUMNS)
    local rowHeightScale = CELL_HEIGHT_SCALE + PADDING_Y_SCALE
    local totalHeightScale = totalRows * rowHeightScale
    self._scrollingFrame.CanvasSize = UDim2.new(0, 0, totalHeightScale, 0)
    
    log("[VirtualScroll] SetData: " .. #itemData .. " items")
    self:Refresh()
end

--[[
    Refreshes visible slots using deterministic modulo mapping.
    Pool index = (dataIndex - 1) % POOL_SIZE + 1
]]
function VirtualScrollManagerModule:Refresh()
    if #self._allItemData == 0 then
        for _, slot in self._slotPool do
            slot.Frame.Visible = false
            slot:SetData(nil)
        end
        return
    end

    local scrollY: number = self._scrollingFrame.CanvasPosition.Y
    
    -- Calculate row height synchronously (avoid AbsoluteCanvasSize race condition)
    -- Row Height = (Cell Scale + Padding Scale) * Viewport Height
    local rowHeightScale = CELL_HEIGHT_SCALE + PADDING_Y_SCALE
    local rowHeightPixels = rowHeightScale * self._scrollingFrame.AbsoluteSize.Y
    
    if rowHeightPixels <= 1 then -- Avoid div by zero or tiny pixels
        rowHeightPixels = 100 
    end
    
    -- Calculate visible range (indices)
    local firstVisibleRow = math.floor(scrollY / rowHeightPixels)
    
    -- Start a bit earlier for buffer (e.g. -1 row)
    local startRow = math.max(0, firstVisibleRow - 1) 
    local endRow = startRow + (POOL_SIZE / COLUMNS) - 1
    
    local startIndex = (startRow * COLUMNS) + 1
    local endIndex = math.min((endRow + 1) * COLUMNS, #self._allItemData)
    
    -- Track used slots to hide unused ones later
    local usedPoolIndices = {}
    
    -- Iterate through the range of items that SHOULD be visible/buffered
    for dataIndex = startIndex, endIndex do
        -- Modulo mapping: This ensures the same slot always handles this pattern
        local poolIndex = ((dataIndex - 1) % POOL_SIZE) + 1
        local slot = self._slotPool[poolIndex]
        
        if slot then
            self:_updateSlot(slot, dataIndex, self._allItemData[dataIndex])
            usedPoolIndices[poolIndex] = true
        end
    end
    
    -- Hide any pool slots that weren't touched in this pass
    -- (This happens at the very end of the list or if list is small)
    for i = 1, POOL_SIZE do
        if not usedPoolIndices[i] then
            local slot = self._slotPool[i]
            if slot.Frame.Visible then
                slot.Frame.Visible = false
                slot:SetData(nil)
            end
        end
    end
end

--[[
    Updates a single slot's position and data.
]]
function VirtualScrollManagerModule:_updateSlot(slot: ItemSlot.ItemSlot, dataIndex: number, itemData: ItemSlotData)
    -- Calculate grid position
    local zeroIndex = dataIndex - 1
    local row = math.floor(zeroIndex / COLUMNS)
    local col = zeroIndex % COLUMNS
    
    local xScale = col * (CELL_WIDTH_SCALE + PADDING_X_SCALE)
    local yScale = row * (CELL_HEIGHT_SCALE + PADDING_Y_SCALE)
    
    slot.Frame.Position = UDim2.new(xScale, 0, yScale, 0)
    slot.Frame.Size = UDim2.new(CELL_WIDTH_SCALE, 0, CELL_HEIGHT_SCALE, 0)
    slot.Frame.LayoutOrder = dataIndex
    
    -- Only update data/visuals if changed
    if slot.Data ~= itemData then
        slot:SetData(itemData)
        
        -- Setup Drag Drop
        if self._screenGui then
            local oldDetector = slot.Frame:FindFirstChild("ItemDragDetector")
            if oldDetector then oldDetector:Destroy() end
            
            local dragData = {
                ItemId = itemData.ItemIds[1] or "",
                TemplateId = itemData.TemplateId,
                Type = itemData.Type,
                Rarity = itemData.Rarity,
                SourceSlot = slot.Frame :: any,
                SourceToolbarSlot = itemData.EquippedSlot,
            }
            DragDrop.MakeDraggable(slot.Frame :: any, dragData, self._screenGui)
        end
    end
    
    slot.Frame.Visible = true
end

--[[
    Scroll handler.
]]
function VirtualScrollManagerModule:_onScroll()
    local newY: number = self._scrollingFrame.CanvasPosition.Y
    local dist = math.abs(newY - self._lastCanvasPosition)
    
    -- Refresh aggressively (small threshold) to prevent visual gaps
    if dist > 2 then 
        self._lastCanvasPosition = newY
        self:Refresh()
    end
end

-- Helper accessors
function VirtualScrollManagerModule:GetSlotAtIndex(dataIndex: number): ItemSlot.ItemSlot?
    local poolIndex = ((dataIndex - 1) % POOL_SIZE) + 1
    local slot = self._slotPool[poolIndex]
    -- Verify it's actually showing this data (it might be recycled)
    if slot and slot.Frame.Visible and slot.Data and slot.Data == self._allItemData[dataIndex] then
        return slot
    end
    return nil
end

function VirtualScrollManagerModule:GetDataAtIndex(dataIndex: number): ItemSlotData?
    return self._allItemData[dataIndex]
end

function VirtualScrollManagerModule:GetItemCount(): number
    return #self._allItemData
end

function VirtualScrollManagerModule:Destroy()
    self._janitor:Destroy()
    table.clear(self._slotPool)
    table.clear(self._allItemData)
end

return VirtualScrollManagerModule

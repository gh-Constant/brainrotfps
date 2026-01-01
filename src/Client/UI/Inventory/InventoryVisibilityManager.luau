--!strict
--[[
    InventoryVisibilityManager
    (Formerly ViewportRotationManager)

    Manages visibility and updates for ALL inventory slots (2D and 3D).
    Implements visibility culling (Lazy Loading) to optimize performance.
    
    Features:
    - Single Heartbeat loop for all updates
    - Culls off-screen items (hides generic UI elements + stops rotations)
    - O(1) registration/unregistration
]]

local RunService = game:GetService("RunService")

-- Configuration


-- Types
type SlotElements = {
    -- The main slot frame (required for bounds check)
    Frame: GuiObject,
    
    -- Elements to toggle visibility
    ToolIcon: ImageLabel?,
    Viewport: ViewportFrame?,
    NameLabel: TextLabel?,
    QuantityLabel: TextLabel?,
    EventsLabel: TextLabel?,
    RarityLabel: TextLabel?,
    
    -- 3D Spec (Optional)
    Camera: Camera?,
    Model: Model?,

    
    -- State
    IsVisible: boolean,
}

-- State
local isPaused = false
-- Using Frame as key
local registeredSlots: {[GuiObject]: SlotElements} = {}

local updateConnection: RBXScriptConnection? = nil

--[[
    The single loop that updates ALL registered slots.
    Uses os.clock() for consistent timing.
    
    NOTE: With VirtualScrollManager, bounds checking is no longer needed.
    All registered slots are guaranteed to be in the visible area.
    This loop now only handles 3D model rotation.
]]
local function startUpdateLoop()
    if updateConnection then return end
    
    updateConnection = RunService.Heartbeat:Connect(function()
        if isPaused then return end
        
        local currentTime = os.clock()
        
        for frame, data in pairs(registeredSlots) do
            -- 1. Validity Check
            if not frame.Parent then
                registeredSlots[frame] = nil
                continue
            end
            
            -- 2. With VirtualScrollManager, all registered slots are visible
            -- No bounds checking needed - virtual scroll only creates visible slots
            if not data.IsVisible then
                data.IsVisible = true
                -- Toggle Elements on
                if data.ToolIcon then data.ToolIcon.Visible = true end
                if data.Viewport and data.Camera then data.Viewport.Visible = true end
                if data.QuantityLabel then data.QuantityLabel.Visible = true end
                if data.EventsLabel then data.EventsLabel.Visible = true end
                if data.RarityLabel then data.RarityLabel.Visible = true end
            end
            

        end
    end)
end

--[[
    Stops the loop if no slots are registered.
]]
local function checkStopUpdateLoop()
    -- Check if table is empty using next()
    if next(registeredSlots) ~= nil then
        return -- Still have registered slots, keep loop running
    end
    
    if updateConnection then
        updateConnection:Disconnect()
        updateConnection = nil
    end
end

local InventoryVisibilityManager = {}

--[[
    Register a slot for visibility management.
    Handles both 2D and 3D slots.
]]
function InventoryVisibilityManager.Register(
    frame: GuiObject,
    elements: {
        ToolIcon: ImageLabel?,
        Viewport: ViewportFrame?,
        NameLabel: TextLabel?,
        QuantityLabel: TextLabel?,
        EventsLabel: TextLabel?,
        RarityLabel: TextLabel?,
        
        -- 3D Data (Optional)
        Camera: Camera?,
        Model: Model?,
        CenterCF: CFrame?,


    }
)
    registeredSlots[frame] = {
        Frame = frame,
        ToolIcon = elements.ToolIcon,
        Viewport = elements.Viewport,
        NameLabel = elements.NameLabel,
        QuantityLabel = elements.QuantityLabel,
        EventsLabel = elements.EventsLabel,
        RarityLabel = elements.RarityLabel,
        
        Camera = elements.Camera,
        Model = elements.Model,

        StartTime = if elements.Model then os.clock() else nil,
        
        IsVisible = true, -- Assume visible initially
    }
    
    startUpdateLoop()
end

--[[
    Unregister a slot.
]]
function InventoryVisibilityManager.Unregister(frame: GuiObject)
    registeredSlots[frame] = nil
    checkStopUpdateLoop()
end

--[[
    Updates just the visible elements for an existing registration.
    Useful when slot data changes (e.g. Quantity 1->2) but we want to keep 3D state.
]]
function InventoryVisibilityManager.UpdateVisibleElements(
    frame: GuiObject,
    elements: {
        ToolIcon: ImageLabel?,
        NameLabel: TextLabel?,
        QuantityLabel: TextLabel?,
        EventsLabel: TextLabel?,
        RarityLabel: TextLabel?,
    }
)
    local data = registeredSlots[frame]
    if not data then return end
    
    -- Update references (nil means "don't manage/hide", so it stays hidden)
    -- We assume the caller passes nil for elements that should be ignored/hidden
    data.ToolIcon = elements.ToolIcon
    data.NameLabel = elements.NameLabel
    data.QuantityLabel = elements.QuantityLabel
    data.EventsLabel = elements.EventsLabel
    data.RarityLabel = elements.RarityLabel
    
    -- Immediately apply visibility state if currently "Visible" in manager's eyes
    -- (If manager thinks it should be visible, ensure we show the new valid elements)
    if data.IsVisible then
        if data.ToolIcon then data.ToolIcon.Visible = true end
        if data.NameLabel then data.NameLabel.Visible = true end
        if data.QuantityLabel then data.QuantityLabel.Visible = true end
        if data.EventsLabel then data.EventsLabel.Visible = true end
        if data.RarityLabel then data.RarityLabel.Visible = true end
    end
end

--[[
    Pause logic (e.g. valid when inventory closed).
]]
function InventoryVisibilityManager.PauseAll()
    isPaused = true
end

--[[
    Resume logic.
]]
function InventoryVisibilityManager.ResumeAll()
    isPaused = false
end

--[[
    Clear all.
]]
function InventoryVisibilityManager.ClearAll()
    table.clear(registeredSlots)
    if updateConnection then
        updateConnection:Disconnect()
        updateConnection = nil
    end
end

return InventoryVisibilityManager

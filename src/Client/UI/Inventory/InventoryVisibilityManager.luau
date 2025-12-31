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
local ROTATION_SPEED = 10 -- Rotations per second

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
    CenterCF: CFrame?,
    Distance: number?,
    StartTime: number?,
    
    -- State
    IsVisible: boolean,
}

-- State
local isPaused = false
-- Using Frame as key
local registeredSlots: {[GuiObject]: SlotElements} = {}

local updateConnection: RBXScriptConnection? = nil

--[[
    The single loop that updates ALL slots.
    Uses os.clock() for consistent timing.
]]
local function startUpdateLoop()
    if updateConnection then return end
    
    updateConnection = RunService.Heartbeat:Connect(function()
        if isPaused then return end
        
        local currentTime = os.clock()
        
        -- Cache container bounds to avoid repetitive AbsolutePosition/Size calls
        local containerCache = {} 
        
        for frame, data in pairs(registeredSlots) do
            -- 1. Validity Check
            if not frame.Parent then
                registeredSlots[frame] = nil
                continue
            end
            
            -- 2. Determine Visibility
            local isVisible = true
            
            if not frame.Visible then
                isVisible = false
            else
                local container = frame.Parent
                if container and container:IsA("ScrollingFrame") then
                    -- Get container bounds (Cached)
                    local bounds = containerCache[container]
                    if not bounds then
                        local cPos = container.AbsolutePosition
                        local cSize = container.AbsoluteSize
                        bounds = {
                            top = cPos.Y,
                            bottom = cPos.Y + cSize.Y
                        }
                        containerCache[container] = bounds
                    end
                    
                    -- Get slot vertical position (Screen space)
                    local slotPos = frame.AbsolutePosition
                    local slotTop = slotPos.Y
                    
                    -- Optimization: Assume fixed height or read only if needed
                    local slotHeight = 84 -- Default slot size + padding roughly
                    if data.Viewport then
                        slotHeight = frame.AbsoluteSize.Y
                    end
                    
                    local slotBottom = slotTop + slotHeight
                    
                    -- Bounds Check
                    if slotBottom < bounds.top or slotTop > bounds.bottom then
                        isVisible = false
                    end
                end
            end
            
            -- 3. Apply Visibility State Change
            if isVisible ~= data.IsVisible then
                data.IsVisible = isVisible
                
                -- Toggle Elements
                if data.ToolIcon then data.ToolIcon.Visible = isVisible end
                -- Only show viewport if it was meant to be there (has Camera/Model)
                if data.Viewport and data.Camera then data.Viewport.Visible = isVisible end
                if data.NameLabel then data.NameLabel.Visible = isVisible end
                if data.QuantityLabel then data.QuantityLabel.Visible = isVisible end
                if data.EventsLabel then data.EventsLabel.Visible = isVisible end
                if data.RarityLabel then data.RarityLabel.Visible = isVisible end
            end
            
            -- 4. Perform Rotation (Only if visible and has 3D data)
            if isVisible and data.Viewport and data.Camera and data.Model and data.CenterCF and data.Distance and data.StartTime then
                local elapsed = currentTime - data.StartTime
                local angle = elapsed * ROTATION_SPEED * math.pi * 2
                local rotatedCF = data.CenterCF * CFrame.Angles(0, angle, 0)
                
                data.Camera.CFrame = CFrame.new(
                    rotatedCF.Position + Vector3.new(data.Distance, data.Distance * 0.3, data.Distance),
                    rotatedCF.Position
                )
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
        Distance: number?,
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
        CenterCF = elements.CenterCF,
        Distance = elements.Distance,
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

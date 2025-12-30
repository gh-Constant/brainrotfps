--!strict
--[[
    ViewportRotationManager - PERFORMANCE OPTIMIZED
    
    Centralizes all 3D viewport rotation into a SINGLE shared loop.
    Instead of each ItemSlot creating its own RenderStepped connection,
    this manager handles ALL rotations with one connection.
    
    Features:
    - Single Heartbeat connection for ALL viewports
    - Automatic pause when inventory is closed
    - O(1) registration/unregistration
    - Automatic cleanup of destroyed viewports
]]

local RunService = game:GetService("RunService")

-- Configuration
local ROTATION_SPEED = 10 -- Rotations per second

-- State
local isPaused = false
local rotatingViewports: {[ViewportFrame]: {
    camera: Camera,
    model: Model,
    centerCF: CFrame,
    distance: number,
    startTime: number,
}} = {}

local rotationConnection: RBXScriptConnection? = nil

--[[
    The single rotation loop that updates ALL viewports.
    Uses os.clock() for consistent timing.
]]
local function startRotationLoop()
    if rotationConnection then return end
    
    rotationConnection = RunService.Heartbeat:Connect(function()
        if isPaused then return end
        
        local currentTime = os.clock()
        
        for viewport, data in pairs(rotatingViewports) do
            -- Skip if viewport was destroyed
            if not viewport.Parent then
                rotatingViewports[viewport] = nil
                continue
            end
            
            -- Skip if viewport is not visible
            if not viewport.Visible then
                continue
            end
            
            -- Also check parent frame visibility
            local parent = viewport.Parent
            if parent and parent:IsA("GuiObject") and not parent.Visible then
                continue
            end
            
            -- Calculate rotation based on elapsed time since registration
            local elapsed = currentTime - data.startTime
            local angle = elapsed * ROTATION_SPEED * math.pi * 2
            local rotatedCF = data.centerCF * CFrame.Angles(0, angle, 0)
            
            -- Update camera position
            data.camera.CFrame = CFrame.new(
                rotatedCF.Position + Vector3.new(data.distance, data.distance * 0.3, data.distance),
                rotatedCF.Position
            )
        end
    end)
end

--[[
    Stops the rotation loop if no viewports are registered.
]]
local function checkStopRotationLoop()
    local count = 0
    for _ in pairs(rotatingViewports) do
        count = count + 1
        if count > 0 then return end
    end
    
    if rotationConnection then
        rotationConnection:Disconnect()
        rotationConnection = nil
    end
end

local ViewportRotationManager = {}

--[[
    Register a viewport for rotation.
    
    @param viewport - The ViewportFrame to rotate
    @param camera - The camera inside the viewport
    @param model - The model being displayed
    @param centerCF - The center CFrame to rotate around
    @param distance - Distance from camera to model center
]]
function ViewportRotationManager.Register(
    viewport: ViewportFrame,
    camera: Camera,
    model: Model,
    centerCF: CFrame,
    distance: number
)
    rotatingViewports[viewport] = {
        camera = camera,
        model = model,
        centerCF = centerCF,
        distance = distance,
        startTime = os.clock(),
    }
    startRotationLoop()
end

--[[
    Unregister a viewport from rotation.
    Call this when the slot is cleared or destroyed.
    
    @param viewport - The ViewportFrame to stop rotating
]]
function ViewportRotationManager.Unregister(viewport: ViewportFrame)
    rotatingViewports[viewport] = nil
    checkStopRotationLoop()
end

--[[
    Pause all viewport rotations.
    Call when inventory UI closes.
]]
function ViewportRotationManager.PauseAll()
    isPaused = true
end

--[[
    Resume all viewport rotations.
    Call when inventory UI opens.
]]
function ViewportRotationManager.ResumeAll()
    isPaused = false
end

--[[
    Get the count of active rotating viewports (for debugging).
]]
function ViewportRotationManager.GetCount(): number
    local count = 0
    for _ in pairs(rotatingViewports) do
        count = count + 1
    end
    return count
end

--[[
    Clear all registered viewports.
    Call on inventory destruction.
]]
function ViewportRotationManager.ClearAll()
    table.clear(rotatingViewports)
    if rotationConnection then
        rotationConnection:Disconnect()
        rotationConnection = nil
    end
end

return ViewportRotationManager

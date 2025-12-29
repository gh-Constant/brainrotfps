--!strict
--[[
    ZebraSynced - Custom Zebra effect preset with synchronized animation timing.
    Uses os.clock() to ensure all Zebra effects animate in phase regardless of creation time.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage:WaitForChild("Rojo"):WaitForChild("Packages")
local ezVisuals = require(Packages:WaitForChild("ezvisualz"))

--[[
    Creates a synchronized zebra gradient effect on the given UI instance.
    All effects created with this function will animate in sync.
]]
local function createZebraSynced(uiInstance: GuiObject, speed: number?, size: number?)
    local effectSpeed = speed or 0.007
    local effectSize = size or 1
    
    -- Sync offset to global time so all Zebra effects animate in phase
    local syncedOffset = (os.clock() * effectSpeed) % 1
    
    local mainGradient = ezVisuals.Gradient.new(uiInstance, ezVisuals.Templates.Zebra.Color, 0)
    mainGradient.Offset = syncedOffset
    mainGradient:SetOffsetSpeed(effectSpeed, 1)
    mainGradient:SetRotation(90, 1)

    local mainStroke = ezVisuals.Stroke.new(uiInstance, effectSize)

    local strokeGradient = ezVisuals.Gradient.new(mainStroke.Instance, ezVisuals.Templates.Zebra.Color, 0)
    strokeGradient.Offset = syncedOffset + 0.5
    strokeGradient:SetRotation(90, 1)
    strokeGradient:SetOffsetSpeed(effectSpeed, 1)

    -- Return an effect-like object that can be destroyed
    local effect = {
        EffectObjects = { mainGradient, strokeGradient, mainStroke },
        IsPaused = false,
    }
    
    function effect:Pause()
        for _, obj in self.EffectObjects do
            if obj.Pause then obj:Pause() end
        end
    end
    
    function effect:Resume()
        for _, obj in self.EffectObjects do
            if obj.Resume then obj:Resume() end
        end
    end
    
    function effect:Destroy()
        for _, obj in self.EffectObjects do
            if obj.Destroy then obj:Destroy() end
        end
    end
    
    return effect
end

return createZebraSynced

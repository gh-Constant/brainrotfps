--!strict
--[[
    RainbowSynced - Custom Rainbow effect preset with synchronized animation timing.
    Uses os.clock() to ensure all Rainbow effects animate in phase regardless of creation time.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage:WaitForChild("Rojo"):WaitForChild("Packages")
local ezVisuals = require(Packages:WaitForChild("ezvisualz"))

--[[
    Creates a synchronized rainbow gradient effect on the given UI instance.
    All effects created with this function will animate in sync.
]]
local function createRainbowSynced(uiInstance: GuiObject, speed: number?, size: number?)
    local effectSpeed = speed or 0.007
    
    -- Sync offset to global time so all Rainbow effects animate in phase
    local syncedOffset = (os.clock() * effectSpeed) % 1
    
    local mainGradient = ezVisuals.Gradient.new(uiInstance, ezVisuals.Templates.Rainbow.Color, 0)
    mainGradient.Offset = syncedOffset
    mainGradient:SetOffsetSpeed(effectSpeed, 1)

    -- Return an effect-like object that can be destroyed
    local effect = {
        EffectObjects = { mainGradient },
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

return createRainbowSynced

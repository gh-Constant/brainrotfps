--!strict
--[[
    PvPToggle
    Handles the PvP toggle UI and server synchronization.
    
    Expected UI Structure:
    - Base/Left/PVP/ActiveValue (BoolValue)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Packets = require(Rojo:WaitForChild("Shared"):WaitForChild("Packets"))

local PvPToggle = {}

function PvPToggle.Init(context: any)
    local leftFrame = context.LeftFrame
    if not leftFrame then return end
    
    local pvpFrame = leftFrame:FindFirstChild("PVP")
    if not pvpFrame then
        warn("[PvPToggle] PVP frame not found!")
        return
    end
    
    local activeValue = pvpFrame:FindFirstChild("ActiveValue")
    if not activeValue or not activeValue:IsA("BoolValue") then
        warn("[PvPToggle] PVP.ActiveValue not found or not a BoolValue!")
        return
    end
    
    -- Listen for changes and send to server
    activeValue.Changed:Connect(function(enabled)
        Packets.pvpToggle.send({ enabled = enabled })
        print(string.format("[PvPToggle] PvP toggled to %s", tostring(enabled)))
    end)
    
    -- Send initial state
    task.defer(function()
        Packets.pvpToggle.send({ enabled = activeValue.Value })
    end)
    
    print("[PvPToggle] Initialized!")
end

return PvPToggle

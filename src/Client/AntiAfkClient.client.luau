--!strict
--[[
    AntiAfkClient
    Monitors user input to detect AFK status.
    If AFK for 17 minutes, requests a server rejoin to prevent Roblox idle kick.
]]
local REQ_MINS = 17 -- Rejoin after 17 minutes of inactivity
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local Packets = require(ReplicatedStorage.Rojo.Shared.Packets)

local CHECK_INTERVAL = 1 -- Check every second

local timeIdx = 0
local reqSeconds = REQ_MINS * 60

local function resetTimer()
    timeIdx = 0
end

-- Connect input listeners
UserInputService.InputBegan:Connect(resetTimer)
UserInputService.InputEnded:Connect(resetTimer)

local player = Players.LocalPlayer
local mouse = player:GetMouse()
mouse.Move:Connect(resetTimer)

-- Start monitoring loop
task.spawn(function()
    while true do
        task.wait(CHECK_INTERVAL)
        timeIdx += CHECK_INTERVAL
        
        if timeIdx >= reqSeconds then
            warn("[AntiAFK] You have been AFK for " .. REQ_MINS .. " minutes. Rejoining to prevent idle kick...")
            
            -- Wait a moment to show warning
            task.wait(3)
            
            -- Send rejoin request via ByteNet
            Packets.requestRejoin.send({})
            
            -- Stop checking
            break
        end
    end
end)

print("[AntiAFK] Client monitor started.")

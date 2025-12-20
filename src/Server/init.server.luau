-- Server entry point
-- This script runs on the server

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local _Shared = Rojo:WaitForChild("Shared")

local SafezoneManager = require(script.SafezoneManager)

print("[Server] Server initialized!")

-- Initialize systems
SafezoneManager.Init()

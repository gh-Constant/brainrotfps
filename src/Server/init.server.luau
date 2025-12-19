-- Server entry point
-- This script runs on the server

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")

print("[Server] Server initialized!")

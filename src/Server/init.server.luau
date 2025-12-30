-- Server entry point
-- This script runs on the server

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local _Shared = Rojo:WaitForChild("Shared")

-- Managers
local PlayerManager = require(script.Player)
local SafezoneManager = require(script.SafezoneManager)
local CmdrSetup = require(script.CmdrSetup)
local BrainrotSpawner = require(script.Brainrot.BrainrotSpawner)
local InventoryManager = require(script.Inventory)
local GrenadeService = require(script.Weapons.GrenadeService)
local BuffService = require(script.Buffs.BuffService)

local IndexSystem = require(script.Index.IndexSystem)

print("[Server] Server initialized!")

-- Initialize systems
InventoryManager.Init()  -- Initialize first for packet listeners
PlayerManager.Init()     -- Handles data, death, ragdoll, VFX
BuffService.Init()       -- Handles XP/Gold buffs (Must be after PlayerManager)
SafezoneManager.Init()   -- Handles safezones
CmdrSetup.Init()         -- Handles Cmdr command console
BrainrotSpawner.Init()   -- Handles brainrot spawning in zones
GrenadeService.Init()    -- Handles grenades
IndexSystem.Init()       -- Handles mob index

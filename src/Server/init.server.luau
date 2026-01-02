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
local PotionService = require(script.Weapons.PotionService)
local BuffService = require(script.Buffs.BuffService)
local GamePassService = require(script.Monetization.GamePassService)
local LeaderboardService = require(script.Leaderboard.LeaderboardService)

local IndexSystem = require(script.Index.IndexSystem)

print("[Server] Server initialized!")


-- Initialize systems
local ItemUtils = require(_Shared:WaitForChild("Inventory"):WaitForChild("ItemUtils"))
ItemUtils.PreloadCache() -- Warm up item cache to prevent lag spikes

InventoryManager.Init()  -- Initialize first for packet listeners
PlayerManager.Init()     -- Handles data, death, ragdoll, VFX
BuffService.Init()       -- Handles XP/Gold buffs (Must be after PlayerManager)
GamePassService.Init()   -- Handles gamepass multipliers (2x XP, Gold, Damage)
SafezoneManager.Init()   -- Handles safezones
CmdrSetup.Init()         -- Handles Cmdr command console
BrainrotSpawner.Init()   -- Handles brainrot spawning in zones
GrenadeService.Init()    -- Handles grenades
PotionService.Init()     -- Handles potions
IndexSystem.Init()       -- Handles mob index

-- Initialize Leaderboard System
LeaderboardService.Init()
LeaderboardService.RegisterLeaderboard("TotalXP", { DisplayName = "Total XP" })
LeaderboardService.RegisterLeaderboard("Level", { DisplayName = "Level" })
LeaderboardService.RegisterLeaderboard("BrainrotKills", { DisplayName = "Brainrot Kills" })
LeaderboardService.RegisterLeaderboard("TotalDamage", { DisplayName = "Total Damage" })
LeaderboardService.RegisterLeaderboard("PlayerKills", { DisplayName = "Player Kills" })

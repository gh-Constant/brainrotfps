--!strict
--[[
	Cmdr Server Setup
	Initializes Cmdr command framework on the server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Packages = Rojo:WaitForChild("Packages")

local Cmdr = require(Packages:WaitForChild("cmdr"))

local CmdrSetup = {}

-- Admin user IDs (add your Roblox user ID here)
local ADMIN_USER_IDS: {number} = {
	-- Add admin user IDs here, e.g.:
	-- 12345678,
}

-- Admin group settings (optional)
local ADMIN_GROUP_ID = 459737860 -- Set to your group ID, or 0 to disable
local ADMIN_MIN_RANK = 253 -- Minimum rank in the group to be an admin

--[[
	Check if a player is an admin.
]]
local function isAdmin(player: Player): boolean
	-- Check user ID list
	if table.find(ADMIN_USER_IDS, player.UserId) then
		return true
	end
	
	-- Check group rank
	if ADMIN_GROUP_ID > 0 then
		local success, rank = pcall(function()
			return player:GetRankInGroup(ADMIN_GROUP_ID)
		end)
		if success and rank >= ADMIN_MIN_RANK then
			return true
		end
	end
	
	-- Studio testing: allow all in Studio
	if game:GetService("RunService"):IsStudio() then
		return true
	end
	
	return false
end

function CmdrSetup.Init()
	-- Register built-in commands
	-- Admin commands: announce, kick, kill, teleport, respawn, etc.
	Cmdr:RegisterDefaultCommands()
	
	-- Register custom types for autocomplete (must be before commands!)
	local typesFolder = script.Parent:FindFirstChild("CmdrTypes")
	if typesFolder then
		Cmdr.Registry:RegisterTypesIn(typesFolder)
		print("[Cmdr] Custom types registered from CmdrTypes folder")
	end
	
	-- Register custom commands from Commands folder
	local commandsFolder = script.Parent:FindFirstChild("Commands")
	if commandsFolder then
		Cmdr:RegisterCommandsIn(commandsFolder)
		
		-- Debug: Check if commands were replicated
		task.wait(0.1)
		local replicatedCommands = Cmdr.ReplicatedRoot:FindFirstChild("Commands")
		if replicatedCommands then
			print("[Cmdr] Commands replicated to:", replicatedCommands:GetFullName())
		else
			warn("[Cmdr] Commands folder not found in ReplicatedRoot!")
		end
	end
	
	-- Set up command permission hook
	Cmdr.Registry:RegisterHook("BeforeRun", function(context)
		-- Allow help command for everyone
		if context.Name == "help" then
			return nil
		end
		
		-- Check admin permissions for other commands
		if not isAdmin(context.Executor) then
			return "You don't have permission to run this command." :: any
		end
		
		return nil :: any -- Allow command to run
	end)
	
	print("[Cmdr] Server initialized with commands!")
end

return CmdrSetup

--!strict
--[[
	Cmdr Client Setup
	Initializes Cmdr command console on the client.
	
	Default keybind: F2 to open/close the console
	(Can be changed via Cmdr:SetActivationKeys)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CmdrClient

local CmdrClientSetup = {}

function CmdrClientSetup.Init()
	-- Wait for CmdrClient to be replicated from server
	local cmdrClient = ReplicatedStorage:WaitForChild("CmdrClient")
	if not cmdrClient then
		warn("[Cmdr] CmdrClient not found - server may not have initialized Cmdr")
		return
	end
	
	CmdrClient = require(cmdrClient)
	
	-- Wait for Commands folder to be created by server
	local commandsFolder = cmdrClient:WaitForChild("Commands", 5)
	if commandsFolder then
		-- Wait for custom commands to be replicated (server moves them here)
		-- We'll wait up to 2 seconds for at least one custom command to appear
		local maxWait = 2
		local elapsed = 0
		local foundCustomCommands = false
		
		while elapsed < maxWait and not foundCustomCommands do
			for _, child in ipairs(commandsFolder:GetChildren()) do
				-- Check if any of our custom commands have appeared
				if child.Name == "broadcast" or child.Name == "suicide" then
					foundCustomCommands = true
					print("[Cmdr] Found custom command:", child.Name)
					break
				end
			end
			
			if not foundCustomCommands then
				task.wait(0.1)
				elapsed = elapsed + 0.1
			end
		end
		
		if foundCustomCommands then
			print("[Cmdr] Custom commands replicated, registering all commands...")
		else
			warn("[Cmdr] Timeout waiting for custom commands, proceeding anyway...")
		end
		
		-- Now register all commands
		print("[Cmdr] Registering commands from:", commandsFolder:GetFullName())
		CmdrClient.Registry:RegisterCommandsIn(commandsFolder)
	else
		warn("[Cmdr] Commands folder not found in CmdrClient!")
	end
	
	-- Set custom activation keys (F2 only)
	CmdrClient:SetActivationKeys({ Enum.KeyCode.F2 })
	
	-- Verify registration
	local clientCommands = CmdrClient.Registry:GetCommandNames()
	print("[Cmdr] Client has access to " .. #clientCommands .. " commands")
	
	local customFound = {}
	for _, cmdName in ipairs(clientCommands) do
		if cmdName == "broadcast" or cmdName == "suicide" then
			table.insert(customFound, cmdName)
		end
	end
	
	if #customFound > 0 then
		print("[Cmdr] ✓ Custom commands loaded:", table.concat(customFound, ", "))
	else
		warn("[Cmdr] ✗ Custom commands not found in registry!")
	end
	
	print("[Cmdr] Client console ready! Press F2 to open.")
end

--[[
	Gets the CmdrClient instance (for running commands programmatically)
]]
function CmdrClientSetup.GetClient()
	return CmdrClient
end

return CmdrClientSetup

local ServerScriptService = game:GetService("ServerScriptService")

local Rojo = ServerScriptService:WaitForChild("Rojo")
local Server = Rojo:WaitForChild("Server")
local BrainrotSpawner = require(Server:WaitForChild("Brainrot"):WaitForChild("BrainrotSpawner"))

return function(context, zoneName, mobName, mutationName)
	-- Call spawner with mutation
	local success, result = pcall(function()
		return BrainrotSpawner.SpawnBrainrotWithMutation(zoneName, mobName, mutationName)
	end)
	
	if not success then
		return "Error spawning mob: " .. tostring(result)
	end
	
	if result then
		local mutationInfo = mutationName and (" with mutation: " .. mutationName) or ""
		return string.format("Spawned %s in %s%s", mobName, zoneName, mutationInfo)
	else
		return "Failed to spawn mob. Check zone/mob names."
	end
end

return function(context)
	local player = context.Executor
	local ServerScriptService = game:GetService("ServerScriptService")
	
	if not player.Character then
		return "You don't have a character!"
	end
	
	-- Check if already dead
	if player.Character:GetAttribute("IsDead") then
		return "You're already dead!"
	end
	
	-- Reset progress (Level/XP)
	local PlayerManager = require(ServerScriptService.Rojo.Server.Player)
	local playerData = PlayerManager.GetPlayerData(player)
	if playerData then
		playerData:ResetProgress()
	end

	-- Directly set health to 0 (bypasses PVP checks)
	-- This is intentional for suicide command
	-- Use task.delay to ensure ResetProgress propagates if needed, but it should be instant
	player.Character:SetAttribute("Health", 0)
	
	return "Committing suicide..."
end

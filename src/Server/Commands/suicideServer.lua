return function(context, targetPlayer)
	local executor = context.Executor
    local target = targetPlayer or executor
	local ServerScriptService = game:GetService("ServerScriptService")
	
	if not target.Character then
		return target.Name .. " doesn't have a character!"
	end
	
	-- Check if already dead
	if target.Character:GetAttribute("IsDead") then
		return target.Name .. " is already dead!"
	end
	
	-- Reset progress (Level/XP)
	local PlayerManager = require(ServerScriptService.Rojo.Server.Player)
	local playerData = PlayerManager.GetPlayerData(target)
	if playerData then
		playerData:ResetProgress()
	end

	-- Directly set health to 0 (bypasses PVP checks)
	target.Character:SetAttribute("Health", 0)
	
    if target == executor then
	    return "Committing suicide..."
    else
        return "Killed " .. target.Name
    end
end

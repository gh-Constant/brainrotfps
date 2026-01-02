local ServerScriptService = game:GetService("ServerScriptService")
local Server = ServerScriptService:WaitForChild("Rojo"):WaitForChild("Server")
local DailyRewardsService = require(Server:WaitForChild("Rewards"):WaitForChild("DailyRewardsService"))
local PlayerManager = require(Server:WaitForChild("Player"))

-- Time constants
local TWENTY_FIVE_HOURS = 25 * 3600

return function(_, target)
	local playerData = PlayerManager.GetPlayerData(target)
	if playerData then
		-- Set last claim to 25 hours ago so they can claim again
		playerData.LastDailyRewardClaim = os.time() - TWENTY_FIVE_HOURS
		DailyRewardsService.SendRewardsState(target)
		return "Skipped cooldown for " .. target.Name
	end
	return "Could not find player data for " .. target.Name
end

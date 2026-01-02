local ServerScriptService = game:GetService("ServerScriptService")
local Server = ServerScriptService:WaitForChild("Rojo"):WaitForChild("Server")
local DailyRewardsService = require(Server:WaitForChild("Rewards"):WaitForChild("DailyRewardsService"))
local PlayerManager = require(Server:WaitForChild("Player"))

return function(_, target)
	local playerData = PlayerManager.GetPlayerData(target)
	if playerData then
		playerData.LastDailyRewardClaim = 0
		playerData.DailyRewardStreak = 1
		DailyRewardsService.SendRewardsState(target)
		return "Reset daily rewards for " .. target.Name
	end
	return "Could not find player data for " .. target.Name
end

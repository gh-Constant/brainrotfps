local Rewards = script.Parent.Parent:WaitForChild("Rewards")
local HourlyRewardsService = require(Rewards:WaitForChild("HourlyRewardsService"))

return function(_, player: Player)
	HourlyRewardsService.ResetSession(player)
	return `Reset hourly rewards session for {player.Name}.`
end

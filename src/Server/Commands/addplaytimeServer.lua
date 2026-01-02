local Rewards = script.Parent.Parent:WaitForChild("Rewards")
local HourlyRewardsService = require(Rewards:WaitForChild("HourlyRewardsService"))

return function(_, player: Player, minutes: number)
	HourlyRewardsService.AddPlaytime(player, minutes * 60)
	return `Added {minutes} minutes of playtime to {player.Name}.`
end

local ServerScriptService = game:GetService("ServerScriptService")
local Server = ServerScriptService.Rojo.Server
local PlayerManager = require(Server.Player)

return function(_, target)
	local playerData = PlayerManager.GetPlayerData(target)
	if not playerData then
		return "Failed to find player data."
	end

	playerData.ChestCooldowns = {}
	return string.format("Reset chest cooldowns for %s.", target.Name)
end

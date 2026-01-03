local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Rojo = ServerScriptService.Rojo
local Server = Rojo.Server
local AntiAfkService = require(Server.AntiAfkService)

return function(context, targetPlayer)
	local playerToRejoin = targetPlayer or context.Executor
	
	if not playerToRejoin then
		return "You must specify a player if running from console."
	end
	
	AntiAfkService.Rejoin(playerToRejoin)
	
	return "Triggered Anti-AFK rejoin for " .. playerToRejoin.Name
end

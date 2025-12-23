local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")
local Health = require(Shared:WaitForChild("Health"))

return function(context)
	local player = context.Executor
	
	if not player.Character then
		return "You don't have a character!"
	end
	
	-- Use custom Health system to kill
	local health = Health.Get(player.Character)
	if health then
		health:TakeDamage(math.huge, player)
		return "Committing suicide..."
	else
		return "Failed to access health system!"
	end
end

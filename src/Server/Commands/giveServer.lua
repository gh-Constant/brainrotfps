local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Rojo = ServerScriptService.Rojo
local Server = Rojo.Server
local PlayerManager = require(Server.Player)

return function(context, targetPlayer, resourceType, amount)
	-- Validate amount
	if amount <= 0 then
		return "Amount must be positive!"
	end
	
	-- Get player data
	local playerData = PlayerManager.GetPlayerData(targetPlayer)
	if not playerData then
		return "Player data not found for " .. targetPlayer.Name
	end
	
	local resourceTypeLower = string.lower(resourceType)
	
	if resourceTypeLower == "level" or resourceTypeLower == "levels" then
		-- Add levels by giving enough XP to level up that many times
		local levelsToAdd = amount
		local xpNeeded = 0
		
		for i = 1, levelsToAdd do
			local targetLevel = playerData.Level + i - 1
			xpNeeded = xpNeeded + playerData:GetExperienceForLevel(targetLevel) - (i == 1 and playerData.Experience or 0)
		end
		
		-- Simpler approach: just set level directly and reset XP
		local newLevel = playerData.Level + levelsToAdd
		playerData.Level = newLevel
		playerData.Experience = 0
		
		-- Fire level up event
		if playerData.OnLevelUp then
			playerData.OnLevelUp:Fire(newLevel)
		end
		
		-- Update character max health
		if targetPlayer.Character then
			local newMaxHealth = playerData:GetMaxHealthForLevel(newLevel)
			targetPlayer.Character:SetAttribute("MaxHealth", newMaxHealth)
			targetPlayer.Character:SetAttribute("Health", newMaxHealth)
		end
		
		return string.format("Gave %d level(s) to %s. New level: %d", levelsToAdd, targetPlayer.Name, newLevel)
		
	elseif resourceTypeLower == "gold" or resourceTypeLower == "coins" or resourceTypeLower == "money" then
		playerData:AddGold(amount)
		return string.format("Gave %d gold to %s. New balance: %d", amount, targetPlayer.Name, playerData.Gold)
		
	elseif resourceTypeLower == "xp" or resourceTypeLower == "experience" or resourceTypeLower == "exp" then
		local leveledUp = playerData:AddExperience(amount)
		local levelInfo = leveledUp and string.format(" (Leveled up to %d!)", playerData.Level) or ""
		return string.format("Gave %d XP to %s.%s", amount, targetPlayer.Name, levelInfo)
		
	else
		return "Invalid resource type! Use: level, gold, or xp"
	end
end

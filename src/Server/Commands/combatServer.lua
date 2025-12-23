return function(context)
	local player = context.Executor
	
	if not player.Character then
		return "You don't have a character!"
	end
	
	local character = player.Character
	
	-- Start combat mode with 13 second countdown
	character:SetAttribute("InCombat", true)
	local combatTimer = (character:GetAttribute("_CombatTimer") :: number?) or 0
	local newTimer = combatTimer + 1
	character:SetAttribute("_CombatTimer", newTimer)
	character:SetAttribute("CombatCountdown", 13)
	
	-- Start countdown
	task.spawn(function()
		for i = 13, 0, -1 do
			if not character or not character.Parent then
				break
			end
			if character:GetAttribute("_CombatTimer") ~= newTimer then
				break
			end
			character:SetAttribute("CombatCountdown", i)
			if i == 0 then
				character:SetAttribute("InCombat", false)
				character:SetAttribute("CombatCountdown", nil)
			else
				task.wait(1)
			end
		end
	end)
	
	return "Combat mode started! 13 second countdown..."
end

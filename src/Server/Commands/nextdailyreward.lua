return {
	Name = "nextdailyreward",
	Aliases = {"nextdr"},
	Description = "Skips the cooldown for a player's daily reward for testing.",
	Group = "Admins",
	Args = {
		{
			Type = "player",
			Name = "target",
			Description = "The player to skip cooldown for.",
		}
	}
}

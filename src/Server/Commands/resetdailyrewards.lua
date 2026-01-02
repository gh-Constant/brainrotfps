return {
	Name = "resetdailyrewards",
	Aliases = {"resetdr"},
	Description = "Resets a player's daily reward progress for testing.",
	Group = "Admins",
	Args = {
		{
			Type = "player",
			Name = "target",
			Description = "The player to reset.",
		}
	}
}

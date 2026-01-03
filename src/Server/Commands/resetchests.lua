return {
	Name = "resetchests",
	Aliases = {"clearchests"},
	Description = "Resets a player's chest cooldowns.",
	Group = "Admin",
	Args = {
		{
			Type = "player",
			Name = "Target",
			Description = "The player to reset chest cooldowns for.",
		}
	},
}

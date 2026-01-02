return {
	Name = "resethourly",
	Aliases = {"rh"},
	Description = "Resets hourly reward claims and session playtime for a player.",
	Group = "Admin",
	Args = {
		{
			Type = "player",
			Name = "Player",
			Description = "The player to reset.",
		}
	},
}

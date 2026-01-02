return {
	Name = "addplaytime",
	Aliases = {"ap"},
	Description = "Adds session playtime to a player (for testing hourly rewards).",
	Group = "Admin",
	Args = {
		{
			Type = "player",
			Name = "Player",
			Description = "The player to add playtime to.",
		},
		{
			Type = "number",
			Name = "Minutes",
			Description = "The number of minutes to add.",
		},
	},
}

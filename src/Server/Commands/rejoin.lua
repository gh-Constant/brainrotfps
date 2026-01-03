return {
	Name = "rejoin";
	Aliases = {"rejoinserver", "antiafktest"};
	Description = "Trigger Anti-AFK rejoin manually for testing.";
	Group = "Admin";
	Args = {
		{
			Type = "player";
			Name = "Player";
			Description = "The player to rejoin (optional, defaults to self).";
			Optional = true;
		},
	};
}

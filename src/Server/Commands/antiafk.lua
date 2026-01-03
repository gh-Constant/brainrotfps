return {
	Name = "antiafk";
	Aliases = {"rejoin", "afkrejoin"};
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

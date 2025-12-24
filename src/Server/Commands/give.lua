return {
	Name = "give";
	Aliases = {"giveplayer"};
	Description = "Give a player levels, gold, or XP.";
	Group = "Admin";
	Args = {
		{
			Type = "player";
			Name = "Player";
			Description = "The player to give resources to.";
		},
		{
			Type = "string";
			Name = "Type";
			Description = "What to give: level, gold, xp";
		},
		{
			Type = "integer";
			Name = "Amount";
			Description = "Amount to give.";
		},
	};
}

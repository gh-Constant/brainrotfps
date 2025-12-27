return {
	Name = "give";
	Aliases = {"giveplayer"};
	Description = "Give a player levels, gold, xp, or credits.";
	Group = "Admin";
	Args = {
		{
			Type = "player";
			Name = "Player";
			Description = "The player to give resources to.";
		},
		{
			Type = "resourceType";
			Name = "Type";
			Description = "What to give";
		},
		{
			Type = "number";
			Name = "Amount";
			Description = "Amount to give.";
		},
	};
}

return {
	Name = "spawnmob",
	Aliases = {"spawn"},
	Description = "Spawn a mob in a specific zone with optional mutation.",
	Group = "Admin",
	Args = {
		{
			Type = "zoneName",
			Name = "Zone",
			Description = "The zone to spawn the mob in.",
		},
		{
			Type = "mobName",
			Name = "Mob",
			Description = "The mob to spawn.",
		},
		{
			Type = "mutationType",
			Name = "Mutation",
			Description = "Optional mutation to apply (or 'none').",
			Optional = true,
		},
	},
}

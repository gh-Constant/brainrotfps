return {
	Name = "suicide";
	Aliases = {"kill", "die"};
	Description = "Kill yourself instantly.";
	Group = "Admin";
	Args = {
        {
            Type = "player",
            Name = "target",
            Description = "The player to kill (optional)",
            Optional = true,
        }
    };
}

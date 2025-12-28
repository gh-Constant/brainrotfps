return {
    Name = "viewinventory",
    Aliases = {"inv", "seeinv"},
    Description = "View a player's inventory items",
    Group = "Admin",
    Args = {
        {
            Type = "player",
            Name = "target",
            Description = "The player to view (optional, defaults to self)",
            Optional = true,
        }
    },
}

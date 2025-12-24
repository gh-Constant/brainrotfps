-- clearinventory command definition
-- Usage: clearinventory <player>
return {
    Name = "clearinventory",
    Aliases = {"ci", "clearinv"},
    Description = "Clears all items from a player's inventory",
    Group = "Admin",
    Args = {
        {
            Type = "player",
            Name = "player",
            Description = "The player whose inventory to clear",
        },
    },
}

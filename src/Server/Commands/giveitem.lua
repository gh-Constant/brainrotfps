-- giveitem command definition
-- Usage: giveitem <player> <itemName>
-- Type and Rarity are read from Config/Items automatically
return {
    Name = "giveitem",
    Aliases = {"gi"},
    Description = "Gives an item to a player's inventory",
    Group = "Admin",
    Args = {
        {
            Type = "player",
            Name = "player",
            Description = "The player to give the item to",
        },
        {
            Type = "itemName",
            Name = "item",
            Description = "The item to give (from Config/Items)",
        },
        {
            Type = "string",
            Name = "mutations",
            Description = "Optional mutations (format: Mutation1:Count,Mutation2:Count)",
            Optional = true,
        },
    },
}

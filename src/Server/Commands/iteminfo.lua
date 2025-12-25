-- iteminfo command definition
return {
    Name = "iteminfo",
    Aliases = { "itemreg", "checkitem" },
    Description = "Looks up an item's registry data by ID",
    Group = "Admin",
    Args = {
        {
            Type = "string",
            Name = "itemId",
            Description = "The item's unique ID (or 'first' for first inventory item)",
        },
    },
}

return {
	Name = "broadcast";
	Aliases = {"bc"};
	Description = "Broadcasts a message to ALL players across ALL servers.";
	Group = "Admin";
	Args = {
		{
			Type = "string";
			Name = "message";
			Description = "The message to broadcast.";
		},
		{
			Type = "string";
			Name = "creator";
			Description = "The creator/sender name to display.";
		},
		{
			Type = "string";
			Name = "color";
			Description = "Color: white, red, green, blue, yellow, purple, rainbow";
			Default = "white";
		},
	};
}

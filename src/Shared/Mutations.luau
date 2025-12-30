--!strict
--[[
	Mutations.luau
	Defines all possible mutations for mobs/brainrots.
	Each mutation has visual properties and stat modifiers.
]]

export type MutationData = {
	Display: string,
	DisplayWithRichText: string,
	Icon: string,
	Color: Color3,
	MultiplierModifier: number,
}

local Mutations: { [string]: MutationData } = {
	Taco = {
		Display = "Taco";
		DisplayWithRichText = "<font color=\"#FFDE59\">Taco</font>";
		Icon = "rbxassetid://89041930759464";
		Color = Color3.fromRGB(255, 222, 89);
		MultiplierModifier = 2;
	};

	Nyan = {
		Display = "Nyan";
		DisplayWithRichText = "<font color=\"#EE59FF\">Nyan</font>";
		Icon = "rbxassetid://104229924295526";
		Color = Color3.fromRGB(238, 89, 255);
		MultiplierModifier = 5;
	};

	Galactic = {
		Display = "Galactic";
		DisplayWithRichText = "<font color=\"#7D59FF\">Galactic</font>";
		Icon = "rbxassetid://99181785766598";
		Color = Color3.fromRGB(125, 89, 255);
		MultiplierModifier = 3;
	};

	Fireworks = {
		Display = "Fireworks";
		DisplayWithRichText = "<font color=\"#FF2828\">Fireworks</font>";
		Icon = "rbxassetid://121100427764858";
		Color = Color3.fromRGB(255, 40, 40);
		MultiplierModifier = 5;
	};

	Zombie = {
		Display = "Zombie";
		DisplayWithRichText = "<font color=\"#4aff47\">Zombie</font>";
		Icon = "rbxassetid://110723387483939";
		Color = Color3.fromRGB(74, 255, 71);
		MultiplierModifier = 4;
	};

	Claws = {
		Display = "Claws";
		DisplayWithRichText = "<font color=\"#eb391a\">Crab Claws</font>";
		Icon = "rbxassetid://104964195846833";
		Color = Color3.fromRGB(235, 57, 26);
		MultiplierModifier = 4;
	};

	Glitched = {
		Display = "Glitched";
		DisplayWithRichText = "<font color=\"#a75edf\">Glitch</font>";
		Icon = "rbxassetid://121332433272976";
		Color = Color3.fromRGB(167, 94, 223);
		MultiplierModifier = 4;
	};

	Bubblegum = {
		Display = "Bubblegum";
		DisplayWithRichText = "<font color=\"#f058fe\">Bubblegum</font>";
		Icon = "rbxassetid://100601425541874";
		Color = Color3.fromRGB(240, 88, 254);
		MultiplierModifier = 3;
	};

	Fire = {
		Display = "Fire";
		DisplayWithRichText = "<font color=\"#ffaa00\">Fire</font>";
		Icon = "rbxassetid://118283346037788";
		Color = Color3.fromRGB(255, 170, 0);
		MultiplierModifier = 5;
	};

	Wet = {
		Display = "Wet";
		DisplayWithRichText = "<font color=\"#1F85DE\">Wet</font>";
		Icon = "rbxassetid://78474194088770";
		Color = Color3.fromRGB(30, 130, 220);
		MultiplierModifier = 1.5;
	};

	Snowy = {
		Display = "Snowy";
		DisplayWithRichText = "<font color=\"#FFFFFF\">Snowy</font>";
		Icon = "rbxassetid://83627475909869";
		Color = Color3.fromRGB(255, 255, 255);
		MultiplierModifier = 2;
	};

	Cometstruck = {
		Display = "Comet-struck";
		DisplayWithRichText = "<font color=\"#ae1fde\">Comet-struck</font>";
		Icon = "rbxassetid://127455440418221";
		Color = Color3.fromRGB(175, 30, 220);
		MultiplierModifier = 2.5;
	};

	Disco = {
		Display = "Disco";
		DisplayWithRichText = "<font color=\"#e863ff\">Disco</font>";
		Icon = "rbxassetid://82620342632406";
		Color = Color3.fromRGB(232, 99, 255);
		MultiplierModifier = 4;
	};

	SharkFin = {
		Display = "Shark Fin";
		DisplayWithRichText = "<font color=\"#1F85DE\">Shark Fin</font>";
		Icon = "rbxassetid://104985313532149";
		Color = Color3.fromRGB(30, 130, 220);
		MultiplierModifier = 3;
	};

	MatteoHat = {
		Display = "Matteo Hat";
		DisplayWithRichText = "<font color=\"#ff961d\">Matteo Hat</font>";
		Icon = "rbxassetid://115664804212096";
		Color = Color3.fromRGB(255, 150, 29);
		MultiplierModifier = 3.5;
	};

	Brazil = {
		Display = "Brazil";
		DisplayWithRichText = "<font color=\"#00ff00\">Brazil</font>";
		Icon = "rbxassetid://75650816341229";
		Color = Color3.fromRGB(0, 255, 0);
		MultiplierModifier = 5;
	};

	Lightning = {
		Display = "Lightning";
		DisplayWithRichText = "<font color=\"#2747ff\">Lightning</font>";
		Icon = "rbxassetid://139729696247144";
		Color = Color3.fromRGB(0, 229, 255);
		MultiplierModifier = 5;
	};

	UFO = {
		Display = "UFO";
		DisplayWithRichText = "<font color=\"#00ff00\">UFO</font>";
		Icon = "rbxassetid://110910518481052";
		Color = Color3.fromRGB(0, 255, 0);
		MultiplierModifier = 2;
	};

	Spider = {
		Display = "Spider";
		DisplayWithRichText = "<font color=\"#fff\">Spider</font>";
		Icon = "rbxassetid://117478971325696";
		Color = Color3.fromRGB(255, 255, 255);
		MultiplierModifier = 3.5;
	};

	Strawberry = {
		Display = "Strawberry";
		DisplayWithRichText = "<font color=\"#ff5e5e\">Strawberry</font>";
		Icon = "rbxassetid://84731118566493";
		Color = Color3.fromRGB(255, 94, 94);
		MultiplierModifier = 7;
	};

	Paint = {
		Display = "Paint";
		DisplayWithRichText = "<font color=\"#ffc800\">Paint</font>";
		Icon = "rbxassetid://119591742504251";
		Color = Color3.fromRGB(255, 200, 0);
		MultiplierModifier = 5;
	};

	Skeleton = {
		Display = "Skeleton";
		DisplayWithRichText = "<font color=\"#fff\">Skeleton</font>";
		Icon = "rbxassetid://89591838221335";
		Color = Color3.fromRGB(255, 255, 255);
		MultiplierModifier = 3;
	};

	Sombrero = {
		Display = "Sombrero";
		DisplayWithRichText = "<font color=\"#fac711\">Sombrero</font>";
		Icon = "rbxassetid://95128039793845";
		Color = Color3.fromRGB(250, 199, 17);
		MultiplierModifier = 4;
	};

	Tie = {
		Display = "Tie";
		DisplayWithRichText = "<font color=\"#f00\">Tie</font>";
		Icon = "rbxassetid://103610037004911";
		Color = Color3.fromRGB(255, 0, 0);
		MultiplierModifier = 3.75;
	};

	WitchHat = {
		Display = "Witch Hat";
		DisplayWithRichText = "<font color=\"#7f51cf\">Witch Hat</font>";
		Icon = "rbxassetid://123964048606874";
		Color = Color3.fromRGB(127, 81, 207);
		MultiplierModifier = 3;
	};

	Indonesia = {
		Display = "Indonesia";
		DisplayWithRichText = "<font color=\"#fb3d29\">Indonesia</font>";
		Icon = "rbxassetid://93350414974589";
		Color = Color3.fromRGB(251, 61, 41);
		MultiplierModifier = 4;
	};

	Meowl = {
		Display = "Meowl";
		DisplayWithRichText = "<font color=\"#ffffff\">Meowl</font>";
		Icon = "rbxassetid://114748221761549";
		Color = Color3.fromRGB(255, 255, 255);
		MultiplierModifier = 6;
	};

	RIPGravestone = {
		Display = "RIP Gravestone";
		DisplayWithRichText = "<font color=\"#ffffff\">RIP Gravestone</font>";
		Icon = "rbxassetid://123115843719383";
		Color = Color3.fromRGB(255, 255, 255);
		MultiplierModifier = 3.5;
	};

	JackolanternPet = {
		Display = "Jackolantern Pet";
		DisplayWithRichText = "<font color=\"#ff9d26\">Jackolantern Pet</font>";
		Icon = "rbxassetid://97054765273857";
		Color = Color3.fromRGB(255, 170, 0);
		MultiplierModifier = 4.5;
	};

	SantaHat = {
		Display = "Santa Hat";
		DisplayWithRichText = "<font color=\"#ce4d4c\">Santa Hat</font>";
		Icon = "rbxassetid://88375043733582";
		Color = Color3.fromRGB(206, 77, 76);
		MultiplierModifier = 4;
	};

	ReindeerPet = {
		Display = "Reindeer Pet";
		DisplayWithRichText = "<font color=\"#ffffff\">Reindeer Pet</font>";
		Icon = "rbxassetid://70894779883038";
		Color = Color3.fromRGB(255, 255, 255);
		MultiplierModifier = 5;
	};

	Skibidi = {
		Display = "Skibidi";
		DisplayWithRichText = "<font color=\"#ffffff\">Skibidi</font>";
		Icon = "rbxassetid://83384385019272";
		Color = Color3.fromRGB(255, 255, 255);
		MultiplierModifier = 5.5;
	}
}

local module = {}

-- Get mutation data by name
function module.GetMutation(name: string): MutationData?
	return Mutations[name]
end

-- Get all mutations as a dictionary
function module.GetAllMutations(): { [string]: MutationData }
	return Mutations
end

-- Get all mutation names as an array
function module.GetMutationNames(): { string }
	local names = {}
	for name in Mutations do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

-- Get a random mutation
function module.GetRandomMutation(): (string, MutationData)
	local names = module.GetMutationNames()
	local randomName = names[math.random(1, #names)]
	return randomName, Mutations[randomName]
end

return module

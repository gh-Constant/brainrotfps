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
		Display = "Taco",
		DisplayWithRichText = "<font color=\"#FFDE59\">Taco</font>",
		Icon = "rbxassetid://89041930759464",
		Color = Color3.fromRGB(255, 222, 89),
		MultiplierModifier = 2,
	},
	Nyan = {
		Display = "Nyan",
		DisplayWithRichText = "<font color=\"#EE59FF\">Nyan</font>",
		Icon = "rbxassetid://104229924295526",
		Color = Color3.fromRGB(238, 89, 255),
		MultiplierModifier = 5,
	},
	Galactic = {
		Display = "Galactic",
		DisplayWithRichText = "<font color=\"#7D59FF\">Galactic</font>",
		Icon = "rbxassetid://99181785766598",
		Color = Color3.fromRGB(125, 89, 255),
		MultiplierModifier = 3,
	},
	Fireworks = {
		Display = "Fireworks",
		DisplayWithRichText = "<font color=\"#FF2828\">Fireworks</font>",
		Icon = "rbxassetid://121100427764858",
		Color = Color3.fromRGB(255, 40, 40),
		MultiplierModifier = 5,
	},
	Zombie = {
		Display = "Zombie",
		DisplayWithRichText = "<font color=\"#4aff47\">Zombie</font>",
		Icon = "rbxassetid://110723387483939",
		Color = Color3.fromRGB(74, 255, 71),
		MultiplierModifier = 4,
	},
	Claws = {
		Display = "Claws",
		DisplayWithRichText = "<font color=\"#eb391a\">Crab Claws</font>",
		Icon = "rbxassetid://104964195846833",
		Color = Color3.fromRGB(235, 57, 26),
		MultiplierModifier = 4,
	},
	Glitched = {
		Display = "Glitched",
		DisplayWithRichText = "<font color=\"#a75edf\">Glitch</font>",
		Icon = "rbxassetid://121332433272976",
		Color = Color3.fromRGB(167, 94, 223),
		MultiplierModifier = 4,
	},
	Bubblegum = {
		Display = "Bubblegum",
		DisplayWithRichText = "<font color=\"#f058fe\">Bubblegum</font>",
		Icon = "rbxassetid://100601425541874",
		Color = Color3.fromRGB(240, 88, 254),
		MultiplierModifier = 3,
	},
	Fire = {
		Display = "Fire",
		DisplayWithRichText = "<font color=\"#ffaa00\">Fire</font>",
		Icon = "rbxassetid://118283346037788",
		Color = Color3.fromRGB(255, 170, 0),
		MultiplierModifier = 5,
	},
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

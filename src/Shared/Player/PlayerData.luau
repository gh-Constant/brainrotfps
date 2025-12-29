--!strict
--[[
    Player Class
    Manages player progression data including level and gold.
    
    This module provides a clean OOP interface for tracking and persisting
    player data across sessions.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Rojo.Packages.signal)
local MoneyLib = require(ReplicatedStorage.Rojo.Shared.MoneyLib)

-- Signal type for type checking
type Signal = typeof(Signal.new())

-- Type definitions
export type PlayerData = {
    Level: number,
    Experience: number,
    Gold: number,
    TotalGoldEarned: number,
    Credits: number,
    TotalCreditsEarned: number,
}

export type Player = {
    -- Properties
    UserId: number,
    Name: string,
    Level: number,
    Experience: number,
    Gold: number,
    TotalGoldEarned: number,
    Credits: number,
    TotalCreditsEarned: number,
    
    -- Multipliers
    GoldMultiplier: number,
    ExperienceMultiplier: number,
    DamageMultiplier: number,
    
    -- Events
    OnLevelUp: Signal?,
    OnGoldChanged: Signal?,
    OnExperienceChanged: Signal?,
    OnCreditsChanged: Signal?,
    
    -- Internal
    _destroyed: boolean,
    
    -- Methods
    GetData: (self: Player) -> PlayerData,
    SetData: (self: Player, data: PlayerData) -> (),
    AddExperience: (self: Player, amount: number) -> boolean,
    AddGold: (self: Player, amount: number) -> boolean,
    SpendGold: (self: Player, amount: number) -> boolean,
    AddCredits: (self: Player, amount: number) -> boolean,
    SpendCredits: (self: Player, amount: number) -> boolean,
    GetExperienceForLevel: (self: Player, level: number) -> number,
    GetExperienceProgress: (self: Player) -> (number, number),
    GetMaxHealthForLevel: (self: Player, level: number) -> number,
    ResetProgress: (self: Player) -> (),
    Destroy: (self: Player) -> (),
}

-- Constants
local DEFAULT_DATA: PlayerData = {
    Level = 1,
    Experience = 0,
    Gold = 0,
    TotalGoldEarned = 0,
    Credits = 0,
    TotalCreditsEarned = 0,
}

-- Experience curve settings
-- Linear progression: Level 1 = 100 XP, Level 2 = 200 XP, etc.
local BASE_EXPERIENCE = 100


-- Health settings
-- Level 1 = 500 HP, Level 2 = 600 HP, etc. (100 per level)
local BASE_HEALTH = 500

-- Module
local PlayerClass = {}
PlayerClass.__index = PlayerClass

--[[
    Creates a new Player instance.
    
    @param robloxPlayer - The Roblox Player instance to wrap
    @param initialData - Optional initial data to load
    @return Player - The new Player instance
]]
function PlayerClass.new(robloxPlayer: Player, initialData: PlayerData?): Player
    local self = setmetatable({}, PlayerClass)
    
    -- Store references
    self._player = robloxPlayer
    self.UserId = robloxPlayer.UserId
    self.Name = robloxPlayer.Name
    
    -- Initialize data
    local data = initialData or table.clone(DEFAULT_DATA)
    self.Level = data.Level
    self.Experience = data.Experience
    self.Gold = data.Gold
    self.TotalGoldEarned = data.TotalGoldEarned
    self.Credits = data.Credits or 0
    self.TotalCreditsEarned = data.TotalCreditsEarned or 0
    
    -- Create signals for changes (using Signal library)
    self.OnLevelUp = Signal.new()
    self.OnGoldChanged = Signal.new()
    self.OnExperienceChanged = Signal.new()
    self.OnCreditsChanged = Signal.new()
    
    -- Track active state
    self._destroyed = false
    
    -- Multipliers (default to 1)
    self.GoldMultiplier = 1
    self.ExperienceMultiplier = 1
    self.DamageMultiplier = 1
    
    return self :: any
end

--[[
    Gets default player data.
    
    @return PlayerData - The default data template
]]
function PlayerClass.GetDefaultData(): PlayerData
    return table.clone(DEFAULT_DATA)
end

--[[
    Gets the current player data as a serializable table.
    
    @return PlayerData - Current player data
]]
function PlayerClass:GetData(): PlayerData
    return {
        Level = self.Level,
        Experience = self.Experience,
        Gold = self.Gold,
        TotalGoldEarned = self.TotalGoldEarned,
        Credits = self.Credits,
        TotalCreditsEarned = self.TotalCreditsEarned,
    }
end

--[[
    Sets player data from a saved table.
    
    @param data - The data to load
]]
function PlayerClass:SetData(data: PlayerData)
    self.Level = data.Level or DEFAULT_DATA.Level
    self.Experience = data.Experience or DEFAULT_DATA.Experience
    self.Gold = data.Gold or DEFAULT_DATA.Gold
    self.TotalGoldEarned = data.TotalGoldEarned or DEFAULT_DATA.TotalGoldEarned
    self.Credits = data.Credits or DEFAULT_DATA.Credits
    self.TotalCreditsEarned = data.TotalCreditsEarned or DEFAULT_DATA.TotalCreditsEarned
end

--[[
    Calculates the experience required to level up FROM a specific level.
    Each level requires level * 100 XP to level up.
    Level 1 = 100 XP, Level 2 = 200 XP, Level 3 = 300 XP, etc.
    
    @param level - The current level
    @return number - XP needed to reach the next level
]]
function PlayerClass:GetExperienceForLevel(level: number): number
    if level < 1 then
        level = 1
    end
    
    -- Simple linear formula: level * 100 XP to level up
    return BASE_EXPERIENCE * level
end

--[[
    Calculates the max health for a specific level.
    
    @param level - The target level
    @return number - Max health for that level
]]
function PlayerClass:GetMaxHealthForLevel(level: number): number
    if level < 1 then
        level = 1
    end
    
    -- Linear scaling: Level 1 = 500 HP, Level 2 = 600 HP, etc. (100 per level)
    return BASE_HEALTH + (level - 1) * 100
end

--[[
    Gets the current experience progress towards the next level.
    
    @return (current: number, required: number) - Current XP and XP needed for next level
]]
function PlayerClass:GetExperienceProgress(): (number, number)
    -- XP is now per-level, not cumulative
    local requiredXP = self:GetExperienceForLevel(self.Level)
    return self.Experience, requiredXP
end

--[[
    Adds experience to the player, potentially causing level ups.
    
    @param amount - The amount of experience to add
    @return boolean - True if any level ups occurred
]]
function PlayerClass:AddExperience(amount: number): boolean
    local player = self :: Player
    if player._destroyed or amount <= 0 then
        return false
    end
    
    -- Apply multiplier
    amount = amount * player.ExperienceMultiplier
    
    local previousExperience = player.Experience
    player.Experience = player.Experience + amount
    
    -- Fire experience changed event
    if player.OnExperienceChanged then
        player.OnExperienceChanged:Fire(player.Experience, previousExperience, amount)
    end
    
    local leveledUp = false
    
    -- Check for level ups (XP is per-level, resets on level up)
    local iteration = 0
    while true do
        iteration += 1
        if iteration % 1000 == 0 then
            task.wait()
        end
        
        local requiredXP = player:GetExperienceForLevel(player.Level)
        
        if player.Experience >= requiredXP then
            -- Level up! Carry over excess XP to next level
            player.Experience = player.Experience - requiredXP
            player.Level = player.Level + 1
            leveledUp = true
            
            -- Fire level up event
            if player.OnLevelUp then
                player.OnLevelUp:Fire(player.Level)
            end
            
            print(string.format("[Player] %s leveled up to %d!", player.Name, player.Level))
        else
            break
        end
    end
    
    return leveledUp
end
            
--[[
    Adds gold to the player's balance.
    
    @param amount - The amount of gold to add
    @return boolean - True if successful
]]
function PlayerClass:AddGold(amount: number): boolean
    local player = self :: Player
    if player._destroyed or amount <= 0 then
        return false
    end
    
    -- Apply multiplier
    amount = amount * player.GoldMultiplier
    
    local previousGold = player.Gold
    player.Gold = player.Gold + amount
    player.TotalGoldEarned = player.TotalGoldEarned + amount
    
    -- Fire gold changed event
    if player.OnGoldChanged then
        player.OnGoldChanged:Fire(player.Gold, previousGold, amount)
    end
    
    return true
end

--[[
    Attempts to spend gold from the player's balance.
    
    @param amount - The amount of gold to spend
    @return boolean - True if successful, false if insufficient funds
]]
function PlayerClass:SpendGold(amount: number): boolean
    local player = self :: Player
    if player._destroyed or amount <= 0 then
        return false
    end
    
    if player.Gold < amount then
        return false
    end
    
    local previousGold = player.Gold
    player.Gold = player.Gold - amount
    
    -- Fire gold changed event
    if player.OnGoldChanged then
        player.OnGoldChanged:Fire(player.Gold, previousGold, -amount)
    end
    
    return true
end

--[[
    Adds credits to the player's balance.
    
    @param amount - The amount of credits to add
    @return boolean - True if successful
]]
function PlayerClass:AddCredits(amount: number): boolean
    local player = self :: Player
    if player._destroyed or amount <= 0 then
        return false
    end
    
    local previousCredits = player.Credits
    player.Credits = player.Credits + amount
    player.TotalCreditsEarned = player.TotalCreditsEarned + amount
    
    -- Fire credits changed event
    if player.OnCreditsChanged then
        player.OnCreditsChanged:Fire(player.Credits, previousCredits, amount)
    end
    
    return true
end

--[[
    Attempts to spend credits from the player's balance.
    
    @param amount - The amount of credits to spend
    @return boolean - True if successful, false if insufficient funds
]]
function PlayerClass:SpendCredits(amount: number): boolean
    local player = self :: Player
    if player._destroyed or amount <= 0 then
        return false
    end
    
    if player.Credits < amount then
        return false
    end
    
    local previousCredits = player.Credits
    player.Credits = player.Credits - amount
    
    -- Fire credits changed event
    if player.OnCreditsChanged then
        player.OnCreditsChanged:Fire(player.Credits, previousCredits, -amount)
    end
    
    return true
end

--[[
    Checks if the player can afford a certain amount.
    
    @param amount - The amount to check
    @return boolean - True if affordable
]]
function PlayerClass:CanAfford(amount: number): boolean
    return self.Gold >= amount
end

--[[
    Checks if the player can afford a certain amount of credits.
    
    @param amount - The amount to check
    @return boolean - True if affordable
]]
function PlayerClass:CanAffordCredits(amount: number): boolean
    return self.Credits >= amount
end

--[[
    Gets the player's current level as a formatted string.
    
    @return string - Formatted level string
]]
function PlayerClass:GetLevelDisplay(): string
    return string.format("Level %d", self.Level)
end

--[[
    Gets a formatted gold display string.
    
    @return string - Formatted gold string with abbreviations for large values
]]
--[[
    Resets the player's progress (Level 1, 0 XP).
]]
function PlayerClass:ResetProgress()
    self.Level = 1
    self.Experience = 0
    
    if self.OnLevelUp then
        self.OnLevelUp:Fire(self.Level)
    end
    
    if self.OnExperienceChanged then
        self.OnExperienceChanged:Fire(0, 0, 0)
    end
end

--[[
    Cleans up the Player instance and its resources.
]]
function PlayerClass:Destroy()
    if self._destroyed then
        return
    end
    
    self._destroyed = true
    
    -- Destroy signals (using Signal library)
    if self.OnLevelUp then
        self.OnLevelUp:Destroy()
        self.OnLevelUp = nil
    end
    
    if self.OnGoldChanged then
        self.OnGoldChanged:Destroy()
        self.OnGoldChanged = nil
    end
    
    if self.OnCreditsChanged then
        self.OnCreditsChanged:Destroy()
        self.OnCreditsChanged = nil
    end
    
    if self.OnExperienceChanged then
        self.OnExperienceChanged:Destroy()
        self.OnExperienceChanged = nil
    end
end

return PlayerClass

--!strict
--[[
    Player Class
    Manages player progression data including level and gold.
    
    This module provides a clean OOP interface for tracking and persisting
    player data across sessions.
]]

-- Type definitions
export type PlayerData = {
    Level: number,
    Experience: number,
    Gold: number,
    TotalGoldEarned: number,
}

export type Player = {
    -- Properties
    UserId: number,
    Name: string,
    Level: number,
    Experience: number,
    Gold: number,
    TotalGoldEarned: number,
    
    -- Events
    OnLevelUp: RBXScriptSignal?,
    OnGoldChanged: RBXScriptSignal?,
    
    -- Methods
    GetData: (self: Player) -> PlayerData,
    SetData: (self: Player, data: PlayerData) -> (),
    AddExperience: (self: Player, amount: number) -> boolean,
    AddGold: (self: Player, amount: number) -> boolean,
    SpendGold: (self: Player, amount: number) -> boolean,
    GetExperienceForLevel: (self: Player, level: number) -> number,
    GetExperienceProgress: (self: Player) -> (number, number),
    Destroy: (self: Player) -> (),
}

-- Constants
local DEFAULT_DATA: PlayerData = {
    Level = 1,
    Experience = 0,
    Gold = 0,
    TotalGoldEarned = 0,
}

-- Experience curve settings
local BASE_EXPERIENCE = 100
local EXPERIENCE_MULTIPLIER = 1.5
local MAX_LEVEL = 100

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
    
    -- Create bindable events for signaling changes
    self._levelUpEvent = Instance.new("BindableEvent")
    self._goldChangedEvent = Instance.new("BindableEvent")
    
    self.OnLevelUp = self._levelUpEvent.Event
    self.OnGoldChanged = self._goldChangedEvent.Event
    
    -- Track active state
    self._destroyed = false
    
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
end

--[[
    Calculates the experience required to reach a specific level.
    
    @param level - The target level
    @return number - Experience required
]]
function PlayerClass:GetExperienceForLevel(level: number): number
    if level <= 1 then
        return 0
    end
    
    -- Exponential curve: baseExp * (multiplier ^ (level - 1))
    return math.floor(BASE_EXPERIENCE * (EXPERIENCE_MULTIPLIER ^ (level - 1)))
end

--[[
    Gets the current experience progress towards the next level.
    
    @return (current: number, required: number) - Current XP and XP needed for next level
]]
function PlayerClass:GetExperienceProgress(): (number, number)
    local currentLevelXP = self:GetExperienceForLevel(self.Level)
    local nextLevelXP = self:GetExperienceForLevel(self.Level + 1)
    
    local progressXP = self.Experience - currentLevelXP
    local requiredXP = nextLevelXP - currentLevelXP
    
    return progressXP, requiredXP
end

--[[
    Adds experience to the player, potentially causing level ups.
    
    @param amount - The amount of experience to add
    @return boolean - True if any level ups occurred
]]
function PlayerClass:AddExperience(amount: number): boolean
    if self._destroyed or amount <= 0 then
        return false
    end
    
    self.Experience = self.Experience + amount
    
    local leveledUp = false
    
    -- Check for level ups
    while self.Level < MAX_LEVEL do
        local requiredXP = self:GetExperienceForLevel(self.Level + 1)
        
        if self.Experience >= requiredXP then
            self.Level = self.Level + 1
            leveledUp = true
            
            -- Fire level up event
            if self._levelUpEvent then
                self._levelUpEvent:Fire(self.Level)
            end
            
            print(string.format("[Player] %s leveled up to %d!", self.Name, self.Level))
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
    if self._destroyed or amount <= 0 then
        return false
    end
    
    local previousGold = self.Gold
    self.Gold = self.Gold + amount
    self.TotalGoldEarned = self.TotalGoldEarned + amount
    
    -- Fire gold changed event
    if self._goldChangedEvent then
        self._goldChangedEvent:Fire(self.Gold, previousGold, amount)
    end
    
    return true
end

--[[
    Attempts to spend gold from the player's balance.
    
    @param amount - The amount of gold to spend
    @return boolean - True if successful, false if insufficient funds
]]
function PlayerClass:SpendGold(amount: number): boolean
    if self._destroyed or amount <= 0 then
        return false
    end
    
    if self.Gold < amount then
        return false
    end
    
    local previousGold = self.Gold
    self.Gold = self.Gold - amount
    
    -- Fire gold changed event
    if self._goldChangedEvent then
        self._goldChangedEvent:Fire(self.Gold, previousGold, -amount)
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
function PlayerClass:GetGoldDisplay(): string
    local gold = self.Gold
    
    if gold >= 1000000000 then
        return string.format("%.1fB", gold / 1000000000)
    elseif gold >= 1000000 then
        return string.format("%.1fM", gold / 1000000)
    elseif gold >= 1000 then
        return string.format("%.1fK", gold / 1000)
    else
        return tostring(gold)
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
    
    local levelUpEvent = self._levelUpEvent
    if levelUpEvent then
        levelUpEvent:Destroy()
        self._levelUpEvent = nil
    end
    
    local goldChangedEvent = self._goldChangedEvent
    if goldChangedEvent then
        goldChangedEvent:Destroy()
        self._goldChangedEvent = nil
    end
    
    self.OnLevelUp = nil
    self.OnGoldChanged = nil
end

return PlayerClass

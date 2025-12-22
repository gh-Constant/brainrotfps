--!strict
--[[
    PlayerManager
    Central server-side manager for all player-related systems.
    
    Coordinates:
    - Player data persistence (level, gold)
    - Death handling (VFX, ragdoll)
    - Character setup and cleanup
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Get modules
local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Packages = Rojo:WaitForChild("Packages")
local Shared = Rojo:WaitForChild("Shared")

local ProfileStore = require(Packages:WaitForChild("profilestore"))
local PlayerClass = require(Shared:WaitForChild("Player"))
local DeathHandler = require(script.DeathHandler)

-- ProfileStore configuration
local STORE_NAME = "PlayerData_v1"
local DATA_TEMPLATE = {
    Level = 1,
    Experience = 0,
    Gold = 0,
    TotalGoldEarned = 0,
}

-- Create ProfileStore
local PlayerProfileStore = ProfileStore.New(STORE_NAME, DATA_TEMPLATE)

-- Module
local PlayerManager = {}

-- Caches
local ActivePlayers: {[number]: PlayerClass.Player} = {}
local ActiveProfiles: {[number]: any} = {}
local PlayerConnections: {[Player]: {RBXScriptConnection}} = {}

--------------------------------------------------------------------------------
-- Private Functions
--------------------------------------------------------------------------------

--[[
    Sets up a character with all player systems.
]]
local function setupCharacter(character: Model, playerData: PlayerClass.Player?)
    -- Apply max health based on player level using Attributes
    if playerData then
        local maxHealth = playerData:GetMaxHealthForLevel(playerData.Level)
        character:SetAttribute("MaxHealth", maxHealth)
        character:SetAttribute("Health", maxHealth) -- Always reset to full health on spawn
        
        -- Also set legacy humanoid health for compatibility
        local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?
        if humanoid then
            humanoid.MaxHealth = maxHealth
            humanoid.Health = maxHealth
        end
    else
        -- Fallback for no player data
        character:SetAttribute("MaxHealth", 100)
        character:SetAttribute("Health", 100)
    end
    
    -- Setup death handler AFTER setting attributes
    DeathHandler.SetupCharacter(character)
end

--[[
    Loads player data and sets up systems.
]]
local function onPlayerAdded(player: Player)
    local userId = player.UserId
    local profileKey = "Player_" .. tostring(userId)
    
    -- Initialize connection tracking
    PlayerConnections[player] = {}
    
    -- Create leaderstats IMMEDIATELY (before profile loads)
    local leaderstats = Instance.new("Folder")
    leaderstats.Name = "leaderstats"
    leaderstats.Parent = player
    
    local levelValue = Instance.new("IntValue")
    levelValue.Name = "Level"
    levelValue.Value = 1
    levelValue.Parent = leaderstats
    
    local xpValue = Instance.new("IntValue")
    xpValue.Name = "XP"
    xpValue.Value = 0
    xpValue.Parent = leaderstats
    
    local goldValue = Instance.new("IntValue")
    goldValue.Name = "Gold"
    goldValue.Value = 0
    goldValue.Parent = leaderstats
    
    -- Start ProfileStore session
    local profile = PlayerProfileStore:StartSessionAsync(profileKey, {
        Cancel = function()
            return player.Parent ~= Players
        end
    })
    
    if profile == nil then
        warn(string.format("[PlayerManager] Failed to load profile for %s (%d)", player.Name, userId))
        player:Kick("Failed to load your data. Please rejoin!")
        return
    end
    
    if player.Parent ~= Players then
        profile:EndSession()
        return
    end
    
    -- Setup profile
    profile:Reconcile()
    profile:AddUserId(userId)
    
    -- Handle session end (another server taking over)
    profile.OnSessionEnd:Connect(function()
        local playerData = ActivePlayers[userId]
        if playerData then
            playerData:Destroy()
            ActivePlayers[userId] = nil
        end
        ActiveProfiles[userId] = nil
        
        if player.Parent == Players then
            player:Kick("Your session was ended. Please rejoin!")
        end
    end)
    
    -- Create PlayerClass instance
    local playerData = PlayerClass.new(player, {
        Level = profile.Data.Level,
        Experience = profile.Data.Experience,
        Gold = profile.Data.Gold,
        TotalGoldEarned = profile.Data.TotalGoldEarned,
    })
    
    -- Update leaderstats with loaded values
    levelValue.Value = playerData.Level
    xpValue.Value = playerData.Experience
    goldValue.Value = playerData.Gold
    
    local levelUpSignal = playerData.OnLevelUp
    if levelUpSignal then
        levelUpSignal:Connect(function(_newLevel)
            if profile:IsActive() then
                profile.Data.Level = playerData.Level
                profile.Data.Experience = playerData.Experience
            end
            -- Update leaderstats
            levelValue.Value = playerData.Level
            xpValue.Value = playerData.Experience
            
            -- Update max health based on new level using Attributes
            if player.Character then
                local newMaxHealth = playerData:GetMaxHealthForLevel(playerData.Level)
                local oldMaxHealth = player.Character:GetAttribute("MaxHealth") or 100
                local currentHealth = player.Character:GetAttribute("Health") or 100
                
                -- Calculate health ratio and scale to new max
                local healthRatio = currentHealth / oldMaxHealth
                local newHealth = newMaxHealth * healthRatio
                
                player.Character:SetAttribute("MaxHealth", newMaxHealth)
                player.Character:SetAttribute("Health", newHealth)
            end
        end)
    end
    
    local goldChangedSignal = playerData.OnGoldChanged
    if goldChangedSignal then
        goldChangedSignal:Connect(function(_newGold, _previousGold, _delta)
            if profile:IsActive() then
                profile.Data.Gold = playerData.Gold
                profile.Data.TotalGoldEarned = playerData.TotalGoldEarned
            end
            -- Update leaderstats
            goldValue.Value = playerData.Gold
        end)
    end
    
    local experienceChangedSignal = playerData.OnExperienceChanged
    if experienceChangedSignal then
        experienceChangedSignal:Connect(function(_newXP, _previousXP, _delta)
            if profile:IsActive() then
                profile.Data.Experience = playerData.Experience
            end
            -- Update leaderstats
            xpValue.Value = playerData.Experience
        end)
    end
    
    -- Store references
    ActivePlayers[userId] = playerData
    ActiveProfiles[userId] = profile
    
    -- Setup future characters (MUST be before LoadCharacter to avoid race condition)
    local characterConnection = player.CharacterAdded:Connect(function(character)
        setupCharacter(character, playerData)
    end)
    table.insert(PlayerConnections[player], characterConnection)
    
    -- Setup current character or load new one
    if player.Character then
        task.spawn(setupCharacter, player.Character, playerData)
    else
        player:LoadCharacter()
    end
    
    print(string.format(
        "[PlayerManager] Loaded %s - Level %d, %d Gold",
        player.Name,
        playerData.Level,
        playerData.Gold
    ))
end

--[[
    Cleans up when a player leaves.
]]
local function onPlayerRemoving(player: Player)
    local userId = player.UserId
    local playerData = ActivePlayers[userId]
    local profile = ActiveProfiles[userId]
    
    -- Sync and save profile
    if profile then
        if playerData and profile:IsActive() then
            profile.Data.Level = playerData.Level
            profile.Data.Experience = playerData.Experience
            profile.Data.Gold = playerData.Gold
            profile.Data.TotalGoldEarned = playerData.TotalGoldEarned
        end
        profile:EndSession()
    end
    
    -- Cleanup PlayerClass
    if playerData then
        playerData:Destroy()
    end
    
    -- Cleanup character
    if player.Character then
        DeathHandler.Cleanup(player.Character)
    end
    
    -- Cleanup connections
    if PlayerConnections[player] then
        for _, connection in ipairs(PlayerConnections[player]) do
            connection:Disconnect()
        end
        PlayerConnections[player] = nil
    end
    
    -- Clear caches
    ActivePlayers[userId] = nil
    ActiveProfiles[userId] = nil
    
    print(string.format("[PlayerManager] Unloaded %s", player.Name))
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--[[
    Initializes the PlayerManager.
]]
function PlayerManager.Init()
    -- Handle existing players
    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(onPlayerAdded, player)
    end
    
    -- Disable auto-loading to prevent conflicts with custom respawn
    Players.CharacterAutoLoads = false

    -- Handle new/leaving players
    Players.PlayerAdded:Connect(onPlayerAdded)
    Players.PlayerRemoving:Connect(onPlayerRemoving)
    
    -- Handle server shutdown
    game:BindToClose(function()
        PlayerManager.SaveAllAndClose()
    end)
    
    print("[PlayerManager] Initialized!")
    
    -- TEST: Give 25 XP to all players every second
    task.spawn(function()
        while true do
            task.wait(1)
            for _, playerData in pairs(ActivePlayers) do
                playerData:AddExperience(25)
            end
        end
    end)
end

--[[
    Gets a player's data instance.
    
    @param player - The Roblox Player
    @return PlayerData? - The player data or nil
]]
function PlayerManager.GetPlayerData(player: Player): PlayerClass.Player?
    return ActivePlayers[player.UserId]
end

--[[
    Gets player data by UserId.
    
    @param userId - The user ID
    @return PlayerData? - The player data or nil
]]
function PlayerManager.GetPlayerDataByUserId(userId: number): PlayerClass.Player?
    return ActivePlayers[userId]
end

--[[
    Checks if a player's data is loaded.
    
    @param player - The Roblox Player
    @return boolean
]]
function PlayerManager.IsLoaded(player: Player): boolean
    return ActivePlayers[player.UserId] ~= nil
end

--[[
    Forces a save for a player.
    
    @param player - The Roblox Player
]]
function PlayerManager.SavePlayer(player: Player)
    local userId = player.UserId
    local playerData = ActivePlayers[userId]
    local profile = ActiveProfiles[userId]
    
    if profile and profile:IsActive() and playerData then
        profile.Data.Level = playerData.Level
        profile.Data.Experience = playerData.Experience
        profile.Data.Gold = playerData.Gold
        profile.Data.TotalGoldEarned = playerData.TotalGoldEarned
        profile:Save()
    end
end

--[[
    Saves all players and ends sessions (for shutdown).
]]
function PlayerManager.SaveAllAndClose()
    print("[PlayerManager] Server shutting down, saving all players...")
    
    for userId, profile in pairs(ActiveProfiles) do
        local playerData = ActivePlayers[userId]
        
        if profile and profile:IsActive() then
            if playerData then
                profile.Data.Level = playerData.Level
                profile.Data.Experience = playerData.Experience
                profile.Data.Gold = playerData.Gold
                profile.Data.TotalGoldEarned = playerData.TotalGoldEarned
            end
            profile:EndSession()
        end
        
        if playerData then
            playerData:Destroy()
        end
    end
    
    table.clear(ActivePlayers)
    table.clear(ActiveProfiles)
    
    print("[PlayerManager] All players saved!")
end

return PlayerManager

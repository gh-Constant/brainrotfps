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
local function setupCharacter(character: Model)
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
    
    -- Sync events to profile
    local levelUpSignal = playerData.OnLevelUp
    if levelUpSignal then
        levelUpSignal:Connect(function(_newLevel)
            if profile:IsActive() then
                profile.Data.Level = playerData.Level
                profile.Data.Experience = playerData.Experience
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
        end)
    end
    
    -- Store references
    ActivePlayers[userId] = playerData
    ActiveProfiles[userId] = profile
    
    -- Setup current character
    if player.Character then
        task.spawn(setupCharacter, player.Character)
    end
    
    -- Setup future characters
    local characterConnection = player.CharacterAdded:Connect(function(character)
        setupCharacter(character)
    end)
    table.insert(PlayerConnections[player], characterConnection)
    
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
    
    -- Handle new/leaving players
    Players.PlayerAdded:Connect(onPlayerAdded)
    Players.PlayerRemoving:Connect(onPlayerRemoving)
    
    -- Handle server shutdown
    game:BindToClose(function()
        PlayerManager.SaveAllAndClose()
    end)
    
    print("[PlayerManager] Initialized!")
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

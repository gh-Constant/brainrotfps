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
local RunService = game:GetService("RunService")

-- Get modules
local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Packages = Rojo:WaitForChild("Packages")
local Shared = Rojo:WaitForChild("Shared")

local ProfileStore = require(Packages:WaitForChild("profilestore"))
local PlayerClass = require(Shared:WaitForChild("Player"))
local Health = require(Shared:WaitForChild("Health"))
local DeathHandler = require(script.DeathHandler)
local PlayerBillboard = require(script.PlayerBillboard)
local Packets = require(Shared:WaitForChild("Packets"))

-- ProfileStore configuration
local STORE_NAME = "PlayerData_v2"
local DATA_TEMPLATE = {
    Level = 1,
    Experience = 0,
    Gold = 0,
    TotalGoldEarned = 0,
    Credits = 0,
    TotalCreditsEarned = 0,
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
    -- Initialize PvP attribute (default: disabled)
    character:SetAttribute("IsPvPEnabled", false)
    -- Initialize combat state (default: not in combat)
    character:SetAttribute("InCombat", false)
    
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
    
    -- Setup player billboard (name, level, health, PVP status)
    PlayerBillboard.new(character, playerData)
    
    -- Setup death handler AFTER setting attributes
    DeathHandler.SetupCharacter(character, function(char, victim, instigator)
        if not victim or not instigator then return end
        if victim == instigator then return end -- Suicide doesn't count
        
        local victimData = ActivePlayers[victim.UserId]
        local instigatorData = ActivePlayers[instigator.UserId]
        
        if victimData and instigatorData then
            -- Killer gets victim's TOTAL XP (all levels + current)
            -- Total XP = sum of XP for all levels up to current level + current experience
            -- Formula: XP for level N = N * 100, so total = (1*100) + (2*100) + ... + ((level-1)*100) + currentXP
            -- Sum of 1 to (level-1) = (level-1) * level / 2, then multiply by 100
            local victimLevel = victimData.Level
            local totalLevelXP = 0
            if victimLevel > 1 then
                -- Sum of XP from all completed levels: sum(i * 100 for i = 1 to level-1)
                -- = 100 * sum(1 to level-1) = 100 * (level-1) * level / 2
                totalLevelXP = 100 * ((victimLevel - 1) * victimLevel / 2)
            end
            local xpToSteal = totalLevelXP + victimData.Experience
            instigatorData:AddExperience(xpToSteal)
            print(string.format("[Player] %s stole %d XP (Level %d + %d current) from %s", instigator.Name, xpToSteal, victimLevel, victimData.Experience, victim.Name))
            
            -- Send LootFX to the killer showing stolen XP
            local victimRootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart?
            if victimRootPart then
                local pos = victimRootPart.Position
                local effectsConfig = ReplicatedStorage:FindFirstChild("Config")
                local xpImage = effectsConfig and effectsConfig.Effects and effectsConfig.Effects.FX and effectsConfig.Effects.FX.XP and effectsConfig.Effects.FX.XP.Image or ""
                
                Packets.lootDropFX.sendTo({
                    posX = pos.X,
                    posY = pos.Y,
                    posZ = pos.Z,
                    config = {
                        image = xpImage,
                        color = {100, 200, 255}, -- Blue for XP
                        trailColor = {150, 220, 255},
                        trailEnabled = true,
                        count = math.floor(xpToSteal / 10), -- 1 part per 10 XP, no limits
                    },
                }, instigator)
            end
            
            -- Victim resets to Level 1, 0 XP
            victimData:ResetProgress()
        end
    end)
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
    
    local creditsValue = Instance.new("IntValue")
    creditsValue.Name = "Credits"
    creditsValue.Value = 0
    creditsValue.Parent = leaderstats
    
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
        Credits = profile.Data.Credits,
        TotalCreditsEarned = profile.Data.TotalCreditsEarned,
    })
    
    -- Update leaderstats with loaded values
    levelValue.Value = playerData.Level
    xpValue.Value = playerData.Experience
    goldValue.Value = playerData.Gold
    creditsValue.Value = playerData.Credits
    
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
    
    local creditsChangedSignal = playerData.OnCreditsChanged
    if creditsChangedSignal then
        creditsChangedSignal:Connect(function(_newCredits, _previousCredits, _delta)
            if profile:IsActive() then
                profile.Data.Credits = playerData.Credits
                profile.Data.TotalCreditsEarned = playerData.TotalCreditsEarned
            end
            -- Update leaderstats
            creditsValue.Value = playerData.Credits
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
    
    local VOID_THRESHOLD = -500
    
    RunService.Heartbeat:Connect(function()
        for _, player in ipairs(Players:GetPlayers()) do
            local character = player.Character
            if character and character.Parent then
                local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
                if rootPart and rootPart.Position.Y < VOID_THRESHOLD then
                    -- Check if already dead to avoid spam
                    if not character:GetAttribute("IsDead") then
                        local health = Health.Get(character)
                        if health then
                            print(string.format("[PlayerManager] %s fell into the void", player.Name))
                            health:TakeDamage(math.huge)
                        end
                    end
                end
            end
        end
    end)
    
    -- Listen for PvP toggle packets from clients
    local Packets = require(Shared:WaitForChild("Packets"))
    Packets.pvpToggle.listen(function(data, player)
        local character = player.Character
        if character then
            -- Prevent disabling PvP while in combat
            local inCombat = character:GetAttribute("InCombat")
            if inCombat and not data.enabled then
                -- Cannot disable PvP while in combat
                print(string.format("[PlayerManager] %s cannot disable PvP while in combat!", player.Name))
                return
            end
            
            character:SetAttribute("IsPvPEnabled", data.enabled)
            print(string.format("[PlayerManager] %s set PvP to %s", player.Name, tostring(data.enabled)))
        end
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

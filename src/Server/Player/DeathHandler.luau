--!strict
--[[
    DeathHandler
    Handles player death with ragdoll clone and respawn.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Rojo = ReplicatedStorage.Rojo
local Shared = Rojo.Shared
local Packets = require(Shared.Packets)
local Health = require(Shared.Health)
local RagdollUtils = require(Shared.Player.RagdollUtils)

-- Configuration
local RESPAWN_DELAY = 1.5

local DeathHandler = {}

--[[
    Handles character death: creates ragdoll clone, hides player, respawns after delay.
]]
function DeathHandler.OnDeath(character: Model, player: Player?)
    -- Send death screen to client
    if player then
        Packets.playerDeath.sendTo({}, player)
    end
    
    -- Freeze player movement completely
    local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if rootPart then
        rootPart.Anchored = true
    end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.WalkSpeed = 0
        humanoid.JumpPower = 0
        humanoid.AutoRotate = false
    end
    
    -- Ensure character is archivable (required for cloning)
    local wasArchivable = character.Archivable
    character.Archivable = true
    
    -- Create ragdoll clone
    local clone = character:Clone()
    
    -- Restore original archivable state
    character.Archivable = wasArchivable
    
    if clone then
        clone.Name = character.Name .. "_DeathClone"
        clone.Archivable = true
        
        -- Clean up clone (remove scripts)
        for _, descendant in clone:GetDescendants() do
            if descendant:IsA("BaseScript") then
                descendant:Destroy()
            end
        end
        
        -- Remove clone humanoid
        local cloneHumanoid = clone:FindFirstChildOfClass("Humanoid")
        if cloneHumanoid then
            cloneHumanoid:Destroy()
        end
        
        -- Spawn and ragdoll the clone
        clone.Parent = workspace
        RagdollUtils.EnableRagdoll(clone, true)
        Debris:AddItem(clone, RESPAWN_DELAY + 0.5) -- Clean up slightly after respawn
    else
        warn("[DeathHandler] Failed to clone character for ragdoll")
    end
    
    -- Make original character invisible
    for _, descendant in character:GetDescendants() do
        if descendant:IsA("BasePart") then
            descendant.Transparency = 1
            descendant.CanCollide = false
        elseif descendant:IsA("Decal") then
            descendant.Transparency = 1
        elseif descendant:IsA("Texture") then
            descendant.Transparency = 1
        end
    end
    
    -- Respawn after delay
    task.delay(RESPAWN_DELAY, function()
        if not character or not character.Parent then return end
        
        local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
        local spawnLocation = workspace:FindFirstChild("SpawnLocation") :: BasePart?
        
        if not rootPart or not spawnLocation then
            warn("[DeathHandler] Missing HumanoidRootPart or SpawnLocation")
            return
        end
        
        -- Unanchor to allow movement
        rootPart.Anchored = false
        
        -- Teleport to spawn
        rootPart.CFrame = spawnLocation.CFrame + Vector3.new(0, 5, 0)
        
        -- Reset all velocities
        for _, descendant in character:GetDescendants() do
            if descendant:IsA("BasePart") then
                descendant.AssemblyLinearVelocity = Vector3.zero
                descendant.AssemblyAngularVelocity = Vector3.zero
            end
        end
        
        -- Restore visibility
        for _, descendant in character:GetDescendants() do
            if descendant:IsA("BasePart") then
                descendant.Transparency = descendant.Name == "HumanoidRootPart" and 1 or 0
                
                -- Only enable CanCollide for non-accessory parts
                local isAccessory = descendant:FindFirstAncestorOfClass("Accessory") ~= nil
                if not isAccessory then
                    descendant.CanCollide = true
                end
            elseif descendant:IsA("Decal") then
                descendant.Transparency = 0
            elseif descendant:IsA("Texture") then
                descendant.Transparency = 0
            end
        end
        
        -- Restore health
        local maxHealth = character:GetAttribute("MaxHealth") or 100
        character:SetAttribute("Health", maxHealth)
        character:SetAttribute("IsDead", false)
        
        if humanoid then
            humanoid.Health = humanoid.MaxHealth
            humanoid.WalkSpeed = 16
            humanoid.JumpPower = 50
            humanoid.AutoRotate = true
        end
        
        -- Recreate Health object for death detection
        local newHealth = Health.new(character)
        newHealth.Died:Connect(function()
            DeathHandler.OnDeath(character, player)
            newHealth:Destroy()
        end)
    end)
end

--[[
    Sets up death handling for a character.
]]
function DeathHandler.SetupCharacter(character: Model)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        warn("[DeathHandler] No Humanoid found")
        return
    end
    
    local player = Players:GetPlayerFromCharacter(character)
    
    -- Setup death detection via custom health system
    local health = Health.new(character)
    health.Died:Connect(function()
        DeathHandler.OnDeath(character, player)
        health:Destroy()
    end)
end

--[[
    Cleanup for character removal.
]]
function DeathHandler.Cleanup(character: Model)
    -- Remove any lingering clones
    local cloneName = character.Name .. "_DeathClone"
    local clone = workspace:FindFirstChild(cloneName)
    if clone then
        clone:Destroy()
    end
end

return DeathHandler

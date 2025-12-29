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
local CombatManager = require(Shared.Health.CombatManager)

local DeathHandler = {}

--[[
    Handles character death: creates ragdoll clone, hides player, respawns after delay.
    @param character - The dying character
    @param player - The player who died (optional)
    @param instigator - The player who killed them (optional, for directional ragdoll)
]]
function DeathHandler.OnDeath(character: Model, player: Player?, instigator: Player?)
    -- Exit combat state when dying
    CombatManager.ExitCombat(character)
    
    -- Send death screen to client
    if player then
        Packets.playerDeath.sendTo({}, player)
    end
    
    -- Get the attacker's position for directional ragdoll
    local attackerPosition: Vector3? = nil
    if instigator and instigator.Character then
        local attackerRoot = instigator.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
        if attackerRoot then
            attackerPosition = attackerRoot.Position
        end
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
        humanoid:UnequipTools()
    end
    
    -- Hide player billboard before cloning
    local billboardAnchor = character:FindFirstChild("BillboardAnchor")
    if billboardAnchor then
        local billboard = billboardAnchor:FindFirstChildOfClass("BillboardGui")
        if billboard then
            billboard.Enabled = false
        end
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
        
        -- Clean up clone (remove scripts and billboard)
        for _, descendant in clone:GetDescendants() do
            if descendant:IsA("BaseScript") then
                descendant:Destroy()
            end
        end
        
        -- Remove billboard from clone so ragdoll doesn't have it
        local cloneBillboardAnchor = clone:FindFirstChild("BillboardAnchor")
        if cloneBillboardAnchor then
            cloneBillboardAnchor:Destroy()
        end
        
        -- Remove clone humanoid
        local cloneHumanoid = clone:FindFirstChildOfClass("Humanoid")
        if cloneHumanoid then
            cloneHumanoid:Destroy()
        end
        
        -- Unanchor all parts so ragdoll can move
        for _, descendant in clone:GetDescendants() do
            if descendant:IsA("BasePart") then
                descendant.Anchored = false
            end
        end
        
        -- Spawn and ragdoll the clone
        clone.Parent = workspace
        RagdollUtils.EnableRagdoll(clone, true)
        
        -- Apply impulse in the direction of the shot (push body away from shooter)
        local cloneRootPart = clone:FindFirstChild("HumanoidRootPart") :: BasePart?
        if cloneRootPart then
            local pushForce: Vector3
            
            if attackerPosition and rootPart then
                -- Calculate push direction (from attacker toward victim)
                local victimPos: Vector3 = rootPart.Position
                local pushDirection = (victimPos - attackerPosition).Unit
                -- Stronger horizontal push + upward lift
                pushForce = Vector3.new(
                    pushDirection.X * 800,
                    250, -- Upward to create a flying effect
                    pushDirection.Z * 800
                )
            else
                -- Fallback: random horizontal nudge
                local randomAngle = math.random() * math.pi * 2
                pushForce = Vector3.new(
                    math.cos(randomAngle) * 300,
                    100,
                    math.sin(randomAngle) * 300
                )
            end
            
            cloneRootPart:ApplyImpulse(pushForce)
        end
        
        Debris:AddItem(clone, 10) -- Clean up after 10 seconds
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
    
end

--[[
    Handles player respawn when they click the respawn button.
]]
function DeathHandler.HandleRespawn(player: Player)
    local character = player.Character
    if not character or not character.Parent then 
        warn("[DeathHandler] Cannot respawn - no character")
        return 
    end
    
    -- Check if actually dead
    if not character:GetAttribute("IsDead") then
        warn("[DeathHandler] Cannot respawn - not dead")
        return
    end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
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
            -- HumanoidRootPart and BillboardAnchor should stay invisible
            local keepInvisible = descendant.Name == "HumanoidRootPart" or descendant.Name == "BillboardAnchor"
            descendant.Transparency = if keepInvisible then 1 else 0
            
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
    
    -- Health object persists - no need to recreate, the original Died connection remains active
    -- Reset damage tracking for the new life
    local health = Health.Get(character)
    if health then
        health:ResetDamageTracking()
    end
    
    -- Restore player billboard visibility
    local billboardAnchor = character:FindFirstChild("BillboardAnchor")
    if billboardAnchor then
        local billboard = billboardAnchor:FindFirstChildOfClass("BillboardGui")
        if billboard then
            billboard.Enabled = true
        end
    end
end

--[[
    Sets up death handling for a character.
    @param character - The model
    @param onDeath - (Optional) Callback(character, player, instigator)
]]
function DeathHandler.SetupCharacter(character: Model, onDeath: ((Model, Player?, Player?) -> ())?)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        warn("[DeathHandler] No Humanoid found")
        return
    end
    
    local player = Players:GetPlayerFromCharacter(character)
    
    -- Setup death detection via custom health system
    -- NOTE: We do NOT destroy the health object on death - it persists through respawns
    -- so the same Died connection (with onDeath callback) stays active for all deaths
    local health = Health.new(character)
    health.Died:Connect(function(instigator)
        if onDeath then
            task.spawn(onDeath, character, player, instigator)
        end
        DeathHandler.OnDeath(character, player, instigator)
        -- Don't destroy health - let it persist for next death cycle
    end)
    
    -- Setup respawn packet listener
    if player then
        Packets.playerRespawn.listen(function(data, fromPlayer)
            if fromPlayer == player then
                DeathHandler.HandleRespawn(player)
            end
        end)
    end
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
    
    -- Destroy the Health object for this character
    local health = Health.Get(character)
    if health then
        health:Destroy()
    end
end

return DeathHandler

--!strict
--[[
    DeathHandler
    Handles death-related effects (VFX).
    
    Part of the Player system.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

-- VFX Configuration
local VFX_LIFETIME = 3 -- How long the death VFX plays

local DeathHandler = {}

--[[
    Gets the death VFX attachment template.
    
    @return Attachment? - The VFX template or nil if not found
]]
local function getDeathVFXTemplate(): Attachment?
    local playerFolder = ReplicatedStorage:FindFirstChild("Player")
    if not playerFolder then
        warn("[DeathHandler] ReplicatedStorage.Player folder not found")
        return nil
    end
    
    local vfxFolder = playerFolder:FindFirstChild("VFX")
    if not vfxFolder then
        warn("[DeathHandler] ReplicatedStorage.Player.VFX folder not found")
        return nil
    end
    
    local deathVFX = vfxFolder:FindFirstChild("Death")
    if not deathVFX or not deathVFX:IsA("Attachment") then
        warn("[DeathHandler] ReplicatedStorage.Player.VFX.Death attachment not found")
        return nil
    end
    
    return deathVFX :: Attachment
end

--[[
    Spawns death VFX on a character.
    
    @param character - The character to spawn VFX on
]]
local function spawnDeathVFX(character: Model)
    local template = getDeathVFXTemplate()
    if not template then return end
    
    local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not rootPart then
        -- Try torso as fallback
        local torso = character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")
        if torso and torso:IsA("BasePart") then
            rootPart = torso
        end
    end
    
    if not rootPart then
        warn("[DeathHandler] No root part found for VFX")
        return
    end
    
    -- Clone and attach the VFX
    local vfxClone = template:Clone()
    vfxClone.Name = "DeathVFX"
    vfxClone.Parent = rootPart
    
    -- Enable all particle emitters
    for _, child in ipairs(vfxClone:GetDescendants()) do
        if child:IsA("ParticleEmitter") then
            child.Enabled = true
            -- Emit burst if it's a burst-type emitter
            local burstCount = child:GetAttribute("BurstCount")
            if typeof(burstCount) == "number" then
                child:Emit(burstCount)
            end
        elseif child:IsA("Beam") then
            child.Enabled = true
        elseif child:IsA("Trail") then
            child.Enabled = true
        end
    end
    
    -- Clean up VFX after lifetime
    Debris:AddItem(vfxClone, VFX_LIFETIME)
    
    -- Disable emitters after a short time so particles can fade out
    task.delay(0.5, function()
        if vfxClone and vfxClone.Parent then
            for _, child in ipairs(vfxClone:GetDescendants()) do
                if child:IsA("ParticleEmitter") then
                    child.Enabled = false
                end
            end
        end
    end)
end

--[[
    Handles a character's death with VFX and ragdoll.
    
    @param character - The character that died
    @param enableRagdoll - Whether to enable ragdoll (default: true)
]]
function DeathHandler.OnDeath(character: Model, _enableRagdoll: boolean?)
    -- Spawn death VFX only (ragdoll disabled)
    spawnDeathVFX(character)
end

--[[
    Sets up death handling for a character.
    
    @param character - The character to setup
]]
function DeathHandler.SetupCharacter(character: Model)
    local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
    
    if not humanoid then
        warn("[DeathHandler] No Humanoid found in character")
        return
    end
    
    -- Disable Roblox's default ragdoll states (prevents ragdoll when hitting walls)
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
    humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
    
    -- Also handle if ragdoll somehow gets triggered
    humanoid.StateChanged:Connect(function(_, newState)
        if newState == Enum.HumanoidStateType.Ragdoll or newState == Enum.HumanoidStateType.FallingDown then
            humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
    end)
    
    -- Setup death handling
    humanoid.Died:Connect(function()
        DeathHandler.OnDeath(character)
    end)
end

--[[
    Cleans up death effects on a character.
    
    @param character - The character to cleanup
]]
function DeathHandler.Cleanup(character: Model)
    -- Remove any lingering death VFX
    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant.Name == "DeathVFX" then
            descendant:Destroy()
        end
    end
end

return DeathHandler

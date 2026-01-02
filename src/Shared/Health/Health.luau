--!strict
--[[
    Health.luau
    Custom health system using Attributes for replication.
    Works for Players and NPCs.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Packages = Rojo:WaitForChild("Packages")
local Shared = Rojo:WaitForChild("Shared")
local HealthFolder = Shared:WaitForChild("Health")
local Janitor = require(Packages:WaitForChild("janitor"))
local Signal = require(Packages:WaitForChild("signal"))

-- Require sibling modules
local PVPManager = require(HealthFolder:WaitForChild("PVPManager"))
local CombatManager = require(HealthFolder:WaitForChild("CombatManager"))


local Health = {}
Health.__index = Health

-- Cache for singleton pattern (one Health object per instance)
local healthCache = {} :: {[Instance]: any}

-- Constants
local ATTR_HEALTH = "Health"
local ATTR_MAX_HEALTH = "MaxHealth"
local ATTR_IS_DEAD = "IsDead"

-- Regeneration settings
local REGEN_DELAY = 3 -- seconds without damage before regen starts
local REGEN_RATE = 0.05 -- 5% of max health per second

export type HealthCallback = (newHealth: number, maxHealth: number) -> ()

export type HealthObject = typeof(setmetatable({}, Health)) & {
    Instance: Instance,
    Died: typeof(Signal.new()),
    HealthChanged: typeof(Signal.new()), -- (newHealth, maxHealth)
    DamageDealt: typeof(Signal.new()),   -- (instigator: Player?, amount: number)
    _janitor: typeof(Janitor.new()),
    _lastDamageTime: number?,
    _damageHistory: {[number]: number}, -- UserId -> Amount
    _lastInstigator: Player?, -- The last player to deal damage
}

--[[
    Creates or retrieves a Health object for the given instance (Model/Part).
    
    @param instance - The model or part to attach health to
    @param maxHealth - (Optional) Initial max health, defaults to 100 or existing attribute
]]
function Health.new(instance: Instance, maxHealth: number?): HealthObject
    -- Check cache for existing Health object
    if healthCache[instance] then
        return healthCache[instance]
    end
    
    local self = setmetatable({}, Health) :: any
    
    self.Instance = instance
    self.Died = Signal.new()
    self.HealthChanged = Signal.new()
    self.DamageDealt = Signal.new()
    self._janitor = Janitor.new()
    self._lastDamageTime = nil
    self._damageHistory = {}
    self._lastInstigator = nil
    
    -- Add Signals to janitor for cleanup
    self._janitor:Add(self.Died, "Destroy")
    self._janitor:Add(self.HealthChanged, "Destroy")
    self._janitor:Add(self.DamageDealt, "Destroy")
    
    -- Store in cache
    healthCache[instance] = self
    
    -- Clean up cache when instance is destroyed
    instance.Destroying:Once(function()
        healthCache[instance] = nil
    end)
    
    -- Check if this is a player's character
    local isPlayerCharacter = false
    if instance:IsA("Model") then
        local player = game:GetService("Players"):GetPlayerFromCharacter(instance)
        isPlayerCharacter = player ~= nil
    end
    
    -- Initialize Attributes only for players (server-side)
    print("[Health] Creating Health for", instance.Name, "- IsServer:", RunService:IsServer(), "IsClient:", RunService:IsClient(), "IsPlayer:", isPlayerCharacter)
    
    if RunService:IsServer() and isPlayerCharacter then
        print("[Health] Initializing attributes for player (server-side)")
        if not instance:GetAttribute(ATTR_MAX_HEALTH) then
            instance:SetAttribute(ATTR_MAX_HEALTH, maxHealth or 100)
        end
        
        if not instance:GetAttribute(ATTR_HEALTH) then
            instance:SetAttribute(ATTR_HEALTH, instance:GetAttribute(ATTR_MAX_HEALTH))
        end
        
        -- Reset dead state on new creation (spawning)
        instance:SetAttribute(ATTR_IS_DEAD, false)
    end
    
    -- Start regeneration loop only on server
    if RunService:IsServer() then
        local regenThread = task.spawn(function()
            while self.Instance and self.Instance.Parent do
                task.wait(0.1) -- Check every 0.1 seconds
                
                -- Skip if dead
                if self.Instance:GetAttribute(ATTR_IS_DEAD) then
                    continue
                end
                
                -- Skip if in combat
                if self.Instance:GetAttribute("InCombat") then
                    continue
                end
                
                local currentHealth = self.Instance:GetAttribute(ATTR_HEALTH) or 0
                local currentMaxHealth = self.Instance:GetAttribute(ATTR_MAX_HEALTH) or 100
                
                -- Skip if already at max health
                if currentHealth >= currentMaxHealth then
                    continue
                end
                
                -- Check if enough time has passed since last damage
                local regenDelay = self.Instance:GetAttribute("RegenDelay") or REGEN_DELAY
                if self._lastDamageTime then
                    local timeSinceDamage = os.clock() - self._lastDamageTime
                    if timeSinceDamage >= regenDelay then
                        -- Regenerate percentage of max health
                        local regenRate = self.Instance:GetAttribute("RegenRate") or REGEN_RATE
                        local regenAmount = currentMaxHealth * regenRate * 0.1 -- 0.1 sec intervals
                        local newHealth = math.min(currentMaxHealth, currentHealth + regenAmount)
                        self.Instance:SetAttribute(ATTR_HEALTH, newHealth)
                    end
                else
                    -- No damage taken yet, start regen immediately
                    local regenRate = self.Instance:GetAttribute("RegenRate") or REGEN_RATE
                    local regenAmount = currentMaxHealth * regenRate * 0.1
                    local newHealth = math.min(currentMaxHealth, currentHealth + regenAmount)
                    self.Instance:SetAttribute(ATTR_HEALTH, newHealth)
                end
            end
        end)
        -- Add thread to janitor for cancellation on cleanup
        self._janitor:Add(regenThread, true)
    end
    
    -- Listen for Attribute changes (Replication & Local updates)
    local attrConnection = instance.AttributeChanged:Connect(function(attrName)
        if attrName == ATTR_HEALTH or attrName == ATTR_MAX_HEALTH then
            local hp = instance:GetAttribute(ATTR_HEALTH) or 0
            local max = instance:GetAttribute(ATTR_MAX_HEALTH) or 100
            
            self.HealthChanged:Fire(hp, max)
            
            -- Detect death
            if hp <= 0 and not instance:GetAttribute(ATTR_IS_DEAD) then
                print("[Health] Death detected for", instance.Name, "HP:", hp)
                print("[Health] IsServer:", RunService:IsServer(), "IsClient:", RunService:IsClient(), "IsStudio:", RunService:IsStudio())
                
                if RunService:IsServer() then
                    print("[Health] Setting IsDead attribute (server)")
                    instance:SetAttribute(ATTR_IS_DEAD, true)
                else
                    warn("[Health] Skipping IsDead attribute (client)")
                end
                
                print("[Health] Firing Died event for", instance.Name)
                self.Died:Fire(self._lastInstigator) -- Pass killer if available
                print("[Health] Died event fired for", instance.Name)
            end
        end
    end)
    self._janitor:Add(attrConnection)
    
    -- Link janitor to instance for automatic cleanup
    self._janitor:LinkToInstance(instance)
    
    return self :: HealthObject
end

--[[
    Gets the Health object wrapper for a model if one exists.
    For full event listening, use .new().
]]
function Health.Get(instance: Instance): HealthObject
    return Health.new(instance)
end

--[[
    Damage the entity. Server only.
    @param amount - Damage amount
    @param instigator - (Optional) Player who dealt the damage
]]
function Health:TakeDamage(amount: number, instigator: Player?)
    if not RunService:IsServer() then return end
    if self.Instance:GetAttribute(ATTR_IS_DEAD) then return end
    
    -- PvP protection check using PVPManager
    if not PVPManager.CanDamage(instigator, self.Instance) then
        return
    end
    
    -- Get target player for combat state
    local targetPlayer = PVPManager.GetPlayerFromInstance(self.Instance)
    
    -- If this is PvP damage (player attacking player), enter combat for both
    if instigator and targetPlayer then
        -- Enter combat for target
        CombatManager.EnterCombat(self.Instance :: Model)
        
        -- Enter combat for attacker
        local attackerChar = instigator.Character
        if attackerChar then
            CombatManager.EnterCombat(attackerChar)
        end
    end
    
    -- Update last damage time to reset regen delay
    self._lastDamageTime = os.clock()
    
    -- Track damage attribution
    if instigator then
        local userId = instigator.UserId
        self._damageHistory[userId] = (self._damageHistory[userId] or 0) + amount
        self._lastInstigator = instigator
    end
    
    local current = self.Instance:GetAttribute(ATTR_HEALTH) or 100
    local newHealth = math.max(0, current - amount)
    
    self.Instance:SetAttribute(ATTR_HEALTH, newHealth)
    
    -- Fire damage dealt signal
    self.DamageDealt:Fire(instigator, amount)
end

--[[
    Heal the entity. Server only.
]]
function Health:Heal(amount: number)
    if not RunService:IsServer() then return end
    if self.Instance:GetAttribute(ATTR_IS_DEAD) then return end
    
    local current = self.Instance:GetAttribute(ATTR_HEALTH) or 100
    local max = self.Instance:GetAttribute(ATTR_MAX_HEALTH) or 100
    local newHealth = math.min(max, current + amount)
    
    self.Instance:SetAttribute(ATTR_HEALTH, newHealth)
end

--[[
    Set Max Health (and optionally scale current health). Server only.
]]
function Health:SetMaxHealth(amount: number, scaleCurrent: boolean?)
    if not RunService:IsServer() then return end
    
    local oldMax = self.Instance:GetAttribute(ATTR_MAX_HEALTH) or 100
    local current = self.Instance:GetAttribute(ATTR_HEALTH) or 100
    
    self.Instance:SetAttribute(ATTR_MAX_HEALTH, amount)
    
    if scaleCurrent and oldMax > 0 then
        local ratio = current / oldMax
        self.Instance:SetAttribute(ATTR_HEALTH, amount * ratio)
    end
end

--[[
    Get current health values.
]]
function Health:GetHealth(): (number, number)
    return self.Instance:GetAttribute(ATTR_HEALTH) or 0, self.Instance:GetAttribute(ATTR_MAX_HEALTH) or 100
end

--[[
    Get the player who dealt the last instance of damage.
    @return Player?
]]
function Health:GetLastInstigator(): Player?
    return self._lastInstigator
end

--[[
    Get the damage history table.
    @return {[number]: number} - UserId -> Total Damage
]]
function Health:GetDamageHistory(): {[number]: number}
    return self._damageHistory
end

--[[
    Resets damage tracking state (for respawns).
    Clears damage history and last instigator to prevent incorrect kill attribution.
]]
function Health:ResetDamageTracking()
    self._damageHistory = {}
    self._lastInstigator = nil
    self._lastDamageTime = nil
end

--[[
    Destroy the Health object (cleanup connections).
    Does NOT destroy the Instance.
]]
function Health:Destroy()
    -- Remove from cache first
    if healthCache[self.Instance] == self then
        healthCache[self.Instance] = nil
    end
    
    -- Janitor cleans up connections, regen thread, and Signals
    self._janitor:Cleanup()
    
    -- Clear state
    self._damageHistory = {}
    self._lastInstigator = nil
end

return Health

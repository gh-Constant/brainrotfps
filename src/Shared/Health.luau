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
local Signal = require(Packages:WaitForChild("signal"))

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
    _connections: {RBXScriptConnection},
    _lastDamageTime: number?,
    _regenThread: any,
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
    self._connections = {}
    self._lastDamageTime = nil
    self._regenThread = nil
    
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
        self._regenThread = task.spawn(function()
            while self.Instance and self.Instance.Parent do
                task.wait(0.1) -- Check every 0.1 seconds
                
                -- Skip if dead
                if self.Instance:GetAttribute(ATTR_IS_DEAD) then
                    continue
                end
                
                local currentHealth = self.Instance:GetAttribute(ATTR_HEALTH) or 0
                local maxHealth = self.Instance:GetAttribute(ATTR_MAX_HEALTH) or 100
                
                -- Skip if already at max health
                if currentHealth >= maxHealth then
                    continue
                end
                
                -- Check if enough time has passed since last damage
                if self._lastDamageTime then
                    local timeSinceDamage = os.clock() - self._lastDamageTime
                    if timeSinceDamage >= REGEN_DELAY then
                        -- Regenerate percentage of max health
                        local regenAmount = maxHealth * REGEN_RATE * 0.1 -- 0.1 sec intervals
                        local newHealth = math.min(maxHealth, currentHealth + regenAmount)
                        self.Instance:SetAttribute(ATTR_HEALTH, newHealth)
                    end
                else
                    -- No damage taken yet, start regen immediately
                    local regenAmount = maxHealth * REGEN_RATE * 0.1
                    local newHealth = math.min(maxHealth, currentHealth + regenAmount)
                    self.Instance:SetAttribute(ATTR_HEALTH, newHealth)
                end
            end
        end)
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
                self.Died:Fire()
                print("[Health] Died event fired for", instance.Name)
            end
        end
    end)
    table.insert(self._connections, attrConnection)
    
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
]]
function Health:TakeDamage(amount: number)
    if not RunService:IsServer() then return end
    if self.Instance:GetAttribute(ATTR_IS_DEAD) then return end
    
    -- Update last damage time to reset regen delay
    self._lastDamageTime = os.clock()
    
    local current = self.Instance:GetAttribute(ATTR_HEALTH) or 100
    local newHealth = math.max(0, current - amount)
    
    self.Instance:SetAttribute(ATTR_HEALTH, newHealth)
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
    Destroy the Health object (cleanup connections).
    Does NOT destroy the Instance.
]]
function Health:Destroy()
    -- Cancel regeneration thread
    if self._regenThread then
        task.cancel(self._regenThread)
        self._regenThread = nil
    end
    
    -- Remove from cache
    if healthCache[self.Instance] == self then
        healthCache[self.Instance] = nil
    end
    
    for _, conn in ipairs(self._connections) do
        conn:Disconnect()
    end
    self.Died:Destroy()
    self.HealthChanged:Destroy()
end

return Health

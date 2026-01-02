--!strict
--[[
    Client Initialization Script
    Waits for character to fully load, then initializes all client systems
    with common references using the SystemLoader for independent loading.
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local MovementController = require(script.Movement.MovementController)
local InputController = require(script.Movement.InputController)
local UI = require(script.UI)
local CmdrClientSetup = require(script.CmdrClientSetup)
local SystemLoader = require(script.SystemLoader)
local GrenadeController = require(script.Weapons.GrenadeController)
local BuffController = require(script.UI.Buffs.BuffController)
local MobDisplayController = require(script:WaitForChild("Brainrot"):WaitForChild("MobDisplayController"))

-- Note: Core GUI is disabled in ReplicatedFirst/LoadingScreen

local player = Players.LocalPlayer
local currentController: MovementController.MovementController? = nil
local systemLoader = SystemLoader.new()

-- Common references that will be passed to systems
export type ClientContext = {
    Player: Player,
    PlayerGui: PlayerGui,
    Character: Model,
    Humanoid: Humanoid,
    RootPart: BasePart,
}

--[[ 
    Safezone collision helpers
]]
local SAFEZONE_TAG = "Safezone"

local function updateSafezoneCollision(inCombat: boolean)
    local safeParts = CollectionService:GetTagged(SAFEZONE_TAG)
    for _, part in safeParts do
        if part:IsA("BasePart") then
            part.CanCollide = inCombat
        end
    end
end

local function setupSafezoneCollision(character: Model)
    local inCombat = (character:GetAttribute("InCombat") :: boolean?) or false
    updateSafezoneCollision(inCombat)
    
    character:GetAttributeChangedSignal("InCombat"):Connect(function()
        local nowInCombat = (character:GetAttribute("InCombat") :: boolean?) or false
        updateSafezoneCollision(nowInCombat)
    end)
end

--[[
    Register all client systems with the loader.
    Each system can initialize independently.
]]

-- System: Cmdr Console (no character needed)
systemLoader:RegisterSystem({
    Name = "Cmdr",
    Priority = 1,
    Init = function(_context)
        CmdrClientSetup.Init()
    end,
})

-- System: UI Components
systemLoader:RegisterSystem({
    Name = "UI",
    Priority = 2,
    Init = function(context)
        UI.Init(context)
    end,
})

-- System: Movement Controller
systemLoader:RegisterSystem({
    Name = "Movement",
    Priority = 3,
    Init = function(context)
        if currentController then
            currentController:Destroy()
            currentController = nil
        end
        
        local controller = MovementController.new(context.Character)
        controller:Start()
        currentController = controller
    end,
})

-- System: Safezone Collision
systemLoader:RegisterSystem({
    Name = "SafezoneCollision",
    Priority = 4,
    Init = function(context)
        setupSafezoneCollision(context.Character)
    end,
})

-- System: Grenades
systemLoader:RegisterSystem({
    Name = "Grenades",
    Priority = 5,
    Init = function(context)
        GrenadeController.Init(context)
    end,
})

-- System: Buff Controller
systemLoader:RegisterSystem({
    Name = BuffController.Name,
    Priority = 6,
    Init = function(context)
        BuffController.Init(context)
    end,
})

-- System: Mob Display Controller
-- System: Mob Display Controller
systemLoader:RegisterSystem({
    Name = "MobDisplay",
    Priority = 7,
    Init = function(_context)
        MobDisplayController.Start()
    end,
})

-- System: Index Controller
local IndexController = require(script.UI.Index.IndexController)
systemLoader:RegisterSystem({
    Name = "Index",
    Priority = 8,
    Init = function(_context)
        IndexController.Init()
    end,
})

--[[
    Creates a context object with common client references.
    Uses WaitForChild to properly wait for character parts to exist.
]]
local function createClientContext(character: Model): ClientContext?
    local WAIT_TIMEOUT = 10 -- seconds to wait for parts
    
    -- Use WaitForChild to properly wait for Humanoid and HumanoidRootPart
    local humanoid = character:WaitForChild("Humanoid", WAIT_TIMEOUT) :: Humanoid?
    local rootPart = character:WaitForChild("HumanoidRootPart", WAIT_TIMEOUT) :: BasePart?
    
    if not humanoid or not rootPart then
        warn("[Client] Failed to find Humanoid or HumanoidRootPart after", WAIT_TIMEOUT, "seconds")
        return nil
    end
    
    local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
    
    return {
        Player = player,
        PlayerGui = playerGui,
        Character = character,
        Humanoid = humanoid,
        RootPart = rootPart,
    }
end

--[[
    Handles character added event.
    Waits for character to fully load before initializing systems.
]]
local function onCharacterAdded(character: Model)
    -- Wait for character to be fully loaded
    if not player:HasAppearanceLoaded() then
        player.CharacterAppearanceLoaded:Wait()
    end
    
    -- Create context with common references
    local context = createClientContext(character)
    if not context then
        warn("[Client] Failed to create client context")
        return
    end
    
    -- Initialize all systems independently with the context
    systemLoader:InitializeAll(context)
    
    -- Wait for all systems to complete
    if not systemLoader:IsComplete() then
        systemLoader.OnAllComplete:Wait()
    end
    
    print("[Client] All systems initialized for character:", context.Character.Name)
end

--[[
    Handle slide input using cross-platform InputController.
    Supports: PC (C key), Mobile (touch button), Console (ButtonB/R1)
]]
local inputController = InputController.new()

inputController.SlidePressed:Connect(function()
    local controller = currentController
    if controller and not controller:IsSliding() then
        controller:TrySlide()
    end
end)

inputController.SlideReleased:Connect(function()
    local controller = currentController
    if controller then
        controller:EndSlide()
    end
end)

-- Setup character handling
player.CharacterAdded:Connect(onCharacterAdded)

if player.Character then
    task.spawn(onCharacterAdded, player.Character)
end

-- Also update when new safezone parts are added
CollectionService:GetInstanceAddedSignal(SAFEZONE_TAG):Connect(function(part)
    if part:IsA("BasePart") then
        local character = player.Character
        if character then
            local inCombat = (character:GetAttribute("InCombat") :: boolean?) or false
            part.CanCollide = inCombat
        end
    end
end)

print("[Client] Client initialization script loaded")

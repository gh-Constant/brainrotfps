--!strict
--[[
    Client Initialization Script
    Waits for character to fully load, then initializes all client systems
    with common references using the SystemLoader for independent loading.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")

local MovementController = require(script.Movement.MovementController)
local UI = require(script.UI)
local CmdrClientSetup = require(script.CmdrClientSetup)
local SystemLoader = require(script.SystemLoader)

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

--[[
    Creates a context object with common client references.
]]
local function createClientContext(character: Model): ClientContext?
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    
    if not humanoid or not rootPart then
        warn("[Client] Failed to find Humanoid or HumanoidRootPart")
        return nil
    end
    
    local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
    
    return {
        Player = player,
        PlayerGui = playerGui,
        Character = character,
        Humanoid = humanoid :: Humanoid,
        RootPart = rootPart :: BasePart,
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
    Handle slide input (LeftShift key).
]]
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    
    if input.KeyCode == Enum.KeyCode.LeftShift then
        local controller = currentController
        if controller and not controller:IsSliding() then
            controller:TrySlide()
        end
    end
end)

UserInputService.InputEnded:Connect(function(input, _gameProcessed)
    if input.KeyCode == Enum.KeyCode.LeftShift then
        local controller = currentController
        if controller then
            controller:EndSlide()
        end
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

--!strict
--[[
    CombatIndicator
    Handles the combat status and countdown display.
    
    Expected UI Structure:
    - Base/Top/Combat/Combat (BoolValue)
    - Base/Top/Combat/Timer (NumberValue)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Packages = Rojo:WaitForChild("Packages")
local Janitor = require(Packages:WaitForChild("janitor"))

local player = Players.LocalPlayer

local CombatIndicator = {}

local characterJanitor = Janitor.new()

function CombatIndicator.Init(context: any)
    local topFrame = context.TopFrame
    if not topFrame then return end
    
    local combatFrame = topFrame:FindFirstChild("Combat")
    if not combatFrame then
        warn("[CombatIndicator] Combat frame not found!")
        return
    end
    
    local combatValue = combatFrame:FindFirstChild("Combat") :: BoolValue?
    local timerValue = combatFrame:FindFirstChild("Timer") :: NumberValue?
    
    local function updateCombatUI(character: Model?)
        if not character then return end
        
        -- Update combat boolean
        local inCombat = (character:GetAttribute("InCombat") :: boolean?) or false
        if combatValue then
            combatValue.Value = inCombat
        end
        
        -- Update timer
        local countdown = (character:GetAttribute("CombatCountdown") :: number?) or 0
        if timerValue then
            timerValue.Value = countdown
        end
    end
    
    local function setupCombatListener(character: Model)
        -- Cleanup previous character connections
        characterJanitor:Cleanup()
        
        updateCombatUI(character)
        
        -- Add connections to janitor
        characterJanitor:Add(character:GetAttributeChangedSignal("InCombat"):Connect(function()
            updateCombatUI(character)
        end))
        characterJanitor:Add(character:GetAttributeChangedSignal("CombatCountdown"):Connect(function()
            updateCombatUI(character)
        end))
        
        -- Link janitor to character for automatic cleanup
        characterJanitor:LinkToInstance(character)
    end
    
    if context.Character then
        setupCombatListener(context.Character)
    end
    
    player.CharacterAdded:Connect(setupCombatListener)
    
    print("[CombatIndicator] Initialized with Janitor!")
end

return CombatIndicator


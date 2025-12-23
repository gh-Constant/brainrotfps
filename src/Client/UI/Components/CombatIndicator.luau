--!strict
--[[
    CombatIndicator
    Handles the combat status and countdown display.
    
    Expected UI Structure:
    - Base/Top/Combat/Combat (BoolValue)
    - Base/Top/Combat/Timer (NumberValue)
]]

local Players = game:GetService("Players")

local player = Players.LocalPlayer

local CombatIndicator = {}

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
        updateCombatUI(character)
        character:GetAttributeChangedSignal("InCombat"):Connect(function()
            updateCombatUI(character)
        end)
        character:GetAttributeChangedSignal("CombatCountdown"):Connect(function()
            updateCombatUI(character)
        end)
    end
    
    if context.Character then
        setupCombatListener(context.Character)
    end
    
    player.CharacterAdded:Connect(setupCombatListener)
    
    print("[CombatIndicator] Initialized!")
end

return CombatIndicator

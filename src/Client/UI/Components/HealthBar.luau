--!strict
--[[
    HealthBar
    Handles the HP bar display and updates.
    
    Expected UI Structure:
    - Base/Bottom/HP/Current (Fill frame)
    - Base/Bottom/HP/CurrentHP (TextLabel)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local MoneyLib = require(Rojo:WaitForChild("Shared"):WaitForChild("MoneyLib"))

local ProgressBar = require(script.Parent.Parent.ProgressBar)

local player = Players.LocalPlayer

local HealthBar = {}

local healthBar: any = nil

local function formatNumber(value: number): string
    return MoneyLib.HandleMoney(value)
end

local function updateHealth()
    if not healthBar then return end
    
    local character = player.Character
    if not character then return end
    
    local currentHP = character:GetAttribute("Health") or 100
    local maxHP = character:GetAttribute("MaxHealth") or 100
    
    healthBar:SetValue(currentHP, maxHP)
end

local function onCharacterAdded(character: Model)
    updateHealth()
    character:GetAttributeChangedSignal("Health"):Connect(updateHealth)
    character:GetAttributeChangedSignal("MaxHealth"):Connect(updateHealth)
end

function HealthBar.Init(context: any)
    local bottomFrame = context.BottomFrame
    if not bottomFrame then return end
    
    local hpFrame = bottomFrame:FindFirstChild("HP")
    if not hpFrame then
        warn("[HealthBar] HP frame not found!")
        return
    end
    
    local hpFill = hpFrame:FindFirstChild("Current")
    local hpLabel = hpFrame:FindFirstChild("CurrentHP") :: TextLabel?
    
    if hpFill and hpLabel then
        healthBar = ProgressBar.new({
            Container = hpFrame,
            Fill = hpFill,
            ValueLabel = hpLabel,
            TweenDuration = 0.2,
            ValueFormat = "%s / %s",
            Formatter = formatNumber,
        })
        HealthBar.Bar = healthBar
    else
        warn("[HealthBar] HP bar UI elements not found!")
    end
    
    -- Setup health tracking
    if context.Character then
        task.spawn(onCharacterAdded, context.Character)
    end
    player.CharacterAdded:Connect(onCharacterAdded)
    
    print("[HealthBar] Initialized!")
end

return HealthBar

--!strict
--[[
    ChestController
    Handles client-side visual indicators for chests (cooldown timers).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Rojo = ReplicatedStorage.Rojo
local Shared = Rojo.Shared
local Packets = require(Shared.Packets)
local ChestRewardsConfig = require(Shared.Rewards.ChestRewardsConfig)

local ChestController = {}

local localCooldowns: {[string]: number} = {}
local lastUpdate = 0

local function getChestModel(name: string): Model?
    local chests = workspace:FindFirstChild("Chests")
    if not chests then return nil end
    local chest = chests:FindFirstChild(name)
    if chest and chest:IsA("Model") then
        return chest
    end
    return nil
end

function ChestController.Init()
    -- Listen for data sync from server
    Packets.chestData.listen(function(data)
        localCooldowns = data.cooldowns
    end)
    
    -- Request initial data
    Packets.requestChestData.send({})

    -- Update loop (low frequency is fine for seconds)
    RunService.Heartbeat:Connect(function()
        local now = os.time()
        if now == lastUpdate then return end
        lastUpdate = now

        for name, config in pairs(ChestRewardsConfig.Rewards) do
            local chest = getChestModel(name)
            if not chest then continue end

            local important = chest:FindFirstChild("Important")
            local indicator = important and important:FindFirstChild("Indicator")
            local textPart = indicator and indicator:FindFirstChild("Text")
            local textLabel = textPart and textPart:FindFirstChild("Text2")
            
            if not textLabel or not textLabel:IsA("TextLabel") then continue end

            local lastClaim = localCooldowns[name] or 0
            
            if now - lastClaim >= config.Cooldown then
                if textLabel.Text ~= "Ready to claim !" then
                    textLabel.Text = "Ready to claim !"
                end
            else
                local timeLeft = config.Cooldown - (now - lastClaim)
                local hours = math.floor(timeLeft / 3600)
                local mins = math.floor((timeLeft % 3600) / 60)
                local secs = timeLeft % 60
                local formatted = string.format("%02d:%02d:%02d", hours, mins, secs)
                if textLabel.Text ~= formatted then
                    textLabel.Text = formatted
                end
            end
        end
    end)
    
    print("[ChestController] Initialized")
end

return ChestController

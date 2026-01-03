--!strict
--[[
    AntiAfkService
    Prevents 20-minute idle kick by teleporting player to same server every ~17 minutes.
    Restores AFK session data (XP gained).
]]

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Server = script.Parent -- src/Server

local AFKRewardsService = require(Server.Rewards.AFKRewardsService)

local AntiAfkService = {}

local MIN_REJOIN_TIME = 17 * 60 -- 17 minutes
local MAX_REJOIN_TIME = 18 * 60 -- 18 minutes

function AntiAfkService.Init()
    -- Handle players joining (check if it's a rejoin)
    Players.PlayerAdded:Connect(function(player)
        local joinData = player:GetJoinData()
        local teleportData = joinData.TeleportData
        
        -- Start AFK timer for this session
        task.delay(math.random(MIN_REJOIN_TIME, MAX_REJOIN_TIME), function()
            if player.Parent then -- Player still in game
                AntiAfkService.Rejoin(player)
            end
        end)
        
        -- If this is an auto-rejoin, handle positioning
        if teleportData and teleportData.isAutoRejoin == true then
            print("[AntiAFK] Player " .. player.Name .. " auto-rejoined. Restoring position...")
            
            player.CharacterAdded:Connect(function(character)
                -- Wait a moment for loading
                task.wait(1)
                
                local afkFolder = workspace:FindFirstChild("AFK")
                local zone = afkFolder and afkFolder:FindFirstChild("Zone")
                
                if zone and zone:IsA("BasePart") then
                    -- Teleport safely above zone
                    local cf = zone.CFrame * CFrame.new(0, 5, 0)
                    -- Randomize slightly to avoid stacking
                    cf = cf * CFrame.new(math.random(-5, 5), 0, math.random(-5, 5))
                    
                    if character.PrimaryPart then
                        character:SetPrimaryPartCFrame(cf)
                    elseif character:FindFirstChild("HumanoidRootPart") then
                        character.HumanoidRootPart.CFrame = cf
                    end
                end
            end)
        end
    end)
end

function AntiAfkService.Rejoin(player: Player)
    print("[AntiAFK] Initiating auto-rejoin for " .. player.Name)
    
    local sessionXp = AFKRewardsService.GetSessionData(player)
    
    local teleportOptions = Instance.new("TeleportOptions")
    teleportOptions:SetTeleportData({
        isAutoRejoin = true,
        sessionXp = sessionXp
    })
    
    -- Teleport back to same server instance
    local success, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, player, {
            isAutoRejoin = true,
            sessionXp = sessionXp
        }) 
    end)
    
    if not success then
        warn("[AntiAFK] Failed to teleport " .. player.Name .. ": " .. tostring(err))
    end
end

return AntiAfkService

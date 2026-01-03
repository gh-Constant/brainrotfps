--!strict
--[[
    AFKRewardsService
    Handles AFK Zone rewards using ZonePlus.
    Gives XP and uses LootUI for feedback.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Packages = Rojo:WaitForChild("Packages")
local Shared = Rojo:WaitForChild("Shared")
local Server = script.Parent.Parent -- src/Server

local Zone = require(Packages:WaitForChild("zoneplus"))
local PlayerManager = require(Server.Player)
local Packets = require(Shared.Packets)

local AFKRewardsService = {}
local REWARD_INTERVAL = 0.5
local XP_AMOUNT = 1

local activeZone = nil -- Store reference to prevent GC

function AFKRewardsService.Init()
    task.spawn(function()
        local afkFolder = workspace:WaitForChild("AFK", 30)
        local afkZonePart = afkFolder and afkFolder:WaitForChild("Zone", 30)
        
        if not afkFolder or not afkZonePart or not afkZonePart:IsA("BasePart") then
            warn("[AFKRewards] Workspace.AFK.Zone part not found!")
            return
        end
        
        -- Ensure detection properties are set
        if not afkZonePart.CanTouch then
            afkZonePart.CanTouch = true
        end
        
        if not afkZonePart.CanQuery then
             afkZonePart.CanQuery = true
        end

        local zone = Zone.new(afkZonePart)
        activeZone = zone
        
        -- Start rewards loop
        task.spawn(function()
            while true do
                local players = zone:getPlayers()
                
                for _, player in ipairs(players) do
                    local playerData = PlayerManager.GetPlayerData(player)
                    if playerData then
                        playerData:AddExperience(XP_AMOUNT)
                        
                        -- LootUI Feedback
                        -- Attempt to find XP image from config, same as PlayerManager
                        local effectsConfig = ReplicatedStorage:FindFirstChild("Config")
                        local xpImage = ""
                        if effectsConfig then
                            -- Safe navigation for Effects.FX.XP.Image
                            local success, result = pcall(function()
                                return effectsConfig["Effects"]["FX"]["XP"]["Image"]
                            end)
                            if success and result then
                                if typeof(result) == "Instance" and result:IsA("StringValue") then
                                    xpImage = result.Value
                                elseif type(result) == "string" then
                                    xpImage = result
                                end
                            end
                        end
                        
                        -- Spawn effect above player
                        local character = player.Character
                        if character and character.PrimaryPart then
                            local pos = character.PrimaryPart.Position
                            
                            Packets.lootDropFX.sendTo({
                                posX = pos.X,
                                posY = pos.Y + 3, -- Spawn slightly above head
                                posZ = pos.Z,
                                config = {
                                    image = xpImage,
                                    color = {100, 200, 255}, -- Blue for XP
                                    trailColor = {150, 220, 255},
                                    trailEnabled = true,
                                    count = 1,
                                    amount = XP_AMOUNT,
                                    text = "+"..XP_AMOUNT.." XP", -- Required for LootDropUI to show
                                },
                            }, player)
                        end
                    end
                end
                
                task.wait(REWARD_INTERVAL)
            end
        end)
        
        print("[AFKRewards] Initialized zone on " .. afkZonePart:GetFullName())
    end)
end

return AFKRewardsService

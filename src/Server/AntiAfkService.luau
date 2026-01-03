local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = script.Parent -- src/Server

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Packages = Rojo:WaitForChild("Packages")
local Promise = require(Packages:WaitForChild("promise"))

local AFKRewardsService = require(Server.Rewards.AFKRewardsService)
local Packets = require(ReplicatedStorage.Rojo.Shared.Packets)

local AntiAfkService = {}

function AntiAfkService.Init()
    -- Listen for client rejoin request via ByteNet
    Packets.requestRejoin.listen(function(data, player)
        warn("[AntiAFK] Received rejoin request from " .. player.Name)
        AntiAfkService.Rejoin(player)
    end)

    -- Function to handle player join logic
    local function onPlayerAdded(player)
        local joinData = player:GetJoinData()
        local teleportData = joinData and joinData.TeleportData
        
        if teleportData and teleportData.isAutoRejoin then
            print("[AntiAFK] Found TeleportData for " .. player.Name, teleportData)
            
            -- Restore session XP
            if teleportData.sessionXp then
                print("[AntiAFK] Restoring session XP: " .. teleportData.sessionXp)
                AFKRewardsService.SetSessionData(player, teleportData.sessionXp)
            end

            -- Teleport logic
            Promise.delay(2):andThen(function()
                local afkFolder = workspace:FindFirstChild("AFK")
                local zone = afkFolder and afkFolder:FindFirstChild("Zone")
                local character = player.Character
                
                if not character then 
                    warn("[AntiAFK] No character to teleport")
                    return 
                end

                if zone and zone:IsA("BasePart") then
                    local cf = zone.CFrame * CFrame.new(0, 5, 0)
                    if character.PrimaryPart then
                        character:PivotTo(cf)
                    elseif character:FindFirstChild("HumanoidRootPart") then
                        character.HumanoidRootPart.CFrame = cf
                    end
                    print("[AntiAFK] Teleported " .. player.Name .. " back to AFK Zone")
                else
                    warn("[AntiAFK] Zone part not found")
                end
            end):catch(function(err)
                warn("[AntiAFK] Teleport back error: " .. tostring(err))
            end)
        else
            print("[AntiAFK] No auto-rejoin TeleportData found for " .. player.Name)
        end
    end

    -- Handle players joining
    Players.PlayerAdded:Connect(onPlayerAdded)
    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(onPlayerAdded, player)
    end
end


local rejoinDebounce = {}

function AntiAfkService.Rejoin(player: Player)
    if rejoinDebounce[player] then return end
    rejoinDebounce[player] = true
    
    warn("[AntiAFK] Rejoining " .. player.Name)
    
    local sessionXp = AFKRewardsService.GetSessionData(player) or 0
    local teleportData = {
        isAutoRejoin = true,
        sessionXp = sessionXp,
        timestamp = os.time()
    }
    
    print("[AntiAFK] Preparing Teleport with Data:", teleportData)
    
    Promise.try(function()
        local teleportOptions = Instance.new("TeleportOptions")
        teleportOptions:SetTeleportData(teleportData)
        if game.JobId and game.JobId ~= "" then
            teleportOptions.ServerInstanceId = game.JobId
        end
        return teleportOptions
    end)
    :andThen(function(teleportOptions)
        warn("[AntiAFK] calling TeleportAsync...")
        return Promise.try(function()
            return TeleportService:TeleportAsync(game.PlaceId, {player}, teleportOptions)
        end)
    end)
    :catch(function(err)
        warn("[AntiAFK] Rejoin process failed: " .. tostring(err))
        rejoinDebounce[player] = nil
    end)
end

return AntiAfkService

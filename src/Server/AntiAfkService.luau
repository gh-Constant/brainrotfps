local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local Server = script.Parent -- src/Server

local AFKRewardsService = require(Server.Rewards.AFKRewardsService)
local Packets = require(ReplicatedStorage.Rojo.Shared.Packets)

local AntiAfkService = {}

-- MemoryStore Map for robust, short-term data persistence across rejoining
local rejoinMap = MemoryStoreService:GetSortedMap("AntiAfkRejoin_v2")

function AntiAfkService.Init()
    -- Listen for client rejoin request via ByteNet
    Packets.requestRejoin.listen(function(data, player)
        warn("[AntiAFK] Received rejoin request from " .. player.Name)
        AntiAfkService.Rejoin(player)
    end)

    -- Function to handle player join logic (isolated for reuse)
    -- Function to handle player join logic (isolated for reuse)
    local function onPlayerAdded(player)
        local key = tostring(player.UserId)
        print("[AntiAFK] Checking rejoin data for " .. player.Name)
        
        local success, rejoinData = pcall(function()
            return rejoinMap:GetAsync(key)
        end)

        if success and rejoinData then
            print("[AntiAFK] Data found:", rejoinData)
            
            if rejoinData.isAutoRejoin then
                -- Restore session XP
                if rejoinData.sessionXp then
                    print("[AntiAFK] Restoring session XP: " .. rejoinData.sessionXp)
                    AFKRewardsService.SetSessionData(player, rejoinData.sessionXp)
                end

                -- Teleport logic
                local function onCharacterAdded(character)
                    task.wait(2) -- Wait for load
                    
                    local afkFolder = workspace:FindFirstChild("AFK")
                    local zone = afkFolder and afkFolder:FindFirstChild("Zone")
                    
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
                end
                
                player.CharacterAdded:Connect(onCharacterAdded)
                if player.Character then
                    task.spawn(onCharacterAdded, player.Character)
                end
                
                -- Cleanup
                rejoinMap:RemoveAsync(key)
            end
        else
            print("[AntiAFK] No rejoin data found or error: " .. tostring(rejoinData))
        end
    end

    -- Handle players joining (Auto-Rejoin Logic)
    Players.PlayerAdded:Connect(onPlayerAdded)
    
    -- Handle existing players
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
    local rejoinData = {
        isAutoRejoin = true,
        sessionXp = sessionXp,
        timestamp = os.time()
    }
    
    local key = tostring(player.UserId)
    
    local success, err = pcall(function()
        rejoinMap:SetAsync(key, rejoinData, 300)
    end)
    
    if success then
        print("[AntiAFK] Saved data to MemoryStore")
        
        local teleportOptions = Instance.new("TeleportOptions")
        if game.JobId and game.JobId ~= "" then
            teleportOptions.ServerInstanceId = game.JobId
        end

        local pv = 0 
        while task.wait(0.5) do
            warn("Waiting for rejoin...")
            pv += 1
            if pv >= 10 then
                break
            end
        end

        task.wait(5)
        
        TeleportService:TeleportAsync(game.PlaceId, {player}, teleportOptions)
    else
        warn("[AntiAFK] Failed to save data: " .. tostring(err))
        rejoinDebounce[player] = nil
    end
end

return AntiAfkService

--!strict
--[[
    ChestService
    Handles logic for Group, Premium, and Discord chests.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local ServerScriptService = game:GetService("ServerScriptService")

local Rojo = ReplicatedStorage.Rojo
local Shared = Rojo.Shared
local Server = ServerScriptService.Rojo.Server
local Packages = Rojo.Packages

local Zone = require(Packages.zoneplus)
local ChestRewardsConfig = require(Shared.Rewards.ChestRewardsConfig)
local PlayerManager = require(Server.Player)
local InventoryManager = require(Server.Inventory)
local MessageSystem = require(Shared.MessageSystem)
local Packets = require(Shared.Packets)

local ChestService = {}

-- Constants
local GROUP_ID = 459737860
local DISCORD_CODE = "DISCORD_RELEASE"

-- Cache for zones to prevent GC
local ActiveZones = {}

-- Helper to find chest models
local function getChestModel(name: string): Model?
    local chest = workspace.Chests:FindFirstChild(name)
    if chest and chest:IsA("Model") then
        return chest
    end
    return nil
end

local function syncChestData(player: Player)
    local playerData = PlayerManager.GetPlayerData(player)
    if not playerData then return end
    
    Packets.chestData.sendTo({
        cooldowns = playerData.ChestCooldowns
    }, player)
end

-- Give Reward Function
local function giveRewards(player: Player, chestType: string, position: Vector3)
    local config = ChestRewardsConfig.Rewards[chestType]
    if not config then return end

    local playerData = PlayerManager.GetPlayerData(player)
    if not playerData then return end

    -- Check Cooldown (Daily)
    local lastClaim = playerData.ChestCooldowns[chestType] or 0
    local now = os.time()
    if now - lastClaim < config.Cooldown then
        local timeLeft = config.Cooldown - (now - lastClaim)
        local hours = math.floor(timeLeft / 3600)
        local mins = math.floor((timeLeft % 3600) / 60)
        MessageSystem.Send(player, "Cooldown", string.format("Please wait %dh %dm to claim again!", hours, mins))
        return
    end

    -- Update Cooldown
    playerData.ChestCooldowns[chestType] = now

    -- Sync to client
    syncChestData(player)

    -- Give Rewards
    if config.Coins and config.Coins > 0 then
        playerData:AddGold(config.Coins)
    end
    
    if config.XP and config.XP > 0 then
        playerData:AddExperience(config.XP)
        -- Visuals for XP
        local xpImage = ReplicatedStorage.Config.Effects.FX.XP.Image
        Packets.lootDropFX.sendTo({
            posX = position.X,
            posY = position.Y + 2,
            posZ = position.Z,
            config = {
                image = xpImage,
                color = {66, 135, 245},
                trailColor = {100, 160, 255},
                trailEnabled = true,
                count = 10,
                text = "+" .. config.XP .. " XP"
            },
        }, player)
    end

    if config.Items then
        for _, itemName in ipairs(config.Items) do
            local ItemUtils = require(Shared:WaitForChild("Inventory"):WaitForChild("ItemUtils"))
            local itemConfig = ItemUtils.FindItemConfig(itemName)
            local rarity = (itemConfig and itemConfig:GetAttribute("Rarity") or "Common")
            
            InventoryManager.AddItem(player, itemName)
            
            -- Item Visual
            Packets.lootDropFX.sendTo({
                posX = position.X,
                posY = position.Y + 2,
                posZ = position.Z,
                config = {
                    rarity = rarity,
                },
            }, player)
        end
    end
    
    -- LootFX for Coins (Golden burst)
    if config.Coins and config.Coins > 0 then
        local goldImage = ReplicatedStorage.Config.Effects.FX.Coin.Image
         Packets.lootDropFX.sendTo({
            posX = position.X,
            posY = position.Y + 2,
            posZ = position.Z,
            config = {
                image = goldImage,
                color = {255, 215, 0},
                trailColor = {255, 200, 50},
                trailEnabled = true,
                count = 15,
                text = "+" .. config.Coins .. " Coins"
            },
        }, player)
    end

    MessageSystem.Send(player, "Success", "Rewards claimed successfully!")
end

local function setupChest(name: string)
    local chest = getChestModel(name)
    if not chest then
        warn("[ChestService] Could not find chest: " .. name)
        return
    end

    local touchPart = chest:FindFirstChild("Important") and chest.Important:FindFirstChild("Touch")
    if not touchPart then
        warn("[ChestService] Could not find Important.Touch in " .. name)
        return
    end

    -- Create Zone
    touchPart.CanTouch = true
    touchPart.CanQuery = true
    
    local zone = Zone.new(touchPart)
    ActiveZones[name] = zone
    
    zone.playerEntered:Connect(function(player)
        print("[ChestService] Player entered zone:", player.Name, "for chest:", name)
        if name == "Group" then
            if player:IsInGroup(GROUP_ID) then
                giveRewards(player, "Group", touchPart.Position)
            else
                MessageSystem.Send(player, "Error", "Join the group to claim this chest!")
            end
        
        elseif name == "Premium" then
            if player.MembershipType == Enum.MembershipType.Premium then
                giveRewards(player, "Premium", touchPart.Position)
            else
                MessageSystem.Send(player, "Error", "You need Roblox Premium to claim this!")
                MarketplaceService:PromptPremiumPurchase(player)
            end
            
        elseif name == "Discord" then
             local playerData = PlayerManager.GetPlayerData(player)
             if playerData and playerData.HasVerifiedDiscord then
                 giveRewards(player, "Discord", touchPart.Position)
             else
                 -- Helper to find UI
                 local playerGui = player:FindFirstChild("PlayerGui")
                 if playerGui then
                    local discordGui = playerGui:FindFirstChild("Discord")
                     if discordGui then
                        discordGui.Enabled = true
                    end
                 end
             end
        end
    end)

    zone.playerExited:Connect(function(player)
        if name == "Discord" then
            local playerGui = player:FindFirstChild("PlayerGui")
            if playerGui then
                local discordGui = playerGui:FindFirstChild("Discord")
                if discordGui then
                    discordGui.Enabled = false
                end
            end
        end
    end)
end

function ChestService.Init()
    setupChest("Group")
    setupChest("Premium")
    setupChest("Discord")
    
    -- Listen for Discord Code Packet
    Packets.submitDiscordCode.listen(function(data, player: Player?)
        if not player then return end
        if data.code:lower() == DISCORD_CODE:lower() then
            local playerData = PlayerManager.GetPlayerData(player)
            if playerData then
                if not playerData.HasVerifiedDiscord then
                     playerData.HasVerifiedDiscord = true
                     PlayerManager.SavePlayer(player)
                     MessageSystem.Send(player, "Success", "Discord verified! Touch chest to claim.")
                     
                     -- Hide UI
                     local playerGui = player:FindFirstChild("PlayerGui")
                     if playerGui then
                        local discordGui = playerGui:FindFirstChild("Discord") :: ScreenGui?
                        if discordGui and discordGui:IsA("ScreenGui") then
                            discordGui.Enabled = false
                        end
                     end
                else
                     MessageSystem.Send(player, "Info", "Already verified!")
                end
            end
        else
            MessageSystem.Send(player, "Error", "Invalid code!")
        end
    end)
    
    print("[ChestService] Initialized with ZonePlus!")

    -- Listen for client data requests
    Packets.requestChestData.listen(function(_, player)
        if player then
            syncChestData(player)
        end
    end)
end

return ChestService

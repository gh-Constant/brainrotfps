--!strict
--[[
    LootSystem
    Handles mob loot drops based on modular config.
    Reads "Loot" ModuleScript from mob model config.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")
local Server = ServerScriptService:WaitForChild("Rojo"):WaitForChild("Server")

local ItemUtils = require(Shared:WaitForChild("Inventory"):WaitForChild("ItemUtils"))
local InventoryManager = require(Server:WaitForChild("Inventory"))

local Packets = require(Shared:WaitForChild("Packets"))

local LootSystem = {}

--[[
    Processes loot for a specific mob and awards it to the killer.
    
    @param mobModel - The mob model (which should contain the config/Loot module or be linked to it)
    @param killer - The player who killed the mob
]]
function LootSystem.ProcessLoot(mobModel: Model, killer: Player)
    if not killer then return end
    
    local primaryPart = mobModel.PrimaryPart or mobModel:FindFirstChildWhichIsA("BasePart")
    
    -- Try to find Loot module inside the mob model
    -- The mobModel here is the CLONE in workspace.
    local lootModule = mobModel:FindFirstChild("Loot")
    
    if not lootModule or not lootModule:IsA("ModuleScript") then
        return
    end
    
    local success, lootTable = pcall(require, lootModule)
    if not success or type(lootTable) ~= "table" then
        warn("[LootSystem] Failed to load Loot module for " .. mobModel.Name)
        return
    end
    
    if not lootTable.Items then return end
    
    for _, item in ipairs(lootTable.Items) do
        local itemName = item.Name
        local chance = item.Chance or 1 -- 1 in X chance
        
        if chance < 1 then chance = 1 end
        
        -- Apply Luck Multiplier
        -- Pre-fetch config to check Rarity
        local itemConfig = ItemUtils.FindItemConfig(itemName)
        local rarity = (itemConfig and itemConfig:GetAttribute("Rarity") or "Common") :: string
        
        -- Apply Luck Multiplier ONLY for non-common items
        local luckMultiplier = killer:GetAttribute("TotalLuckMultiplier") :: number or 1
        local adjustedChance = chance
        
        if rarity ~= "Common" and luckMultiplier > 1 then
            -- Higher luck means lower "1 in X" chance value
            adjustedChance = math.max(1, math.floor(chance / luckMultiplier))
        end
        
        if math.random(1, adjustedChance) == 1 then
            local itemType = (itemConfig and itemConfig:GetAttribute("Type"))
            
            if not itemType then
                itemType = ItemUtils.GetItemType(itemName)
            end
            
            if not itemType then
                warn("[LootSystem] Unknown item type for: " .. itemName)
                continue
            end
            
            InventoryManager.AddItem(killer, itemName, itemType :: any, rarity, nil)
            
            -- Trigger Loot FX for the item orb
            if primaryPart then
                Packets.lootDropFX.sendTo({
                    posX = primaryPart.Position.X,
                    posY = primaryPart.Position.Y + 1,
                    posZ = primaryPart.Position.Z,
                    config = {
                        rarity = rarity,
                    },
                }, killer)
            end
            
            if luckMultiplier > 1 and rarity ~= "Common" then
                 print(string.format("[LootSystem] 🍀 Lucky drop for %s! Item: %s, Rarity: %s (Luck: x%.1f, Chance: 1/%d -> 1/%d)", 
                 killer.Name, itemName, rarity, luckMultiplier, chance, adjustedChance))
            end
        end
    end
end

return LootSystem

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

local LootSystem = {}

--[[
    Processes loot for a specific mob and awards it to the killer.
    
    @param mobModel - The mob model (which should contain the config/Loot module or be linked to it)
    @param killer - The player who killed the mob
]]
function LootSystem.ProcessLoot(mobModel: Model, killer: Player)
    if not killer then return end
    
    -- Try to find Loot module inside the mob model
    -- The mobModel here is the CLONE in workspace.
    -- However, the user said "inside the mob config".
    -- In BrainrotSpawner, the mob is cloned from a Template in ReplicatedStorage.Config.Brainrots.Zones...
    -- The clone might NOT have the ModuleScript if scripts don't clone or if it wasn't there.
    -- BUT, usually we want to read from the Template Config to avoid cloning scripts into every mob.
    -- We can fallback to checking if the mob has a "Loot" module inside it (if user puts it there).
    -- OR we check the Config that generated it.
    
    -- Strategy: Check mobModel for "Loot" ModuleScript.
    local lootModule = mobModel:FindFirstChild("Loot")
    
    if not lootModule or not lootModule:IsA("ModuleScript") then
        -- Warn only if debug is on, otherwise silent (not all mobs drop loot)
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
        
        -- Default to 1 (always drop) if chance is nil/0
        if chance < 1 then chance = 1 end
        
        -- Roll: 1/Chance
        -- e.g. Chance 10 = 1/10 = 10%
        if math.random(1, chance) == 1 then
            -- Drop Success!
            
            -- Get Item Config first to get correct data
            local itemConfig = ItemUtils.FindItemConfig(itemName)
            
            -- KEY FIX: Use the "Type" attribute (e.g. "Tool") NOT the ItemType (e.g. "Gun")
            -- ToolbarUtils requires Type == "Tool" to allow equipping.
            local itemType = (itemConfig and itemConfig:GetAttribute("Type"))
            
            -- Fallback if Type attribute is missing (shouldn't happen for valid items)
            if not itemType then
                itemType = ItemUtils.GetItemType(itemName)
            end
            
            if not itemType then
                warn("[LootSystem] Unknown item type for: " .. itemName)
                continue
            end
            
            -- Get Rarity
            local rarity = (itemConfig and itemConfig:GetAttribute("Rarity") or "Common") :: string
            
            -- Add to Inventory
            -- Note: InventoryManager handles validation and addition
            InventoryManager.AddItem(killer, itemName, itemType :: any, rarity, nil)
            
        end
    end
end

return LootSystem

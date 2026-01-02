--!strict
--[[
    PotionService
    Handles server-side potion logic (drinking, applying buffs/instant effects).
    
    Potion Tool Attributes:
    - IsPotion: boolean (true to mark as potion)
    - PotionType: "Boost" | "Instant"
    - ValueType: string (what the potion affects: "Luck", "Coins", "MobDamage", "Health", "XP", etc.)
    - Value: number (the multiplier for Boost, or amount for Instant)
    - ValueFormat: "%" | "raw" (for Instant potions - percentage or raw number)
    - Duration: number (seconds, only for Boost potions)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")

local Inventory = require(Shared:WaitForChild("Inventory"))
local InventoryManager = require(ServerScriptService.Rojo.Server.Inventory)

-- Lazy load PlayerManager to avoid circular dependency
local PlayerManager = nil
local function getPlayerManager()
    if not PlayerManager then
        PlayerManager = require(ServerScriptService.Rojo.Server.Player)
    end
    return PlayerManager
end

local PotionService = {}

-- Track active buff timers to prevent stacking of same buff type
local ActiveBuffTimers: {[string]: thread} = {} -- Key: "userId_valueType"

-- Track connected tools to prevent double connections
local ConnectedTools: {[Tool]: boolean} = {}

--------------------------------------------------------------------------------
-- Helper Functions
--------------------------------------------------------------------------------

--[[
    Formats duration in seconds to a nice string like "15m 14" or "59"
]]
local function formatDuration(seconds: number): string
    local minutes = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    
    if minutes > 0 then
        return string.format("%dm %d", minutes, secs)
    else
        return tostring(secs)
    end
end

--[[
    Formats the boost multiplier nicely
]]
local function _formatBoost(value: number): string
    if value == math.floor(value) then
        return "x" .. tostring(math.floor(value))
    else
        return "x" .. string.format("%.1f", value)
    end
end

--[[
    Gets the tool icon for display in buff UI
]]
local function getToolIcon(tool: Tool): string
    local textureId = tool.TextureId
    if textureId and textureId ~= "" then
        return textureId
    end
    
    -- Try to get from Config
    local templateId = (tool:GetAttribute("StackTemplateId") :: string?) or tool.Name
    local itemConfig = Inventory.ItemUtils.FindItemConfig(templateId)
    if itemConfig then
        local image = itemConfig:GetAttribute("Image") :: string?
        if image and image ~= "" then
            if not string.find(image, "://") then
                return "rbxassetid://" .. image
            end
            return image
        end
    end
    
    return ""
end

--------------------------------------------------------------------------------
-- Buff Application
--------------------------------------------------------------------------------

--[[
    Applies a Boost buff to a player.
    Sets attributes on player that BuffController.luau will read.
]]
local function applyBoostBuff(player: Player, valueType: string, value: number, duration: number, icon: string)
    local buffKey = player.UserId .. "_" .. valueType
    
    -- Cancel existing timer for this buff type
    if ActiveBuffTimers[buffKey] then
        task.cancel(ActiveBuffTimers[buffKey])
        ActiveBuffTimers[buffKey] = nil
    end
    
    local endTime = os.time() + duration
    
    -- Set buff attributes on player
    player:SetAttribute("Buff_Potion_" .. valueType, value)
    player:SetAttribute("Buff_Potion_" .. valueType .. "_EndTime", endTime)
    player:SetAttribute("Buff_Potion_" .. valueType .. "_Icon", icon)
    
    print(string.format("[PotionService] Applied %s boost (x%.2f) to %s for %s", 
        valueType, value, player.Name, formatDuration(duration)))
    
    -- Schedule removal
    local timerThread = task.delay(duration, function()
        -- Clear attributes
        player:SetAttribute("Buff_Potion_" .. valueType, nil)
        player:SetAttribute("Buff_Potion_" .. valueType .. "_EndTime", nil)
        player:SetAttribute("Buff_Potion_" .. valueType .. "_Icon", nil)
        
        ActiveBuffTimers[buffKey] = nil
        print(string.format("[PotionService] %s boost expired for %s", valueType, player.Name))
    end)
    
    ActiveBuffTimers[buffKey] = timerThread
end

--[[
    Applies an Instant effect to a player.
]]
local function applyInstantEffect(player: Player, valueType: string, value: number, valueFormat: string)
    local playerData = getPlayerManager().GetPlayerData(player)
    local character = player.Character
    
    local lowerType = string.lower(valueType)
    
    if lowerType == "health" or lowerType == "hp" then
        if character then
            local maxHealth = (character:GetAttribute("MaxHealth") :: number?) or 100
            local currentHealth = (character:GetAttribute("Health") :: number?) or 100
            
            local healAmount: number
            if valueFormat == "%" then
                healAmount = maxHealth * (value / 100)
            else
                healAmount = value
            end
            
            local newHealth = math.min(currentHealth + healAmount, maxHealth)
            character:SetAttribute("Health", newHealth)
            
            -- Also update humanoid for compatibility
            local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?
            if humanoid then
                humanoid.Health = newHealth
            end
            
            print(string.format("[PotionService] %s healed for %.0f HP (%.0f -> %.0f)", 
                player.Name, healAmount, currentHealth, newHealth))
        end
        
    elseif lowerType == "xp" or lowerType == "experience" then
        if playerData then
            local xpAmount: number
            if valueFormat == "%" then
                -- Percentage of XP needed for next level
                local xpForLevel = playerData.Level * 100
                xpAmount = math.floor(xpForLevel * (value / 100))
            else
                xpAmount = math.floor(value)
            end
            
            playerData:AddExperience(xpAmount)
            print(string.format("[PotionService] %s gained %d XP", player.Name, xpAmount))
        end
        
    elseif lowerType == "coins" or lowerType == "gold" then
        if playerData then
            local coinAmount: number
            if valueFormat == "%" then
                coinAmount = math.floor(playerData.Gold * (value / 100))
            else
                coinAmount = math.floor(value)
            end
            
            playerData:AddGold(coinAmount)
            print(string.format("[PotionService] %s gained %d Gold", player.Name, coinAmount))
        end
        
    elseif lowerType == "credits" then
        if playerData then
            local creditAmount: number
            if valueFormat == "%" then
                creditAmount = math.floor(playerData.Credits * (value / 100))
            else
                creditAmount = math.floor(value)
            end
            
            playerData:AddCredits(creditAmount)
            print(string.format("[PotionService] %s gained %d Credits", player.Name, creditAmount))
        end
        
    else
        warn(string.format("[PotionService] Unknown instant effect type: %s", valueType))
    end
end

--------------------------------------------------------------------------------
-- Main Drink Logic
--------------------------------------------------------------------------------

--[[
    Called when a player drinks a potion tool.
]]
function PotionService.DrinkPotion(player: Player, tool: Tool)
    -- Validate potion
    if not tool:GetAttribute("IsPotion") then
        return
    end
    
    -- Get potion attributes
    local potionType = tool:GetAttribute("PotionType") :: string?
    local valueType = tool:GetAttribute("ValueType") :: string?
    local value = tool:GetAttribute("Value") :: number?
    local valueFormat = (tool:GetAttribute("ValueFormat") :: string?) or "%"
    local duration = (tool:GetAttribute("Duration") :: number?) or 0
    
    if not potionType or not valueType or not value then
        warn(string.format("[PotionService] Potion %s missing required attributes", tool.Name))
        return
    end
    
    -- Get inventory item info from the tool
    local inventoryItemId = tool:GetAttribute("InventoryItemId") :: string?
    
    if not inventoryItemId then
        warn(string.format("[PotionService] BLOCKED: %s tried to drink potion without InventoryItemId", player.Name))
        return
    end
    
    -- Verify item exists in player's inventory
    local inventory = InventoryManager.GetInventory(player)
    if not inventory then
        warn(string.format("[PotionService] BLOCKED: %s has no inventory loaded", player.Name))
        return
    end
    
    local foundInInventory = false
    for _, invItem in ipairs(inventory.Items) do
        if invItem.Id == inventoryItemId then
            foundInInventory = true
            break
        end
    end
    
    if not foundInInventory then
        warn(string.format("[PotionService] BLOCKED: %s tried to drink potion %s not in inventory", 
            player.Name, inventoryItemId:sub(1, 8)))
        return
    end
    
    -- Get icon before removing
    local icon = getToolIcon(tool)
    
    -- Consume the potion
    local removed = InventoryManager.RemoveItem(player, inventoryItemId)
    
    if not removed then
        warn(string.format("[PotionService] BLOCKED: Failed to consume potion %s", inventoryItemId:sub(1, 8)))
        return
    end
    
    print(string.format("[PotionService] %s drank %s (%s)", player.Name, tool.Name, potionType))
    
    -- Apply effect based on type
    if potionType == "Boost" then
        if duration <= 0 then
            warn(string.format("[PotionService] Boost potion %s has no duration set", tool.Name))
            duration = 60 -- Default 1 minute
        end
        applyBoostBuff(player, valueType, value, duration, icon)
        
    elseif potionType == "Instant" then
        applyInstantEffect(player, valueType, value, valueFormat)
        
    else
        warn(string.format("[PotionService] Unknown potion type: %s", potionType))
    end
end

--------------------------------------------------------------------------------
-- Tool Connection
--------------------------------------------------------------------------------

--[[
    Connects the Activated event for a potion tool.
]]
local function connectPotionTool(tool: Tool, player: Player)
    if ConnectedTools[tool] then return end
    ConnectedTools[tool] = true
    
    print(string.format("[PotionService] Connected potion tool: %s for %s", tool.Name, player.Name))
    
    tool.Activated:Connect(function()
        print(string.format("[PotionService] Tool activated: %s by %s", tool.Name, player.Name))
        PotionService.DrinkPotion(player, tool)
    end)
end

--[[
    Scans player's backpack and character for potion tools and connects them.
]]
local function scanPlayerTools(player: Player)
    local function checkAndConnect(tool: Tool)
        local isPotion = tool:GetAttribute("IsPotion")
        if isPotion then
            connectPotionTool(tool, player)
        end
    end
    
    -- Wait for backpack if it doesn't exist yet
    local backpack = player:FindFirstChild("Backpack") or player:WaitForChild("Backpack", 10)
    if backpack then
        -- Connect to future tools
        backpack.ChildAdded:Connect(function(child)
            if child:IsA("Tool") then
                checkAndConnect(child)
            end
        end)
        
        -- Scan existing tools
        for _, child in backpack:GetChildren() do
            if child:IsA("Tool") then
                checkAndConnect(child)
            end
        end
    end
    
    -- Scan current character
    local character = player.Character
    if character then
        for _, child in character:GetChildren() do
            if child:IsA("Tool") then
                checkAndConnect(child)
            end
        end
        
        character.ChildAdded:Connect(function(child)
            if child:IsA("Tool") then
                checkAndConnect(child)
            end
        end)
    end
    
    -- Listen for future characters
    player.CharacterAdded:Connect(function(char)
        char.ChildAdded:Connect(function(child)
            if child:IsA("Tool") then
                checkAndConnect(child)
            end
        end)
        
        for _, child in char:GetChildren() do
            if child:IsA("Tool") then
                checkAndConnect(child)
            end
        end
    end)
    
    print(string.format("[PotionService] Scanned tools for %s", player.Name))
end

--------------------------------------------------------------------------------
-- Cleanup
--------------------------------------------------------------------------------

local function onPlayerRemoving(player: Player)
    -- Cancel any active buff timers for this player
    for key, timerThread in pairs(ActiveBuffTimers) do
        if string.find(key, "^" .. tostring(player.UserId) .. "_") then
            task.cancel(timerThread)
            ActiveBuffTimers[key] = nil
        end
    end
    
    -- Clean up connected tools
    local backpack = player:FindFirstChild("Backpack")
    if backpack then
        for _, child in backpack:GetChildren() do
            if child:IsA("Tool") then
                ConnectedTools[child] = nil
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

function PotionService.Init()
    -- Handle new players
    Players.PlayerAdded:Connect(function(player)
        -- Wait for inventory to load and tools to spawn
        task.delay(2, function()
            scanPlayerTools(player)
        end)
    end)
    
    -- Handle existing players
    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(function()
            task.wait(0.5) -- Brief delay for init order
            scanPlayerTools(player)
        end)
    end
    
    -- Cleanup on player leave
    Players.PlayerRemoving:Connect(onPlayerRemoving)
    
    print("[PotionService] Initialized!")
end

return PotionService

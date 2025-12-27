-- giveitem server handler
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Get InventoryManager
local Server = ServerScriptService:WaitForChild("Rojo"):WaitForChild("Server")
local InventoryManager = require(Server:WaitForChild("Inventory"))

--[[
    Gets item config from ReplicatedStorage/Config/Items (supports nested folders)
]]
local function getItemConfig(itemName: string)
    local config = ReplicatedStorage:FindFirstChild("Config")
    if not config then return nil end
    
    local items = config:FindFirstChild("Items")
    if not items then return nil end
    
    -- Recursive search for Configuration elements
    local function searchRecursive(parent)
        for _, child in parent:GetChildren() do
            if child:IsA("Configuration") and child.Name == itemName then
                return child
            elseif child:IsA("Folder") then
                local found = searchRecursive(child)
                if found then return found end
            end
        end
        return nil
    end
    
    return searchRecursive(items)
end

return function(context, player, itemName)
    -- Check if item exists in config
    local itemConfig = getItemConfig(itemName)
    if not itemConfig then
        return string.format("Item '%s' not found in Config/Items", itemName)
    end
    
    -- Get Type from config attribute
    local itemType = itemConfig:GetAttribute("Type")
    if not itemType then
        return string.format("Item '%s' is missing 'Type' attribute", itemName)
    end
    
    -- Get rarity from config
    local rarity = itemConfig:GetAttribute("Rarity")
    
    -- Add item
    local item = InventoryManager.AddItem(player, itemName, itemType, rarity)
    
    if item then
        local rarityStr = rarity and (" [" .. rarity .. "]") or ""
        return string.format(
            "Gave %s: %s (%s)%s",
            player.Name,
            itemName,
            itemType,
            rarityStr
        )
    else
        return "Failed to add item. Player may not have inventory loaded."
    end
end

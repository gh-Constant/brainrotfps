-- dupeitem server handler
local ServerScriptService = game:GetService("ServerScriptService")

-- Get InventoryManager
local Server = ServerScriptService:WaitForChild("Rojo"):WaitForChild("Server")
local InventoryManager = require(Server:WaitForChild("Inventory"))

return function(context)
    local player = context.Executor
    
    -- Get player's inventory
    local inventory = InventoryManager.GetInventory(player)
    if not inventory then
        return "No inventory loaded. Try again later."
    end
    
    -- Check if player has any items
    if #inventory.Items == 0 then
        return "Your inventory is empty. Use /giveitem first."
    end
    
    -- Get first item
    local firstItem = inventory.Items[1]
    
    -- Duplicate it (this does NOT register in ItemRegistry)
    local dupedItem = InventoryManager.DuplicateItem(player, firstItem.Id)
    
    if dupedItem then
        return string.format(
            "Duplicated '%s' (original: %s -> dupe: %s)\n" ..
            "The dupe is NOT registered in ItemRegistry.\n" ..
            "Relog to trigger dupe detection!",
            firstItem.TemplateId,
            firstItem.Id:sub(1, 8),
            dupedItem.Id:sub(1, 8)
        )
    else
        return "Failed to duplicate item."
    end
end

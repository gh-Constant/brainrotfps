-- clearinventory server handler
local ServerScriptService = game:GetService("ServerScriptService")

-- Get InventoryManager
local Server = ServerScriptService:WaitForChild("Rojo"):WaitForChild("Server")
local InventoryManager = require(Server:WaitForChild("Inventory"))

return function(context, player)
    local inventory = InventoryManager.GetInventory(player)
    
    if not inventory then
        return "Player has no inventory loaded."
    end
    
    local itemCount = #inventory.Items
    
    if itemCount == 0 then
        return string.format("%s's inventory is already empty.", player.Name)
    end
    
    -- Remove all items (iterate backwards to avoid index issues)
    for i = #inventory.Items, 1, -1 do
        local item = inventory.Items[i]
        InventoryManager.RemoveItem(player, item.Id)
    end
    
    return string.format("Cleared %d items from %s's inventory.", itemCount, player.Name)
end

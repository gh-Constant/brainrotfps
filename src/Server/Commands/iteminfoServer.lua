-- iteminfo server handler
local ServerScriptService = game:GetService("ServerScriptService")

-- Get InventoryManager
local Server = ServerScriptService:WaitForChild("Rojo"):WaitForChild("Server")
local InventoryManager = require(Server:WaitForChild("Inventory"))
local ItemRegistry = InventoryManager.GetItemRegistry()

return function(context, itemId)
    local player = context.Executor
    
    -- Handle "first" shortcut
    if itemId:lower() == "first" then
        local inventory = InventoryManager.GetInventory(player)
        if not inventory or #inventory.Items == 0 then
            return "No items in inventory."
        end
        itemId = inventory.Items[1].Id
    end
    
    -- Look up in registry
    local record = nil
    local success = ItemRegistry.GetRecord(itemId):andThen(function(result)
        record = result
    end):await()
    
    if not success then
        return "Error looking up item in registry."
    end
    
    return ItemRegistry.FormatRecord(record)
end

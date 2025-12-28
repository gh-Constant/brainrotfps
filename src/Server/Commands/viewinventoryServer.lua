-- viewinventory server handler
local ServerScriptService = game:GetService("ServerScriptService")

-- Get InventoryManager
local Server = ServerScriptService:WaitForChild("Rojo"):WaitForChild("Server")
local InventoryManager = require(Server:WaitForChild("Inventory"))

return function(context, targetPlayer)
    local player = targetPlayer or context.Executor
    
    local inventory = InventoryManager.GetInventory(player)
    
    if not inventory then
        return "Could not find inventory for " .. player.Name
    end
    
    if #inventory.Items == 0 then
        return player.Name .. " has no items."
    end
    
    local lines = {
        string.format("=== Inventory: %s (%d items) ===", player.Name, #inventory.Items)
    }
    
    for i, item in ipairs(inventory.Items) do
        local mutationsStr = ""
        if item.Metadata and item.Metadata.Mutations then
            local legParts = {}
            for name, count in pairs(item.Metadata.Mutations) do
                table.insert(legParts, name .. " x" .. count)
            end
            mutationsStr = " {Mutations: " .. table.concat(legParts, ", ") .. "}"
        end
        
        local info = string.format(
            "%d. [%s] %s (%s)%s [ID: %s]",
            i,
            item.Rarity or "Common",
            item.TemplateId,
            item.Type,
            mutationsStr,
            item.Id
        )
        table.insert(lines, info)
    end
    
    return table.concat(lines, "\n")
end

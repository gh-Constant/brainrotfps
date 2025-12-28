local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")
local Types = require(Shared:WaitForChild("Inventory"):WaitForChild("Types"))
local Mutations = require(Shared:WaitForChild("Mutations"))

return {
    Name = "givemutated",
    Aliases = {"gm"},
    Description = "Give a mutated item (Debug)",
    Args = {
        {Name = "Player", Type = "Player", Optional = true},
        {Name = "ItemName", Type = "string"},
        {Name = "Mutation", Type = "string"},
        {Name = "Count", Type = "number", Optional = true},
    },
    Run = function(context, player, itemName, mutationName, count)
        local target = player or context.Executor
        local count = count or 1
        
        local mutationData = Mutations.GetMutation(mutationName)
        if not mutationData then
            return "Invalid mutation name: " .. tostring(mutationName)
        end
        
        local InventoryManager = require(game:GetService("ServerScriptService"):WaitForChild("Rojo").Server.Inventory)
        
        -- Create item with mutation metadata
        local mutations = {}
        mutations[mutationName] = count
        
        local metadata = {
            Mutations = mutations
        }
        
        local success = InventoryManager.AddItem(target, itemName, "Tool", "Common", metadata)
        
        if success then
            return "Given " .. itemName .. " with " .. mutationName .. " x" .. count .. " to " .. target.Name
        else
            return "Failed to give item."
        end
    end
}

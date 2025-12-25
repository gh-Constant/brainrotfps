-- Mutation type for spawnmob command autocomplete
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- We'll require the Mutations module to get mutation names
local mutationNames = nil

return function(registry)
    local function getMutationNames()
        if mutationNames then return mutationNames end
        
        -- Try to require Mutations module
        local Rojo = ReplicatedStorage:FindFirstChild("Rojo")
        if Rojo then
            local Shared = Rojo:FindFirstChild("Shared")
            if Shared then
                local MutationsModule = Shared:FindFirstChild("Mutations")
                if MutationsModule then
                    local success, Mutations = pcall(function()
                        return require(MutationsModule)
                    end)
                    if success and Mutations and Mutations.GetMutationNames then
                        mutationNames = Mutations.GetMutationNames()
                        table.insert(mutationNames, 1, "none") -- Add "none" option at start
                        return mutationNames
                    end
                end
            end
        end
        
        -- Fallback list
        mutationNames = {"none", "Taco", "Nyan", "Galactic", "Fireworks", "Zombie", "Claws", "Glitched", "Bubblegum", "Fire"}
        return mutationNames
    end
    
    registry:RegisterType("mutationType", {
        DisplayName = "Mutation Type",
        
        Transform = function(text)
            return text
        end,
        
        Validate = function(text)
            local mutations = getMutationNames()
            for _, mutationName in ipairs(mutations) do
                if mutationName:lower() == text:lower() then
                    return true
                end
            end
            return false, "Invalid mutation. Valid: " .. table.concat(mutations, ", ")
        end,
        
        Autocomplete = function(text)
            local results = {}
            local mutations = getMutationNames()
            for _, mutationName in ipairs(mutations) do
                if mutationName:lower():sub(1, #text) == text:lower() then
                    table.insert(results, mutationName)
                end
            end
            return results
        end,
        
        Parse = function(text)
            if text:lower() == "none" then
                return nil
            end
            -- Return properly cased mutation name
            local mutations = getMutationNames()
            for _, mutationName in ipairs(mutations) do
                if mutationName:lower() == text:lower() then
                    return mutationName
                end
            end
            return text
        end,
    })
end

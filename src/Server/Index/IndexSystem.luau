--!strict
--[[
    IndexSystem.luau
    Manages player index data (killed mobs) and persistence.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")
local Packages = Rojo:WaitForChild("Packages")

local IndexConstants = require(Shared:WaitForChild("IndexConstants"))
local Packets = require(Shared:WaitForChild("Packets"))
local Promise = require(Packages:WaitForChild("promise"))

-- DataStore
local indexDataStore = DataStoreService:GetDataStore(IndexConstants.DataStoreKey)

local IndexSystem = {}

-- Types
type IndexData = {
    Brainrots: {[string]: boolean},
    Weapons: {[string]: boolean},
}

-- State
local playerIndexData: {[Player]: IndexData} = {}

--[[
    Loads player data from DataStore.
]]
local function loadData(player: Player)
    Promise.try(function()
        return indexDataStore:GetAsync(tostring(player.UserId))
    end):andThen(function(data)
        if data then
            playerIndexData[player] = data
        else
            -- New player
            playerIndexData[player] = {
                Brainrots = {},
                Weapons = {},
            }
        end
        print("[IndexSystem] Loaded data for " .. player.Name)
    end):catch(function(err)
        warn("[IndexSystem] Failed to load data for " .. player.Name .. ": " .. tostring(err))
        -- Fallback to empty
        playerIndexData[player] = {
            Brainrots = {},
            Weapons = {},
        }
    end)
end

--[[
    Saves player data to DataStore.
]]
local function saveData(player: Player)
    local data = playerIndexData[player]
    if not data then return end
    
    Promise.try(function()
        return indexDataStore:SetAsync(tostring(player.UserId), data)
    end):andThen(function()
        print("[IndexSystem] Saved data for " .. player.Name)
    end):catch(function(err)
        warn("[IndexSystem] Failed to save data for " .. player.Name .. ": " .. tostring(err))
    end):finally(function()
        playerIndexData[player] = nil
    end)
end

--[[
    Helper to convert map to array for ByteNet
]]
local function mapToArray(map: {[string]: boolean}): {string}
    local arr = {}
    for k, v in pairs(map) do
        if v then table.insert(arr, k) end
    end
    return arr
end

--[[
    Records a mob kill for a player.
]]
function IndexSystem.OnMobKilled(player: Player, mobName: string)
    if not player or not mobName then return end
    
    local data = playerIndexData[player]
    if not data then return end
    
    -- Ensure sub-table exists (migration safety)
    if not data.Brainrots then data.Brainrots = {} end
    
    if not data.Brainrots[mobName] then
        -- New discovery!
        data.Brainrots[mobName] = true
        print("[IndexSystem] Player " .. player.Name .. " discovered " .. mobName)
        
        -- Notify client immediately with updated data
        local response = {
            brainrots = mapToArray(data.Brainrots or {}),
            weapons = mapToArray(data.Weapons or {}),
        }
        Packets.indexData.sendTo(response, player)
    end
end



--[[
    Initializes the Index System.
]]
function IndexSystem.Init()
    -- Packet Listeners
    Packets.requestIndexData.listen(function(_, player)
        if not player then return end
        local data = playerIndexData[player]
        if data then
            -- Convert to ByteNet format (Arrays)
            local response = {
                brainrots = mapToArray(data.Brainrots or {}),
                weapons = mapToArray(data.Weapons or {}),
            }
            Packets.indexData.sendTo(response, player)
        end
    end)
    
    -- Player Lifecycle
    Players.PlayerAdded:Connect(loadData)
    Players.PlayerRemoving:Connect(saveData)
    
    -- Handle existing players (for hot reload)
    for _, player in Players:GetPlayers() do
        task.spawn(function() loadData(player) end)
    end
    
    print("[IndexSystem] Initialized")
end

return IndexSystem

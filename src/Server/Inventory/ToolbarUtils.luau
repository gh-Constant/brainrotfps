--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")

local Inventory = require(Shared:WaitForChild("Inventory"))

local ToolbarUtils = {}

-- Helper log function
local function log(message: string)
    local config = ReplicatedStorage:FindFirstChild("Config")
    if config then
        local invConfig = config:FindFirstChild("Inventory")
        if invConfig and invConfig:GetAttribute("Logging") == true then
            print(message)
        end
    end
end

--[[
    Spawns all toolbar tools for a player.
]]
function ToolbarUtils.SpawnToolbarTools(player: Player, inventory: any)
    if not inventory then return end
    
    local backpack = player:FindFirstChild("Backpack")
    if not backpack then return end
    
    local config = ReplicatedStorage:FindFirstChild("Config")
    if not config then return end
    
    local items = config:FindFirstChild("Items")
    if not items then return end
    
    -- Spawn each toolbar item
    for slot, itemId in pairs(inventory.ToolbarSlots) do
        if not itemId then continue end
        local item = Inventory.FindById(inventory.Items, itemId :: string)
        if item and item.Type == "Tool" then
            -- Check if already spawned
            local alreadyExists = false
            for _, tool in backpack:GetChildren() do
                if tool:IsA("Tool") and tool:GetAttribute("InventoryItemId") == itemId then
                    alreadyExists = true
                    break
                end
            end
            
            if not alreadyExists then
                local itemConfig = Inventory.ItemUtils.FindItemConfig(item.TemplateId)
                if itemConfig then
                    local toolTemplate = itemConfig:FindFirstChildWhichIsA("Tool")
                    if toolTemplate then
                        local toolClone = toolTemplate:Clone()
                        toolClone:SetAttribute("InventoryItemId", itemId)
                        toolClone:SetAttribute("ToolbarSlot", slot)
                        
                        -- Check if this is a stackable item and set stack attributes
                        local isStackable = Inventory.IsStackable(item.TemplateId)
                        if isStackable then
                            -- Count all items of same template in inventory
                            local stackCount = 0
                            for _, invItem in ipairs(inventory.Items) do
                                if invItem.TemplateId == item.TemplateId 
                                    and invItem.Type == item.Type 
                                    and invItem.Rarity == item.Rarity then
                                    stackCount = stackCount + 1
                                end
                            end
                            toolClone:SetAttribute("StackCount", stackCount)
                            toolClone:SetAttribute("StackTemplateId", item.TemplateId)
                            toolClone:SetAttribute("IsStackable", true)
                        end
                        
                        -- Apply Mutations/Metadata
                        if item.Metadata and item.Metadata.Mutations then
                            toolClone:SetAttribute("Mutations", HttpService:JSONEncode(item.Metadata.Mutations))
                        end
                        
                        toolClone.Parent = backpack
                        log(string.format("[ToolbarUtils] Spawned %s for %s (slot %d)", item.TemplateId, player.Name, slot))
                    end
                end
            end
        end
    end
end

--[[
    Helper to spawn a single tool in backpack for a slot.
]]
function ToolbarUtils.SpawnToolInSlot(player: Player, item: any, slot: number, stackCount: number?)
    local backpack = player:FindFirstChild("Backpack")
    if not backpack then return end
    
    local itemConfig = Inventory.ItemUtils.FindItemConfig(item.TemplateId)
    if not itemConfig then return end
    
    local toolTemplate = itemConfig:FindFirstChildWhichIsA("Tool")
    if not toolTemplate then return end
    
    local toolClone = toolTemplate:Clone()
    toolClone:SetAttribute("InventoryItemId", item.Id)
    toolClone:SetAttribute("ToolbarSlot", slot)
    
    if stackCount then
        toolClone:SetAttribute("StackCount", stackCount)
        toolClone:SetAttribute("StackTemplateId", item.TemplateId)
        toolClone:SetAttribute("IsStackable", true)
    end
    
    -- Apply Mutations/Metadata
    if item.Metadata and item.Metadata.Mutations then
        toolClone:SetAttribute("Mutations", HttpService:JSONEncode(item.Metadata.Mutations))
    end
    
    toolClone.Parent = backpack
end

return ToolbarUtils

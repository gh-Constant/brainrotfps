--!strict
--[[
    BuffController
    Manages the Client-Side Buff UI (FriendBoost, Premium).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BuffController = {
    Name = "BuffController",
    Priority = 10
}

-- References
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local config = ReplicatedStorage:WaitForChild("Config")
local buffTemplates = config:WaitForChild("Buffs"):WaitForChild("Template")
local friendTemplate = buffTemplates:WaitForChild("FriendBoost")
local premiumTemplate = buffTemplates:WaitForChild("Premium")

-- Constants
local BUFF_NAMES = {
    FRIEND = "FriendBoost",
    PREMIUM = "Premium",
}

--[[
    Updates the Friend Boost UI.
    @param container - The Verified UI container (Frame)
    @param percentage - The boost percentage (0.0 - 0.5)
]]
local function updateFriendBoost(container: Frame, percentage: number)
    local existing = container:FindFirstChild(BUFF_NAMES.FRIEND)
    
    if percentage > 0 then
        local frame = existing or friendTemplate:Clone()
        
        if not existing then
            frame.Name = BUFF_NAMES.FRIEND
            frame.Parent = container
        end
        
        -- Update Text
        local textLabel = frame:FindFirstChild("TextLabel") :: TextLabel?
        if textLabel then
            -- "10% Friend Boost"
            textLabel.Text = string.format("%d%% FriendXP", math.floor(percentage * 100))
        end
    else
        -- Remove if exists
        if existing then
            existing:Destroy()
        end
    end
end

--[[
    Updates the Premium UI.
    @param container - The Verified UI container (Frame)
    @param isActive - Whether Premium is active
]]
local function updatePremiumBuff(container: Frame, isActive: boolean)
    local existing = container:FindFirstChild(BUFF_NAMES.PREMIUM)
    
    if isActive then
        if not existing then
            local frame = premiumTemplate:Clone()
            frame.Name = BUFF_NAMES.PREMIUM
            frame.Parent = container
        end
        -- No text update needed for Premium likely, just the static template
    else
        -- Remove if exists
        if existing then
            existing:Destroy()
        end
    end
end

--[[
    Main update function triggered by attribute changes.
]]
local function updateBuffs()
    local buffsGui = playerGui:FindFirstChild("Buffs")
    if not buffsGui then return end
    
    local buffsFrame = buffsGui:FindFirstChild("Buffs")
    if not buffsFrame then return end
    
    local container = buffsFrame:FindFirstChild("Vertical")
    if not container then return end
    
    -- Get Attributes
    local friendBoost = player:GetAttribute("Buff_FriendBoost") or 0
    local isPremium = player:GetAttribute("Buff_Premium") == true
    
    updateFriendBoost(container, friendBoost)
    updatePremiumBuff(container, isPremium)
end

function BuffController.Init(_context: any)
    -- Wait for initial UI
    task.spawn(function()
        local buffsGui = playerGui:WaitForChild("Buffs", 10)
        if not buffsGui then 
            warn("[BuffController] Could not find Buffs UI!")
            return 
        end
        
        -- Initial Update
        updateBuffs()
        
        -- Listen for Attribute Changes
        player.AttributeChanged:Connect(function(attributeName)
            if attributeName == "Buff_FriendBoost" or attributeName == "Buff_Premium" then
                updateBuffs()
            end
        end)
    end)
    
    print("[BuffController] Initialized")
end

return BuffController

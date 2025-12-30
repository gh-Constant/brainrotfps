--!strict
--[[
    BuffController
    Manages the Client-Side Buff UI (FriendBoost, Premium).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local Packages = ReplicatedStorage:WaitForChild("Rojo"):WaitForChild("Packages")
local Promise = require(Packages:WaitForChild("promise"))

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

-- UI References (cached after init)
local friendFrame: Frame?
local premiumFrame: Frame?

-- Colors
-- local ACTIVE_COLOR = Color3.fromRGB(255, 255, 255)
-- local INACTIVE_COLOR = Color3.fromRGB(100, 100, 100)

--[[
    Updates the Friend Boost UI.
    @param container - The Verified UI container (Frame)
    @param percentage - The boost percentage (0.0 - 0.5)
]]
local function updateFriendBoost(container: Frame, percentage: number)
    local frame = friendFrame
    if not frame then
        frame = container:FindFirstChild(BUFF_NAMES.FRIEND) :: Frame?
        if not frame then
            frame = friendTemplate:Clone() :: Frame
            frame.Name = BUFF_NAMES.FRIEND
            frame.Parent = container
        end
        friendFrame = frame
    end
    
    -- Update Text (visible only if percentage > 0)
    local textLabel = frame:FindFirstChild("TextLabel") :: TextLabel?
    if textLabel then
        if percentage > 0 then
            textLabel.Text = string.format("+%d%% FriendXP", math.floor(percentage * 100))
            textLabel.Visible = true
        else
            textLabel.Visible = false
        end
    end
end

--[[
    Prompts Premium purchase using Promise.
]]
local function promptPremiumInterval()
    return Promise.new(function(resolve, reject)
        local conn
        conn = MarketplaceService.PromptPremiumPurchaseFinished:Connect(function(plr)
            if plr == player then
                conn:Disconnect()
                resolve()
            end
        end)
        
        MarketplaceService:PromptPremiumPurchase(player)
    end)
end

--[[
    Updates the Premium UI.
    @param container - The Verified UI container (Frame)
    @param isActive - Whether Premium is active
]]
local function updatePremiumBuff(container: Frame, isActive: boolean)
    local frame = premiumFrame
    if not frame then
        frame = container:FindFirstChild(BUFF_NAMES.PREMIUM) :: Frame?
        if not frame then
            frame = premiumTemplate:Clone() :: Frame
            frame.Name = BUFF_NAMES.PREMIUM
            frame.Parent = container
            
            -- Add click handler for purchase prompt
            local button = frame:FindFirstChildOfClass("TextButton") or frame:FindFirstChildOfClass("ImageButton")
            if not button then
                -- Make the frame clickable
                local clickButton = Instance.new("TextButton")
                clickButton.Name = "ClickDetector"
                clickButton.Size = UDim2.fromScale(1, 1)
                clickButton.BackgroundTransparency = 1
                clickButton.Text = ""
                clickButton.Parent = frame
                button = clickButton
            end
            
            button.Activated:Connect(function()
                -- Only prompt if not premium
                if not player:GetAttribute("Buff_Premium") then
                     promptPremiumInterval():andThen(function()
                         print("[BuffController] Premium purchase finished, waiting for attribute update...")
                     end):catch(function(err)
                         warn("[BuffController] Premium purchase failed: " .. tostring(err))
                     end)
                end
            end)
        end
        premiumFrame = frame
    end
    
    if not frame then return end

    -- Update Text: +25% only when active
    local textLabel = frame:FindFirstChild("TextLabel") :: TextLabel?
    if textLabel then
        if isActive then
            textLabel.Text = "+25%"
            textLabel.Visible = true
        else
            textLabel.Visible = false
        end
    end

    -- Update Visuals (Button or ImageLabel)
    local visual = frame:FindFirstChild("Button") or frame:FindFirstChild("ImageLabel")
    if visual then
        if visual:IsA("ImageLabel") then
            visual.ImageColor3 = isActive and Color3.fromRGB(255, 220, 50) or Color3.fromRGB(255, 255, 255)
        elseif visual:IsA("ImageButton") then
            visual.ImageColor3 = isActive and Color3.fromRGB(255, 220, 50) or Color3.fromRGB(255, 255, 255)
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

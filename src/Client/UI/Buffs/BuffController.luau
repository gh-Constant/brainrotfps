--!strict
--[[
    BuffController
    Manages the Client-Side Buff UI (FriendBoost, Premium, Potion Buffs).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")

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

-- Try to get Potion template (may not exist yet)
local potionTemplate: Frame? = buffTemplates:FindFirstChild("Potion") :: Frame?

-- Constants
local BUFF_NAMES = {
    FRIEND = "FriendBoost",
    PREMIUM = "Premium",
}

local GAMEPASS_NAMES = {
    DOUBLE_XP = "GamePass_DoubleXP",
    DOUBLE_GOLD = "GamePass_DoubleGold",
    DOUBLE_DAMAGE = "GamePass_DoubleDamage",
}

-- UI References (cached after init)
local friendFrame: Frame?
local premiumFrame: Frame?
local potionBuffFrames: {[string]: Frame} = {} -- valueType -> Frame
local gamepassBuffFrames: {[string]: GuiObject} = {} -- passName -> Frame/ImageLabel
local gamepassIcons: {[number]: string} = {} -- id -> assetId

-- Duration update connection
local durationUpdateConnection: RBXScriptConnection?

--------------------------------------------------------------------------------
-- Helper Functions
--------------------------------------------------------------------------------

--[[
    Formats duration in seconds to a nice string like "15m 14m 13m" for minutes, then just "59" for seconds
]]
local function formatDuration(seconds: number): string
    if seconds <= 0 then
        return "0"
    end
    
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = math.floor(seconds % 60)
    
    if hours > 0 then
        return string.format("%dh %dm %d", hours, minutes, secs)
    elseif minutes > 0 then
        return string.format("%dm %d", minutes, secs)
    else
        return tostring(secs)
    end
end

--[[
    Formats the boost multiplier nicely (e.g., "x2", "x1.5")
]]
local function formatBoost(value: number): string
    if value == math.floor(value) then
        return "x" .. tostring(math.floor(value))
    else
        return "x" .. string.format("%.1f", value)
    end
end

--[[
    Fetches the icon for a gamepass.
    @param id - The GamePass ID
    @return Promise<string> - Resolves with the asset ID
]]
local function fetchGamePassIcon(id: number)
    return Promise.new(function(resolve, reject)
        if gamepassIcons[id] then
            resolve(gamepassIcons[id])
            return
        end
        
        local success, info = pcall(function()
            return MarketplaceService:GetProductInfo(id, Enum.InfoType.GamePass)
        end)
        
        if success and info then
            local iconId = "rbxassetid://" .. tostring(info.IconImageAssetId)
            gamepassIcons[id] = iconId
            resolve(iconId)
        else
            reject("Failed to fetch info for GP " .. tostring(id))
        end
    end)
end

--------------------------------------------------------------------------------
-- Existing Buff Updates (Friend/Premium)
--------------------------------------------------------------------------------

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
    return Promise.new(function(resolve, _reject)
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

--------------------------------------------------------------------------------
-- Potion Buff Updates
--------------------------------------------------------------------------------

--[[
    Updates a single potion buff UI element.
]]
local function updatePotionBuffFrame(frame: Frame, valueType: string, boost: number, endTime: number, icon: string)
    -- Update Duration label
    local durationLabel = frame:FindFirstChild("Duration") :: TextLabel?
    if durationLabel then
        local remaining = endTime - os.time()
        if remaining > 0 then
            durationLabel.Text = formatDuration(remaining)
        else
            durationLabel.Text = "Expired"
        end
    end
    
    -- Update Boost label
    local boostLabel = frame:FindFirstChild("Boost") :: TextLabel?
    if boostLabel then
        boostLabel.Text = formatBoost(boost)
    end
    
    -- Update ImageLabel (tool icon)
    local imageLabel = frame:FindFirstChild("ImageLabel") :: ImageLabel?
    if imageLabel then
        if icon and icon ~= "" then
            imageLabel.Image = icon
            imageLabel.Visible = true
        else
            imageLabel.Visible = false
        end
    end
    
    -- Update name label if exists
    local nameLabel = frame:FindFirstChild("NameLabel") :: TextLabel?
    if nameLabel then
        nameLabel.Text = valueType
    end
end

--[[
    Scans player attributes for active potion buffs and updates UI.
]]
local function updatePotionBuffs(container: Frame)
    -- Collect all active potion buff value types
    local activeBuffTypes: {string} = {}
    
    for _, attrName in ipairs(player:GetAttributes()) do
        -- Pattern: Buff_Potion_{ValueType} (not _EndTime or _Icon)
    end
    
    -- Scan attributes manually
    local attributes = player:GetAttributes()
    for attrName, value in pairs(attributes) do
        -- Match Buff_Potion_X where X is not _EndTime or _Icon suffix
        local valueType = string.match(attrName, "^Buff_Potion_([^_]+)$")
        if valueType and type(value) == "number" then
            table.insert(activeBuffTypes, valueType)
        end
    end
    
    -- Update or create frames for active buffs
    for _, valueType in ipairs(activeBuffTypes) do
        local boost = (player:GetAttribute("Buff_Potion_" .. valueType) :: number?) or 1
        local endTime = (player:GetAttribute("Buff_Potion_" .. valueType .. "_EndTime") :: number?) or 0
        local icon = (player:GetAttribute("Buff_Potion_" .. valueType .. "_Icon") :: string?) or ""
        
        local frame = potionBuffFrames[valueType]
        
        if not frame then
            -- Create new frame
            if potionTemplate then
                local newFrame = potionTemplate:Clone() :: Frame
                newFrame.Name = "Potion_" .. valueType
                newFrame.Parent = container
                potionBuffFrames[valueType] = newFrame
                frame = newFrame
            else
                -- Create a simple frame if template doesn't exist
                local newFrame = Instance.new("Frame")
                newFrame.Name = "Potion_" .. valueType
                newFrame.Size = UDim2.new(1, 0, 0, 50)
                newFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
                newFrame.BackgroundTransparency = 0.3
                newFrame.BorderSizePixel = 0
                
                -- Add corner
                local corner = Instance.new("UICorner")
                corner.CornerRadius = UDim.new(0, 8)
                corner.Parent = newFrame
                
                -- Add ImageLabel
                local img = Instance.new("ImageLabel")
                img.Name = "ImageLabel"
                img.Size = UDim2.new(0, 40, 0, 40)
                img.Position = UDim2.new(0, 5, 0.5, -20)
                img.BackgroundTransparency = 1
                img.ScaleType = Enum.ScaleType.Fit
                img.Parent = newFrame
                
                -- Add Boost label
                local boostLbl = Instance.new("TextLabel")
                boostLbl.Name = "Boost"
                boostLbl.Size = UDim2.new(0, 60, 0, 20)
                boostLbl.Position = UDim2.new(0, 50, 0, 5)
                boostLbl.BackgroundTransparency = 1
                boostLbl.Font = Enum.Font.GothamBold
                boostLbl.TextColor3 = Color3.fromRGB(100, 255, 100)
                boostLbl.TextSize = 16
                boostLbl.TextXAlignment = Enum.TextXAlignment.Left
                boostLbl.Parent = newFrame
                
                -- Add Duration label
                local durLbl = Instance.new("TextLabel")
                durLbl.Name = "Duration"
                durLbl.Size = UDim2.new(0, 80, 0, 20)
                durLbl.Position = UDim2.new(0, 50, 0, 25)
                durLbl.BackgroundTransparency = 1
                durLbl.Font = Enum.Font.Gotham
                durLbl.TextColor3 = Color3.fromRGB(200, 200, 200)
                durLbl.TextSize = 14
                durLbl.TextXAlignment = Enum.TextXAlignment.Left
                durLbl.Parent = newFrame
                
                newFrame.Parent = container
                potionBuffFrames[valueType] = newFrame
                frame = newFrame
            end
        end
        
        if frame then
            frame.Visible = true
            updatePotionBuffFrame(frame, valueType, boost, endTime, icon)
        end
    end
    
    -- Hide frames for inactive buffs
    for valueType, frame in pairs(potionBuffFrames) do
        local isActive = false
        for _, activeType in ipairs(activeBuffTypes) do
            if activeType == valueType then
                isActive = true
                break
            end
        end
        
        if not isActive then
            frame.Visible = false
        end
    end
end

--[[
    Updates duration labels every second for active potion buffs.
]]
local function startDurationUpdater()
    if durationUpdateConnection then
        durationUpdateConnection:Disconnect()
    end
    
    local lastUpdate = 0
    durationUpdateConnection = RunService.Heartbeat:Connect(function()
        local now = os.clock()
        if now - lastUpdate < 1 then return end -- Update every second
        lastUpdate = now
        
        for valueType, frame in pairs(potionBuffFrames) do
            if frame.Visible then
                local endTime = (player:GetAttribute("Buff_Potion_" .. valueType .. "_EndTime") :: number?) or 0
                local durationLabel = frame:FindFirstChild("Duration") :: TextLabel?
                if durationLabel then
                    local remaining = endTime - os.time()
                    if remaining > 0 then
                        durationLabel.Text = formatDuration(remaining)
                    else
                        durationLabel.Text = "Expired"
                    end
                end
            end
        end
    end)
end

--------------------------------------------------------------------------------
-- Main Update
--------------------------------------------------------------------------------

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
    local friendBoost = (player:GetAttribute("Buff_FriendBoost") :: number?) or 0
    local isPremium = player:GetAttribute("Buff_Premium") == true
    
    updateFriendBoost(container, friendBoost)
    updatePremiumBuff(container, isPremium)
    updatePotionBuffs(container)
    
    -- Update Gamepass Buffs
    local gamepassData = {
        { attr = "GamePass_DoubleXP", name = "2x XP", key = GAMEPASS_NAMES.DOUBLE_XP, id = 1642681579 },
        { attr = "GamePass_DoubleGold", name = "2x Gold", key = GAMEPASS_NAMES.DOUBLE_GOLD, id = 1642645563 },
        { attr = "GamePass_DoubleDamage", name = "2x DMG", key = GAMEPASS_NAMES.DOUBLE_DAMAGE, id = 1642445917 },
    }
    
    for _, gpData in ipairs(gamepassData) do
        local hasPass = player:GetAttribute(gpData.attr) == true
        local existingFrame = gamepassBuffFrames[gpData.key]
        
        if hasPass then
            -- Create or update frame
            if not existingFrame or not existingFrame.Parent then
                -- Create new gamepass buff frame (ImageLabel)
                local newFrame = Instance.new("ImageLabel")
                newFrame.Name = gpData.key
                newFrame.Size = UDim2.new(0, 40, 0, 40) -- Square icon
                newFrame.BackgroundTransparency = 1
                newFrame.ScaleType = Enum.ScaleType.Fit
                newFrame.Image = "rbxassetid://0" -- Placeholder
                
                -- Attempt to load real icon
                fetchGamePassIcon(gpData.id):andThen(function(icon)
                    if newFrame.Parent then -- Check if still valid
                        newFrame.Image = icon
                    end
                end)
                
                -- Add corner (though for ImageLabel, maybe just round caching?)
                local corner = Instance.new("UICorner")
                corner.CornerRadius = UDim.new(0, 8)
                corner.Parent = newFrame
                
                -- Tooltip/Name on hover?
                -- For now, just the icon as requested.
                
                newFrame.Parent = container
                gamepassBuffFrames[gpData.key] = newFrame
            end
        else
            -- Remove frame if pass is not owned
            if existingFrame and existingFrame.Parent then
                existingFrame:Destroy()
                gamepassBuffFrames[gpData.key] = nil
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

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
        
        -- Start duration updater
        startDurationUpdater()
        
        -- Listen for Attribute Changes (Buff_ and GamePass_)
        player.AttributeChanged:Connect(function(attributeName)
            if string.find(attributeName, "^Buff_") or string.find(attributeName, "^GamePass_") then
                updateBuffs()
            end
        end)
    end)
    
    print("[BuffController] Initialized")
end

return BuffController

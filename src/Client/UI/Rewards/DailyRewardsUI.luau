--!strict
--[[
    DailyRewardsUI
    Client-side controller for the daily rewards UI.
    
    Displays the 7-day reward cycle in PlayerGui.Rewards.Hub.Daily_Rewards
    - Top frame: Days 1-3
    - Middle frame: Days 4-6
    - Bottom.7.List: Day 7 special rewards
    
    Uses ItemSlot template from Config.Rewards.Template.ItemSlot
    Styles coins/XP with LootUI gradients
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local _TweenService = game:GetService("TweenService")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")

local Packets = require(Shared:WaitForChild("Packets"))
local DailyRewardsConfig = require(Shared:WaitForChild("Rewards"):WaitForChild("DailyRewardsConfig"))
local HourlyRewardsConfig = require(Shared:WaitForChild("Rewards"):WaitForChild("HourlyRewardsConfig"))
local MoneyLib = require(Shared:WaitForChild("MoneyLib"))
local ItemSlot = require(script.Parent.Parent:WaitForChild("Inventory"):WaitForChild("ItemSlot"))
local InventoryVisibilityManager = require(script.Parent.Parent:WaitForChild("Inventory"):WaitForChild("InventoryVisibilityManager"))
local ItemUtils = require(Shared:WaitForChild("Inventory"):WaitForChild("ItemUtils"))

local DailyRewardsUI = {}

-- Configuration
local config = ReplicatedStorage:WaitForChild("Config")
local rewardsConfig = config:WaitForChild("Rewards")
local templates = rewardsConfig:WaitForChild("Template")
local itemSlotTemplate = templates:WaitForChild("ItemSlot")

-- State
local _rewardsContainer: GuiObject? = nil
type SlotState = {
    frames: {Frame},
    overlays: {Frame},
    timerLabels: {TextLabel},
    lockedOverlays: {Frame}
}
local daySlots: {[number]: SlotState} = {}
type HourlySlotState = {
    frame: Frame,
    overlay: Frame,
    locked: Frame,
    timerLabel: TextLabel?,
    timeRequired: number
}
local hourlySlots: {[number]: HourlySlotState} = {}
local currentRewardsData: any = nil
local currentHourlyData: any = nil
local isInitialized = false

-- Animation TweenInfo
local _HOVER_TWEEN = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local _CLAIM_TWEEN = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

--[[
    Checks if a day has been claimed.
]]
local function isDayClaimed(day: number): boolean
    if not currentRewardsData then return false end
    for _, claimedDay in ipairs(currentRewardsData.claimedDays) do
        if claimedDay == day then
            return true
        end
    end
    return false
end

--[[
    Checks if a day is the current claimable day.
]]
local function isCurrentDay(day: number): boolean
    if not currentRewardsData then return false end
    return day == currentRewardsData.currentDay
end

-- Helper: Formats seconds to a nice string
local function formatTime(seconds: number): string
    if seconds <= 0 then return "READY" end
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    
    if h > 0 then
        return string.format("%dh %dm %ds", h, m, s)
    elseif m > 0 then
        return string.format("%dm %ds", m, s)
    else
        return string.format("%ds", s)
    end
end

-- Helper: Get Timer/Name label from slot
local function getSlotLabel(slotFrame: GuiObject): TextLabel?
    local label = slotFrame:FindFirstChild("Timer") or slotFrame:FindFirstChild("NameLabel") or slotFrame:FindFirstChild("ToolNameLabel")
    return if label and label:IsA("TextLabel") then label else nil
end

-- Helper: Add/Find Claimed overlay
local function addClaimedOverlay(frame: GuiObject): Frame
    local overlay = frame:FindFirstChild("Claimed") :: Frame?
    if not overlay then
        local newOverlay = Instance.new("Frame")
        newOverlay.Name = "Claimed"
        newOverlay.Size = UDim2.fromScale(1, 1)
        newOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
        newOverlay.BackgroundTransparency = 0.5
        newOverlay.ZIndex = 40
        newOverlay.Visible = false
        newOverlay.Parent = frame
        
        local text = Instance.new("TextLabel")
        text.Name = "ClaimedText"
        text.Size = UDim2.fromScale(0.8, 0.4)
        text.Position = UDim2.fromScale(0.1, 0.3)
        text.BackgroundTransparency = 1
        text.Text = "CLAIMED"
        text.TextColor3 = Color3.fromRGB(100, 255, 100)
        text.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
        text.TextScaled = true
        text.Rotation = -15
        text.Parent = newOverlay
        
        local stroke = Instance.new("UIStroke")
        stroke.Thickness = 2
        stroke.Color = Color3.new(0, 0, 0)
        stroke.Parent = text
        
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = newOverlay
        
        overlay = newOverlay
    end
    return overlay :: Frame
end

-- Helper: Add/Find Locked overlay (for darkening)
local function addLockedOverlay(frame: GuiObject): Frame
    local overlay = frame:FindFirstChild("Locked") :: Frame?
    if not overlay then
        local newOverlay = Instance.new("Frame")
        newOverlay.Name = "Locked"
        newOverlay.Size = UDim2.fromScale(1, 1)
        newOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
        newOverlay.BackgroundTransparency = 0.6
        newOverlay.ZIndex = 30
        newOverlay.Visible = false
        newOverlay.Parent = frame
        
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = newOverlay
        
        overlay = newOverlay
    end
    return overlay :: Frame
end

-- Helper: Handle slot clicks
local function onSlotClicked(day: number)
    print(`[DailyRewardsUI] Clicked Day {day}`)
    if not currentRewardsData then return end
    
    local claimed = false
    for _, d in ipairs(currentRewardsData.claimedDays) do
        if d == day then claimed = true; break end
    end
    
    if not claimed and currentRewardsData.canClaim and currentRewardsData.currentDay == day then
        print(`[DailyRewardsUI] Sending claim packet for Day {day}`)
        Packets.claimDailyReward.send({ day = day })
    else
        warn(`[DailyRewardsUI] Cannot claim Day {day}: claimed={claimed}, canClaim={currentRewardsData.canClaim}, currentDay={currentRewardsData.currentDay}`)
    end
end

-- Helper: Add click button
local function addClickButton(frame: GuiObject, callback: () -> ()): TextButton
    local button = frame:FindFirstChild("ClaimButton") :: TextButton?
    if not button then
        local newButton = Instance.new("TextButton")
        newButton.Name = "ClaimButton"
        newButton.Size = UDim2.fromScale(1, 1)
        newButton.BackgroundTransparency = 1
        newButton.Text = ""
        newButton.ZIndex = 100 -- MUST be on top of overlays
        newButton.Parent = frame
        newButton.MouseButton1Click:Connect(callback)
        button = newButton
    end
    return button :: TextButton
end

--[[
    Creates a slot for coins/XP display with LootUI styling.
]]
local function createCurrencySlot(parent: GuiObject, currencyType: string, amount: number, day: number): any
    local slot = ItemSlot.new(parent, itemSlotTemplate)
    -- Set minimal data
    slot:SetData({
        TemplateId = currencyType,
        Type = "Currency",
        Rarity = "Common",
        Count = 1,
        ItemIds = {},
        Metadata = {},
    })
    
    -- MUST Unregister AFTER SetData because SetData calls Register
    InventoryVisibilityManager.Unregister(slot.Frame)
    
    slot.Frame.Visible = true
    
    -- Timer Label: "Day1", "Day2", etc.
    local timerLabel = getSlotLabel(slot.Frame)
    if timerLabel then
        timerLabel.Text = "DAY " .. day
        timerLabel.Visible = (day ~= 7) -- Hide for Day 7
        timerLabel.TextColor3 = Color3.new(1, 1, 1)
        timerLabel.TextSize = 14
        timerLabel.ZIndex = 50 -- Ensure it's above locked overlay
        timerLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    end
    
    -- Setup overlays and button
    addClaimedOverlay(slot.Frame)
    addClickButton(slot.Frame, function()
        onSlotClicked(day)
    end)
    
    -- Store components for easy updates
    daySlots[day] = daySlots[day] or { frames = {}, overlays = {}, timerLabels = {}, lockedOverlays = {} }
    table.insert(daySlots[day].frames, slot.Frame :: Frame)
    table.insert(daySlots[day].overlays, addClaimedOverlay(slot.Frame))
    if timerLabel then table.insert(daySlots[day].timerLabels, timerLabel) end
    table.insert(daySlots[day].lockedOverlays, addLockedOverlay(slot.Frame))
    
    -- Apply currency-specific gradient (like LootDropUI)
    local gradient = slot.Frame:FindFirstChildWhichIsA("UIGradient")
    if gradient then
        if currencyType == "XP" then
            gradient.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 170, 255)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 85, 255))
            })
        else -- Coins/Gold
            gradient.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 0)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 170, 0))
            })
        end
    end
    
    -- Override icon based on currency type
    local toolIcon = slot.Frame:FindFirstChild("ToolIcon") :: ImageLabel?
    if toolIcon and toolIcon:IsA("ImageLabel") then
        local fxConfig = config:FindFirstChild("Effects") and config.Effects:FindFirstChild("FX")
        if currencyType == "XP" then
            local xpFx = fxConfig and fxConfig:FindFirstChild("XP") :: ImageLabel?
            if xpFx and xpFx:IsA("ImageLabel") then
                toolIcon.Image = xpFx.Image
            end
            toolIcon.ImageColor3 = Color3.fromRGB(100, 200, 255) -- Cyan/Blue
        else -- Coins
            local coinFx = fxConfig and fxConfig:FindFirstChild("Coin") :: ImageLabel?
            if coinFx and coinFx:IsA("ImageLabel") then
                toolIcon.Image = coinFx.Image
            end
            toolIcon.ImageColor3 = Color3.fromRGB(255, 215, 0) -- Gold/Yellow
        end
        toolIcon.Visible = true
    end
    
    -- Disable viewport for currency
    local viewport = slot.Frame:FindFirstChild("ViewportFrame") :: ViewportFrame?
    if viewport then viewport.Visible = false end
    
    -- Style display
    local suffix = if currencyType == "XP" then " XP" else " Coins"
    local displayText = MoneyLib.HandleMoney(amount) .. suffix
    
    -- Use RarityLabel for amount display
    local rarityLabel = slot.Frame:FindFirstChild("RarityLabel") :: TextLabel?
    if rarityLabel then
        rarityLabel.Visible = true
        rarityLabel.Text = displayText
        rarityLabel.TextColor3 = Color3.new(1, 1, 1)
        rarityLabel.TextSize = 16
        rarityLabel.FontFace = Font.new(rarityLabel.FontFace.Family, Enum.FontWeight.Bold, rarityLabel.FontFace.Style)
        
        -- Clean up existing strokes/gradients
        for _, child in rarityLabel:GetChildren() do
            if child:IsA("UIStroke") or child:IsA("UIGradient") then
                child:Destroy()
            end
        end
        
        -- Add stroke
        local stroke = Instance.new("UIStroke")
        stroke.Thickness = 2
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
        stroke.Color = Color3.new(0, 0, 0)
        stroke.Transparency = 0
        stroke.Parent = rarityLabel
    end
    
    -- Hide name label to prevent overlap
    local nameLabel = slot.Frame:FindFirstChild("NameLabel") or slot.Frame:FindFirstChild("ToolNameLabel")
    if nameLabel and nameLabel:IsA("TextLabel") then
        nameLabel.Visible = false
    end
    
    return slot
end

local function updateDaySlots()
    if not currentRewardsData then return end
    
    for day, components in pairs(daySlots) do
        local claimed = isDayClaimed(day)
        local isCurrent = isCurrentDay(day)
        local canClaim = currentRewardsData.canClaim
        
        -- A slot is "locked" (darkened) if it's not claimed AND it's not the currently claimable day
        local isLocked = not claimed and not (isCurrent and canClaim)
        
        -- Update claimed overlays
        for _, overlay in ipairs(components.overlays) do
            overlay.Visible = claimed
        end
        
        -- Update locked overlays (darken)
        for _, lockedOverlay in ipairs(components.lockedOverlays) do
            lockedOverlay.Visible = isLocked
        end
        
        -- Update timer labels
        for _, timerLabel in ipairs(components.timerLabels) do
            if claimed then
                timerLabel.TextColor3 = Color3.fromRGB(100, 255, 100) -- Green for claimed
            elseif isCurrent and canClaim then
                timerLabel.TextColor3 = Color3.fromRGB(255, 255, 100) -- Yellow for claimable
            elseif isCurrent then
                timerLabel.TextColor3 = Color3.fromRGB(255, 150, 50) -- Orange for current but not ready
            else
                timerLabel.TextColor3 = Color3.fromRGB(200, 200, 200) -- Gray for future
            end
        end
        
        -- Frame highlighting (on the first frame of each day)
        local mainFrame = components.frames[1] :: Frame?
        if mainFrame then
            local highlight = mainFrame:FindFirstChild("Highlight") :: Frame?
            if isCurrent and canClaim and not claimed then
                if not highlight then
                    highlight = Instance.new("Frame")
                    highlight.Name = "Highlight"
                    highlight.Size = UDim2.new(1, 4, 1, 4)
                    highlight.Position = UDim2.new(0, -2, 0, -2)
                    highlight.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
                    highlight.BackgroundTransparency = 0.5
                    highlight.BorderSizePixel = 0
                    highlight.ZIndex = 0
                    highlight.Parent = mainFrame
                    
                    local corner = Instance.new("UICorner")
                    corner.CornerRadius = UDim.new(0, 8)
                    corner.Parent = highlight
                end
                highlight.Visible = true
            elseif highlight then
                highlight.Visible = false
            end
        end
    end
end

--[[
    Clears all children from a frame except layout components.
]]
local function clearFrameExceptLayouts(frame: Frame)
    for _, child in frame:GetChildren() do
        if not child:IsA("UIGridLayout") and not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
            child:Destroy()
        end
    end
end

--[[
    Updates the hourly rewards UI state and timers.
]]
local function updateHourlyTimers()
    if not currentHourlyData then 
        return 
    end
    
    local playtime = currentHourlyData.playtimeSeconds
    
    for id, components in pairs(hourlySlots) do
        local idNum = tonumber(id) :: number
        local claimed = false
        if currentHourlyData.claimedIds then
            for _, cid in ipairs(currentHourlyData.claimedIds) do
                if cid == idNum then
                    claimed = true
                    break
                end
            end
        end
        
        local timeRequired = components.timeRequired
        local remaining = timeRequired - playtime
        local isReady = remaining <= 0
        
        -- Overlays
        components.overlay.Visible = claimed
        components.locked.Visible = not claimed and not isReady
        
        -- Timer Label
        if components.timerLabel then
            if claimed then
                components.timerLabel.Text = "CLAIMED"
                components.timerLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
            elseif isReady then
                components.timerLabel.Text = "READY"
                components.timerLabel.TextColor3 = Color3.fromRGB(255, 255, 100)
                components.locked.Visible = false
            else
                local text = formatTime(remaining)
                components.timerLabel.Text = text
                components.timerLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
            end
            components.timerLabel.ZIndex = 50
            components.timerLabel.Visible = true
        end
    end
end

--[[
    Handles clicking an hourly reward slot.
]]
local function onHourlySlotClicked(rewardId: number)
    if not currentHourlyData then return end
    
    local claimed = false
    for _, id in ipairs(currentHourlyData.claimedIds) do
        if id == rewardId then
            claimed = true
            break
        end
    end
    
    local reward = HourlyRewardsConfig.GetReward(rewardId)
    if not reward then return end
    
    local playtime = currentHourlyData.playtimeSeconds
    local canClaim = playtime >= reward.TimeRequired
    
    if not claimed and canClaim then
        print(`[DailyRewardsUI] Sending claim packet for Hourly Reward {rewardId}`)
        Packets.claimHourlyReward.send({ rewardId = rewardId })
    else
        warn(`[DailyRewardsUI] Cannot claim Hourly {rewardId}: claimed={claimed}, canClaim={canClaim}`)
    end
end

--[[
    Sets up the hourly rewards UI list.
]]
local function setupHourlyUI(hub: Frame)
    local hourlyRewards = hub:FindFirstChild("Hourly_Rewards") :: Frame?
    if not hourlyRewards then return end
    
    local list = hourlyRewards:FindFirstChild("List") :: Frame?
    if not list then return end
    
    clearFrameExceptLayouts(list)
    table.clear(hourlySlots)
    
    for _, reward in ipairs(HourlyRewardsConfig.Rewards) do
        local slot = ItemSlot.new(list, itemSlotTemplate)
        
        -- Get ItemType/Rarity for the reward
        local itemTemplate = reward.TemplateId
        local itemType = ItemUtils.GetItemType(itemTemplate) or "Other"
        local rarity = ItemUtils.GetRarity(itemTemplate) or "Common"
        
        slot:SetData({
            TemplateId = itemTemplate,
            Type = itemType,
            Rarity = rarity,
            Count = 1,
            ItemIds = {},
            Metadata = {},
        })
        
        InventoryVisibilityManager.Unregister(slot.Frame)
        slot.Frame.Visible = true
        slot.Frame.LayoutOrder = reward.Id
        
        -- Hide NameLabel to follow DailyRewards style
        local nameLabel = slot.Frame:FindFirstChild("NameLabel") or slot.Frame:FindFirstChild("ToolNameLabel")
        if nameLabel and nameLabel:IsA("TextLabel") then nameLabel.Visible = false end
        
        -- Add overlays and button
        local claimedOverlay = addClaimedOverlay(slot.Frame)
        local lockedOverlay = addLockedOverlay(slot.Frame)
        
        -- Initial state (until data arrives)
        claimedOverlay.Visible = false
        lockedOverlay.Visible = true
        
        local timerLabel = getSlotLabel(slot.Frame)
        if timerLabel then
            timerLabel.Text = "WAIT..."
            timerLabel.ZIndex = 50
            timerLabel.Visible = true
        end
        
        addClickButton(slot.Frame, function()
            onHourlySlotClicked(reward.Id)
        end)
        
        -- Store components
        hourlySlots[reward.Id] = {
            frame = slot.Frame :: Frame,
            overlay = claimedOverlay,
            locked = lockedOverlay,
            timerLabel = timerLabel,
            timeRequired = reward.TimeRequired
        }
    end
end

--[[
    Creates a slot for an item reward (used for Days 1-6).
]]
local function createItemRewardSlot(parent: GuiObject, templateId: string, day: number): any
    local slot = ItemSlot.new(parent, itemSlotTemplate)
    
    local rarity = ItemUtils.GetRarity(templateId) or "Common"
    local itemType = ItemUtils.GetItemType(templateId) or "Other"
    
    slot:SetData({
        TemplateId = templateId,
        Type = itemType,
        Rarity = rarity,
        Count = 1,
        ItemIds = {},
        Metadata = {},
    })
    
    -- MUST Unregister AFTER SetData
    InventoryVisibilityManager.Unregister(slot.Frame)
    
    slot.Frame.Visible = true
    
    -- Timer Label: "Day 1", etc.
    local timerLabel = getSlotLabel(slot.Frame)
    if timerLabel then
        timerLabel.Text = "DAY " .. day
        timerLabel.Visible = true
        timerLabel.TextColor3 = Color3.new(1, 1, 1)
        timerLabel.TextSize = 14
        timerLabel.ZIndex = 50 -- Ensure it's above locked overlay
        timerLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    end
    
    -- Setup overlays and button
    addClaimedOverlay(slot.Frame)
    addClickButton(slot.Frame, function()
        onSlotClicked(day)
    end)
    
    -- Store components for easy updates
    daySlots[day] = daySlots[day] or { frames = {}, overlays = {}, timerLabels = {}, lockedOverlays = {} }
    table.insert(daySlots[day].frames, slot.Frame :: Frame)
    table.insert(daySlots[day].overlays, addClaimedOverlay(slot.Frame))
    if timerLabel then table.insert(daySlots[day].timerLabels, timerLabel) end
    table.insert(daySlots[day].lockedOverlays, addLockedOverlay(slot.Frame))
    
    return slot
end

--[[
    Creates a single ItemSlot for a day reward.
]]
local function createDayRewardSlot(parent: Frame, day: number, layoutOrder: number): any
    local rewardConfig = DailyRewardsConfig.GetReward(day)
    if not rewardConfig then return nil end
    
    local slot = nil
    
    -- Check for items first (newly supported for days 1-6)
    if rewardConfig.Items and #rewardConfig.Items > 0 then
        slot = createItemRewardSlot(parent, rewardConfig.Items[1].TemplateId, day)
    elseif rewardConfig.Coins and rewardConfig.Coins > 0 then
        slot = createCurrencySlot(parent, "Coins", rewardConfig.Coins, day)
    elseif rewardConfig.XP and rewardConfig.XP > 0 then
        slot = createCurrencySlot(parent, "XP", rewardConfig.XP, day)
    end
    
    if slot then
        slot.Frame.LayoutOrder = layoutOrder
    end
    
    return slot
end

--[[
    Sets up the daily rewards UI by populating the existing containers.
]]
local function setupUI(playerGui: PlayerGui)
    local rewardsGui = playerGui:WaitForChild("Rewards", 10)
    if not rewardsGui then
        warn("[DailyRewardsUI] Rewards ScreenGui not found!")
        return
    end
    
    -- Reset state tracking to avoid leaks
    table.clear(daySlots)
    
    local hub = rewardsGui:FindFirstChild("Hub")
    if not hub then
        warn("[DailyRewardsUI] Hub not found in Rewards!")
        return
    end
    
    local dailyRewards = hub:FindFirstChild("Daily_Rewards") :: Frame?
    if not dailyRewards then
        local uis = hub:FindFirstChild("UIs")
        if uis then
            dailyRewards = uis:FindFirstChild("Daily_Rewards") :: Frame?
        end
    end
    
    if not dailyRewards then
        warn("[DailyRewardsUI] Daily_Rewards not found!")
        return
    end
    
    setupHourlyUI(hub :: Frame)
    updateHourlyTimers() -- Force update if data already exists
    
    local list = dailyRewards:FindFirstChild("List")
    if not list then
        warn("[DailyRewardsUI] List not found in Daily_Rewards!")
        return
    end
    
    -- Get existing frames
    local topFrame = list:FindFirstChild("Top") :: Frame?
    local middleFrame = list:FindFirstChild("Middle") :: Frame?
    local bottomFrame = list:FindFirstChild("Bottom") :: Frame?
    
    if not topFrame or not middleFrame or not bottomFrame then
        warn("[DailyRewardsUI] Top/Middle/Bottom frames not found!")
        return
    end
    
    -- Clear example content from frames (keep UIGridLayout/UIListLayout)
    clearFrameExceptLayouts(topFrame)
    clearFrameExceptLayouts(middleFrame)
    
    -- Get Day 7 container
    local day7Frame = bottomFrame:FindFirstChild("7") :: Frame?
    local day7List = day7Frame and day7Frame:FindFirstChild("List") :: Frame?
    
    if day7List then
        clearFrameExceptLayouts(day7List)
    end
    
    -- Clone ItemSlots for Days 1-3 into Top
    for day = 1, 3 do
        createDayRewardSlot(topFrame, day, day)
    end
    
    -- Clone ItemSlots for Days 4-6 into Middle
    for day = 4, 6 do
        createDayRewardSlot(middleFrame, day, day - 3)
    end
    
    -- Clone ItemSlots for Day 7 into Bottom.7.List
    if day7List then
        local rewardConfig = DailyRewardsConfig.GetReward(7)
        if rewardConfig then
            local slotIndex = 0
            
            -- Coins slot
            if rewardConfig.Coins and rewardConfig.Coins > 0 then
                local coinSlot = createCurrencySlot(day7List, "Coins", rewardConfig.Coins, 7)
                coinSlot.Frame.LayoutOrder = slotIndex
                slotIndex += 1
            end
            
            -- XP slot
            if rewardConfig.XP and rewardConfig.XP > 0 then
                local xpSlot = createCurrencySlot(day7List, "XP", rewardConfig.XP, 7)
                xpSlot.Frame.LayoutOrder = slotIndex
                slotIndex += 1
            end
            
            -- Item slots
            if rewardConfig.Items then
                for _, itemReward in ipairs(rewardConfig.Items) do
                    local itemSlot = ItemSlot.new(day7List, itemSlotTemplate)
                    
                    local rarity = ItemUtils.GetRarity(itemReward.TemplateId) or "Common"
                    local itemType = ItemUtils.GetItemType(itemReward.TemplateId) or "Other"
                    
                    itemSlot:SetData({
                        TemplateId = itemReward.TemplateId,
                        Type = itemType,
                        Rarity = rarity,
                        Count = 1,
                        ItemIds = {},
                        Metadata = {},
                    })
                    
                    -- MUST Unregister AFTER SetData
                    InventoryVisibilityManager.Unregister(itemSlot.Frame)
                    
                    -- Timer Label for Day 7 items (hide it)
                    local timerLabel = getSlotLabel(itemSlot.Frame)
                    if timerLabel then
                        timerLabel.Visible = false
                    end
                    
                    -- Setup overlays and button
                    addClaimedOverlay(itemSlot.Frame)
                    addLockedOverlay(itemSlot.Frame)
                    addClickButton(itemSlot.Frame, function()
                        onSlotClicked(7)
                    end)
                    
                    daySlots[7] = daySlots[7] or { frames = {}, overlays = {}, timerLabels = {}, lockedOverlays = {} }
                    table.insert(daySlots[7].frames, itemSlot.Frame :: Frame)
                    table.insert(daySlots[7].overlays, addClaimedOverlay(itemSlot.Frame))
                    table.insert(daySlots[7].lockedOverlays, addLockedOverlay(itemSlot.Frame))
                    if timerLabel then table.insert(daySlots[7].timerLabels, timerLabel) end
                    
                    itemSlot.Frame.LayoutOrder = slotIndex
                    itemSlot.Frame.Visible = true
                    slotIndex += 1
                end
            end
        end
    end
    
    print("[DailyRewardsUI] UI setup complete!")
end

--[[
    Initializes the Daily Rewards UI.
]]
function DailyRewardsUI.Init(context: any)
    local playerGui = context.PlayerGui :: PlayerGui
    
    -- Setup UI (re-run setup even if initialized to refresh frames)
    setupUI(playerGui)
    
    if isInitialized then 
        -- Already listening, just request fresh data
        Packets.requestDailyRewards.send({})
        Packets.requestHourlyRewards.send({})
        return 
    end
    isInitialized = true
    
    -- Listen for rewards data updates
    Packets.dailyRewardsData.listen(function(data)
        currentRewardsData = {
            currentDay = data.currentDay,
            claimedDays = data.claimedDays,
            canClaim = data.canClaim,
            timeUntilNextClaim = data.timeUntilNextClaim,
        }
        updateDaySlots()
    end)
    
    -- Listen for claim confirmations
    Packets.dailyRewardClaimed.listen(function(data)
        if data.success then
            -- Refresh state
            Packets.requestDailyRewards.send({})
            print(`[DailyRewardsUI] Successfully claimed Day {data.day}`)
        end
    end)
    
    Packets.hourlyRewardsData.listen(function(data)
        currentHourlyData = data
        updateHourlyTimers()
    end)
    
    Packets.hourlyRewardClaimed.listen(function(data)
        if data.success then
            -- Refresh state
            Packets.requestHourlyRewards.send({})
            print(`[DailyRewardsUI] Successfully claimed Hourly reward {data.rewardId}`)
        end
    end)
    
    -- Internal playtime timer (smoother UI)
    task.spawn(function()
        while true do
            task.wait(1)
            if currentHourlyData then
                currentHourlyData.playtimeSeconds += 1
                updateHourlyTimers()
            end
        end
    end)
    
    -- Request initial states
    task.delay(1, function()
        Packets.requestDailyRewards.send({})
        Packets.requestHourlyRewards.send({})
    end)
end

return DailyRewardsUI


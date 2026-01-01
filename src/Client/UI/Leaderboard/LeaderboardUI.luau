--!strict
--[[
    LeaderboardUI
    Separated UI module for rendering the leaderboard display.
    
    Creates and manages the visual elements of the leaderboard.
    This module is responsible ONLY for rendering - state management is in LeaderboardController.
    
    Usage:
        local ui = LeaderboardUI.Create(surfaceGui)
        ui:Render(leaderboardData)
        ui:SetPeriod("Daily")
        ui:SetPage(1, 40)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")
local Packages = Rojo:WaitForChild("Packages")

local Signal = require(Packages:WaitForChild("signal"))
local LeaderboardModule = require(Shared:WaitForChild("Leaderboard"))
local Constants = LeaderboardModule.Constants
local MoneyLib = require(Shared:WaitForChild("MoneyLib"))

type LeaderboardEntry = LeaderboardModule.LeaderboardEntry
type LeaderboardPage = LeaderboardModule.LeaderboardPage
type LeaderboardPeriod = LeaderboardModule.LeaderboardPeriod

-- Size tier type (inline to avoid cross-module type issues)
type SizeTier = {
    MaxRank: number,
    Height: number,
    FontSize: number,
    Icon: string?,
    GlowColor: Color3?,
}

local LeaderboardUI = {}
LeaderboardUI.__index = LeaderboardUI

export type LeaderboardUIOptions = {
    ShowPeriodTabs: boolean?,
    Title: string?,
}

export type LeaderboardUIInstance = typeof(setmetatable({} :: {
    Frame: Frame,
    Header: Frame,
    TitleLabel: TextLabel,
    PeriodTabs: Frame?,
    ScrollFrame: ScrollingFrame,
    PageFrame: Frame,
    PageLabel: TextLabel,
    PrevButton: TextButton,
    NextButton: TextButton,
    EntryPool: {Frame},
    CurrentPeriod: LeaderboardPeriod,
    OnPeriodClicked: any,
    OnPrevClicked: any,
    OnNextClicked: any,
    ShowPeriodTabs: boolean,
}, LeaderboardUI))

--------------------------------------------------------------------------------
-- UI Creation Helpers
--------------------------------------------------------------------------------

local function createCorner(parent: GuiObject, radius: number): UICorner
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent = parent
    return corner
end

local function createPadding(parent: GuiObject, padding: number): UIPadding
    local uiPadding = Instance.new("UIPadding")
    uiPadding.PaddingTop = UDim.new(0, padding)
    uiPadding.PaddingBottom = UDim.new(0, padding)
    uiPadding.PaddingLeft = UDim.new(0, padding)
    uiPadding.PaddingRight = UDim.new(0, padding)
    uiPadding.Parent = parent
    return uiPadding
end

local function _createStroke(parent: GuiObject, color: Color3, thickness: number): UIStroke
    local stroke = Instance.new("UIStroke")
    stroke.Color = color
    stroke.Thickness = thickness
    stroke.Parent = parent
    return stroke
end

local function createGradient(parent: GuiObject, colorSequence: ColorSequence, rotation: number?): UIGradient
    local gradient = Instance.new("UIGradient")
    gradient.Color = colorSequence
    gradient.Rotation = rotation or 90
    gradient.Parent = parent
    return gradient
end

local function getSizeTier(rank: number): any -- Using any to bypass type issue for now, or just remove strict type
    for _, tier in ipairs(Constants.SizeTiers) do
        if rank <= tier.MaxRank then
            return tier
        end
    end
    -- Fallback
    return Constants.SizeTiers[#Constants.SizeTiers]
end

local entryPool = {}
local Players = game:GetService("Players")

local function formatValue(value: number, valueName: string?): string
    if valueName == "Level" then
        return MoneyLib.FormatWithCommas(value)
    else
        return MoneyLib.HandleMoney(value)
    end
end

--------------------------------------------------------------------------------
-- Entry Rendering
--------------------------------------------------------------------------------

local function createEntryFrame(): Frame
    local frame = Instance.new("Frame")
    frame.Name = "Entry"
    frame.BackgroundColor3 = Constants.Colors.Entry
    frame.BorderSizePixel = 0
    frame.Size = UDim2.new(1, 0, 0, 50)
    createCorner(frame, 8)
    
    -- Rank Label (Leftmost)
    local rankLabel = Instance.new("TextLabel")
    rankLabel.Name = "RankLabel"
    rankLabel.Size = UDim2.new(0.15, 0, 1, 0)
    rankLabel.Position = UDim2.new(0, 0, 0, 0)
    rankLabel.BackgroundTransparency = 1
    rankLabel.TextColor3 = Constants.Colors.Text
    rankLabel.Font = Enum.Font.GothamBold
    rankLabel.TextSize = 20
    rankLabel.TextXAlignment = Enum.TextXAlignment.Center
    rankLabel.Parent = frame
    
    -- Avatar (Square, next to rank)
    local avatar: ImageLabel = Instance.new("ImageLabel")
    avatar.Name = "Avatar"
    avatar.Size = UDim2.new(0.8, 0, 0.8, 0) -- Relative to height
    avatar.SizeConstraint = Enum.SizeConstraint.RelativeYY
    avatar.Position = UDim2.new(0.15, 5, 0.5, 0)
    avatar.AnchorPoint = Vector2.new(0, 0.5) -- Center vertically
    avatar.BackgroundTransparency = 1
    avatar.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    createCorner(avatar, 100) -- Circle
    avatar.Parent = frame
    
    -- Icon Label (for top 3 medals, overlay on rank)
    local iconLabel = Instance.new("TextLabel")
    iconLabel.Name = "IconLabel"
    iconLabel.Size = UDim2.new(0.15, 0, 1, 0)
    iconLabel.Position = UDim2.new(0, 0, 0, 0)
    iconLabel.BackgroundTransparency = 1
    iconLabel.TextColor3 = Constants.Colors.Text
    iconLabel.Font = Enum.Font.GothamBold
    iconLabel.TextSize = 24
    iconLabel.Visible = false
    iconLabel.ZIndex = 2
    iconLabel.Parent = frame
    
    -- Value Label (Rightmost)
    local valueLabel = Instance.new("TextLabel")
    valueLabel.Name = "ValueLabel"
    valueLabel.Size = UDim2.new(0.25, -10, 1, 0)
    valueLabel.Position = UDim2.new(1, -10, 0, 0)
    valueLabel.AnchorPoint = Vector2.new(1, 0)
    valueLabel.BackgroundTransparency = 1
    valueLabel.TextColor3 = Constants.Colors.Accent
    valueLabel.Font = Enum.Font.GothamBold
    valueLabel.TextSize = 18
    valueLabel.TextXAlignment = Enum.TextXAlignment.Right
    valueLabel.Parent = frame
    
    -- Info Area (Name + Subname) - Centered between Avatar and Value
    local infoFrame = Instance.new("Frame")
    infoFrame.Name = "Info"
    -- Width: 100% - (Rank 15% + Avatar offset 5px + Avatar width ~40px + Value 25%)
    -- Roughly 0.6 scale - offsets
    infoFrame.Size = UDim2.new(0.55, -50, 0.8, 0) 
    infoFrame.Position = UDim2.new(0.15, 55, 0.5, 0) -- Starts after avatar
    infoFrame.AnchorPoint = Vector2.new(0, 0.5)
    infoFrame.BackgroundTransparency = 1
    infoFrame.Parent = frame
    
    -- Name Label
    local nameLabel: TextLabel = Instance.new("TextLabel")
    nameLabel.Name = "NameLabel"
    nameLabel.Size = UDim2.new(1, 0, 0.5, 0)
    nameLabel.Position = UDim2.new(0, 0, 0, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.TextColor3 = Constants.Colors.Text
    nameLabel.Font = Enum.Font.GothamMedium
    nameLabel.TextSize = 18
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.TextYAlignment = Enum.TextYAlignment.Bottom
    nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    nameLabel.Parent = infoFrame
    
    -- Subname Label (@username)
    local subnameLabel: TextLabel = Instance.new("TextLabel")
    subnameLabel.Name = "SubnameLabel"
    subnameLabel.Size = UDim2.new(1, 0, 0.5, 0)
    subnameLabel.Position = UDim2.new(0, 0, 0.5, 0)
    subnameLabel.BackgroundTransparency = 1
    subnameLabel.TextColor3 = Constants.Colors.TextSecondary
    subnameLabel.Font = Enum.Font.Gotham
    subnameLabel.TextSize = 12
    subnameLabel.TextXAlignment = Enum.TextXAlignment.Left
    subnameLabel.TextYAlignment = Enum.TextYAlignment.Top
    subnameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    subnameLabel.Parent = infoFrame
    
    -- Glow Effect
    local glow: ImageLabel = Instance.new("ImageLabel")
    glow.Name = "Glow"
    glow.Size = UDim2.new(1, 20, 1, 20)
    glow.Position = UDim2.new(0, -10, 0, -10)
    glow.BackgroundTransparency = 1
    glow.Image = "rbxassetid://5028857084" 
    glow.ImageTransparency = 0.8
    glow.ZIndex = 0
    glow.Visible = false
    glow.Parent = frame
    
    return frame
end

local function getEntryFrame(): Frame
    if #entryPool > 0 then
        return table.remove(entryPool) :: Frame
    end
    return createEntryFrame()
end

local function updateEntry(entry: Frame, data: LeaderboardEntry, isAlt: boolean, valueName: string?)
    local tier = getSizeTier(data.Rank)
    
    -- Update size
    entry.Size = UDim2.new(1, 0, 0, tier.Height)
    
    -- Update background
    if data.Rank == 1 then
        entry.BackgroundColor3 = Color3.fromRGB(60, 50, 20)
        local gradient = entry:FindFirstChild("RankGradient") :: UIGradient?
        if not gradient then
            gradient = createGradient(entry, Constants.Gradients.Gold, -90)
            gradient.Name = "RankGradient"
        else
            gradient.Color = Constants.Gradients.Gold
        end
    elseif data.Rank == 2 then
        entry.BackgroundColor3 = Color3.fromRGB(50, 50, 55)
        local gradient = entry:FindFirstChild("RankGradient") :: UIGradient?
        if not gradient then
            gradient = createGradient(entry, Constants.Gradients.Silver, -90)
            gradient.Name = "RankGradient"
        else
            gradient.Color = Constants.Gradients.Silver
        end
    elseif data.Rank == 3 then
        entry.BackgroundColor3 = Color3.fromRGB(55, 40, 25)
        local gradient = entry:FindFirstChild("RankGradient") :: UIGradient?
        if not gradient then
            gradient = createGradient(entry, Constants.Gradients.Bronze, -90)
            gradient.Name = "RankGradient"
        else
            gradient.Color = Constants.Gradients.Bronze
        end
    else
        entry.BackgroundColor3 = isAlt and Constants.Colors.EntryAlt or Constants.Colors.Entry
        local gradient = entry:FindFirstChild("RankGradient")
        if gradient then
            gradient:Destroy()
        end
    end
    
    -- Update labels
    local rankLabel = entry:FindFirstChild("RankLabel") :: TextLabel
    local avatar = entry:FindFirstChild("Avatar") :: ImageLabel
    local infoFrame = entry:FindFirstChild("Info") :: Frame
    local nameLabel = infoFrame:FindFirstChild("NameLabel") :: TextLabel
    local subnameLabel = infoFrame:FindFirstChild("SubnameLabel") :: TextLabel
    local valueLabel = entry:FindFirstChild("ValueLabel") :: TextLabel
    local iconLabel = entry:FindFirstChild("IconLabel") :: TextLabel
    local glow = entry:FindFirstChild("Glow") :: ImageLabel
    
    if rankLabel then
        rankLabel.Text = "#" .. tostring(data.Rank)
        rankLabel.TextSize = tier.FontSize
        
        if tier.GlowColor then
            rankLabel.TextColor3 = tier.GlowColor
        else
            rankLabel.TextColor3 = Constants.Colors.Text
        end
    end
    
    if avatar then
        task.spawn(function()
            local content, isReady = Players:GetUserThumbnailAsync(data.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
            if isReady then
                avatar.Image = content
            else
                avatar.Image = "rbxassetid://0" -- Fallback or placeholder
            end
        end)
        
         -- Adjust InfoFrame position dynamically based on actual avatar size being relative
         -- UDim2.new(0.15, 55, 0, 0) assumes a certain offset.
         -- Using binding or just static offset is fine for now as Avatar is RelativeYY
         -- Since Parent is scrolling frame width (e.g. 500px), 0.8 * 50 = 40px width.
         -- Offset 55 covers it.
    end
    
    if iconLabel then
        if tier.Icon then
            iconLabel.Text = tier.Icon
            iconLabel.Visible = true
            iconLabel.TextSize = tier.FontSize
        else
            iconLabel.Visible = false
        end
    end
    
    if nameLabel then
        nameLabel.Text = data.DisplayName
        nameLabel.TextSize = math.max(14, tier.FontSize - 4)
    end
    
    if subnameLabel then
        if data.Username and data.Username ~= "" then
            subnameLabel.Text = "@" .. data.Username
        else
            subnameLabel.Text = ""
        end
    end
    
    if valueLabel then
        valueLabel.Text = formatValue(data.Value, valueName)
        valueLabel.TextSize = math.max(14, tier.FontSize - 4)
    end
    
    if glow then
        if tier.GlowColor then
            glow.Visible = true
            glow.ImageColor3 = tier.GlowColor
        else
            glow.Visible = false
        end
    end
end


function LeaderboardUI:Render(data: LeaderboardPage)
    -- Update title if provided
    if self.Config.Title and self.TitleLabel then
        self.TitleLabel.Text = self.Config.Title
    elseif self.TitleLabel then
         -- Format title nicely
        local title = data.ValueName == "TotalXP" and "Total XP" or data.ValueName
        title = title .. " (" .. (data.Period == "AllTime" and "All Time" or data.Period) .. ")"
        self.TitleLabel.Text = title
    end
    
    -- Clear current entries
    for _, child in self.ListContainer:GetChildren() do
        if child:IsA("Frame") then
            -- Push to pool
            child.Parent = nil
            table.insert(entryPool, child)
        end
    end
    
    -- Render new entries
    for i, entryData in ipairs(data.Entries) do
        local entryFrame = getEntryFrame()
        entryFrame.LayoutOrder = i
        entryFrame.Parent = self.ListContainer
        
        -- Flash effect for local player
        local isLocalPlayer = entryData.UserId == Players.LocalPlayer.UserId
        
        updateEntry(entryFrame, entryData, i % 2 == 0, data.ValueName)
        
        if isLocalPlayer then
             -- Add highlight stroke
             local stroke = entryFrame:FindFirstChild("LocalPlayerStroke") :: UIStroke?
             if not stroke then
                 stroke = Instance.new("UIStroke")
                 stroke.Name = "LocalPlayerStroke"
                 stroke.Color = Constants.Colors.Accent
                 stroke.Thickness = 2
                 stroke.Parent = entryFrame
             end
        else
            local stroke = entryFrame:FindFirstChild("LocalPlayerStroke")
            if stroke then stroke:Destroy() end
        end
    end
    
    -- Update pagination buttons
    if self.PageLabel then
        self.PageLabel.Text = string.format("Page %d / %d", data.PageNumber, data.TotalPages)
    end
    
    if self.PrevButton then
        self.PrevButton.Visible = data.PageNumber > 1
    end
    
    if self.NextButton then
        self.NextButton.Visible = data.PageNumber < data.TotalPages
    end
    
    -- Update period tabs
    if self.Config.ShowPeriodTabs then
        for period, button in self.PeriodTabs do
            if period == data.Period then
                button.BackgroundColor3 = Constants.Colors.TabActive
            else
                button.BackgroundColor3 = Constants.Colors.TabInactive
            end
        end
    end
    
    self:SetLoading(false)
end

--------------------------------------------------------------------------------
-- Main UI Creation
--------------------------------------------------------------------------------

--[[
    Creates the leaderboard UI and returns an instance.
    
    @param parent - Parent GuiObject (typically a SurfaceGui or Frame)
    @param options - Optional configuration (ShowPeriodTabs, Title)
    @return LeaderboardUIInstance
]]
function LeaderboardUI.Create(parent: GuiObject, options: LeaderboardUIOptions?): LeaderboardUIInstance
    local self = setmetatable({}, LeaderboardUI)
    
    -- Store Config
    self.Config = (options or {}) :: LeaderboardUIOptions
    
    local showPeriodTabs = self.Config.ShowPeriodTabs ~= false
    local customTitle = self.Config.Title
    self.ShowPeriodTabs = showPeriodTabs
    
    -- Main Container
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "LeaderboardUI"
    mainFrame.Size = UDim2.new(1, 0, 1, 0)
    mainFrame.BackgroundColor3 = Constants.Colors.Background
    mainFrame.BorderSizePixel = 0
    createCorner(mainFrame, 16)
    mainFrame.Parent = parent
    self.Frame = mainFrame
    
    createPadding(mainFrame, 15)
    
    -- Header height depends on whether tabs are shown
    local headerHeight = showPeriodTabs and 80 or 50
    local scrollY = showPeriodTabs and 90 or 60
    
    -- Header
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, headerHeight)
    header.Position = UDim2.new(0, 0, 0, 0)
    header.BackgroundColor3 = Constants.Colors.Header
    header.BorderSizePixel = 0
    createCorner(header, 12)
    header.Parent = mainFrame
    self.Header = header
    
    -- Title
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.Size = UDim2.new(1, 0, 0, headerHeight)
    titleLabel.Position = UDim2.new(0, 0, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = customTitle or "🏆 LEADERBOARD 🏆"
    titleLabel.TextColor3 = Constants.Colors.Gold
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextSize = 28
    titleLabel.Parent = header
    self.TitleLabel = titleLabel
    
    -- Period Tabs Container (only if enabled)
    self.OnPeriodClicked = Signal.new()
    
    if showPeriodTabs then
        local periodTabs = Instance.new("Frame")
        periodTabs.Name = "PeriodTabs"
        periodTabs.Size = UDim2.new(1, -20, 0, 30)
        periodTabs.Position = UDim2.new(0, 10, 0, 45)
        periodTabs.BackgroundTransparency = 1
        periodTabs.Parent = header
        self.PeriodTabs = periodTabs
        
        local tabLayout = Instance.new("UIListLayout")
        tabLayout.FillDirection = Enum.FillDirection.Horizontal
        tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        tabLayout.Padding = UDim.new(0, 10)
        tabLayout.Parent = periodTabs
        
        -- Create period tabs
        local periods = {"Daily", "Weekly", "Monthly", "AllTime"}
        local periodLabels = {
            Daily = "Daily",
            Weekly = "Weekly", 
            Monthly = "Monthly",
            AllTime = "All Time"
        }
        
        for _, period in periods do
            local tab = Instance.new("TextButton")
            tab.Name = period .. "Tab"
            tab.Size = UDim2.new(0, 90, 1, 0)
            tab.BackgroundColor3 = Constants.Colors.TabInactive
            tab.Text = periodLabels[period] or period
            tab.TextColor3 = Constants.Colors.Text
            tab.Font = Enum.Font.GothamMedium
            tab.TextSize = 14
            tab.BorderSizePixel = 0
            tab.AutoButtonColor = false
            createCorner(tab, 6)
            tab.Parent = periodTabs
            
            tab.MouseButton1Click:Connect(function()
                self.OnPeriodClicked:Fire(period)
            end)
            
            -- Hover effect
            tab.MouseEnter:Connect(function()
                if tab.BackgroundColor3 ~= Constants.Colors.TabActive then
                    TweenService:Create(tab, TweenInfo.new(0.15), {
                        BackgroundColor3 = Constants.Colors.PageButtonHover
                    }):Play()
                end
            end)
            
            tab.MouseLeave:Connect(function()
                if tab.BackgroundColor3 ~= Constants.Colors.TabActive then
                    TweenService:Create(tab, TweenInfo.new(0.15), {
                        BackgroundColor3 = Constants.Colors.TabInactive
                    }):Play()
                end
            end)
        end
    end
    
    -- Scroll Container
    local listContainer = Instance.new("ScrollingFrame")
    listContainer.Name = "ListContainer"
    listContainer.Size = UDim2.new(1, 0, 1, -(scrollY + 50)) -- Header + Page controls
    listContainer.Position = UDim2.new(0, 0, 0, scrollY)
    listContainer.BackgroundTransparency = 1
    listContainer.ScrollBarThickness = 6
    listContainer.ScrollBarImageColor3 = Constants.Colors.Accent
    listContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
    listContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
    listContainer.Parent = mainFrame
    self.ListContainer = listContainer
    
    local entryLayout = Instance.new("UIListLayout")
    entryLayout.SortOrder = Enum.SortOrder.LayoutOrder
    entryLayout.Padding = UDim.new(0, 5)
    entryLayout.Parent = listContainer
    
    -- Page Controls
    local pageFrame = Instance.new("Frame")
    pageFrame.Name = "PageControls"
    pageFrame.Size = UDim2.new(1, 0, 0, 40)
    pageFrame.Position = UDim2.new(0, 0, 1, -45)
    pageFrame.BackgroundColor3 = Constants.Colors.Header
    pageFrame.BorderSizePixel = 0
    createCorner(pageFrame, 8)
    pageFrame.Parent = mainFrame
    self.PageFrame = pageFrame
    
    -- Prev Button
    local prevButton = Instance.new("TextButton")
    prevButton.Name = "PrevButton"
    prevButton.Size = UDim2.new(0, 80, 0, 30)
    prevButton.Position = UDim2.new(0, 10, 0.5, -15)
    prevButton.BackgroundColor3 = Constants.Colors.PageButton
    prevButton.Text = "◀ Prev"
    prevButton.TextColor3 = Constants.Colors.Text
    prevButton.Font = Enum.Font.GothamMedium
    prevButton.TextSize = 14
    prevButton.BorderSizePixel = 0
    createCorner(prevButton, 6)
    prevButton.Parent = pageFrame
    self.PrevButton = prevButton
    
    self.OnPrevClicked = Signal.new()
    prevButton.MouseButton1Click:Connect(function()
        self.OnPrevClicked:Fire()
    end)
    
    -- Page Label
    local pageLabel = Instance.new("TextLabel")
    pageLabel.Name = "PageLabel"
    pageLabel.Size = UDim2.new(1, -200, 1, 0)
    pageLabel.Position = UDim2.new(0.5, -50, 0, 0)
    pageLabel.BackgroundTransparency = 1
    pageLabel.Text = "Page 1 of 1"
    pageLabel.TextColor3 = Constants.Colors.TextSecondary
    pageLabel.Font = Enum.Font.GothamMedium
    pageLabel.TextSize = 16
    pageLabel.Parent = pageFrame
    self.PageLabel = pageLabel
    
    -- Next Button
    local nextButton = Instance.new("TextButton")
    nextButton.Name = "NextButton"
    nextButton.Size = UDim2.new(0, 80, 0, 30)
    nextButton.Position = UDim2.new(1, -90, 0.5, -15)
    nextButton.BackgroundColor3 = Constants.Colors.PageButton
    nextButton.Text = "Next ▶"
    nextButton.TextColor3 = Constants.Colors.Text
    nextButton.Font = Enum.Font.GothamMedium
    nextButton.TextSize = 14
    nextButton.BorderSizePixel = 0
    createCorner(nextButton, 6)
    nextButton.Parent = pageFrame
    self.NextButton = nextButton
    
    self.OnNextClicked = Signal.new()
    nextButton.MouseButton1Click:Connect(function()
        self.OnNextClicked:Fire()
    end)
    
    self.CurrentPeriod = "AllTime"
    
    return self :: any
end

--------------------------------------------------------------------------------
-- Rendering Methods
--------------------------------------------------------------------------------

-- Note: Render is defined earlier in the file to reference local helpers

--[[
    Updates the active period tab.
]]
function LeaderboardUI:SetPeriod(period: LeaderboardPeriod)
    self.CurrentPeriod = period
    
    if not self.PeriodTabs then return end
    
    for _, tab in self.PeriodTabs:GetChildren() do
        if tab:IsA("TextButton") then
            local tabPeriod = string.gsub(tab.Name, "Tab", "")
            if tabPeriod == period then
                tab.BackgroundColor3 = Constants.Colors.TabActive
            else
                tab.BackgroundColor3 = Constants.Colors.TabInactive
            end
        end
    end
end

--[[
    Updates the page label and button states.
]]
function LeaderboardUI:SetPage(current: number, total: number)
    self.PageLabel.Text = string.format("Page %d of %d", current, total)
    
    -- Update button states
    self.PrevButton.BackgroundColor3 = current > 1 
        and Constants.Colors.PageButton 
        or Constants.Colors.TabInactive
    self.PrevButton.TextTransparency = current > 1 and 0 or 0.5
    
    self.NextButton.BackgroundColor3 = current < total 
        and Constants.Colors.PageButton 
        or Constants.Colors.TabInactive
    self.NextButton.TextTransparency = current < total and 0 or 0.5
end

--[[
    Shows a loading indicator.
]]
function LeaderboardUI:SetLoading(isLoading: boolean)
    if self.LoadingFrame then
        self.LoadingFrame.Visible = isLoading
        return
    end
    
    -- Fallback opacity on list
    if self.ListContainer then
        for _, child in self.ListContainer:GetChildren() do
            if child:IsA("Frame") then
                 child.BackgroundTransparency = isLoading and 0.5 or (child.Name == "rank1" and 0 or Constants.Colors.Entry == child.BackgroundColor3 and 0 or 0)
                 -- Simplified: just set visible children opacity if needed, 
                 -- but actually 'Render' clears children or uses pool.
                 -- If loading, typically we clear or show spinner.
                 -- For now, do nothing.
            end
        end
    end
end

--[[
    Destroys the UI.
]]
function LeaderboardUI:Destroy()
    if self.Frame then
        self.Frame:Destroy()
    end
    
    self.OnPeriodClicked:Destroy()
    self.OnPrevClicked:Destroy()
    self.OnNextClicked:Destroy()
end

return LeaderboardUI

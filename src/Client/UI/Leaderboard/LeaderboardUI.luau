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
local Players = game:GetService("Players")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")
local Packages = Rojo:WaitForChild("Packages")

local Signal = require(Packages:WaitForChild("signal"))
local LeaderboardModule = require(Shared:WaitForChild("Leaderboard"))
local Constants = LeaderboardModule.Constants
local MoneyLib = require(Shared:WaitForChild("MoneyLib"))
local ExternalConfig = ReplicatedStorage:WaitForChild("Config")

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
    ListContainer: ScrollingFrame,
    PageFrame: Frame,
    PageLabel: TextLabel,
    PrevButton: TextButton,
    NextButton: TextButton,
    CurrentPeriod: LeaderboardPeriod,
    Config: LeaderboardUIOptions,
    OnPeriodClicked: any,
    OnPrevClicked: any,
    OnNextClicked: any,
    LoadingIndicator: Frame?,
    LoadingSpinner: TextLabel?,
    _spinnerConnection: RBXScriptConnection?,
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

local function formatValue(value: number, valueName: string?): string
    if valueName == "Level" then
        return MoneyLib.FormatWithCommas(value)
    else
        return MoneyLib.HandleMoney(value)
    end
end

local entryPool: {Frame} = {}
local _entryTemplate: Frame?

local function getEntryFrame(): Frame
    if #entryPool > 0 then
        return table.remove(entryPool) :: Frame
    end
    
    if not _entryTemplate then
        assert(ExternalConfig, "ExternalConfig (ReplicatedStorage.Config) missing!")
        local leaderboardNode = ExternalConfig:WaitForChild("Leaderboard", 5)
        local templateNode = leaderboardNode and leaderboardNode:WaitForChild("Template", 5)
        local entryPath = templateNode and templateNode:WaitForChild("EntryTemplate", 5)
        
        _entryTemplate = entryPath :: any
    end
    
    if not _entryTemplate then
        error("[LeaderboardUI] Could not find EntryTemplate in ReplicatedStorage.Config.Leaderboard.Template")
    end
    
    return (_entryTemplate :: Frame):Clone()
end

local function updateEntry(entry: Frame, data: LeaderboardEntry, isAlt: boolean, valueName: string?)
    local rank = data.Rank
    local tier = getSizeTier(rank)
    
    -- Calculate height scale based on top 3 hierarchy
    local heightScale = 0.08 -- Default for Rank 4+
    if rank == 1 then
        heightScale = 0.22 -- ~2.8x base
    elseif rank == 2 then
        heightScale = 0.16 -- 2x base
    elseif rank == 3 then
        heightScale = 0.12 -- 1.5x base
    end
    
    entry.Size = UDim2.fromScale(1, heightScale)
    
    -- Update background colors/gradients
    local rankGradient = entry:FindFirstChild("RankGradient") :: UIGradient?
    if rank == 1 then
        entry.BackgroundColor3 = Color3.fromRGB(60, 50, 20)
        if not rankGradient then
            rankGradient = createGradient(entry, Constants.Gradients.Gold, -90)
            rankGradient.Name = "RankGradient"
        else
            rankGradient.Color = Constants.Gradients.Gold
        end
    elseif rank == 2 then
        entry.BackgroundColor3 = Color3.fromRGB(50, 50, 55)
        if not rankGradient then
            rankGradient = createGradient(entry, Constants.Gradients.Silver, -90)
            rankGradient.Name = "RankGradient"
        else
            rankGradient.Color = Constants.Gradients.Silver
        end
    elseif rank == 3 then
        entry.BackgroundColor3 = Color3.fromRGB(55, 40, 25)
        if not rankGradient then
            rankGradient = createGradient(entry, Constants.Gradients.Bronze, -90)
            rankGradient.Name = "RankGradient"
        else
            rankGradient.Color = Constants.Gradients.Bronze
        end
    else
        entry.BackgroundColor3 = isAlt and Constants.Colors.EntryAlt or Constants.Colors.Entry
        if rankGradient then
            rankGradient:Destroy()
        end
    end
    
    -- Update labels
    local rankLabel = entry:FindFirstChild("RankLabel") :: TextLabel?
    local avatar = entry:FindFirstChild("Avatar") :: ImageLabel?
    local infoFrame = entry:FindFirstChild("Info") :: Frame?
    local nameLabel = infoFrame and infoFrame:FindFirstChild("NameLabel") :: TextLabel?
    local subnameLabel = infoFrame and infoFrame:FindFirstChild("SubnameLabel") :: TextLabel?
    local valueLabel = entry:FindFirstChild("ValueLabel") :: TextLabel?
    local iconLabel = entry:FindFirstChild("IconLabel") :: TextLabel?
    local glow = entry:FindFirstChild("Glow") :: ImageLabel?
    
    if rankLabel then
        rankLabel.Text = "#" .. tostring(data.Rank)
        rankLabel.TextColor3 = tier.GlowColor or Constants.Colors.Text
    end
    
    if avatar then
        task.spawn(function()
            local content, isReady = Players:GetUserThumbnailAsync(data.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
            avatar.Image = isReady and content or "rbxassetid://0"
        end)
    end
    
    if iconLabel then
        if tier.Icon then
            iconLabel.Text = tier.Icon
            iconLabel.Visible = true
        else
            iconLabel.Visible = false
        end
    end
    
    if nameLabel then
        nameLabel.Text = data.DisplayName
    end
    
    if subnameLabel then
        subnameLabel.Text = (data.Username and data.Username ~= "") and ("@" .. data.Username) or ""
    end
    
    if valueLabel then
        valueLabel.Text = formatValue(data.Value, valueName)
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
    if not data then return end
    
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
    if self.ListContainer then
        for _, child in self.ListContainer:GetChildren() do
            if child:IsA("Frame") then
                -- Push to pool
                child.Parent = nil
                table.insert(entryPool, child)
            end
        end
    end
    
    -- Render new entries
    for i, entryData in ipairs(data.Entries) do
        local entryFrame = getEntryFrame() :: any
        entryFrame.LayoutOrder = i
        entryFrame.Parent = self.ListContainer
        
        -- Flash effect for local player
        local localPlayer = Players.LocalPlayer
        local isLocalPlayer = localPlayer and entryData.UserId == localPlayer.UserId
        
        updateEntry(entryFrame, entryData, i % 2 == 0, data.ValueName)
        
        if isLocalPlayer then
             -- Add highlight stroke
             local stroke = entryFrame:FindFirstChild("LocalPlayerStroke") :: UIStroke?
             if not stroke then
                 stroke = Instance.new("UIStroke")
                 stroke.Name = "LocalPlayerStroke"
                 stroke.Color = (Constants :: any).Colors.Accent
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
    if self.Config.ShowPeriodTabs and self.PeriodTabs then
        for _, tab in self.PeriodTabs:GetChildren() do
            if tab:IsA("TextButton") then
                local tabPeriod = string.gsub(tab.Name, "Tab", "")
                if tabPeriod == data.Period then
                    tab.BackgroundColor3 = Constants.Colors.TabActive
                else
                    tab.BackgroundColor3 = Constants.Colors.TabInactive
                end
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
function LeaderboardUI.Create(parent: Instance, options: LeaderboardUIOptions?): LeaderboardUIInstance
    local self = setmetatable({}, LeaderboardUI)
    
    -- Store Config
    self.Config = (options or {}) :: LeaderboardUIOptions
    
    local showPeriodTabs = self.Config.ShowPeriodTabs ~= false
    local customTitle = self.Config.Title
    self.ShowPeriodTabs = showPeriodTabs
    
    -- Main Container
    local mainFrame: Frame = Instance.new("Frame")
    mainFrame.Name = "LeaderboardUI"
    mainFrame.Size = UDim2.fromScale(1, 1)
    mainFrame.BackgroundColor3 = Constants.Colors.Background
    mainFrame.BorderSizePixel = 0
    createCorner(mainFrame, 16)
    mainFrame.Parent = parent
    self.Frame = mainFrame
    
    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0.04, 0)
    padding.PaddingBottom = UDim.new(0.04, 0)
    padding.PaddingLeft = UDim.new(0.04, 0)
    padding.PaddingRight = UDim.new(0.04, 0)
    padding.Parent = mainFrame
    
    -- Layout constants
    local headerScale = showPeriodTabs and 0.18 or 0.1
    local footerScale = 0.1
    local listScale = 1 - headerScale - footerScale - 0.05
    
    -- Header
    local header: Frame = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.fromScale(1, headerScale)
    header.Position = UDim2.fromScale(0, 0)
    header.BackgroundColor3 = Constants.Colors.Header
    header.BorderSizePixel = 0
    createCorner(header, 12)
    header.Parent = mainFrame
    header.ZIndex = 10
    self.Header = header
    
    -- Title
    local titleLabel: TextLabel = Instance.new("TextLabel")
    titleLabel.Name = "TitleLabel"
    titleLabel.Size = UDim2.fromScale(1, showPeriodTabs and 0.5 or 1)
    titleLabel.BackgroundTransparency = 1
    titleLabel.TextColor3 = Constants.Colors.Text
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextScaled = true
    titleLabel.Text = customTitle or "LEADERBOARD"
    titleLabel.Parent = header
    self.TitleLabel = titleLabel

    -- Period Tabs (if enabled)
    self.OnPeriodClicked = Signal.new()
    if showPeriodTabs then
        local periodTabs = Instance.new("Frame")
        periodTabs.Name = "PeriodTabs"
        periodTabs.Size = UDim2.fromScale(1, 0.4)
        periodTabs.Position = UDim2.fromScale(0, 0.55)
        periodTabs.BackgroundTransparency = 1
        periodTabs.Parent = header
        self.PeriodTabs = periodTabs
        
        local tabLayout = Instance.new("UIListLayout")
        tabLayout.FillDirection = Enum.FillDirection.Horizontal
        tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        tabLayout.Padding = UDim.new(0.02, 0)
        tabLayout.Parent = periodTabs
        
        local periods = {"Daily", "Weekly", "Monthly", "AllTime"}
        local periodLabels = { Daily = "Daily", Weekly = "Weekly", Monthly = "Monthly", AllTime = "All Time" }
        
        for _, period in periods do
            local tab = Instance.new("TextButton")
            tab.Name = period .. "Tab"
            tab.Size = UDim2.fromScale(0.22, 1)
            local colors = (Constants :: any).Colors
            tab.BackgroundColor3 = colors.TabInactive
            tab.Text = periodLabels[period] or period
            tab.TextColor3 = colors.Text
            tab.Font = Enum.Font.GothamMedium
            tab.TextScaled = true
            tab.BorderSizePixel = 0
            createCorner(tab, 6)
            tab.Parent = periodTabs
            
            tab.MouseButton1Click:Connect(function()
                self.OnPeriodClicked:Fire(period)
            end)
        end
    end

    -- Scroll List
    local listContainer = Instance.new("ScrollingFrame")
    listContainer.Name = "ListContainer"
    listContainer.Size = UDim2.fromScale(1, listScale)
    listContainer.Position = UDim2.fromScale(0, headerScale + 0.02)
    listContainer.BackgroundTransparency = 1
    listContainer.BorderSizePixel = 0
    listContainer.ScrollBarThickness = 4
    listContainer.ScrollBarImageColor3 = Constants.Colors.Accent
    listContainer.CanvasSize = UDim2.fromScale(1, 0)
    listContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
    listContainer.Parent = mainFrame
    self.ListContainer = listContainer
    
    local entryLayout = Instance.new("UIListLayout")
    entryLayout.SortOrder = Enum.SortOrder.LayoutOrder
    entryLayout.Padding = UDim.new(0.012, 0)
    entryLayout.Parent = listContainer
    
    -- Footer Area
    local footer = Instance.new("Frame")
    footer.Name = "Footer"
    footer.Size = UDim2.fromScale(1, footerScale)
    footer.Position = UDim2.fromScale(0, 1 - footerScale)
    footer.BackgroundTransparency = 1
    footer.Parent = mainFrame
    
    -- Page Controls
    local pageFrame = Instance.new("Frame")
    pageFrame.Name = "PageFrame"
    pageFrame.Size = UDim2.fromScale(0.6, 1)
    pageFrame.BackgroundTransparency = 1
    pageFrame.Parent = footer
    self.PageFrame = pageFrame
    
    self.OnPrevClicked = Signal.new()
    local prevButton = Instance.new("TextButton")
    prevButton.Size = UDim2.fromScale(0.3, 0.8)
    prevButton.Position = UDim2.fromScale(0, 0.1)
    prevButton.BackgroundColor3 = Constants.Colors.PageButton
    prevButton.Text = "PREV"
    prevButton.TextColor3 = Constants.Colors.Text
    prevButton.Font = Enum.Font.GothamBold
    prevButton.TextScaled = true
    createCorner(prevButton, 6)
    prevButton.Parent = pageFrame
    self.PrevButton = prevButton
    prevButton.MouseButton1Click:Connect(function() self.OnPrevClicked:Fire() end)
    
    local pageLabel = Instance.new("TextLabel")
    pageLabel.Size = UDim2.fromScale(0.4, 1)
    pageLabel.Position = UDim2.fromScale(0.3, 0)
    pageLabel.BackgroundTransparency = 1
    pageLabel.TextColor3 = Constants.Colors.TextSecondary
    pageLabel.Font = Enum.Font.GothamMedium
    pageLabel.TextScaled = true
    pageLabel.Text = "Page 1 of 1"
    pageLabel.Parent = pageFrame
    self.PageLabel = pageLabel
    
    self.OnNextClicked = Signal.new()
    local nextButton = Instance.new("TextButton")
    nextButton.Size = UDim2.fromScale(0.3, 0.8)
    nextButton.Position = UDim2.fromScale(1, 0.1)
    nextButton.AnchorPoint = Vector2.new(1, 0)
    nextButton.BackgroundColor3 = Constants.Colors.PageButton
    nextButton.Text = "NEXT"
    nextButton.TextColor3 = Constants.Colors.Text
    nextButton.Font = Enum.Font.GothamBold
    nextButton.TextScaled = true
    createCorner(nextButton, 6)
    nextButton.Parent = pageFrame
    self.NextButton = nextButton
    nextButton.MouseButton1Click:Connect(function() self.OnNextClicked:Fire() end)

    -- Inline Loading Indicator (small text + spinner)
    local loadingIndicator = Instance.new("Frame")
    loadingIndicator.Name = "LoadingIndicator"
    loadingIndicator.Size = UDim2.fromScale(0.35, 0.7)
    loadingIndicator.Position = UDim2.fromScale(1, 0.15)
    loadingIndicator.AnchorPoint = Vector2.new(1, 0)
    loadingIndicator.BackgroundTransparency = 1
    loadingIndicator.Visible = false
    loadingIndicator.Parent = footer
    self.LoadingIndicator = loadingIndicator
    
    local loadingLayout = Instance.new("UIListLayout")
    loadingLayout.FillDirection = Enum.FillDirection.Horizontal
    loadingLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    loadingLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    loadingLayout.Padding = UDim.new(0, 4)
    loadingLayout.Parent = loadingIndicator
    
    local loadingSpinner = Instance.new("TextLabel")
    loadingSpinner.Name = "Spinner"
    loadingSpinner.Size = UDim2.fromScale(0.25, 1)
    loadingSpinner.BackgroundTransparency = 1
    loadingSpinner.Text = "◐" -- Will be animated
    loadingSpinner.TextColor3 = Constants.Colors.Gold
    loadingSpinner.Font = Enum.Font.GothamBold
    loadingSpinner.TextScaled = true
    loadingSpinner.LayoutOrder = 1
    loadingSpinner.Parent = loadingIndicator
    self.LoadingSpinner = loadingSpinner
    
    local loadingText = Instance.new("TextLabel")
    loadingText.Name = "LoadingText"
    loadingText.Size = UDim2.fromScale(0.7, 1)
    loadingText.BackgroundTransparency = 1
    loadingText.Text = "Loading..."
    loadingText.TextColor3 = Constants.Colors.TextSecondary
    loadingText.Font = Enum.Font.GothamMedium
    loadingText.TextScaled = true
    loadingText.TextXAlignment = Enum.TextXAlignment.Right
    loadingText.LayoutOrder = 2
    loadingText.Parent = loadingIndicator
    


    self.CurrentPeriod = "AllTime" :: any
    
    return self
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
    if self.PageLabel then
        self.PageLabel.Text = string.format("Page %d of %d", current, total)
    end
    
    if self.PrevButton then
        self.PrevButton.BackgroundColor3 = current > 1 
            and Constants.Colors.PageButton 
            or Constants.Colors.TabInactive
        self.PrevButton.TextTransparency = current > 1 and 0 or 0.5
    end
    
    if self.NextButton then
        self.NextButton.BackgroundColor3 = current < total 
            and Constants.Colors.PageButton 
            or Constants.Colors.TabInactive
        self.NextButton.TextTransparency = current < total and 0 or 0.5
    end
end

--[[
    Shows a loading indicator with spinning animation.
]]
local SPINNER_FRAMES = {"◐", "◓", "◑", "◒"}

function LeaderboardUI:SetLoading(isLoading: boolean)
    if self.LoadingIndicator then
        self.LoadingIndicator.Visible = isLoading
    end
    
    -- Manage spinner animation
    if isLoading then
        if not self._spinnerConnection and self.LoadingSpinner then
            local frameIndex = 1
            self._spinnerConnection = game:GetService("RunService").Heartbeat:Connect(function()
                frameIndex = (frameIndex % #SPINNER_FRAMES) + 1
                if self.LoadingSpinner then
                    self.LoadingSpinner.Text = SPINNER_FRAMES[frameIndex]
                end
            end)
        end
    else
        if self._spinnerConnection then
            self._spinnerConnection:Disconnect()
            self._spinnerConnection = nil
        end
    end
end

--[[
    Destroys the UI.
]]
function LeaderboardUI:Destroy()
    -- Stop spinner animation
    if self._spinnerConnection then
        self._spinnerConnection:Disconnect()
        self._spinnerConnection = nil
    end
    
    if self.Frame then
        self.Frame:Destroy()
    end
    
    if self.OnPeriodClicked then self.OnPeriodClicked:Destroy() end
    if self.OnPrevClicked then self.OnPrevClicked:Destroy() end
    if self.OnNextClicked then self.OnNextClicked:Destroy() end
end

return LeaderboardUI

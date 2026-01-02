--!strict
--[[
    LeaderboardExample
    Example script showing how to initialize and display the leaderboard system.
    
    This script demonstrates:
    1. How to register a leaderboard on the server
    2. How to create a SurfaceGui leaderboard display on a Part
    3. How to connect the controller and UI together
    
    USAGE (Server):
        -- In your server init script or a separate script:
        local LeaderboardService = require(ServerScriptService.Rojo.Server.Leaderboard.LeaderboardService)
        LeaderboardService.Init()
        LeaderboardService.RegisterLeaderboard("TotalXP", { DisplayName = "Total XP" })
        LeaderboardService.RegisterLeaderboard("Level", { DisplayName = "Level" })
        
        -- Update scores when player gains XP:
        LeaderboardService.UpdateScore(player, "TotalXP", totalXP)
        -- Or increment:
        LeaderboardService.IncrementScore(player, "TotalXP", xpGained)
    
    USAGE (Client - Creating a SurfaceGui Leaderboard):
        local LeaderboardExample = require(path.to.LeaderboardExample)
        
        -- Find your part in workspace
        local displayPart = workspace:FindFirstChild("LeaderboardPart")
        
        -- Create the leaderboard display
        LeaderboardExample.CreateDisplay({
            Part = displayPart,
            Face = Enum.NormalId.Front,
            ValueName = "TotalXP",
            Period = "AllTime",
            PixelsPerStud = 50, -- Higher = sharper text
        })
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local _Rojo = ReplicatedStorage:WaitForChild("Rojo") -- Reserved for path reference

local LeaderboardController = require(script.Parent.LeaderboardController)
local LeaderboardUI = require(script.Parent.LeaderboardUI)

local LeaderboardExample = {}

export type DisplayConfig = {
    Part: BasePart,
    Face: Enum.NormalId?,
    ValueName: string,
    Period: ("Daily" | "Weekly" | "Monthly" | "AllTime")?,
    PixelsPerStud: number?,
    AutoRefresh: boolean?,
    RefreshInterval: number?,
    ShowPeriodTabs: boolean?,
    Title: string?,
}

--[[
    Creates a leaderboard display on a Part's surface.
    
    @param config - Configuration for the display
    @return { SurfaceGui: SurfaceGui, UI: LeaderboardUIInstance }
]]
function LeaderboardExample.CreateDisplay(config: DisplayConfig): { SurfaceGui: SurfaceGui, UI: any }
    assert(config.Part, "Part is required!")
    assert(config.ValueName, "ValueName is required!")
    
    local face = config.Face or Enum.NormalId.Front
    local valueName = config.ValueName
    local period = config.Period or "AllTime"
    local pixelsPerStud = config.PixelsPerStud or 50
    local autoRefresh = config.AutoRefresh ~= false -- Default true
    local refreshInterval = config.RefreshInterval or 30
    
    -- Find or Create SurfaceGui
    local surfaceGui = config.Part:FindFirstChild("LeaderboardDisplay") :: SurfaceGui?
    if not surfaceGui then
        surfaceGui = Instance.new("SurfaceGui")
        surfaceGui.Name = "LeaderboardDisplay"
        surfaceGui.Face = face
        surfaceGui.PixelsPerStud = pixelsPerStud
        surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
        surfaceGui.LightInfluence = 0
        surfaceGui.ResetOnSpawn = false
        surfaceGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        surfaceGui.Parent = config.Part
    end
    
    local validSurfaceGui = surfaceGui :: SurfaceGui
    
    -- Create UI with options
    local ui = LeaderboardUI.Create(validSurfaceGui, {
        ShowPeriodTabs = config.ShowPeriodTabs,
        Title = config.Title,
    })
    
    -- Connect UI buttons to controller
    ui.OnPeriodClicked:Connect(function(newPeriod: string)
        LeaderboardController.SetPeriod(valueName, newPeriod :: any)
    end)
    
    ui.OnPrevClicked:Connect(function()
        LeaderboardController.PrevPage(valueName)
    end)
    
    ui.OnNextClicked:Connect(function()
        LeaderboardController.NextPage(valueName)
    end)
    
    -- Connect controller signals to UI
    LeaderboardController.OnDataReceived:Connect(function(receivedValueName, data)
        if receivedValueName == valueName then
            ui:Render(data)
            ui:SetPage(data.PageNumber, data.TotalPages)
            ui:SetPeriod(data.Period)
        end
    end)

    LeaderboardController.OnPeriodChanged:Connect(function(receivedValueName, newPeriod)
        if receivedValueName == valueName then
            ui:SetPeriod(newPeriod)
        end
    end)
    
    LeaderboardController.OnLoadingChanged:Connect(function(receivedValueName, isLoading)
        if receivedValueName == valueName then
            ui:SetLoading(isLoading)
        end
    end)
    
    -- Initial request
    LeaderboardController.RequestPage(valueName, period :: any, 1)
    
    -- Auto-refresh loop
    if autoRefresh then
        task.spawn(function()
            while validSurfaceGui.Parent do
                task.wait(refreshInterval)
                if validSurfaceGui.Parent then
                    local state = LeaderboardController.GetCurrentData(valueName)
                    if state and state.valueName then
                        LeaderboardController.Refresh(valueName)
                    end
                end
            end
        end)
    end
    
    return {
        SurfaceGui = validSurfaceGui,
        UI = ui,
    }
end

--[[
    Creates a leaderboard display in a ScreenGui (for testing in PlayerGui).
    
    @param config - Configuration for the display
    @return { Frame: Frame, UI: LeaderboardUIInstance }
]]
function LeaderboardExample.CreateScreenDisplay(config: {
    Parent: Instance,
    ValueName: string,
    Period: ("Daily" | "Weekly" | "Monthly" | "AllTime")?,
    Size: UDim2?,
    Position: UDim2?,
    AutoRefresh: boolean?,
    RefreshInterval: number?,
}): { Frame: Frame, UI: any }
    assert(config.Parent, "Parent is required!")
    assert(config.ValueName, "ValueName is required!")
    
    local period = config.Period or "AllTime"
    local size = config.Size or UDim2.new(0, 400, 0, 600)
    local position = config.Position or UDim2.new(0.5, -200, 0.5, -300)
    local autoRefresh = config.AutoRefresh ~= false
    local refreshInterval = config.RefreshInterval or 30
    
    -- Create container Frame
    local container = Instance.new("Frame")
    container.Name = "LeaderboardContainer"
    container.Size = size
    container.Position = position
    container.BackgroundTransparency = 1
    container.Parent = config.Parent
    
    -- Create UI
    local ui = LeaderboardUI.Create(container)
    
    -- Connect UI signals to controller
    ui.OnPeriodClicked:Connect(function(newPeriod: string)
        LeaderboardController.SetPeriod(newPeriod :: any)
    end)
    
    ui.OnPrevClicked:Connect(function()
        LeaderboardController.PrevPage()
    end)
    
    ui.OnNextClicked:Connect(function()
        LeaderboardController.NextPage()
    end)
    
    -- Connect controller signals to UI
    LeaderboardController.OnDataReceived:Connect(function(data)
        ui:Render(data)
    end)
    
    LeaderboardController.OnLoadingChanged:Connect(function(isLoading)
        ui:SetLoading(isLoading)
    end)
    
    -- Initial request
    LeaderboardController.RequestPage(config.ValueName, period :: any, 1)
    
    -- Auto-refresh loop
    if autoRefresh then
        task.spawn(function()
            while container.Parent do
                task.wait(refreshInterval)
                if container.Parent then
                    local state = LeaderboardController.GetCurrentData()
                    if state.valueName then
                        LeaderboardController.RequestPage(
                            state.valueName,
                            state.period,
                            state.pageNumber
                        )
                    end
                end
            end
        end)
    end
    
    return {
        Frame = container,
        UI = ui,
    }
end

return LeaderboardExample


--[[
    ========================================
    FULL EXAMPLE - HOW TO USE THIS SYSTEM
    ========================================
    
    === SERVER SIDE ===
    
    -- In src/Server/init.server.luau, add:
    local LeaderboardService = require(script.Leaderboard.LeaderboardService)
    LeaderboardService.Init()
    LeaderboardService.RegisterLeaderboard("TotalXP", { DisplayName = "Total XP" })
    
    -- In your player XP code (e.g., when player gains XP):
    LeaderboardService.UpdateScore(player, "TotalXP", playerData:GetTotalXP())
    
    
    === CLIENT SIDE ===
    
    -- Option 1: SurfaceGui on a Part in the world
    -- Create a Part in Workspace called "LeaderboardPart" (sized appropriately, e.g., 10x6x0.5)
    -- Then in a LocalScript:
    
    local LeaderboardController = require(ReplicatedStorage.Rojo.Client.UI.Leaderboard.LeaderboardController)
    local LeaderboardExample = require(ReplicatedStorage.Rojo.Client.UI.Leaderboard.LeaderboardExample)
    
    LeaderboardController.Init()
    
    local displayPart = workspace:WaitForChild("LeaderboardPart")
    LeaderboardExample.CreateDisplay({
        Part = displayPart,
        Face = Enum.NormalId.Front,
        ValueName = "TotalXP",
        Period = "AllTime",
        PixelsPerStud = 50,
    })
    
    
    -- Option 2: ScreenGui for testing
    local Players = game:GetService("Players")
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    
    LeaderboardController.Init()
    
    LeaderboardExample.CreateScreenDisplay({
        Parent = playerGui,
        ValueName = "TotalXP",
        Period = "AllTime",
        Size = UDim2.new(0, 450, 0, 650),
        Position = UDim2.new(0.5, -225, 0.5, -325),
    })
]]

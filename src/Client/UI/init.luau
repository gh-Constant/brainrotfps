--!strict
--[[
    UI Module
    Client-side UI systems.
    
    Components are organized in the Components subfolder:
    - HealthBar: HP bar display
    - XPBar: XP/level bar display
    - StatsDisplay: Coins, Credits, Damage labels
    - PvPToggle: PvP switch
    - CombatIndicator: Combat status/countdown
]]

-- Top-level UI modules
local ProgressBar = require(script.ProgressBar)
local Toolbar = require(script.Toolbar)
local BroadcastUI = require(script.BroadcastUI)
local DeathScreen = require(script.DeathScreen)
local LootFX = require(script.LootFX)
local DamageIndicator = require(script.DamageIndicator)
local InventoryUI = require(script.Inventory)

-- Component modules
local Components = script.Components
local HealthBar = require(Components.HealthBar)
local XPBar = require(Components.XPBar)
local StatsDisplay = require(Components.StatsDisplay)
local PvPToggle = require(Components.PvPToggle)
local CombatIndicator = require(Components.CombatIndicator)
local ButtonToggles = require(Components.ButtonToggles)
local HomeButton = require(Components.HomeButton)

local UI = {
    -- Shared utilities
    ProgressBar = ProgressBar,
    LootFX = LootFX,
    
    -- Top-level UI
    Toolbar = Toolbar,
    BroadcastUI = BroadcastUI,
    DeathScreen = DeathScreen,
    InventoryUI = InventoryUI,
    
    -- Components
    HealthBar = HealthBar,
    XPBar = XPBar,
    StatsDisplay = StatsDisplay,
    PvPToggle = PvPToggle,
    CombatIndicator = CombatIndicator,
    ButtonToggles = ButtonToggles,
}

--[[
    Initializes all UI systems with the given client context.
    @param context - ClientContext with Player, PlayerGui, Character, etc.
]]
function UI.Init(context: any)
    local playerGui = context.PlayerGui
    
    -- Get base UI frame
    local baseGui = playerGui:WaitForChild("Base", 5)
    if not baseGui then
        warn("[UI] Base UI not found in PlayerGui!")
        return
    end
    
    -- Create extended context with UI frame references
    -- Bottom/Left frames are inside HID container
    local hidFrame = baseGui:FindFirstChild("HID")
    
    local uiContext = {
        Player = context.Player,
        PlayerGui = context.PlayerGui,
        Character = context.Character,
        Humanoid = context.Humanoid,
        RootPart = context.RootPart,
        BaseFrame = baseGui,
        HIDFrame = hidFrame,
        BottomFrame = hidFrame and hidFrame:FindFirstChild("Bottom"),
        LeftFrame = hidFrame and hidFrame:FindFirstChild("Left"),
        TopFrame = hidFrame and hidFrame:FindFirstChild("Top"),
        Toolbar = Toolbar, -- Pass Toolbar module reference
    }
    
    -- Initialize components
    HealthBar.Init(uiContext)
    XPBar.Init(uiContext)
    StatsDisplay.Init(uiContext)
    PvPToggle.Init(uiContext)
    CombatIndicator.Init(uiContext)
    
    -- Initialize top-level UI
    Toolbar.Init(context)
    BroadcastUI.Init()
    LootFX.Init()
    DamageIndicator.Init()
    InventoryUI.Init(uiContext)
    ButtonToggles.Init(uiContext)
    HomeButton.Init(uiContext)
    
    print("[UI] All systems initialized!")
end

return UI

--!strict
--[[
    UI Module
    Client-side UI systems.
]]

local ProgressBar = require(script.ProgressBar)
local ValueHandler = require(script.ValueHandler)
local Toolbar = require(script.Toolbar)
local BroadcastUI = require(script.BroadcastUI)
local DeathScreen = require(script.DeathScreen)

local UI = {
    ProgressBar = ProgressBar,
    ValueHandler = ValueHandler,
    Toolbar = Toolbar,
    BroadcastUI = BroadcastUI,
    DeathScreen = DeathScreen,
}

--[[
    Initializes all UI systems with the given client context.
    @param context - ClientContext with Player, PlayerGui, Character, etc.
]]
function UI.Init(context: any) -- Using 'any' to avoid circular type dependencies
    -- Initialize systems that need the context
    ValueHandler.Init(context)
    Toolbar.Init(context)
    BroadcastUI.Init()
end

return UI


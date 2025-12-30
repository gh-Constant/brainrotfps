--!strict
--[[
    Logger
    Centralized logging utility for inventory system.
    Checks Config.Inventory.Logging attribute to enable/disable.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Logger = {}

-- Cache the logging state to avoid repeated lookups
local loggingEnabled: boolean? = nil

--[[
    Logs a message if logging is enabled in Config.Inventory.
    
    @param source - Module name (e.g., "InventoryUI", "Toolbar")
    @param message - The message to log
]]
function Logger.log(source: string, message: string)
    -- Cache lookup on first call
    if loggingEnabled == nil then
        local config = ReplicatedStorage:FindFirstChild("Config")
        if config then
            local invConfig = config:FindFirstChild("Inventory")
            if invConfig then
                loggingEnabled = invConfig:GetAttribute("Logging") == true
            end
        end
        loggingEnabled = loggingEnabled or false
    end
    
    if loggingEnabled then
        print(string.format("[%s] %s", source, message))
    end
end

--[[
    Forces a refresh of the logging state.
    Call this if the Logging attribute might have changed.
]]
function Logger.refresh()
    loggingEnabled = nil
end

return Logger

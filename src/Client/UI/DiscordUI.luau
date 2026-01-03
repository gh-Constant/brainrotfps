--!strict
--[[
    DiscordUI
    Handles the Discord verification UI input (Client-side).
    Visuals/Toggling are handled by the Server.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")
local Packets = require(Shared:WaitForChild("Packets"))

local DiscordUI = {}

local function setupUI(player: Player)
    local playerGui = player:WaitForChild("PlayerGui")
    local discordGui = playerGui:WaitForChild("Discord")
    local base = discordGui:WaitForChild("Base")
    local textBox = base:WaitForChild("TextBox") :: TextBox
    local textButton = base:WaitForChild("TextButton") :: TextButton -- Assuming TextButton exists per user request
    
    local function submitCode()
        local code = textBox.Text
        if code and #code > 0 then
            Packets.submitDiscordCode.send({
                code = code
            })
            -- We don't hide UI here; Server does it on success
        end
    end

    -- Handle Enter Pressed
    textBox.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            submitCode()
        end
    end)
    
    -- Handle Button Click
    if textButton then
        textButton.MouseButton1Click:Connect(submitCode)
    end
end

function DiscordUI.Init()
    local player = Players.LocalPlayer
    if player then
        setupUI(player)
    end
    print("[DiscordUI] Input handler initialized!")
end

return DiscordUI

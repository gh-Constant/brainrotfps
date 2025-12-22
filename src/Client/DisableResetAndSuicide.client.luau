--!strict
-- DisableResetAndSuicide
-- Disables the default reset button and adds F2 keybind for suicide

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local _player = Players.LocalPlayer

-- Disable reset button
local function disableReset()
	local success = false
	local attempts = 0
	
	while not success and attempts < 10 do
		success = pcall(function()
			StarterGui:SetCore("ResetButtonCallback", false)
		end)
		
		if not success then
			attempts += 1
			task.wait(1)
		end
	end
	
	if success then
		print("[DisableReset] Reset button disabled!")
	else
		warn("[DisableReset] Failed to disable reset button after 10 attempts")
	end
end

-- Initialize
disableReset()

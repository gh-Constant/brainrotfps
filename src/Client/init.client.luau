--!strict
-- Client entry point
-- Initializes all client-side systems

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Movement = require(script.Movement)

local player = Players.LocalPlayer
local currentController = nil

local function onCharacterAdded(character: Model)
	-- Clean up previous controller
	if currentController then
		currentController:Destroy()
		currentController = nil
	end
	
	-- Wait for character to be ready
	local humanoid = character:WaitForChild("Humanoid", 10)
	local rootPart = character:WaitForChild("HumanoidRootPart", 10)
	
	if not humanoid or not rootPart then
		warn("[Client] Failed to find Humanoid or HumanoidRootPart")
		return
	end
	
	-- Create and start movement controller
	currentController = Movement.MovementController.new(character)
	currentController:Start()
	
	print("[Client] Movement controller initialized!")
end

-- Slide input (Left Control or C)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	
	if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.C then
		if currentController then
			currentController:TrySlide()
		end
	end
end)

-- Handle character spawning
player.CharacterAdded:Connect(onCharacterAdded)

-- Handle existing character (if script runs after spawn)
if player.Character then
	task.spawn(onCharacterAdded, player.Character)
end

print("[Client] Client initialized!")

--!strict

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Movement = require(script.Movement)

local player = Players.LocalPlayer
local currentController: Movement.MovementController.MovementController? = nil

local function onCharacterAdded(character: Model)
	if currentController then
		currentController:Destroy()
		currentController = nil
	end
	
	local humanoid = character:WaitForChild("Humanoid", 10)
	local rootPart = character:WaitForChild("HumanoidRootPart", 10)
	
	if not humanoid or not rootPart then
		warn("[Client] Failed to find Humanoid or HumanoidRootPart")
		return
	end
	
	currentController = Movement.MovementController.new(character)
	currentController:Start()
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	
	if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.C then
		if currentController and not currentController:IsSliding() then
			currentController:TrySlide()
		end
	end
end)

UserInputService.InputEnded:Connect(function(input, _gameProcessed)
	if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.C then
		if currentController then
			currentController:EndSlide()
		end
	end
end)

player.CharacterAdded:Connect(onCharacterAdded)

if player.Character then
	task.spawn(onCharacterAdded, player.Character)
end

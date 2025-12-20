--!strict

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local MovementController = require(script.Movement.MovementController)

local player = Players.LocalPlayer
local currentController: MovementController.MovementController? = nil

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
	
	local controller = MovementController.new(character)
	controller:Start()
	currentController = controller
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	
	if input.KeyCode == Enum.KeyCode.LeftShift then
		local controller = currentController
		if controller and not controller:IsSliding() then
			controller:TrySlide()
		end
	end
end)

UserInputService.InputEnded:Connect(function(input, _gameProcessed)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		local controller = currentController
		if controller then
			controller:EndSlide()
		end
	end
end)

player.CharacterAdded:Connect(onCharacterAdded)

if player.Character then
	task.spawn(onCharacterAdded, player.Character)
end

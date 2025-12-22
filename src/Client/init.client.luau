--!strict
--[[
	Client Initialization Script
	Waits for character to fully load, then initializes all client systems
	with common references to avoid redundant lookups.
]]

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local MovementController = require(script.Movement.MovementController)
local UI = require(script.UI)
local CmdrClientSetup = require(script.CmdrClientSetup)

-- Disable default Roblox UI elements
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)

-- Initialize Cmdr console (doesn't need character)
CmdrClientSetup.Init()

local player = Players.LocalPlayer
local currentController: MovementController.MovementController? = nil

-- Common references that will be passed to systems
export type ClientContext = {
	Player: Player,
	PlayerGui: PlayerGui,
	Character: Model,
	Humanoid: Humanoid,
	RootPart: BasePart,
}

--[[
	Creates a context object with common client references.
]]
local function createClientContext(character: Model): ClientContext?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	
	if not humanoid or not rootPart then
		warn("[Client] Failed to find Humanoid or HumanoidRootPart")
		return nil
	end
	
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
	
	return {
		Player = player,
		PlayerGui = playerGui,
		Character = character,
		Humanoid = humanoid :: Humanoid,
		RootPart = rootPart :: BasePart,
	}
end

--[[
	Initializes all client systems with the given context.
]]
local function initializeSystems(context: ClientContext)
	-- Initialize UI systems with context
	UI.Init(context)
	
	-- Initialize movement controller
	if currentController then
		currentController:Destroy()
		currentController = nil
	end
	
	local controller = MovementController.new(context.Character)
	controller:Start()
	currentController = controller
	
	print("[Client] All systems initialized for character:", context.Character.Name)
end

--[[
	Handles character added event.
	Waits for character to fully load before initializing systems.
]]
local function onCharacterAdded(character: Model)
	-- Wait for character to be fully loaded
	if not player:HasAppearanceLoaded() then
		player.CharacterAppearanceLoaded:Wait()
	end
	
	-- Create context with common references
	local context = createClientContext(character)
	if not context then
		warn("[Client] Failed to create client context")
		return
	end
	
	-- Initialize all systems with the context
	initializeSystems(context)
end

--[[
	Handle slide input (LeftShift key).
]]
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

-- Setup character handling
player.CharacterAdded:Connect(onCharacterAdded)

if player.Character then
	task.spawn(onCharacterAdded, player.Character)
end

print("[Client] Client initialization script loaded")


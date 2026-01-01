--!strict
--[[
	LootFX - Physics-based loot drop visual effects
	
	Spawns coins/items with physics, trails, and magnet effect to collect.
	Based on coin splash effect pattern.
	
	Usage:
		LootFX.SpawnLoot({
			position = Vector3.new(0, 5, 0),
			targetPart = playerHudTarget,
			image = "rbxassetid://123456",
			color = Color3.fromRGB(255, 215, 0),
			trailColor = Color3.fromRGB(255, 200, 50),
			count = 10,
			text = "+50 Gold",
		})
]]

local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Packets = require(Rojo:WaitForChild("Shared"):WaitForChild("Packets"))
local ColorSystem = require(Rojo:WaitForChild("Shared"):WaitForChild("Inventory"):WaitForChild("ColorSystem"))

-- Get pickup sound reference
local function getPickupSound(): Sound?
	local config = ReplicatedStorage:FindFirstChild("Config")
	if not config then return nil end
	
	local playerFolder = config:FindFirstChild("Player")
	if not playerFolder then return nil end
	
	local audiosFolder = playerFolder:FindFirstChild("Audios")
	if not audiosFolder then return nil end
	
	return audiosFolder:FindFirstChild("Pickup") :: Sound?
end

-- Play the pickup sound (non-blocking, with debounce)
local lastPickupSoundTime = 0
local PICKUP_SOUND_DEBOUNCE = 0.05 -- Small debounce to prevent sound spam

local function playPickupSound()
	local now = tick()
	if now - lastPickupSoundTime < PICKUP_SOUND_DEBOUNCE then return end
	lastPickupSoundTime = now
	
	local pickupSound = getPickupSound()
	if not pickupSound then return end
	
	local soundClone = pickupSound:Clone()
	soundClone.Parent = SoundService
	soundClone:Play()
	
	soundClone.Ended:Connect(function()
		soundClone:Destroy()
	end)
end

local LootFX = {}

-- ==========================================================
-- CONFIGURATION
-- ==========================================================
local FX_FOLDER_NAME = "Effects"

-- Physics settings
local HORIZONTAL_SPEED = 15
local VERTICAL_SPEED = 35
local BOUNCINESS = 0.3
local COIN_SIZE = UDim2.new(1.5, 0, 1.5, 0)
local WAIT_BEFORE_MAGNET = 1.25

-- Magnet settings
local START_SPEED = 40
local ACCELERATION = 180

-- Spawning settings
local DEFAULT_COIN_COUNT = 5
local COINS_PER_FRAME = 3 -- How many coins to spawn before yielding
local LOOT_FX_COLLISION_GROUP = "LootFX"

-- Setup collision group (won't collide with anything, invisible to raycasts)
local function setupCollisionGroup()
	-- Create the LootFX collision group if it doesn't exist
	local success = pcall(function()
		PhysicsService:RegisterCollisionGroup(LOOT_FX_COLLISION_GROUP)
	end)
	
	-- Make LootFX not collide with Default (so raycasts using default params ignore it)
	if success then
		pcall(function()
			PhysicsService:CollisionGroupSetCollidable(LOOT_FX_COLLISION_GROUP, "Default", false)
		end)
	end
end

setupCollisionGroup()

-- ==========================================================
-- HELPERS
-- ==========================================================

local function getEffectsFolder(): Folder
	local folder = workspace:FindFirstChild(FX_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FX_FOLDER_NAME
		folder.Parent = workspace
	end
	return folder :: Folder
end

local function getPlayerScreenTarget(): BasePart?
	local player = Players.LocalPlayer
	if not player then return nil end
	
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then return nil end
	
	-- Try to find a target part in the UI (you can customize this)
	-- For now, we'll use the character's HumanoidRootPart as the target
	local character = player.Character
	if character then
		return character:FindFirstChild("HumanoidRootPart") :: BasePart?
	end
	
	return nil
end

-- ==========================================================
-- TEMPLATE CREATION
-- ==========================================================

local function createCoinTemplate(imageId: string, color: Color3, trailColor: Color3, gradient: ColorSequence?): Part
	local coinPart = Instance.new("Part")
	coinPart.Name = "LootFXCoin"
	coinPart.Shape = Enum.PartType.Ball
	coinPart.Size = Vector3.new(0.4, 0.4, 0.4)
	coinPart.Transparency = 1
	coinPart.Massless = true	
	coinPart.CastShadow = false
	coinPart.CanTouch = false
	coinPart.CanQuery = false
	coinPart.CanCollide = true
	coinPart.CollisionGroup = LOOT_FX_COLLISION_GROUP
	coinPart.CustomPhysicalProperties = PhysicalProperties.new(1, 2.0, BOUNCINESS, 10, 1)
	
	-- BillboardGui for the image
	local bbGui = Instance.new("BillboardGui")
	bbGui.Size = COIN_SIZE
	bbGui.Adornee = coinPart
	bbGui.AlwaysOnTop = false
	bbGui.LightInfluence = 0
	bbGui.Parent = coinPart
	
	local img = Instance.new("ImageLabel")
	img.Name = "CoinImage"
	img.BackgroundTransparency = 1
	img.Size = UDim2.new(1, 0, 1, 0)
	img.Image = imageId
	img.ImageColor3 = color
	img.ScaleType = Enum.ScaleType.Fit
	img.ScaleType = Enum.ScaleType.Fit
	img.Parent = bbGui
	
	if gradient then
		local uiGradient = Instance.new("UIGradient")
		uiGradient.Color = gradient
		uiGradient.Parent = img
		
		-- Use white for image if gradient is applied so gradient shows true colors
		img.ImageColor3 = Color3.new(1, 1, 1)
	end
	
	-- Trail attachments
	local attach0 = Instance.new("Attachment")
	attach0.Position = Vector3.new(0, 0.075, 0)
	attach0.Parent = coinPart
	
	local attach1 = Instance.new("Attachment")
	attach1.Position = Vector3.new(0, -0.075, 0)
	attach1.Parent = coinPart
	
	-- Trail
	local trail = Instance.new("Trail")
	trail.Attachment0 = attach0
	trail.Attachment1 = attach1
	trail.Color = ColorSequence.new(trailColor)
	trail.LightEmission = 1
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Lifetime = 0.2
	trail.FaceCamera = true
	trail.Parent = coinPart
	
	-- Preload image
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync({img})
		end)
	end)
	
	return coinPart
end

-- ==========================================================
-- SPAWN LOOT
-- ==========================================================

export type LootConfig = {
	position: Vector3,
	targetPart: BasePart?,
	image: string?,
	color: { number }?, -- RGB array
    customColor: string?,
	trailColor: { number }?, -- RGB array
	trailEnabled: boolean?,
	count: number?,
	text: string?,
	textColor: { number }?, -- RGB array
	floatHeight: number?,
	floatDuration: number?,
}

function LootFX.SpawnLoot(config: LootConfig)
	local centerPos = config.position + Vector3.new(0, 1, 0)
	local coinCount = config.count or DEFAULT_COIN_COUNT
	
	-- Parse colors
	local color = Color3.fromRGB(255, 255, 255)
    local useColorSystem = false
    local gradient: ColorSequence? = nil
    
    if config.customColor and config.customColor ~= "" then
        local colorConfig = ColorSystem.GetColorConfig(config.customColor)
        if colorConfig then
            color = colorConfig.Color
            gradient = colorConfig.Gradient
            useColorSystem = true
        end
    end
    
	if not useColorSystem and config.color then
		color = Color3.fromRGB(config.color[1], config.color[2], config.color[3])
	end
	
	local trailColor = color
	if config.trailColor then
		trailColor = Color3.fromRGB(config.trailColor[1], config.trailColor[2], config.trailColor[3])
	end
	
	-- Get target part (fallback to player's HumanoidRootPart)
	local targetPart = config.targetPart or getPlayerScreenTarget()
	
	-- Create template
	local imageId = config.image or ""
	local coinTemplate = createCoinTemplate(imageId, color, trailColor, gradient)
	
	-- Get effects folder
	local fxFolder = getEffectsFolder()
	
	-- Spawn coins
	for i = 1, coinCount do
		-- Batching: yield every COINS_PER_FRAME
		if i % COINS_PER_FRAME == 0 then
			task.wait()
		end
		
		local coinPart = coinTemplate:Clone()
		
		-- Random offset
		local offset = Vector3.new(
			(math.random() - 0.5) * 0.5,
			(math.random() - 0.5) * 0.5,
			(math.random() - 0.5) * 0.5
		)
		coinPart.Position = centerPos + offset
		-- Start with collision disabled to prevent instant collision at spawn point
		coinPart.CanCollide = false
		coinPart.Parent = fxFolder
		
		-- Random velocity for physics splash
		local randomAngle = math.rad(math.random(0, 360))
		local xDir = math.cos(randomAngle) * math.random(5, HORIZONTAL_SPEED)
		local zDir = math.sin(randomAngle) * math.random(5, HORIZONTAL_SPEED)
		local yDir = math.random(VERTICAL_SPEED - 10, VERTICAL_SPEED + 10)
		
		coinPart.AssemblyLinearVelocity = Vector3.new(xDir, yDir, zDir)
		
		-- Enable collision after a short delay to prevent initial collision impulse
		task.delay(0.1, function()
			if coinPart and coinPart.Parent and not coinPart.Anchored then
				coinPart.CanCollide = true
			end
		end)
		coinPart.AssemblyAngularVelocity = Vector3.new(
			math.random(-5, 5),
			math.random(-5, 5),
			math.random(-5, 5)
		)
		
		-- Random delay before magnet effect
		local randomDelay = WAIT_BEFORE_MAGNET + (math.random(1, 5) / 10)
		
		task.delay(randomDelay, function()
			if not coinPart or not coinPart.Parent then return end
			
			-- If no target, just fade out
			if not targetPart or not targetPart.Parent then
				coinPart:Destroy()
				return
			end
			
			-- Switch to anchored for magnet movement
			coinPart.Anchored = true
			coinPart.CanCollide = false
			coinPart.AssemblyLinearVelocity = Vector3.zero
			coinPart.AssemblyAngularVelocity = Vector3.zero
			
			local currentSpeed = START_SPEED
			local connection: RBXScriptConnection?
			
			connection = RunService.Heartbeat:Connect(function(dt)
				if not coinPart or not coinPart.Parent then
					if connection then connection:Disconnect() end
					return
				end
				
				if not targetPart or not targetPart.Parent then
					coinPart:Destroy()
					if connection then connection:Disconnect() end
					return
				end
				
				local targetPos = targetPart.Position
				local currentPos = coinPart.Position
				local direction = (targetPos - currentPos).Unit
				local distance = (targetPos - currentPos).Magnitude
				
				currentSpeed = currentSpeed + (ACCELERATION * dt)
				local moveAmount = direction * currentSpeed * dt
				
				if distance < moveAmount.Magnitude or distance < 1.5 then
					playPickupSound()
					coinPart:Destroy()
					if connection then connection:Disconnect() end
				else
					coinPart.Position = currentPos + moveAmount
				end
			end)
		end)
	end
	
	-- Cleanup template
	coinTemplate:Destroy()
	
	-- Text popup disabled - LootDropUI now handles XP/coin display in the HUD
	-- if config.text and config.text ~= "" then
	-- 	LootFX.ShowTextPopup(config.position, config.text, config.textColor or config.color)
	-- end
end

-- ==========================================================
-- TEXT POPUP (for "+50 XP" style notifications)
-- ==========================================================

function LootFX.ShowTextPopup(position: Vector3, text: string, textColor: { number }?)
	local TweenService = game:GetService("TweenService")
	
	local color = Color3.fromRGB(255, 255, 255)
	if textColor then
		color = Color3.fromRGB(textColor[1], textColor[2], textColor[3])
	end
	
	-- Create anchor part
	local anchorPart = Instance.new("Part")
	anchorPart.Name = "LootTextAnchor"
	anchorPart.Anchored = true
	anchorPart.CanCollide = false
	anchorPart.CanQuery = false
	anchorPart.CanTouch = false
	anchorPart.Transparency = 1
	anchorPart.Size = Vector3.new(0.1, 0.1, 0.1)
	anchorPart.CFrame = CFrame.new(position + Vector3.new(0, 2, 0))
	anchorPart.Parent = getEffectsFolder()
	
	-- Create BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 100, 0, 40)
	billboard.StudsOffset = Vector3.zero
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Adornee = anchorPart
	billboard.Parent = anchorPart
	
	-- Text label
	local txt = Instance.new("TextLabel")
	txt.Size = UDim2.new(1, 0, 1, 0)
	txt.BackgroundTransparency = 1
	txt.Text = text
	txt.TextColor3 = color
	txt.TextTransparency = 0
	txt.TextScaled = true
	txt.Font = Enum.Font.GothamBold
	txt.TextStrokeTransparency = 0.5
	txt.TextStrokeColor3 = Color3.new(0, 0, 0)
	txt.Parent = billboard
	
	-- Animate: float up and fade out
	local duration = 1.2
	local floatInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local fadeInfo = TweenInfo.new(duration * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	
	TweenService:Create(anchorPart, floatInfo, {
		CFrame = CFrame.new(position + Vector3.new(0, 5, 0)),
	}):Play()
	
	task.delay(duration * 0.6, function()
		TweenService:Create(txt, fadeInfo, {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}):Play()
	end)
	
	task.delay(duration + 0.5, function()
		anchorPart:Destroy()
	end)
end

-- ==========================================================
-- NETWORK LISTENER (for server-triggered FX)
-- ==========================================================

function LootFX.Init()
	Packets.lootDropFX.listen(function(data)
		local position = Vector3.new(data.posX, data.posY, data.posZ)
		
		LootFX.SpawnLoot({
			position = position,
			image = data.config.image,
			color = data.config.color,
            customColor = data.config.customColor,
			trailColor = data.config.trailColor,
			trailEnabled = data.config.trailEnabled,
			count = data.config.count or 5,
			text = data.config.text,
			textColor = data.config.textColor,
			floatHeight = data.config.floatHeight,
			floatDuration = data.config.floatDuration,
		})
	end)
	
	print("[LootFX] Initialized!")
end

return LootFX

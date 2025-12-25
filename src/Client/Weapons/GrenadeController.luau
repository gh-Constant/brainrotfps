--!strict
-- GrenadeController: Handles client-side grenade input and trajectory visualization using Beams

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")
local Packets = require(Shared:WaitForChild("Packets"))

local GrenadeController = {}

-- Config
local MAX_CHARGE_TIME = 1.5
local MIN_CHARGE_TIME = 0.2 -- Minimum hold time to prevent misclicks
local MIN_STRENGTH = 40
local MAX_STRENGTH = 100
local TRAJECTORY_SEGMENTS = 60 -- More segments for smooth curve
local TIME_STEP = 0.03 -- Smaller step for no gaps

-- State
local charging = false
local chargeStartTime = 0
local trajectoryContainer: Part? = nil
local attachments: {Attachment} = {}
local beams: {Beam} = {}
local impactMarker: Part? = nil
local mouse: Mouse? = nil

-- Helper: Get mouse world position (where cursor is pointing in 3D)
local function getMouseWorldPosition(): Vector3?
	local player = Players.LocalPlayer
	if not player then return nil end
	
	local playerMouse = mouse or player:GetMouse()
	mouse = playerMouse
	
	return playerMouse.Hit.Position
end

-- Helper: Get throw direction toward cursor
local function getThrowDirection(origin: Vector3): Vector3
	local targetPos = getMouseWorldPosition()
	if not targetPos then
		local camera = workspace.CurrentCamera
		return (camera.CFrame.LookVector + Vector3.new(0, 0.3, 0)).Unit
	end
	
	local rawDir = (targetPos - origin).Unit
	local arcDir = (rawDir + Vector3.new(0, 0.4, 0)).Unit
	return arcDir
end

-- Helper: Get right hand position from character
local function getRightHandPosition(character: Model): Vector3?
	-- Try to find RightHand (R15) or Right Arm (R6)
	local rightHand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if rightHand and rightHand:IsA("BasePart") then
		return rightHand.Position
	end
	
	-- Fallback to primary part with offset
	local primaryPart = character.PrimaryPart
	if primaryPart then
		return primaryPart.Position + Vector3.new(1, 1.5, 0)
	end
	
	return nil
end

-- Calculate trajectory points using physics
local function calculateTrajectoryPoints(origin: Vector3, velocity: Vector3, gravity: number): ({Vector3}, Vector3?)
	local points: {Vector3} = {}
	local hitPoint: Vector3? = nil
	
	local character = Players.LocalPlayer.Character
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	local excludeList = {character}
	if trajectoryContainer then
		table.insert(excludeList, trajectoryContainer)
	end
	raycastParams.FilterDescendantsInstances = excludeList
	
	local gravityVec = Vector3.new(0, -gravity, 0)
	
	for i = 0, TRAJECTORY_SEGMENTS do
		local t = i * TIME_STEP
		local pos = origin + (velocity * t) + (0.5 * gravityVec * t * t)
		table.insert(points, pos)
		
		-- Check for collision
		if i > 0 then
			local prevPos = points[i] -- Previous point (1-indexed, so points[i] is the one before current)
			local result = workspace:Raycast(prevPos, pos - prevPos, raycastParams)
			if result then
				hitPoint = result.Position
				table.insert(points, hitPoint)
				break
			end
		end
	end
	
	return points, hitPoint
end

-- Create or update the beam-based trajectory visualization
local function updateBeamTrajectory(points: {Vector3}, hitPoint: Vector3?)
	local character = Players.LocalPlayer.Character
	if not character then return end
	
	-- Create container part (invisible, used to parent attachments)
	if not trajectoryContainer then
		local container = Instance.new("Part")
		container.Name = "GrenadeTrajectoryContainer"
		container.Anchored = true
		container.CanCollide = false
		container.CanQuery = false
		container.CanTouch = false
		container.Transparency = 1
		container.Size = Vector3.new(1, 1, 1)
		container.CFrame = CFrame.new(0, 0, 0)
		container.Parent = workspace
		trajectoryContainer = container
	end
	
	local container = trajectoryContainer :: Part
	
	-- Ensure we have enough attachments
	while #attachments < #points do
		local att = Instance.new("Attachment")
		att.Parent = container
		table.insert(attachments, att)
	end
	
	-- Ensure we have enough beams (one less than points)
	while #beams < #points - 1 do
		local beam = Instance.new("Beam")
		beam.Width0 = 0.25
		beam.Width1 = 0.2
		beam.FaceCamera = true
		beam.Segments = 1
		beam.LightEmission = 1 -- Full glow/emission
		beam.LightInfluence = 0 -- Not affected by world lighting (always bright)
		beam.Brightness = 2 -- Extra brightness for vibrant look
		beam.Parent = container
		table.insert(beams, beam)
	end
	
	-- Update attachment positions
	for i, pos in ipairs(points) do
		attachments[i].WorldPosition = pos
	end
	
	-- Hide unused attachments
	for i = #points + 1, #attachments do
		attachments[i].WorldPosition = Vector3.new(0, -1000, 0)
	end
	
	-- Calculate charge percent for color
	local chargeDuration = math.min(os.clock() - chargeStartTime, MAX_CHARGE_TIME)
	local chargePercent = chargeDuration / MAX_CHARGE_TIME
	
	-- Update beams with pure vibrant red colors
	for i = 1, #points - 1 do
		local beam = beams[i]
		beam.Attachment0 = attachments[i]
		beam.Attachment1 = attachments[i + 1]
		beam.Enabled = true
		
		-- Pure red color - starts bright, fades slightly toward end
		local segmentPercent = i / (#points - 1)
		
		-- Pure red throughout (255, 0, 0) with slight darkening at end
		local brightness = 1 - segmentPercent * 0.2 -- 1.0 -> 0.8
		local redColor = Color3.fromRGB(math.floor(255 * brightness), 0, 0)
		
		beam.Color = ColorSequence.new(redColor)
		beam.Transparency = NumberSequence.new(0, 0.2 + segmentPercent * 0.5) -- Fade toward end
		beam.Width0 = 0.3 - segmentPercent * 0.15
		beam.Width1 = 0.25 - segmentPercent * 0.1
	end
	
	-- Hide unused beams
	for i = #points, #beams do
		beams[i].Enabled = false
	end
	
	-- Create/update impact marker (vibrant glowing red sphere)
	if hitPoint then
		if not impactMarker then
			local marker = Instance.new("Part")
			marker.Name = "ImpactMarker"
			marker.Shape = Enum.PartType.Ball
			marker.Size = Vector3.new(2, 2, 2)
			marker.Material = Enum.Material.Neon
			marker.Color = Color3.fromRGB(255, 20, 20) -- Vibrant red
			marker.Anchored = true
			marker.CanCollide = false
			marker.CanQuery = false
			marker.CanTouch = false
			marker.CastShadow = false
			marker.Transparency = 0.2
			marker.Parent = container
			
			-- Add a point light for glow effect
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 50, 30)
			light.Brightness = 2
			light.Range = 8
			light.Shadows = false
			light.Parent = marker
			
			impactMarker = marker
		end
		impactMarker.Position = hitPoint
		impactMarker.Transparency = 0.2
		
		-- Pulse effect based on charge
		local pulse = 1.8 + math.sin(os.clock() * 8) * 0.3
		impactMarker.Size = Vector3.new(pulse, pulse, pulse)
	elseif impactMarker then
		impactMarker.Transparency = 1
	end
end

function GrenadeController.Init(_context: any)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local character = Players.LocalPlayer.Character
			if character then
				local tool = character:FindFirstChildWhichIsA("Tool")
				if tool and tool:GetAttribute("IsGrenade") then
					charging = true
					chargeStartTime = os.clock()
				end
			end
		end
	end)
	
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and charging then
			charging = false
			
			-- Only fire if held long enough (prevent misclicks)
			local chargeDuration = os.clock() - chargeStartTime
			if chargeDuration >= MIN_CHARGE_TIME then
				GrenadeController.Fire()
			else
				-- Too short, don't throw
				print("[Grenade] Hold longer to throw!")
			end
			
			GrenadeController.ClearTrajectory()
		end
	end)
	
	RunService.RenderStepped:Connect(function()
		if charging then
			local character = Players.LocalPlayer.Character
			local tool = character and character:FindFirstChildWhichIsA("Tool")
			if not character or not tool or not tool:GetAttribute("IsGrenade") then
				charging = false
				GrenadeController.ClearTrajectory()
				return
			end
			GrenadeController.UpdateTrajectory()
		end
	end)
	
	print("[GrenadeController] Initialized with beam trajectory")
end

function GrenadeController.Fire()
	local character = Players.LocalPlayer.Character
	if not character then return end
	
	local origin = getRightHandPosition(character)
	if not origin then return end
	
	local chargeDuration = math.min(os.clock() - chargeStartTime, MAX_CHARGE_TIME)
	local strength = MIN_STRENGTH + (chargeDuration / MAX_CHARGE_TIME) * (MAX_STRENGTH - MIN_STRENGTH)
	
	local direction = getThrowDirection(origin)
	
	Packets.throwGrenade.send({
		originX = origin.X,
		originY = origin.Y,
		originZ = origin.Z,
		dirX = direction.X,
		dirY = direction.Y,
		dirZ = direction.Z,
		strength = strength,
	})
end

function GrenadeController.UpdateTrajectory()
	local character = Players.LocalPlayer.Character
	if not character then return end
	
	local origin = getRightHandPosition(character)
	if not origin then return end
	
	local chargeDuration = math.min(os.clock() - chargeStartTime, MAX_CHARGE_TIME)
	local strength = MIN_STRENGTH + (chargeDuration / MAX_CHARGE_TIME) * (MAX_STRENGTH - MIN_STRENGTH)
	
	local direction = getThrowDirection(origin)
	local velocity = direction * strength
	
	local points, hitPoint = calculateTrajectoryPoints(origin, velocity, workspace.Gravity)
	updateBeamTrajectory(points, hitPoint)
end

function GrenadeController.ClearTrajectory()
	if trajectoryContainer then
		trajectoryContainer:Destroy()
		trajectoryContainer = nil
		table.clear(attachments)
		table.clear(beams)
		impactMarker = nil
	end
end

return GrenadeController

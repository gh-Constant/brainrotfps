--!optimize 2
--[[
	MobAI.luau - Mob wandering AI with PathfindingService
	- Model with Humanoid, PrimaryPart
	- Model.Animations.Walk, Model.Animations.Idle
	- Debug waypoint visualization when Logging=true
	- Uses Janitor for connection cleanup
]]

local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Packages = Rojo:WaitForChild("Packages")
local Janitor = require(Packages:WaitForChild("janitor"))

local brainrotConfig = ReplicatedStorage:WaitForChild("Config"):WaitForChild("Brainrots")

local MobAI = {}
MobAI.__index = MobAI

-- Configuration
local WANDER_RANGE = 50
local WANDER_WAIT_MIN = 2
local WANDER_WAIT_MAX = 5
local RADIUS_BUFFER = 1 -- Extra padding to keep mobs away from walls

-- Debug colors
local DEBUG_WAYPOINT_COLOR = Color3.fromRGB(0, 255, 100)
local DEBUG_WAYPOINT_JUMP_COLOR = Color3.fromRGB(255, 200, 0)
local DEBUG_BOUNDING_COLOR = Color3.fromRGB(100, 150, 255)
local DEBUG_PATH_LINE_COLOR = Color3.fromRGB(255, 100, 100)

local function isLoggingEnabled(): boolean
	return brainrotConfig:GetAttribute("Logging") == true
end

local function getDebugFolder(): Folder
	local folder = workspace:FindFirstChild("MobAIDebug")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "MobAIDebug"
		folder.Parent = workspace
	end
	return folder
end

function MobAI.new(model)
	local humanoid = model:FindFirstChildWhichIsA("Humanoid")
	local primaryPart = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	
	if not humanoid or not primaryPart then
		return nil
	end
	
	-- Calculate actual model dimensions from bounding box
	local _, modelSize = model:GetBoundingBox()
	local actualHeight = modelSize.Y
	-- Use the larger of X/Z as radius base, add buffer to keep away from walls
	local actualRadius = math.max(modelSize.X, modelSize.Z) / 2 + RADIUS_BUFFER
	
	-- Agent parameters for pathfinding
	local agentParams = {
		AgentRadius = actualRadius,
		AgentHeight = actualHeight,
		AgentCanJump = false,
		AgentCanClimb = false,
		WaypointSpacing = math.max(4, actualRadius * 2), -- Scale spacing with size
	}

	
	local self = setmetatable({
		Model = model,
		Humanoid = humanoid,
		PrimaryPart = primaryPart,
		WalkAnim = nil,
		IdleAnim = nil,
		_spawnPos = primaryPart.Position,
		_path = PathfindingService:CreatePath(agentParams),
		_janitor = Janitor.new(),
		_agentParams = agentParams,
		_isActive = false,
		_currentAnim = "Idle",
		_name = model.Name,
		_debugFolder = nil,
		_boundingVisual = nil,
	}, MobAI)
	
	-- Load animations
	local animFolder = model:FindFirstChild("Animations")
	if animFolder then
		local animator = humanoid:FindFirstChildWhichIsA("Animator") or Instance.new("Animator", humanoid)
		
		local walkAnim = animFolder:FindFirstChild("Walk")
		if walkAnim and walkAnim:IsA("Animation") then
			self.WalkAnim = animator:LoadAnimation(walkAnim)
			self.WalkAnim.Looped = true
		end
		
		local idleAnim = animFolder:FindFirstChild("Idle")
		if idleAnim and idleAnim:IsA("Animation") then
			self.IdleAnim = animator:LoadAnimation(idleAnim)
			self.IdleAnim.Looped = true
		end
	end
	
	-- Create bounding visualization if logging enabled
	if isLoggingEnabled() then
		self:_createBoundingVisual()
	end
	
	return self
end

-- Create bounding cylinder visualization (separate from mob, follows via RunService)
function MobAI:_createBoundingVisual()
	local radius = self._agentParams.AgentRadius
	local height = self._agentParams.AgentHeight
	
	-- Cylinder for agent bounding box
	local boundingPart = Instance.new("Part")
	boundingPart.Name = self._name .. "_AgentBounds"
	boundingPart.Shape = Enum.PartType.Cylinder
	boundingPart.Size = Vector3.new(height, radius * 2, radius * 2)
	boundingPart.Anchored = true
	boundingPart.CanCollide = false
	boundingPart.CanQuery = false
	boundingPart.CanTouch = false
	boundingPart.Transparency = 0.7
	boundingPart.Color = DEBUG_BOUNDING_COLOR
	boundingPart.Material = Enum.Material.ForceField
	boundingPart.CastShadow = false
	boundingPart.Parent = getDebugFolder()
	
	-- Add label showing dimensions
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "AgentInfo"
	billboard.Size = UDim2.new(0, 120, 0, 30)
	billboard.StudsOffset = Vector3.new(0, height / 2 + 1, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = boundingPart
	
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 0.5
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Text = string.format("R:%.1f H:%.1f", radius, height)
	label.Font = Enum.Font.Code
	label.Parent = billboard
	
	self._boundingVisual = boundingPart
	
	-- Update position via RunService (not welded, not child)
	local updateConn = RunService.Heartbeat:Connect(function()
		if self.PrimaryPart and self.PrimaryPart.Parent and boundingPart.Parent then
			boundingPart.CFrame = self.PrimaryPart.CFrame * CFrame.Angles(0, 0, math.rad(90))
		end
	end)
	
	self._janitor:Add(updateConn, "Disconnect", "BoundingUpdate")
	self._janitor:Add(boundingPart, "Destroy", "BoundingVisual")
end

-- Get random wander point (uses spawn Y level)
function MobAI:_getWanderPoint(): Vector3?
	local angle = math.random() * math.pi * 2
	local dist = math.random() * WANDER_RANGE
	return self._spawnPos + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
end

-- Play animation
function MobAI:_playAnim(anim: string)
	if self._currentAnim == anim then return end
	self._currentAnim = anim
	
	if anim == "Walk" then
		if self.IdleAnim then self.IdleAnim:Stop() end
		if self.WalkAnim then self.WalkAnim:Play() end
	else
		if self.WalkAnim then self.WalkAnim:Stop() end
		if self.IdleAnim then self.IdleAnim:Play() end
	end
end

-- Clear debug waypoint visuals
function MobAI:_clearDebugWaypoints()
	if self._debugFolder then
		self._debugFolder:Destroy()
		self._debugFolder = nil
	end
end

-- Visualize waypoints for debugging
function MobAI:_visualizeWaypoints(waypoints: { PathWaypoint })
	self:_clearDebugWaypoints()
	
	local waypointFolder = Instance.new("Folder")
	waypointFolder.Name = self._name .. "_Waypoints"
	waypointFolder.Parent = getDebugFolder()
	self._debugFolder = waypointFolder
	
	local previousPos: Vector3? = nil
	
	for i, waypoint in waypoints do
		-- Waypoint sphere
		local wpPart = Instance.new("Part")
		wpPart.Name = "WP_" .. i
		wpPart.Shape = Enum.PartType.Ball
		wpPart.Size = Vector3.new(0.8, 0.8, 0.8)
		wpPart.Position = waypoint.Position
		wpPart.Anchored = true
		wpPart.CanCollide = false
		wpPart.CanQuery = false
		wpPart.CanTouch = false
		wpPart.CastShadow = false
		wpPart.Material = Enum.Material.Neon
		
		-- Color based on action type
		if waypoint.Action == Enum.PathWaypointAction.Jump then
			wpPart.Color = DEBUG_WAYPOINT_JUMP_COLOR
		else
			wpPart.Color = DEBUG_WAYPOINT_COLOR
		end
		
		wpPart.Parent = waypointFolder
		
		-- Line to previous waypoint
		if previousPos then
			local distance = (waypoint.Position - previousPos).Magnitude
			local midpoint = (waypoint.Position + previousPos) / 2
			
			local linePart = Instance.new("Part")
			linePart.Name = "Line_" .. i
			linePart.Size = Vector3.new(0.1, 0.1, distance)
			linePart.CFrame = CFrame.lookAt(midpoint, waypoint.Position)
			linePart.Anchored = true
			linePart.CanCollide = false
			linePart.CanQuery = false
			linePart.CanTouch = false
			linePart.CastShadow = false
			linePart.Color = DEBUG_PATH_LINE_COLOR
			linePart.Material = Enum.Material.Neon
			linePart.Transparency = 0.3
			linePart.Parent = waypointFolder
		end
		
		previousPos = waypoint.Position
	end
	
	print(string.format("[MobAI Debug] %s: %d waypoints", self._name, #waypoints))
end

-- Compute path to destination
function MobAI:_computePath(destination: Vector3): boolean
	local success, _ = pcall(function()
		self._path:ComputeAsync(self.PrimaryPart.Position, destination)
	end)
	
	if not success then
		return false
	end
	
	return self._path.Status == Enum.PathStatus.Success
end

-- Check if a waypoint has enough clearance from obstacles
function MobAI:_isWaypointSafe(position: Vector3): boolean
	local radius = self._agentParams.AgentRadius
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { self.Model }
	
	-- Check 4 cardinal directions for clearance
	local directions = {
		Vector3.new(1, 0, 0),
		Vector3.new(-1, 0, 0),
		Vector3.new(0, 0, 1),
		Vector3.new(0, 0, -1),
	}
	
	for _, dir in directions do
		local result = workspace:Raycast(position, dir * radius, rayParams)
		if result then
			-- Wall is too close
			return false
		end
	end
	
	return true
end


-- Move to destination using pathfinding
function MobAI:_moveTo(dest: Vector3): boolean
	if not self._isActive then 
		return false 
	end
	
	-- Try to compute path
	if not self:_computePath(dest) then
		-- Fallback to direct movement if path fails
		self:_playAnim("Walk")
		self.Humanoid:MoveTo(dest)
		self.Humanoid.MoveToFinished:Wait()
		self:_playAnim("Idle")
		return true
	end
	
	local waypoints = self._path:GetWaypoints()
	if #waypoints == 0 then return false end
	
	-- Visualize waypoints if logging enabled
	if isLoggingEnabled() then
		self:_visualizeWaypoints(waypoints)
	end
	
	self:_playAnim("Walk")
	
	-- Create a path janitor for this movement session
	local pathJanitor = Janitor.new()
	self._janitor:Add(pathJanitor, "Destroy", "PathJanitor")
	
	-- Follow each waypoint
	for i, waypoint in waypoints do
		if not self._isActive then
			break
		end
		
		-- Skip waypoints that are too close to walls (except first and last)
		if i > 1 and i < #waypoints then
			if not self:_isWaypointSafe(waypoint.Position) then
				if isLoggingEnabled() then
					print(string.format("[MobAI Debug] %s: Skipping unsafe waypoint %d", self._name, i))
				end
				continue
			end
		end
		
		-- Handle jump waypoints
		if waypoint.Action == Enum.PathWaypointAction.Jump then
			self.Humanoid.Jump = true
		end
		
		-- Move to waypoint
		self.Humanoid:MoveTo(waypoint.Position)
		
		-- Wait for waypoint reached
		local finished = false
		pathJanitor:Add(self.Humanoid.MoveToFinished:Connect(function()
			finished = true
		end), "Disconnect", "MoveConn")
		
		local startTime = tick()
		while not finished and self._isActive do
			if tick() - startTime > 5 then
				break -- Timeout
			end
			task.wait(0)
		end
		
		pathJanitor:Remove("MoveConn")
	end
	
	-- Cleanup path janitor
	self._janitor:Remove("PathJanitor")
	
	-- Clear debug visuals after path complete
	if isLoggingEnabled() then
		task.delay(0.5, function()
			self:_clearDebugWaypoints()
		end)
	end
	
	self:_playAnim("Idle")
	return true
end

-- Start AI
function MobAI:Start()
	if self._isActive then return end
	self._isActive = true
	
	if self.IdleAnim then self.IdleAnim:Play() end
	
	-- Main loop
	local thread = task.spawn(function()
		while self._isActive and self.Model.Parent do
			local dest = self:_getWanderPoint()
			self:_moveTo(dest)
			-- Wait at destination
			if self._isActive then
				local waitTime = WANDER_WAIT_MIN + math.random() * (WANDER_WAIT_MAX - WANDER_WAIT_MIN)
				task.wait(waitTime)
			end
		end
	end)
	
	-- Janitor manages thread cleanup
	self._janitor:Add(function()
		task.cancel(thread)
	end, true, "MainThread")
end

-- Stop AI
function MobAI:Stop()
	if not self._isActive then return end
	self._isActive = false
	
	-- Janitor cleans up thread and connections
	self._janitor:Cleanup()
	
	self:_clearDebugWaypoints()
	
	if self.WalkAnim and self.WalkAnim.IsPlaying then self.WalkAnim:Stop() end
	if self.IdleAnim and self.IdleAnim.IsPlaying then self.IdleAnim:Stop() end
	
	self.Humanoid:MoveTo(self.PrimaryPart.Position)
end

-- Destroy AI
function MobAI:Destroy()
	self:Stop()
	self._janitor:Destroy()
	self.WalkAnim = nil
	self.IdleAnim = nil
end

return MobAI

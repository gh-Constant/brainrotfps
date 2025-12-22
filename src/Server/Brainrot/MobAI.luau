--!strict
--[[
	MobAI.luau
	Handles wandering pathfinding and animation for mobs spawned by BrainrotSpawner.
	Mobs will wander randomly within a configurable range.
	
	Expected structure:
	- Model with Humanoid
	- Model.Animations.Walk (Animation)
	- Model.Animations.Idle (Animation)
	- Model:GetAttribute("WanderRange") - Max distance to wander from spawn (optional)
]]

local PathfindingService = game:GetService("PathfindingService")

local MobAI = {}
MobAI.__index = MobAI

-- Types
export type MobAIObject = typeof(setmetatable({}, MobAI)) & {
	Model: Model,
	Humanoid: Humanoid,
	PrimaryPart: BasePart,
	WalkAnim: AnimationTrack?,
	IdleAnim: AnimationTrack?,
	_path: Path?,
	_spawnPosition: Vector3,
	_currentDestination: Vector3?,
	_pathUpdateThread: any,
	_isActive: boolean,
	_connections: { RBXScriptConnection },
}

-- Configuration (can be overridden with attributes on the mob model)
local DEFAULT_WANDER_RANGE = 50 -- Max distance to wander from spawn point (studs)
local DEFAULT_WANDER_WAIT_MIN = 2 -- Min wait time at destination before next wander (seconds)
local DEFAULT_WANDER_WAIT_MAX = 5 -- Max wait time at destination before next wander (seconds)
local DEFAULT_PATH_TIMEOUT = 10 -- Give up on path after this many seconds

--[[
	Creates a new MobAI instance for the given model.
	
	@param model - The mob's Model (must have Humanoid and PrimaryPart)
	@return MobAIObject or nil if invalid
]]
function MobAI.new(model: Model): MobAIObject?
	-- Validate model
	if not model or not model:IsA("Model") then
		warn("[MobAI] Invalid model provided")
		return nil
	end

	local humanoid = model:FindFirstChildWhichIsA("Humanoid")
	if not humanoid then
		warn("[MobAI] Model missing Humanoid:", model.Name)
		return nil
	end

	local primaryPart = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not primaryPart then
		warn("[MobAI] Model missing PrimaryPart/HumanoidRootPart:", model.Name)
		return nil
	end

	local self = setmetatable({}, MobAI) :: any

	self.Model = model
	self.Humanoid = humanoid
	self.PrimaryPart = primaryPart
	self.WalkAnim = nil
	self.IdleAnim = nil
	self._path = nil
	self._spawnPosition = primaryPart.Position
	self._currentDestination = nil
	self._pathUpdateThread = nil
	self._isActive = false
	self._connections = {}

	-- Load animations
	self:_loadAnimations()

	return self :: MobAIObject
end

--[[
	Load and set up walk and idle animations
]]
function MobAI:_loadAnimations()
	local animFolder = self.Model:FindFirstChild("Animations")
	if not animFolder then
		warn("[MobAI] No Animations folder found in model:", self.Model.Name)
		return
	end

	local animator = self.Humanoid:FindFirstChildWhichIsA("Animator") :: Animator?
	if not animator then
		animator = Instance.new("Animator") :: Animator
		animator.Parent = self.Humanoid
	end

	-- Load Walk animation
	local walkAnim = animFolder:FindFirstChild("Walk") :: Animation?
	if walkAnim and walkAnim:IsA("Animation") then
		self.WalkAnim = animator:LoadAnimation(walkAnim)
		self.WalkAnim.Looped = true
	else
		warn("[MobAI] Walk animation not found for:", self.Model.Name)
	end

	-- Load Idle animation
	local idleAnim = animFolder:FindFirstChild("Idle") :: Animation?
	if idleAnim and idleAnim:IsA("Animation") then
		self.IdleAnim = animator:LoadAnimation(idleAnim)
		self.IdleAnim.Looped = true
	else
		warn("[MobAI] Idle animation not found for:", self.Model.Name)
	end
end

--[[
	Get configuration value from model attributes with fallback
]]
function MobAI:_getConfig(key: string, default: any): any
	local value = self.Model:GetAttribute(key)
	return if value ~= nil then value else default
end

--[[
	Generate a random wander destination within the wander range
]]
function MobAI:_getRandomWanderPoint(): Vector3?
	local wanderRange = self:_getConfig("WanderRange", DEFAULT_WANDER_RANGE)
	
	-- Pick random angle and distance
	local angle = math.random() * math.pi * 2
	local distance = math.random() * wanderRange
	
	local offset = Vector3.new(
		math.cos(angle) * distance,
		0,
		math.sin(angle) * distance
	)
	
	local targetPos = self._spawnPosition + offset
	
	-- Raycast down to find ground
	local rayOrigin = targetPos + Vector3.new(0, 50, 0)
	local rayResult = workspace:Raycast(rayOrigin, Vector3.new(0, -100, 0))
	
	if rayResult then
		return rayResult.Position + Vector3.new(0, 3, 0)
	end
	
	return nil
end

--[[
	Start the pathfinding AI
]]
function MobAI:Start()
	if self._isActive then
		return
	end

	self._isActive = true

	-- Create path object
	self._path = PathfindingService:CreatePath({
		AgentRadius = 2,
		AgentHeight = 5,
		AgentCanJump = true,
		WaypointSpacing = 4,
		Costs = {
			Water = 20, -- Avoid water
		},
	})

	-- Start idle animation by default
	if self.IdleAnim then
		self.IdleAnim:Play()
	end

	-- Main wander loop
	self._pathUpdateThread = task.spawn(function()
		while self._isActive and self.Model.Parent do
			-- Pick a random destination
			local destination = self:_getRandomWanderPoint()
			
			if destination then
				self._currentDestination = destination
				self:_walkToDestination(destination)
				
				-- Wait at destination before next wander
				if self._isActive and self.Model.Parent then
					self:_playAnimation("Idle")
					local waitMin: number = self:_getConfig("WanderWaitMin", DEFAULT_WANDER_WAIT_MIN)
					local waitMax: number = self:_getConfig("WanderWaitMax", DEFAULT_WANDER_WAIT_MAX)
					local waitTime = waitMin + math.random() * (waitMax - waitMin)
					task.wait(waitTime)
				end
			else
				-- Failed to find destination, wait and try again
				self:_playAnimation("Idle")
				task.wait(2)
			end
		end
	end)
end

--[[
	Walk to the given destination using pathfinding
]]
function MobAI:_walkToDestination(destination: Vector3)
	if not self._path then
		return
	end

	-- Compute path to destination
	local success, errorMessage = pcall(function()
		if self._path then
			self._path:ComputeAsync(self.PrimaryPart.Position, destination)
		end
	end)

	if not success then
		warn("[MobAI] Path computation failed:", errorMessage)
		return
	end

	if self._path.Status == Enum.PathStatus.Success then
		local waypoints = self._path:GetWaypoints()

		-- Start walking animation
		self:_playAnimation("Walk")

		local pathTimeout = self:_getConfig("PathTimeout", DEFAULT_PATH_TIMEOUT)
		local pathStartTime = os.clock()

		-- Follow waypoints
		for i, waypoint in waypoints do
			if not self._isActive or not self.Model.Parent then
				break
			end

			-- Check for timeout
			if os.clock() - pathStartTime > pathTimeout then
				break
			end

			-- Move to waypoint
			self.Humanoid:MoveTo(waypoint.Position)

			-- Handle jump action
			if waypoint.Action == Enum.PathWaypointAction.Jump then
				self.Humanoid.Jump = true
			end

			-- Wait for humanoid to reach waypoint or timeout
			local moveSuccess = self.Humanoid.MoveToFinished:Wait()
			if not moveSuccess then
				-- Couldn't reach waypoint, give up on this path
				break
			end
		end
	end
end

--[[
	Play animation (only if different from current)
]]
function MobAI:_playAnimation(animName: "Walk" | "Idle")
	if animName == "Walk" then
		if self.WalkAnim and not self.WalkAnim.IsPlaying then
			if self.IdleAnim and self.IdleAnim.IsPlaying then
				self.IdleAnim:Stop()
			end
			self.WalkAnim:Play()
		end
	elseif animName == "Idle" then
		if self.IdleAnim and not self.IdleAnim.IsPlaying then
			if self.WalkAnim and self.WalkAnim.IsPlaying then
				self.WalkAnim:Stop()
			end
			self.IdleAnim:Play()
		end
	end
end

--[[
	Stop the AI and clean up
]]
function MobAI:Stop()
	if not self._isActive then
		return
	end

	self._isActive = false

	-- Cancel threads
	if self._pathUpdateThread then
		task.cancel(self._pathUpdateThread)
		self._pathUpdateThread = nil
	end

	if self._moveThread then
		task.cancel(self._moveThread)
		self._moveThread = nil
	end

	if self._animThread then
		task.cancel(self._animThread)
		self._animThread = nil
	end

	-- Stop animations
	if self.WalkAnim and self.WalkAnim.IsPlaying then
		self.WalkAnim:Stop()
	end

	if self.IdleAnim and self.IdleAnim.IsPlaying then
		self.IdleAnim:Stop()
	end

	-- Stop humanoid movement
	if self.Humanoid then
		self.Humanoid:MoveTo(self.PrimaryPart.Position)
	end
end

--[[
	Destroy the AI object (cleanup)
]]
function MobAI:Destroy()
	self:Stop()

	-- Disconnect any connections
	for _, conn in self._connections do
		conn:Disconnect()
	end
	self._connections = {}

	-- Cleanup animations (don't destroy AnimationTracks, just stop them)
	self.WalkAnim = nil
	self.IdleAnim = nil
end

return MobAI

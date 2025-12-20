--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local SlideController = {}
SlideController.__index = SlideController

export type SlideController = typeof(setmetatable({} :: {
	_character: Model,
	_humanoid: Humanoid,
	_rootPart: BasePart,
	_originalHipHeight: number,
	_animator: Animator?,
	_slideAnimation: Animation?,
	_slideTrack: AnimationTrack?,
	_raycastParams: RaycastParams,
	_targetCameraOffset: number,
	IsSliding: boolean,
	SlideDirection: Vector3,
	SlideStartTime: number,
	LastSlideEnd: number,
	SlideSpeed: number,
	UphillMomentum: number,
}, SlideController))

local SLIDE_HIP_HEIGHT = 0.8
local CAMERA_DROP = -2.5
local SLIDE_DECEL = 8
local SLOPE_DOWNHILL_MULT = 35 -- Speed gain when sliding downhill
local SLOPE_UPHILL_MULT = 2.5  -- Extra penalty multiplier when sliding uphill
local STEER_RATE = 2.0
local MIN_SLIDE_SPEED = 3
local MIN_CAMERA_HEIGHT = 0.5
local MAX_STORED_MOMENTUM = 25
local MOMENTUM_DECAY = 0.85

local TWEEN_IN = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_OUT = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function getSlideAnimation(): Animation?
	local config = ReplicatedStorage:FindFirstChild("Config")
	if config then
		local movementConfig = config:FindFirstChild("Movement")
		if movementConfig then
			return movementConfig:FindFirstChild("Sliding") :: Animation?
		end
	end
	return nil
end

function SlideController.new(character: Model): SlideController
	local self = setmetatable({}, SlideController)
	
	self._character = character
	self._humanoid = character:WaitForChild("Humanoid") :: Humanoid
	self._rootPart = character:WaitForChild("HumanoidRootPart") :: BasePart
	self._originalHipHeight = self._humanoid.HipHeight
	
	self._raycastParams = RaycastParams.new()
	self._raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	self._raycastParams.FilterDescendantsInstances = { character }
	
	self._targetCameraOffset = 0
	
	self._animator = self._humanoid:FindFirstChildOfClass("Animator")
	self._slideAnimation = getSlideAnimation()
	
	local slideTrack: AnimationTrack? = nil
	if self._animator and self._slideAnimation then
		slideTrack = self._animator:LoadAnimation(self._slideAnimation)
	end
	self._slideTrack = slideTrack
	
	self.IsSliding = false
	self.SlideDirection = Vector3.zero
	self.SlideStartTime = 0
	self.LastSlideEnd = 0
	self.SlideSpeed = 0
	self.UphillMomentum = 0
	
	return self :: SlideController
end

function SlideController.CanSlide(self: SlideController, _currentSpeed: number, _minSpeed: number, cooldown: number): boolean
	if self.IsSliding then return false end
	return (tick() - self.LastSlideEnd) >= cooldown
end

function SlideController.StartSlide(self: SlideController, direction: Vector3, initialSpeed: number)
	if self.IsSliding then return end
	
	self.IsSliding = true
	self.SlideDirection = direction.Unit
	self.SlideStartTime = tick()
	self.SlideSpeed = initialSpeed
	
	-- Smooth tween for hip height and camera
	TweenService:Create(self._humanoid, TWEEN_IN, { HipHeight = SLIDE_HIP_HEIGHT }):Play()
	TweenService:Create(self._humanoid, TWEEN_IN, { CameraOffset = Vector3.new(0, CAMERA_DROP, 0) }):Play()
	self._targetCameraOffset = CAMERA_DROP
	
	if self._slideTrack then
		self._slideTrack:Play(0.1)
	end
end

function SlideController.EndSlide(self: SlideController)
	if not self.IsSliding then return end
	
	self.IsSliding = false
	self.LastSlideEnd = tick()
	self.SlideSpeed = 0
	
	-- Smooth tween back
	TweenService:Create(self._humanoid, TWEEN_OUT, { HipHeight = self._originalHipHeight }):Play()
	TweenService:Create(self._humanoid, TWEEN_OUT, { CameraOffset = Vector3.zero }):Play()
	self._targetCameraOffset = 0
	
	if self._slideTrack then
		self._slideTrack:Stop(0.2)
	end
end

function SlideController.UpdateSlide(self: SlideController, dt: number, slopeNormal: Vector3?): number
	if not self.IsSliding then return 0 end
	
	-- Update camera offset based on ground distance (prevent clipping)
	self:_updateCameraOffset()
	
	local slopeBonus = 0
	local isGoingUphill = false
	if slopeNormal and slopeNormal.Y < 0.99 and slopeNormal.Y > 0.1 then
		-- Project gravity onto the slope plane to get the true downhill direction
		local gravity = Vector3.new(0, -1, 0)
		local downhillDir = (gravity - slopeNormal * gravity:Dot(slopeNormal))
		
		if downhillDir.Magnitude > 0.01 then
			downhillDir = downhillDir.Unit
			-- Positive dot = sliding downhill = gain speed
			-- Negative dot = sliding uphill = lose speed (with extra penalty)
			local slopeFactor = self.SlideDirection:Dot(downhillDir)
			
			if slopeFactor > 0 then
				-- Sliding downhill: gain a lot of speed
				slopeBonus = slopeFactor * SLOPE_DOWNHILL_MULT * dt
			else
				-- Sliding uphill: lose momentum faster
				slopeBonus = slopeFactor * SLOPE_DOWNHILL_MULT * SLOPE_UPHILL_MULT * dt
				isGoingUphill = true
			end
		end
	end
	
	-- Track uphill momentum for ramp jumping
	if isGoingUphill and slopeBonus < 0 then
		local momentumLost = math.abs(slopeBonus)
		self.UphillMomentum = math.min(self.UphillMomentum + momentumLost, MAX_STORED_MOMENTUM)
	else
		self.UphillMomentum = self.UphillMomentum * MOMENTUM_DECAY
	end
	
	self.SlideSpeed = math.max(self.SlideSpeed - (SLIDE_DECEL * dt) + slopeBonus, MIN_SLIDE_SPEED)
	return self.SlideSpeed
end

function SlideController._updateCameraOffset(self: SlideController)
	local headPosition = self._rootPart.Position + Vector3.new(0, self._humanoid.HipHeight, 0)
	
	local result = workspace:Raycast(
		headPosition,
		Vector3.new(0, CAMERA_DROP - MIN_CAMERA_HEIGHT, 0),
		self._raycastParams
	)
	
	local finalOffset = self._targetCameraOffset
	if result then
		local groundY = result.Position.Y
		local maxDrop = headPosition.Y - groundY - MIN_CAMERA_HEIGHT
		finalOffset = math.max(CAMERA_DROP, -maxDrop)
	end
	
	-- Only update if different (to not interrupt ongoing tweens unnecessarily)
	if math.abs(finalOffset - self._humanoid.CameraOffset.Y) > 0.1 then
		self._humanoid.CameraOffset = Vector3.new(0, finalOffset, 0)
	end
end

function SlideController.Steer(self: SlideController, wishDir: Vector3, dt: number)
	if not self.IsSliding or wishDir.Magnitude < 0.01 then return end
	self.SlideDirection = (self.SlideDirection + wishDir * STEER_RATE * dt).Unit
end

function SlideController.Destroy(self: SlideController)
	if self.IsSliding then
		self:EndSlide()
	end
	
	self._humanoid.CameraOffset = Vector3.zero
	
	if self._slideTrack then
		self._slideTrack:Stop()
		self._slideTrack = nil
	end
end

return SlideController


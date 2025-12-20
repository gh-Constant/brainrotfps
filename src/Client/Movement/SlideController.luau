--!strict

local TweenService = game:GetService("TweenService")

local SlideController = {}
SlideController.__index = SlideController

export type SlideController = typeof(setmetatable({} :: {
	_character: Model,
	_humanoid: Humanoid,
	_rootPart: BasePart,
	_originalHipHeight: number,
	IsSliding: boolean,
	SlideDirection: Vector3,
	SlideStartTime: number,
	LastSlideEnd: number,
	SlideSpeed: number,
}, SlideController))

local SLIDE_HIP_HEIGHT = 0.8
local CAMERA_DROP = -2.5
local SLIDE_DECEL = 8
local SLOPE_SPEED_MULT = 15
local STEER_RATE = 2.0
local MIN_SLIDE_SPEED = 3

local TWEEN_IN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_OUT = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

function SlideController.new(character: Model): SlideController
	local self = setmetatable({}, SlideController)
	
	self._character = character
	self._humanoid = character:WaitForChild("Humanoid") :: Humanoid
	self._rootPart = character:WaitForChild("HumanoidRootPart") :: BasePart
	self._originalHipHeight = self._humanoid.HipHeight
	
	self.IsSliding = false
	self.SlideDirection = Vector3.zero
	self.SlideStartTime = 0
	self.LastSlideEnd = 0
	self.SlideSpeed = 0
	
	return self :: SlideController
end

function SlideController.CanSlide(self: SlideController, _currentSpeed: number, _minSpeed: number, cooldown: number): boolean
	if self.IsSliding then return false end
	
	local timeSinceLastSlide = tick() - self.LastSlideEnd
	return timeSinceLastSlide >= cooldown
end

function SlideController.StartSlide(self: SlideController, direction: Vector3, initialSpeed: number)
	if self.IsSliding then return end
	
	self.IsSliding = true
	self.SlideDirection = direction.Unit
	self.SlideStartTime = tick()
	self.SlideSpeed = initialSpeed
	
	TweenService:Create(self._humanoid, TWEEN_IN, { HipHeight = SLIDE_HIP_HEIGHT }):Play()
	TweenService:Create(self._humanoid, TWEEN_IN, { CameraOffset = Vector3.new(0, CAMERA_DROP, 0) }):Play()
end

function SlideController.EndSlide(self: SlideController)
	if not self.IsSliding then return end
	
	self.IsSliding = false
	self.LastSlideEnd = tick()
	self.SlideSpeed = 0
	
	TweenService:Create(self._humanoid, TWEEN_OUT, { HipHeight = self._originalHipHeight }):Play()
	TweenService:Create(self._humanoid, TWEEN_OUT, { CameraOffset = Vector3.zero }):Play()
end

function SlideController.UpdateSlide(self: SlideController, dt: number, slopeNormal: Vector3?): number
	if not self.IsSliding then return 0 end
	
	local slopeBonus = 0
	if slopeNormal and slopeNormal.Y < 0.99 then
		local slopeDir = Vector3.new(slopeNormal.X, 0, slopeNormal.Z)
		if slopeDir.Magnitude > 0.01 then
			local slopeDot = self.SlideDirection:Dot(slopeDir.Unit)
			slopeBonus = slopeDot * SLOPE_SPEED_MULT * dt
		end
	end
	
	self.SlideSpeed = math.max(self.SlideSpeed - (SLIDE_DECEL * dt) + slopeBonus, MIN_SLIDE_SPEED)
	
	return self.SlideSpeed
end

function SlideController.Steer(self: SlideController, wishDir: Vector3, dt: number)
	if not self.IsSliding or wishDir.Magnitude < 0.01 then return end
	
	self.SlideDirection = (self.SlideDirection + wishDir * STEER_RATE * dt).Unit
end

function SlideController.Destroy(self: SlideController)
	if self.IsSliding then
		self:EndSlide()
	end
end

return SlideController

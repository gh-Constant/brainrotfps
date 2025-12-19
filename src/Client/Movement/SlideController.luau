--!strict
-- SlideController.luau
-- Handles sliding mechanics

local SlideController = {}
SlideController.__index = SlideController

local TweenService = game:GetService("TweenService")

export type SlideController = typeof(setmetatable({} :: {
	_character: Model,
	_humanoid: Humanoid,
	
	IsSliding: boolean,
	SlideDirection: Vector3,
	SlideStartTime: number,
	LastSlideEnd: number,
	
	_originalHipHeight: number,
	_slideHipHeight: number,
}, SlideController))

local SLIDE_DURATION = 0.8 -- Max slide time
local SLIDE_HIP_HEIGHT = 1.0 -- Lowered hip height when sliding

function SlideController.new(character: Model): SlideController
	local self = setmetatable({}, SlideController)
	
	self._character = character
	self._humanoid = character:WaitForChild("Humanoid") :: Humanoid
	
	self.IsSliding = false
	self.SlideDirection = Vector3.zero
	self.SlideStartTime = 0
	self.LastSlideEnd = 0
	
	self._originalHipHeight = self._humanoid.HipHeight
	self._slideHipHeight = SLIDE_HIP_HEIGHT
	
	return self :: SlideController
end

function SlideController.CanSlide(self: SlideController, currentSpeed: number, minSpeed: number, cooldown: number): boolean
	if self.IsSliding then
		return false
	end
	
	if currentSpeed < minSpeed then
		return false
	end
	
	local timeSinceLastSlide = tick() - self.LastSlideEnd
	if timeSinceLastSlide < cooldown then
		return false
	end
	
	return true
end

function SlideController.StartSlide(self: SlideController, direction: Vector3)
	if self.IsSliding then
		return
	end
	
	self.IsSliding = true
	self.SlideDirection = direction.Unit
	self.SlideStartTime = tick()
	
	-- Lower the character (crouch)
	TweenService:Create(
		self._humanoid,
		TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ HipHeight = self._slideHipHeight }
	):Play()
end

function SlideController.EndSlide(self: SlideController)
	if not self.IsSliding then
		return
	end
	
	self.IsSliding = false
	self.LastSlideEnd = tick()
	
	-- Restore hip height
	TweenService:Create(
		self._humanoid,
		TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ HipHeight = self._originalHipHeight }
	):Play()
end

function SlideController.Update(self: SlideController, dt: number): boolean
	if not self.IsSliding then
		return false
	end
	
	-- Check if slide should end due to time
	local slideTime = tick() - self.SlideStartTime
	if slideTime >= SLIDE_DURATION then
		self:EndSlide()
		return false
	end
	
	return true
end

function SlideController.Destroy(self: SlideController)
	if self.IsSliding then
		self:EndSlide()
	end
end

return SlideController

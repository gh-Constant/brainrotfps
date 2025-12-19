--!strict
-- MovementController.luau
-- Main velocity-based movement controller (source-engine inspired)

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local MovementSettings = require(script.Parent.MovementSettings)
local GroundCheck = require(script.Parent.GroundCheck)
local SlideController = require(script.Parent.SlideController)

local MovementController = {}
MovementController.__index = MovementController

export type MovementController = typeof(setmetatable({} :: {
	_character: Model,
	_humanoid: Humanoid,
	_rootPart: BasePart,
	
	_settings: MovementSettings.MovementSettings,
	_groundCheck: GroundCheck.GroundCheck,
	_slideController: SlideController.SlideController,
	
	_connection: RBXScriptConnection?,
	_wasGrounded: boolean,
	_lastLandTime: number,
	_wishJump: boolean,
	
	Enabled: boolean,
}, MovementController))

function MovementController.new(character: Model): MovementController
	local self = setmetatable({}, MovementController)
	
	self._character = character
	self._humanoid = character:WaitForChild("Humanoid") :: Humanoid
	self._rootPart = character:WaitForChild("HumanoidRootPart") :: BasePart
	
	-- Initialize sub-systems
	self._settings = MovementSettings.new(character)
	self._groundCheck = GroundCheck.new(character)
	self._slideController = SlideController.new(character)
	
	-- State
	self._wasGrounded = true
	self._lastLandTime = 0
	self._wishJump = false
	self.Enabled = true
	
	-- Disable default Roblox movement
	self._humanoid.WalkSpeed = 0
	self._humanoid.JumpPower = 0
	self._humanoid.JumpHeight = 0
	
	return self :: MovementController
end

function MovementController.Start(self: MovementController)
	if self._connection then
		return
	end
	
	self._connection = RunService.RenderStepped:Connect(function(dt)
		if self.Enabled then
			self:_update(dt)
		end
	end)
	
	-- Jump input handling
	UserInputService.JumpRequest:Connect(function()
		self._wishJump = true
		task.delay(0.1, function()
			self._wishJump = false
		end)
	end)
end

function MovementController._update(self: MovementController, dt: number)
	local groundResult = self._groundCheck:Check()
	local velocity = self._rootPart.AssemblyLinearVelocity
	local wishDir = self:_getWishDirection()
	
	-- DEBUG: Log ground check and velocity info
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	print(string.format("[Movement] Grounded: %s | Distance: %.2f | HSpeed: %.1f | WishDir: %.2f",
		tostring(groundResult.IsGrounded),
		groundResult.Distance,
		horizontalSpeed,
		wishDir.Magnitude
	))
	
	-- Handle landing (for bhop detection)
	if groundResult.IsGrounded and not self._wasGrounded then
		self._lastLandTime = tick()
	end
	self._wasGrounded = groundResult.IsGrounded
	
	-- Slide logic
	if self._slideController.IsSliding then
		if not groundResult.IsGrounded or self._wishJump then
			self._slideController:EndSlide()
		else
			self._slideController:Update(dt)
			velocity = self:_applySlideMovement(velocity, dt)
		end
	else
		-- Normal movement
		if groundResult.IsGrounded then
			print("[Movement] Using GROUND movement - Speed:", self._settings.GroundSpeed)
			velocity = self:_applyGroundMovement(velocity, wishDir, dt)
			
			-- Jump
			if self._wishJump then
				velocity = self:_applyJump(velocity)
				self._wishJump = false
			end
		else
			print("[Movement] Using AIR movement - Speed:", self._settings.AirSpeed)
			velocity = self:_applyAirMovement(velocity, wishDir, dt)
			velocity = self:_applyGravity(velocity, dt)
		end
	end
	
	-- Clamp max velocity
	local horizontalVel = Vector3.new(velocity.X, 0, velocity.Z)
	if horizontalVel.Magnitude > self._settings.MaxVelocity then
		horizontalVel = horizontalVel.Unit * self._settings.MaxVelocity
		velocity = Vector3.new(horizontalVel.X, velocity.Y, horizontalVel.Z)
	end
	
	self._rootPart.AssemblyLinearVelocity = velocity
end

function MovementController._getWishDirection(self: MovementController): Vector3
	-- MoveDirection is already in world space and camera-relative from Roblox
	local moveDir = self._humanoid.MoveDirection
	if moveDir.Magnitude < 0.01 then
		return Vector3.zero
	end
	
	-- Flatten to horizontal plane and normalize
	local flatDir = Vector3.new(moveDir.X, 0, moveDir.Z)
	return if flatDir.Magnitude > 0.01 then flatDir.Unit else Vector3.zero
end

function MovementController._applyGroundMovement(
	self: MovementController, 
	velocity: Vector3, 
	wishDir: Vector3, 
	dt: number
): Vector3
	local settings = self._settings
	
	-- Get horizontal velocity
	local horizontalVel = Vector3.new(velocity.X, 0, velocity.Z)
	
	-- Apply friction
	local speed = horizontalVel.Magnitude
	if speed > 0.1 then
		local drop = speed * settings.GroundFriction * dt
		local newSpeed = math.max(speed - drop, 0)
		horizontalVel = horizontalVel * (newSpeed / speed)
	end
	
	-- Accelerate towards wish direction
	if wishDir.Magnitude > 0.01 then
		local currentSpeed = horizontalVel:Dot(wishDir)
		local addSpeed = settings.GroundSpeed - currentSpeed
		
		if addSpeed > 0 then
			local accelSpeed = math.min(settings.GroundAcceleration * dt * settings.GroundSpeed, addSpeed)
			horizontalVel = horizontalVel + wishDir * accelSpeed
		end
	end
	
	return Vector3.new(horizontalVel.X, velocity.Y, horizontalVel.Z)
end

function MovementController._applyAirMovement(
	self: MovementController, 
	velocity: Vector3, 
	wishDir: Vector3, 
	dt: number
): Vector3
	local settings = self._settings
	
	-- Get horizontal velocity
	local horizontalVel = Vector3.new(velocity.X, 0, velocity.Z)
	
	-- Very minimal air friction to preserve momentum
	local speed = horizontalVel.Magnitude
	if speed > 0.1 then
		local drop = speed * settings.AirFriction * dt
		local newSpeed = math.max(speed - drop, 0)
		horizontalVel = horizontalVel * (newSpeed / speed)
	end
	
	-- Air control: allow player to influence direction in air
	-- Use a higher cap for air speed to maintain momentum
	if wishDir.Magnitude > 0.01 then
		local currentSpeed = horizontalVel:Dot(wishDir)
		-- Use current speed or AirSpeed, whichever is higher (preserves jump momentum)
		local wishSpeed = math.max(speed, settings.AirSpeed)
		local addSpeed = wishSpeed - currentSpeed
		
		if addSpeed > 0 then
			local accelSpeed = math.min(settings.AirAcceleration * dt, addSpeed)
			horizontalVel = horizontalVel + wishDir * accelSpeed
		end
	end
	
	return Vector3.new(horizontalVel.X, velocity.Y, horizontalVel.Z)
end

function MovementController._applyGravity(self: MovementController, velocity: Vector3, dt: number): Vector3
	return Vector3.new(
		velocity.X, 
		velocity.Y - self._settings.Gravity * dt, 
		velocity.Z
	)
end

function MovementController._applyJump(self: MovementController, velocity: Vector3): Vector3
	local settings = self._settings
	local jumpVelocity = settings.JumpForce
	
	-- Bhop bonus if jumping within window after landing
	local timeSinceLand = tick() - self._lastLandTime
	if timeSinceLand < settings.BhopWindow then
		local horizontalVel = Vector3.new(velocity.X, 0, velocity.Z)
		local newHorizontal = horizontalVel * settings.BhopMultiplier
		velocity = Vector3.new(newHorizontal.X, velocity.Y, newHorizontal.Z)
	end
	
	return Vector3.new(velocity.X, jumpVelocity, velocity.Z)
end

function MovementController._applySlideMovement(self: MovementController, velocity: Vector3, dt: number): Vector3
	local settings = self._settings
	local slideDir = self._slideController.SlideDirection
	
	local horizontalVel = Vector3.new(velocity.X, 0, velocity.Z)
	local speed = horizontalVel.Magnitude
	
	-- Apply slide friction
	if speed > 0.1 then
		local drop = speed * settings.SlideFriction * dt
		local newSpeed = math.max(speed - drop, 0)
		horizontalVel = slideDir * newSpeed
	end
	
	-- End slide if too slow
	if speed < 5 then
		self._slideController:EndSlide()
	end
	
	return Vector3.new(horizontalVel.X, velocity.Y, horizontalVel.Z)
end

-- Start a slide if conditions are met
function MovementController.TrySlide(self: MovementController): boolean
	local velocity = self._rootPart.AssemblyLinearVelocity
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local settings = self._settings
	
	local groundResult = self._groundCheck:Check()
	if not groundResult.IsGrounded then
		return false
	end
	
	if not self._slideController:CanSlide(horizontalSpeed, settings.SlideMinSpeed, settings.SlideCooldown) then
		return false
	end
	
	-- Slide in current movement direction
	local direction = Vector3.new(velocity.X, 0, velocity.Z)
	if direction.Magnitude < 0.1 then
		return false
	end
	
	self._slideController:StartSlide(direction)
	
	-- Boost speed on slide start
	local newSpeed = math.max(horizontalSpeed, settings.SlideSpeed)
	local newVel = direction.Unit * newSpeed
	self._rootPart.AssemblyLinearVelocity = Vector3.new(newVel.X, velocity.Y, newVel.Z)
	
	return true
end

function MovementController.RefreshSettings(self: MovementController)
	self._settings:Refresh(self._character)
end

function MovementController.Destroy(self: MovementController)
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
	
	self._slideController:Destroy()
	
	-- Restore default movement
	self._humanoid.WalkSpeed = 16
	self._humanoid.JumpPower = 50
end

return MovementController

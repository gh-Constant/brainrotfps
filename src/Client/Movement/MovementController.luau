--!strict

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local MovementSettings = require(script.Parent.MovementSettings)
local GroundCheck = require(script.Parent.GroundCheck)
local SlideController = require(script.Parent.SlideController)
local WallJump = require(script.Parent.WallJump)

local MovementController = {}
MovementController.__index = MovementController

export type MovementController = typeof(setmetatable({} :: {
	_character: Model,
	_humanoid: Humanoid,
	_rootPart: BasePart,
	_settings: MovementSettings.MovementSettings,
	_groundCheck: GroundCheck.GroundCheck,
	_slideController: SlideController.SlideController,
	_wallJump: WallJump.WallJump,
	_connection: RBXScriptConnection?,
	_wasGrounded: boolean,
	_lastLandTime: number,
	_wishJump: boolean,
	_wishSlide: boolean,
	_velocity: Vector3,
	Enabled: boolean,
}, MovementController))

local SLIDE_JUMP_WINDOW = 0.3
local SLIDE_JUMP_BOOST = 1.15

function MovementController.new(character: Model): MovementController
	local self = setmetatable({}, MovementController)
	
	self._character = character
	self._humanoid = character:WaitForChild("Humanoid") :: Humanoid
	self._rootPart = character:WaitForChild("HumanoidRootPart") :: BasePart
	self._settings = MovementSettings.new()
	self._groundCheck = GroundCheck.new(character)
	self._slideController = SlideController.new(character)
	self._wallJump = WallJump.new(character, self._settings)
	
	self._wasGrounded = true
	self._lastLandTime = 0
	self._wishJump = false
	self._wishSlide = false
	self._velocity = Vector3.zero
	self.Enabled = true
	
	self._humanoid.WalkSpeed = 0
	self._humanoid.JumpPower = 0
	self._humanoid.JumpHeight = 0
	
	return self :: MovementController
end

function MovementController.Start(self: MovementController)
	if self._connection then return end
	
	self._connection = RunService.RenderStepped:Connect(function(dt)
		if self.Enabled then
			self:_update(dt)
		end
	end)
	
	UserInputService.JumpRequest:Connect(function()
		self._wishJump = true
		task.delay(0.1, function()
			self._wishJump = false
		end)
	end)
end

function MovementController._update(self: MovementController, dt: number)
	local groundResult = self._groundCheck:Check()
	local wishDir = self:_getWishDirection()
	local velocity = self._velocity
	
	local justLanded = groundResult.IsGrounded and not self._wasGrounded
	if justLanded then
		self._lastLandTime = tick()
		local physicsVel = self._rootPart.AssemblyLinearVelocity
		velocity = Vector3.new(velocity.X, physicsVel.Y, velocity.Z)
		self._wallJump:OnLanded()
		
		if self._wishSlide then
			self._wishSlide = false
			local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
			local direction = Vector3.new(velocity.X, 0, velocity.Z)
			if direction.Magnitude < 0.1 then
				direction = self._humanoid.MoveDirection
			end
			if direction.Magnitude > 0.1 then
				local slideSpeed = math.max(horizontalSpeed, self._settings.SlideSpeed)
				self._slideController:StartSlide(direction, slideSpeed)
			end
		end
	end
	
	self._wasGrounded = groundResult.IsGrounded
	
	if self._slideController.IsSliding then
		velocity = self:_handleSliding(velocity, wishDir, groundResult, dt)
	else
		velocity = self:_handleNormalMovement(velocity, wishDir, groundResult, dt)
	end
	
	-- Cap velocity only when NOT sliding (allow slide boost to work)
	if not self._slideController.IsSliding then
		local horizontalVel = Vector3.new(velocity.X, 0, velocity.Z)
		if horizontalVel.Magnitude > self._settings.BhopMaxVelocity then
			horizontalVel = horizontalVel.Unit * self._settings.BhopMaxVelocity
			velocity = Vector3.new(horizontalVel.X, velocity.Y, horizontalVel.Z)
		end
	end
	
	self._velocity = velocity
	self._rootPart.AssemblyLinearVelocity = velocity
end

function MovementController._handleSliding(
	self: MovementController,
	velocity: Vector3,
	wishDir: Vector3,
	groundResult: GroundCheck.GroundCheckResult,
	dt: number
): Vector3
	
	if self._wishJump and groundResult.IsGrounded then
		self._slideController:EndSlide()
		velocity = self:_applyJump(velocity)
		self._wishJump = false
	else
		-- Allow sliding to continue in the air - only end on low speed or jump
		self._slideController:Steer(wishDir, dt)
		local slideSpeed = self._slideController:UpdateSlide(dt, groundResult.Normal)
		local slideDir = self._slideController.SlideDirection
		local horizontalVel = slideDir * slideSpeed
		velocity = Vector3.new(horizontalVel.X, velocity.Y, horizontalVel.Z)
		
		-- Apply gravity when airborne during slide
		if not groundResult.IsGrounded then
			velocity = self:_applyGravity(velocity, dt)
		end
		
		if slideSpeed < 3 then
			self._slideController:EndSlide()
		end
	end
	
	return velocity
end

function MovementController._handleNormalMovement(
	self: MovementController,
	velocity: Vector3,
	wishDir: Vector3,
	groundResult: GroundCheck.GroundCheckResult,
	dt: number
): Vector3
	if groundResult.IsGrounded then
		-- Reset Y velocity when grounded to prevent clipping into the ground
		-- Only keep positive Y velocity (e.g., from a jump that's about to happen)
		if velocity.Y < 0 then
			velocity = Vector3.new(velocity.X, 0, velocity.Z)
		end
		
		local timeSinceLand = tick() - self._lastLandTime
		local inBhopWindow = timeSinceLand < self._settings.BhopWindow
		local isBhopping = inBhopWindow and self._wishJump
		
		if isBhopping then
			if wishDir.Magnitude > 0.01 then
				velocity = self:_applyGroundAccelOnly(velocity, wishDir, dt)
			end
		else
			velocity = self:_applyGroundMovement(velocity, wishDir, dt)
		end
		
		if self._wishJump then
			velocity = self:_applyJump(velocity)
			self._wishJump = false
		end
	else
		self._wallJump:CheckForWall(velocity)
		
		if self._wishJump and self._wallJump:CanWallJump(groundResult.IsGrounded) then
			local camera = workspace.CurrentCamera
			local lookDir = if camera then camera.CFrame.LookVector else self._rootPart.CFrame.LookVector
			velocity = self._wallJump:DoWallJump(velocity, lookDir)
			self._wishJump = false
		else
			velocity = self:_applyAirMovement(velocity, wishDir, dt)
			velocity = self:_applyGravity(velocity, dt)
		end
	end
	
	return velocity
end

function MovementController._getWishDirection(self: MovementController): Vector3
	local inputVector = Vector3.zero
	
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then
		inputVector += Vector3.new(0, 0, -1)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then
		inputVector += Vector3.new(0, 0, 1)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then
		inputVector += Vector3.new(-1, 0, 0)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then
		inputVector += Vector3.new(1, 0, 0)
	end
	
	if inputVector.Magnitude < 0.01 then
		return Vector3.zero
	end
	
	local camera = workspace.CurrentCamera
	if not camera then
		return Vector3.zero
	end
	
	local cameraLook = camera.CFrame.LookVector
	local cameraRight = camera.CFrame.RightVector
	local flatLook = Vector3.new(cameraLook.X, 0, cameraLook.Z)
	local flatRight = Vector3.new(cameraRight.X, 0, cameraRight.Z)
	
	if flatLook.Magnitude > 0.01 then flatLook = flatLook.Unit end
	if flatRight.Magnitude > 0.01 then flatRight = flatRight.Unit end
	
	local worldDir = (flatRight * inputVector.X) + (flatLook * -inputVector.Z)
	
	if worldDir.Magnitude > 0.01 then
		return worldDir.Unit
	end
	
	return Vector3.zero
end

function MovementController._applyGroundMovement(
	self: MovementController,
	velocity: Vector3,
	wishDir: Vector3,
	dt: number
): Vector3
	local settings = self._settings
	local horizontalVel = Vector3.new(velocity.X, 0, velocity.Z)
	local speed = horizontalVel.Magnitude
	
	if speed > 0.1 then
		local control = math.max(speed, settings.GroundSpeed * 0.25)
		local drop = control * settings.GroundFriction * dt
		local newSpeed = math.max(speed - drop, 0)
		horizontalVel = horizontalVel * (newSpeed / speed)
	end
	
	if wishDir.Magnitude > 0.01 then
		local wishSpeed = settings.GroundSpeed
		local currentSpeedInWishDir = horizontalVel:Dot(wishDir)
		local addSpeed = wishSpeed - currentSpeedInWishDir
		
		if addSpeed > 0 then
			local accelSpeed = math.min(settings.GroundAcceleration * wishSpeed * dt, addSpeed)
			horizontalVel = horizontalVel + wishDir * accelSpeed
		end
	end
	
	return Vector3.new(horizontalVel.X, velocity.Y, horizontalVel.Z)
end

function MovementController._applyGroundAccelOnly(
	self: MovementController,
	velocity: Vector3,
	wishDir: Vector3,
	dt: number
): Vector3
	local settings = self._settings
	local horizontalVel = Vector3.new(velocity.X, 0, velocity.Z)
	
	if wishDir.Magnitude > 0.01 then
		local wishSpeed = settings.GroundSpeed
		local currentSpeedInWishDir = horizontalVel:Dot(wishDir)
		local addSpeed = wishSpeed - currentSpeedInWishDir
		
		if addSpeed > 0 then
			local accelSpeed = math.min(settings.GroundAcceleration * wishSpeed * dt, addSpeed)
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
	local horizontalVel = Vector3.new(velocity.X, 0, velocity.Z)
	
	if wishDir.Magnitude > 0.01 then
		local wishSpeed = settings.AirSpeed
		local currentSpeedInWishDir = horizontalVel:Dot(wishDir)
		local addSpeed = wishSpeed - currentSpeedInWishDir
		
		if addSpeed > 0 then
			local accelSpeed = math.min(settings.AirAcceleration * wishSpeed * dt, addSpeed)
			horizontalVel = horizontalVel + wishDir * accelSpeed
		end
	end
	
	return Vector3.new(horizontalVel.X, velocity.Y, horizontalVel.Z)
end

function MovementController._applyGravity(self: MovementController, velocity: Vector3, dt: number): Vector3
	return Vector3.new(velocity.X, velocity.Y - self._settings.Gravity * dt, velocity.Z)
end

function MovementController._applyJump(self: MovementController, velocity: Vector3): Vector3
	local settings = self._settings
	local timeSinceLand = tick() - self._lastLandTime
	
	if timeSinceLand < settings.BhopWindow then
		local horizontalVel = Vector3.new(velocity.X, 0, velocity.Z)
		local newHorizontal = horizontalVel * settings.BhopMultiplier
		velocity = Vector3.new(newHorizontal.X, velocity.Y, newHorizontal.Z)
	end
	
	local timeSinceSlide = tick() - self._slideController.LastSlideEnd
	if timeSinceSlide < SLIDE_JUMP_WINDOW then
		local horizontalVel = Vector3.new(velocity.X, 0, velocity.Z)
		local newHorizontal = horizontalVel * SLIDE_JUMP_BOOST
		velocity = Vector3.new(newHorizontal.X, velocity.Y, newHorizontal.Z)
	end
	
	return Vector3.new(velocity.X, settings.JumpForce, velocity.Z)
end

function MovementController.TrySlide(self: MovementController): boolean
	local velocity = self._velocity
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local settings = self._settings
	local groundResult = self._groundCheck:Check()
	
	if not groundResult.IsGrounded then
		self._wishSlide = true
		return false
	end
	
	if not self._slideController:CanSlide(horizontalSpeed, settings.SlideMinSpeed, settings.SlideCooldown) then
		return false
	end
	
	local direction = Vector3.new(velocity.X, 0, velocity.Z)
	if direction.Magnitude < 0.1 then
		direction = self._humanoid.MoveDirection
		if direction.Magnitude < 0.1 then
			return false
		end
	end
	
	local newSpeed = math.max(horizontalSpeed, settings.SlideSpeed)
	self._slideController:StartSlide(direction, newSpeed)
	
	local newVel = direction.Unit * newSpeed
	local finalVel = Vector3.new(newVel.X, velocity.Y, newVel.Z)
	self._velocity = finalVel
	self._rootPart.AssemblyLinearVelocity = finalVel
	
	return true
end

function MovementController.RefreshSettings(self: MovementController)
	self._settings:Refresh()
end

function MovementController.IsSliding(self: MovementController): boolean
	return self._slideController.IsSliding
end

function MovementController.EndSlide(self: MovementController)
	self._wishSlide = false
	self._slideController:EndSlide()
end

function MovementController.Destroy(self: MovementController)
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
	
	self._slideController:Destroy()
	self._humanoid.WalkSpeed = 16
	self._humanoid.JumpPower = 50
end

return MovementController

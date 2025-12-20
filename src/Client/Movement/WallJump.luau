--!strict

local MovementSettings = require(script.Parent.MovementSettings)

local WallJump = {}
WallJump.__index = WallJump

export type WallJump = typeof(setmetatable({} :: {
	_character: Model,
	_rootPart: BasePart,
	_settings: MovementSettings.MovementSettings,
	_raycastParams: RaycastParams,
	LastWallJumpTime: number,
	LastWallNormal: Vector3?,
	IsNearWall: boolean,
	WallNormal: Vector3?,
}, WallJump))

local MIN_WALL_ANGLE = 70
local MAX_WALL_ANGLE = 110
local WALL_SAMENESS_THRESHOLD = 0.95

function WallJump.new(character: Model, settings: MovementSettings.MovementSettings): WallJump
	local self = setmetatable({}, WallJump)
	
	self._character = character
	self._rootPart = character:WaitForChild("HumanoidRootPart") :: BasePart
	self._settings = settings
	
	self._raycastParams = RaycastParams.new()
	self._raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	self._raycastParams.FilterDescendantsInstances = { character }
	self._raycastParams.IgnoreWater = true
	
	self.LastWallJumpTime = 0
	self.LastWallNormal = nil
	self.IsNearWall = false
	self.WallNormal = nil
	
	return self :: WallJump
end

function WallJump.CheckForWall(self: WallJump, velocity: Vector3): boolean
	local rootPart = self._rootPart
	local position = rootPart.Position
	local checkDistance = self._settings.WallCheckDistance
	
	local horizontalVel = Vector3.new(velocity.X, 0, velocity.Z)
	local checkDirection: Vector3
	
	if horizontalVel.Magnitude > 1 then
		checkDirection = horizontalVel.Unit
	else
		checkDirection = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
		if checkDirection.Magnitude > 0.01 then
			checkDirection = checkDirection.Unit
		else
			self.IsNearWall = false
			self.WallNormal = nil
			return false
		end
	end
	
	local rayOffsets = {
		checkDirection,
		(checkDirection + rootPart.CFrame.RightVector * 0.5).Unit,
		(checkDirection - rootPart.CFrame.RightVector * 0.5).Unit,
	}
	
	for _, direction in rayOffsets do
		local ray = workspace:Raycast(position, direction * checkDistance, self._raycastParams)
		
		if ray then
			local angleFromUp = math.deg(math.acos(ray.Normal:Dot(Vector3.yAxis)))
			
			if angleFromUp >= MIN_WALL_ANGLE and angleFromUp <= MAX_WALL_ANGLE then
				self.IsNearWall = true
				self.WallNormal = ray.Normal
				return true
			end
		end
	end
	
	self.IsNearWall = false
	self.WallNormal = nil
	return false
end

function WallJump.CanWallJump(self: WallJump, isGrounded: boolean): boolean
	if isGrounded then return false end
	if not self.IsNearWall or not self.WallNormal then return false end
	
	local timeSinceJump = tick() - self.LastWallJumpTime
	if timeSinceJump < self._settings.WallJumpCooldown then
		return false
	end
	
	if self.LastWallNormal then
		local sameness = self.WallNormal:Dot(self.LastWallNormal)
		if sameness > WALL_SAMENESS_THRESHOLD then
			return false
		end
	end
	
	return true
end

function WallJump.DoWallJump(self: WallJump, currentVelocity: Vector3, lookDirection: Vector3): Vector3
	if not self.WallNormal then
		return currentVelocity
	end
	
	local wallNormal = self.WallNormal
	local settings = self._settings
	
	local horizontalLook = Vector3.new(lookDirection.X, 0, lookDirection.Z)
	if horizontalLook.Magnitude > 0.01 then
		horizontalLook = horizontalLook.Unit
	else
		horizontalLook = wallNormal
	end
	
	local pushDirection = (wallNormal * 0.7 + horizontalLook * 0.3)
	pushDirection = Vector3.new(pushDirection.X, 0, pushDirection.Z)
	if pushDirection.Magnitude > 0.01 then
		pushDirection = pushDirection.Unit
	else
		pushDirection = wallNormal
	end
	
	local horizontalVel = Vector3.new(currentVelocity.X, 0, currentVelocity.Z)
	local approachAngle = 0
	if horizontalVel.Magnitude > 1 then
		approachAngle = -horizontalVel.Unit:Dot(wallNormal)
	end
	
	local approachFactor = math.clamp(approachAngle, 0, 1)
	local verticalBoost = settings.WallJumpForce * (0.7 + approachFactor * 0.3)
	local pushSpeed = settings.WallPushForce + horizontalVel.Magnitude * 0.5
	
	local newHorizontalVel = pushDirection * pushSpeed
	local newVelocity = Vector3.new(newHorizontalVel.X, verticalBoost, newHorizontalVel.Z)
	
	self.LastWallJumpTime = tick()
	self.LastWallNormal = wallNormal
	
	return newVelocity
end

function WallJump.OnLanded(self: WallJump)
	self.LastWallNormal = nil
end

return WallJump

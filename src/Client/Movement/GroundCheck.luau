--!strict

local GroundCheck = {}
GroundCheck.__index = GroundCheck

export type GroundCheckResult = {
	IsGrounded: boolean,
	Normal: Vector3?,
	Material: Enum.Material?,
	Distance: number,
}

export type GroundCheck = typeof(setmetatable({} :: {
	_character: Model,
	_raycastParams: RaycastParams,
	_groundDistance: number,
}, GroundCheck))

local GROUND_DISTANCE = 1.5
local CAST_EXTRA = 1.0

function GroundCheck.new(character: Model): GroundCheck
	local self = setmetatable({}, GroundCheck)
	
	self._character = character
	self._groundDistance = GROUND_DISTANCE
	
	self._raycastParams = RaycastParams.new()
	self._raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	self._raycastParams.FilterDescendantsInstances = { character }
	
	return self :: GroundCheck
end

function GroundCheck.Check(self: GroundCheck): GroundCheckResult
	local rootPart = self._character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = self._character:FindFirstChildOfClass("Humanoid")
	
	if not rootPart or not humanoid then
		return {
			IsGrounded = false,
			Normal = nil,
			Material = nil,
			Distance = math.huge,
		}
	end
	
	local hipHeight = humanoid.HipHeight
	local origin = rootPart.Position
	local castDistance = hipHeight + CAST_EXTRA
	local direction = Vector3.new(0, -castDistance, 0)
	
	local result = workspace:Raycast(origin, direction, self._raycastParams)
	
	if result then
		local hitDistance = (result.Position - origin).Magnitude
		local distanceFromFeet = hitDistance - hipHeight
		return {
			IsGrounded = distanceFromFeet <= self._groundDistance,
			Normal = result.Normal,
			Material = result.Material,
			Distance = distanceFromFeet,
		}
	end
	
	return {
		IsGrounded = false,
		Normal = nil,
		Material = nil,
		Distance = math.huge,
	}
end

function GroundCheck.UpdateFilter(self: GroundCheck, character: Model)
	self._character = character
	self._raycastParams.FilterDescendantsInstances = { character }
end

return GroundCheck

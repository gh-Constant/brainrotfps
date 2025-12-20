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
	_humanoid: Humanoid,
	_raycastParams: RaycastParams,
}, GroundCheck))

-- Distance for normal raycasting (only used to get slope normal, not for grounded check)
local NORMAL_CAST_DISTANCE = 3

function GroundCheck.new(character: Model): GroundCheck
	local self = setmetatable({}, GroundCheck)
	
	self._character = character
	self._humanoid = character:WaitForChild("Humanoid") :: Humanoid
	
	self._raycastParams = RaycastParams.new()
	self._raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	self._raycastParams.FilterDescendantsInstances = { character }
	
	return self :: GroundCheck
end

function GroundCheck.Check(self: GroundCheck): GroundCheckResult
	local rootPart = self._character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = self._humanoid
	
	if not rootPart or not humanoid then
		return {
			IsGrounded = false,
			Normal = nil,
			Material = nil,
			Distance = math.huge,
		}
	end
	
	-- Use native Roblox ground detection via FloorMaterial
	-- When FloorMaterial is not Air, the Humanoid is touching ground
	local floorMaterial = humanoid.FloorMaterial
	local isGrounded = floorMaterial ~= Enum.Material.Air
	
	-- Perform a raycast to get the surface normal for slope calculations
	local origin = rootPart.Position
	local direction = Vector3.new(0, -NORMAL_CAST_DISTANCE, 0)
	local result = workspace:Raycast(origin, direction, self._raycastParams)
	
	if result then
		local hitDistance = (result.Position - origin).Magnitude
		return {
			IsGrounded = isGrounded,
			Normal = result.Normal,
			Material = floorMaterial,
			Distance = hitDistance - humanoid.HipHeight,
		}
	end
	
	return {
		IsGrounded = isGrounded,
		Normal = if isGrounded then Vector3.yAxis else nil,
		Material = floorMaterial,
		Distance = if isGrounded then 0 else math.huge,
	}
end

function GroundCheck.UpdateFilter(self: GroundCheck, character: Model)
	self._character = character
	self._humanoid = character:WaitForChild("Humanoid") :: Humanoid
	self._raycastParams.FilterDescendantsInstances = { character }
end

return GroundCheck

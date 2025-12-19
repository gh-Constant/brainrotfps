--!strict
-- GroundCheck.luau
-- Utility for detecting if player is grounded using raycasts

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

function GroundCheck.new(character: Model): GroundCheck
	local self = setmetatable({}, GroundCheck)
	
	self._character = character
	self._groundDistance = 1.5 -- How close to ground to be considered "grounded"
	
	-- Setup raycast params to ignore the character
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
	
	-- Get the actual hip height from the humanoid
	local hipHeight = humanoid.HipHeight
	
	-- Cast ray from center of character downward
	-- Cast distance = hipHeight + some extra to detect ground slightly below
	local origin = rootPart.Position
	local castDistance = hipHeight + 1.0
	local direction = Vector3.new(0, -castDistance, 0)
	
	local result = workspace:Raycast(origin, direction, self._raycastParams)
	
	if result then
		-- Distance from feet to ground = ray hit distance - hip height
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

-- Update filter when character changes (e.g., respawn)
function GroundCheck.UpdateFilter(self: GroundCheck, character: Model)
	self._character = character
	self._raycastParams.FilterDescendantsInstances = { character }
end

return GroundCheck

--!strict
-- MovementSettings.luau
-- Reads movement configuration from character attributes

local MovementSettings = {}
MovementSettings.__index = MovementSettings

export type MovementSettings = typeof(setmetatable({} :: {
	-- Ground movement
	GroundSpeed: number,
	GroundAcceleration: number,
	GroundFriction: number,
	
	-- Air movement
	AirSpeed: number,
	AirAcceleration: number,
	AirFriction: number,
	
	-- Jump
	JumpForce: number,
	BhopMultiplier: number,
	BhopWindow: number, -- seconds after landing to preserve momentum
	
	-- Slide
	SlideSpeed: number,
	SlideFriction: number,
	SlideCooldown: number,
	SlideMinSpeed: number, -- minimum speed to initiate slide
	
	-- General
	Gravity: number,
	MaxVelocity: number,
}, MovementSettings))

-- Default values if attributes are missing
local DEFAULTS = {
	-- Ground
	GroundSpeed = 24,
	GroundAcceleration = 100,
	GroundFriction = 8,
	
	-- Air
	AirSpeed = 2,
	AirAcceleration = 50,
	AirFriction = 0.1,
	
	-- Jump
	JumpForce = 50,
	BhopMultiplier = 1.05,
	BhopWindow = 0.15,
	
	-- Slide
	SlideSpeed = 35,
	SlideFriction = 1,
	SlideCooldown = 0.5,
	SlideMinSpeed = 15,
	
	-- General
	Gravity = 75,
	MaxVelocity = 100,
}

function MovementSettings.new(character: Model): MovementSettings
	local self = setmetatable({}, MovementSettings)
	
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	
	-- Read each setting from attributes, falling back to defaults
	for key, default in DEFAULTS do
		local attrValue = if humanoid then humanoid:GetAttribute(key) else nil
		self[key] = if attrValue ~= nil then attrValue else default
	end
	
	return self :: MovementSettings
end

-- Refresh settings from attributes (useful for live tweaking)
function MovementSettings.Refresh(self: MovementSettings, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	
	for key, default in DEFAULTS do
		local attrValue = if humanoid then humanoid:GetAttribute(key) else nil
		self[key] = if attrValue ~= nil then attrValue else default
	end
end

-- Get all default values (for setting up attributes)
function MovementSettings.GetDefaults(): { [string]: number }
	return table.clone(DEFAULTS)
end

return MovementSettings

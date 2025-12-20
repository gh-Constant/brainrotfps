--!strict

local MovementSettings = {}
MovementSettings.__index = MovementSettings

export type MovementSettings = typeof(setmetatable({} :: {
	GroundSpeed: number,
	GroundAcceleration: number,
	GroundFriction: number,
	AirSpeed: number,
	AirAcceleration: number,
	AirFriction: number,
	JumpForce: number,
	BhopMultiplier: number,
	BhopWindow: number,
	SlideSpeed: number,
	SlideFriction: number,
	SlideCooldown: number,
	SlideMinSpeed: number,
	WallJumpForce: number,
	WallPushForce: number,
	WallJumpCooldown: number,
	WallCheckDistance: number,
	Gravity: number,
	MaxVelocity: number,
}, MovementSettings))

local DEFAULTS: { [string]: number } = {
	GroundSpeed = 32,
	GroundAcceleration = 60,
	GroundFriction = 6,
	AirSpeed = 32,
	AirAcceleration = 30,
	AirFriction = 0,
	JumpForce = 28,
	BhopMultiplier = 1,
	BhopWindow = 0.2,
	SlideSpeed = 40,
	SlideFriction = 1,
	SlideCooldown = 0.15,
	SlideMinSpeed = 5,
	WallJumpForce = 45,
	WallPushForce = 38,
	WallJumpCooldown = 0.15,
	WallCheckDistance = 3.5,
	Gravity = 80,
	MaxVelocity = 36,
}

local clientScript = script.Parent.Parent

function MovementSettings.new(): MovementSettings
	local self = setmetatable({}, MovementSettings)
	
	for key, default in DEFAULTS do
		local attrValue = clientScript:GetAttribute(key)
		(self :: any)[key] = if attrValue ~= nil then attrValue else default
	end
	
	return self :: MovementSettings
end

function MovementSettings.Refresh(self: MovementSettings)
	for key, default in DEFAULTS do
		local attrValue = clientScript:GetAttribute(key)
		(self :: any)[key] = if attrValue ~= nil then attrValue else default
	end
end

function MovementSettings.GetDefaults(): { [string]: number }
	return table.clone(DEFAULTS)
end

return MovementSettings

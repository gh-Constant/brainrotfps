local ReplicatedStorage = game:GetService("ReplicatedStorage")

local castRays = require(ReplicatedStorage.Blaster.Utility.castRays)
local canPlayerDamageHumanoid = require(ReplicatedStorage.Blaster.Utility.canPlayerDamageHumanoid)

local BASE_DIRECTION_BUFFER = 10 -- Minimum buffer in studs
local WALL_DISTANCE_BUFFER_CONSTANT = 8

--[[
	Calculates the direction buffer based on the target's size.
	Larger targets get a larger buffer to make them easier to hit.
]]
local function getDirectionBuffer(character: Model): number
	-- Get the bounding box of the target
	local _, size = character:GetBoundingBox()
	
	-- Use the full diagonal as the buffer for generous hit detection on big mobs
	local diagonal = size.Magnitude
	local targetBuffer = diagonal * 1.0 -- Full diagonal for more leniency
	
	-- Clamp between BASE_DIRECTION_BUFFER and a maximum of 100 studs
	return math.clamp(targetBuffer, BASE_DIRECTION_BUFFER, 100)
end

local function validateTag(
	player: Player,
	taggedHumanoid: Humanoid,
	position: Vector3,
	direction: Vector3,
	rayResult: castRays.RayResult
): boolean
	-- Make sure the player is actually allowed to damage this humanoid. No team killing!
	if not canPlayerDamageHumanoid(player, taggedHumanoid) then
		print("cannot damage the humanoid")
		return false
	end

	local character = taggedHumanoid:FindFirstAncestorOfClass("Model")
	if not character then
		return false
	end

	local pivot = character:GetPivot()
	local characterOffset = pivot.Position - position
	local characterDistance = characterOffset.Magnitude
	local rayDistance = (position - rayResult.position).Magnitude

	-- If the server's version of the ray hits static geometry before the player, then we know the shot
	-- the client reported could not be made.
	if rayDistance < characterDistance - WALL_DISTANCE_BUFFER_CONSTANT then
		print(" If the server's version of the ray hits static geometry before the player, then we know the shot")
		return false
	end

	-- Calculate the direction buffer based on the target's size
	-- Larger mobs get a more lenient buffer
	local directionBuffer = getDirectionBuffer(character)

	-- In order to make sure that the ray is actually aiming within a certain distance of the character,
	-- we'll calculate a maximum angle based on our direction buffer.
	-- The buffer is the maximum amount of studs away from the character that the ray can aim.
	-- atan(directionBuffer / characterDistance) will give us the maximum angle based on how far away the character is.
	--[[
		◎───y───
		▲     /
		│    /
		x   /
		│  /
		│θ/
		│/

		x = characterDistance
		y = directionBuffer
		θ = atan(y/x)
	]]

	local maxAngle = math.atan(directionBuffer / characterDistance) * 2 -- 2x multiplier for extra leniency
	-- Check what angle the ray is actually aiming relative to the character and make sure it's within our maximum.
	-- This will stop a client from passing in arbitrary humanoids, only allowing them to damage what they could
	-- conceivably be aiming at.
	local angle = characterOffset:Angle(direction)
	
	-- Debug: show what values we're working with
	print(string.format("[validateTag] angle=%.3f, maxAngle=%.3f, buffer=%d, dist=%.1f", 
		math.deg(angle), math.deg(maxAngle), directionBuffer, characterDistance))
	
	if angle > maxAngle then
		print("not good angle")
		return false
	end

	return true
end

return validateTag

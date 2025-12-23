local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Constants = require(ReplicatedStorage.Blaster.Constants)
local validateInstance = require(ServerScriptService.Utility.TypeValidation.validateInstance)
local validateShootArguments = require(script.validateShootArguments)
local validateShot = require(script.validateShot)
local validateTag = require(script.validateTag)
local validateReload = require(script.validateReload)
local getRayDirections = require(ReplicatedStorage.Blaster.Utility.getRayDirections)
local castRays = require(ReplicatedStorage.Blaster.Utility.castRays)

-- CUSTOM HEALTH SYSTEM
local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")
local Health = require(Shared:WaitForChild("Health"))

local remotes = ReplicatedStorage.Blaster.Remotes
local shootRemote = remotes.Shoot
local reloadRemote = remotes.Reload
local replicateShotRemote = remotes.ReplicateShot
local events = ServerScriptService.Blaster.Events
local taggedEvent = events.Tagged
local eliminatedEvent = events.Eliminated

-- Helper function to get player's level
local function getPlayerLevel(player: Player): number
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local level = leaderstats:FindFirstChild("Level")
		if level then
			return level.Value
		end
	end
	return 1 -- Default to level 1 if not found
end

local function onShootEvent(
	player: Player,
	timestamp: number,
	blaster: Tool,
	origin: CFrame,
	tagged: { [string]: Humanoid }
)

	-- Validate the received arguments
	if not validateShootArguments(timestamp, blaster, origin, tagged) then
		warn("[Blaster] Invalid Arguments") -- DEBUG
		return
	end
	-- Validate that the player can make this shot
	if not validateShot(player, timestamp, blaster, origin) then
		warn("[Blaster] Shot Validation Failed (Cooldown or ammo)") -- DEBUG
		return
	end

	local spread = blaster:GetAttribute(Constants.SPREAD_ATTRIBUTE)
	local raysPerShot = blaster:GetAttribute(Constants.RAYS_PER_SHOT_ATTRIBUTE)
	local range = blaster:GetAttribute(Constants.RANGE_ATTRIBUTE)
	local rayRadius = blaster:GetAttribute(Constants.RAY_RADIUS_ATTRIBUTE)

	-- Get damage based on player level instead of weapon attribute
	local damage = getPlayerLevel(player) * 3
	local ammo = blaster:GetAttribute(Constants.AMMO_ATTRIBUTE)
	blaster:SetAttribute(Constants.AMMO_ATTRIBUTE, ammo - 1)

	-- Calculate spread
	local spreadAngle = math.rad(spread)
	local rayDirections = getRayDirections(origin, raysPerShot, spreadAngle, timestamp)
	for index, direction in rayDirections do
		rayDirections[index] = direction * range
	end

	-- Raycast against static geometry only
	local rayResults = castRays(player, origin.Position, rayDirections, rayRadius, true)

	-- DEBUG: Loop through what the client claimed to hit
	for indexString, taggedHumanoid in tagged do
		local index = tonumber(indexString)
		if not index then continue end
		-- CRITICAL CHECK: Did the server raycast exist?
		if not rayResults[index] then
			-- If castRays returns nil when hitting nothing (air), this will fail.
			-- If the mob is in the open, the server ray hits 'nil', so we might be skipping the logic here.

			-- WARNING: If your 'castRays' module returns nil on a miss, 
			-- you must NOT 'continue' here if you want to allow hitting mobs in the open.
			-- You should likely construct a fake ray result for the validation.
			continue 
		end

		local rayResult = rayResults[index]
		local rayDirection = rayDirections[index]

		-- Validate that the player is able to tag this humanoid
		local isValid = validateTag(player, taggedHumanoid, origin.Position, rayDirection, rayResult)
		if not isValid then
			continue
		end

		rayResult.taggedHumanoid = taggedHumanoid

		-- Align the rayResult position to the tagged humanoid
		local model = taggedHumanoid:FindFirstAncestorOfClass("Model")
		if model then
			local modelPosition = model:GetPivot().Position
			local distance = (modelPosition - origin.Position).Magnitude
			rayResult.position = origin.Position + rayDirection.Unit * distance
		end

		-- USE CUSTOM HEALTH SYSTEM WITH ATTRIBUTES
		if model then
			if model:GetAttribute("IsDead") then
				continue
			end

			local currentHP = model:GetAttribute("Health") or 0
			local healthComponent = Health.Get(model)
			healthComponent:TakeDamage(damage, player)

			taggedEvent:Fire(player, taggedHumanoid, damage)

			local newHP = model:GetAttribute("Health") or 0
			if newHP <= 0 and currentHP > 0 then
				eliminatedEvent:Fire(player, taggedHumanoid, damage)
			end
		end
	end

	-- Apply physics impulse code...
	local force = blaster:GetAttribute(Constants.UNANCHORED_IMPULSE_FORCE_ATTRIBUTE)
	if force ~= 0 then
		for index, rayResult in rayResults do
			if rayResult.taggedHumanoid then continue end
			if rayResult.instance and rayResult.instance:IsA("BasePart") and not rayResult.instance.Anchored then
				local direction = rayDirections[index]
				local impulse = direction * force
				rayResult.instance:ApplyImpulseAtPosition(impulse, rayResult.position)
			end
		end
	end

	-- Replicate shot
	for _, otherPlayer in Players:GetPlayers() do
		if otherPlayer == player then continue end
		replicateShotRemote:FireClient(otherPlayer, blaster, origin.Position, rayResults)
	end
end

local function onReloadEvent(player: Player, blaster: Tool)
	-- Validate the received argument
	if not validateInstance(blaster, "Tool") then
		return
	end
	-- Make sure the player is able to reload this blaster
	if not validateReload(player, blaster) then
		return
	end
	local reloadTime = blaster:GetAttribute(Constants.RELOAD_TIME_ATTRIBUTE)
	local magazineSize = blaster:GetAttribute(Constants.MAGAZINE_SIZE_ATTRIBUTE)
	local character = player.Character
	blaster:SetAttribute(Constants.RELOADING_ATTRIBUTE, true)
	local reloadTask
	local ancestryChangedConnection
	reloadTask = task.delay(reloadTime, function()
		blaster:SetAttribute(Constants.AMMO_ATTRIBUTE, magazineSize)
		blaster:SetAttribute(Constants.RELOADING_ATTRIBUTE, false)
		ancestryChangedConnection:Disconnect()
	end)
	ancestryChangedConnection = blaster.AncestryChanged:Connect(function()
		if blaster.Parent ~= character then
			blaster:SetAttribute(Constants.RELOADING_ATTRIBUTE, false)
			task.cancel(reloadTask)
			ancestryChangedConnection:Disconnect()
		end
	end)
end

local function initialize()
	shootRemote.OnServerEvent:Connect(onShootEvent)
	reloadRemote.OnServerEvent:Connect(onReloadEvent)
end

initialize()
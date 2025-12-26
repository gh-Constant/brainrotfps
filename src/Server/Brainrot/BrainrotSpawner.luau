--!strict
-- BrainrotSpawner: Handles spawning brainrots in tagged zones
-- Zones are tagged parts (e.g., "Forest"), config is in ReplicatedStorage.Config.Brainrots

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Packages = Rojo:WaitForChild("Packages")
local Shared = Rojo:WaitForChild("Shared")
local Server = ServerScriptService:WaitForChild("Rojo"):WaitForChild("Server")

local Zone = require(Packages:WaitForChild("zoneplus"))
local Health = require(Shared:WaitForChild("Health"))
local Packets = require(Shared:WaitForChild("Packets"))
local PlayerManager = require(Server:WaitForChild("Player"))
local config = ReplicatedStorage:WaitForChild("Config")
local brainrotConfig = config:WaitForChild("Brainrots")
local zonesConfig = brainrotConfig:WaitForChild("Zones")
local MobAI = require(Server:WaitForChild("Brainrot"):WaitForChild("MobAI"))
local MobDisplay = require(Server:WaitForChild("Brainrot"):WaitForChild("MobDisplay"))
local Mutations = require(Shared:WaitForChild("Mutations"))

local BrainrotSpawner = {}

-- Types
type ZoneGroup = {
	zoneName: string,
	parts: { BasePart },
	spawnedBrainrots: { Model },
	zoneObjects: { any }, -- Keep references to ZonePlus objects if needed
}

-- State
local zoneGroups: { [string]: ZoneGroup } = {}

-- Default values (overridden by attributes)
local DEFAULT_SPAWN_INTERVAL = 5
local DEFAULT_MAX_PER_ZONE = 10

local function isLoggingEnabled(): boolean
	return brainrotConfig:GetAttribute("Logging") == true
end

local function log(message: string)
	if isLoggingEnabled() then
		print(message)
	end
end

local function getEffectsFolder(): Folder
	local folder = workspace:FindFirstChild("Effects")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Effects"
		folder.Parent = workspace
	end
	return folder :: Folder
end

local function getSpawnInterval(): number
	local interval = brainrotConfig:GetAttribute("SpawnInterval")
	if typeof(interval) == "number" then
		return interval
	end
	return DEFAULT_SPAWN_INTERVAL
end

local function getMaxPerZone(): number
	local max = brainrotConfig:GetAttribute("MaxPerZone")
	if typeof(max) == "number" then
		return max
	end
	return DEFAULT_MAX_PER_ZONE
end

local function getZoneModels(zoneName: string): { Model }
	
	local zoneFolder = zonesConfig:FindFirstChild(zoneName)
	if not zoneFolder then
		warn("[BrainrotSpawner] Zone folder not found: " .. zoneName)
		return {}
	end
	
	local models: { Model } = {}
	for _, child in zoneFolder:GetChildren() do
		if child:IsA("Model") then
			table.insert(models, child)
		end
	end
	
	return models
end

local function getRandomSpawnPosition(part: BasePart): Vector3?
	local size = part.Size
	local cframe = part.CFrame
	
	-- Random position within the part's bounds
	local randomOffset = Vector3.new(
		math.random() * size.X - size.X / 2,
		0, -- Spawn at part's Y level (will be adjusted for ground)
		math.random() * size.Z - size.Z / 2
	)
	
	local worldPos = cframe:PointToWorldSpace(randomOffset)
	
	-- Raycast down to find ALL valid floors (tagged Spawnable or is Terrain)
	local rayOrigin = Vector3.new(worldPos.X, worldPos.Y + 100, worldPos.Z)
	local remainingDistance = 200
	
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { part }
	
	-- Collect all valid spawn positions
	local validPositions: { Vector3 } = {}
	local currentOrigin = rayOrigin
	local maxAttempts = 20
	
	for _ = 1, maxAttempts do
		if remainingDistance <= 0 then
			break
		end
		
		local result = workspace:Raycast(currentOrigin, Vector3.new(0, -remainingDistance, 0), raycastParams)
		if not result then
			break
		end
		
		local hitInstance = result.Instance
		local hitPos = result.Position
		
		-- Check if it's valid ground: Terrain or tagged "Spawnable"
		local isValidGround = hitInstance:IsA("Terrain") or CollectionService:HasTag(hitInstance, "Spawnable")
		
		if isValidGround then
			-- Check there's open space above (not inside a wall)
			local upCheck = workspace:Raycast(hitPos + Vector3.new(0, 0.5, 0), Vector3.new(0, 5, 0), raycastParams)
			if not upCheck then
				-- Valid floor with open space above
				table.insert(validPositions, hitPos + Vector3.new(0, 3, 0))
			end
		end
		
		-- Continue raycasting from below this hit
		local distanceUsed = (currentOrigin.Y - hitPos.Y) + 0.1
		remainingDistance = remainingDistance - distanceUsed
		currentOrigin = hitPos + Vector3.new(0, -0.1, 0)
	end
	
	-- Pick a random valid position
	if #validPositions > 0 then
		return validPositions[math.random(1, #validPositions)]
	end
	
	-- No valid ground found
	return nil
end

local function getWeightedRandomModel(models: { Model }): Model
	-- Weight system: Luck attribute = "1 in X chance"
	-- Luck=1 means 1/1 (100% relative chance), Luck=1000 means 1/1000 (very rare)
	-- We invert the luck values to get weights: weight = 1/luck
	local totalWeight = 0
	local items = {}
	
	for _, model in models do
		local luckAttr = model:GetAttribute("Luck")
		-- Handle both number and string attributes (tonumber handles both)
		local luckParsed = tonumber(luckAttr)
		local luck: number = if luckParsed and luckParsed > 0 then luckParsed else 1
		
		-- Invert luck to get weight: lower luck value = higher weight (more common)
		local weight = 1 / luck
		
		table.insert(items, { model = model, weight = weight })
		totalWeight += weight
	end
	
	-- Fallback if no weights
	if totalWeight <= 0 then
		return models[math.random(1, #models)]
	end
	
	local rng = math.random() * totalWeight
	local currentWeight = 0
	
	for _, item in items do
		currentWeight += item.weight
		if rng <= currentWeight then
			return item.model
		end
	end
	
	return models[1] -- Should rarely happen
end

local function spawnBrainrot(group: ZoneGroup)
	local models = getZoneModels(group.zoneName)
	if #models == 0 then
		return
	end
	
	-- Check max per zone GROUP
	local maxPerZone = getMaxPerZone()
	if #group.spawnedBrainrots >= maxPerZone then
		return
	end
	
	-- Pick weighted random model based on "Luck" attribute
	local template = getWeightedRandomModel(models)
	local brainrot = template:Clone()
	
	-- Pick a random part from the group
	if #group.parts == 0 then return end
	local randomPart = group.parts[math.random(1, #group.parts)]
	
	-- Get spawn position
	local spawnPos = getRandomSpawnPosition(randomPart)
	if not spawnPos then
		brainrot:Destroy()
		return
	end
	
	-- Position the brainrot
	local primaryPart = brainrot.PrimaryPart or brainrot:FindFirstChildWhichIsA("BasePart")
	if primaryPart then
		brainrot:PivotTo(CFrame.new(spawnPos))
	end
	
	-- Track the spawned brainrot
	table.insert(group.spawnedBrainrots, brainrot)
	
	-- Parent to Workspace.Zones.{ZoneName} folder
	local zonesFolder = workspace:FindFirstChild("Zones")
	if zonesFolder then
		local zoneFolder = zonesFolder:FindFirstChild(group.zoneName)
		if zoneFolder then
			brainrot.Parent = zoneFolder
		else
			brainrot.Parent = workspace
		end
	else
		brainrot.Parent = workspace
	end
	
	-- Setup Health and Death logic
	-- Get max health from attribute or default
	local maxHealthAttr = brainrot:GetAttribute("MaxHealth")
	local maxHealth: number = if typeof(maxHealthAttr) == "number" then maxHealthAttr else 100
	local health = Health.new(brainrot, maxHealth)
	
	-- Setup AI pathfinding and animation
	local mobAI = MobAI.new(brainrot)
	if mobAI then
		mobAI:Start()
		log("[BrainrotSpawner] Started AI for: " .. brainrot.Name)
	else
		warn("[BrainrotSpawner] Failed to create AI for: " .. brainrot.Name)
	end

	-- Setup Mob Display (UI)
	local mobDisplay = MobDisplay.new(brainrot)

	health.Died:Connect(function(instigator)
		-- Log kill info if enabled
		local healthConfig = config:FindFirstChild("Health")
		local loggingEnabled = healthConfig and healthConfig:GetAttribute("Logging") == true
		
		if loggingEnabled then
			local killerName = instigator and instigator.Name or "Unknown"
			print(string.format("💀 %s died! Last Hit: %s", brainrot.Name, killerName))
		end
		
		-- Award XP to killer
		if instigator then
			local playerData = PlayerManager.GetPlayerData(instigator)
			if playerData then
			local xpRewardAttr = brainrot:GetAttribute("BaseXPReward")
				local xpReward: number = if typeof(xpRewardAttr) == "number" then xpRewardAttr else 10
				
				local goldRewardAttr = brainrot:GetAttribute("BaseGoldReward")
				local goldReward: number = if typeof(goldRewardAttr) == "number" then goldRewardAttr else 5
				
				-- Apply mutation multiplier to rewards
				local mobMutation = brainrot:GetAttribute("Mutation")
				if mobMutation then
					local mutationData = Mutations.GetMutation(mobMutation)
					if mutationData then
						xpReward = math.floor(xpReward * mutationData.MultiplierModifier)
						goldReward = math.floor(goldReward * mutationData.MultiplierModifier)
					end
				end
				
				playerData:AddExperience(xpReward)
				playerData:AddGold(goldReward)
				
				-- Send Loot FX to killer client
				if primaryPart then
					local fxPos = primaryPart.Position
					
					local xpImage = config.Effects.FX.XP.Image
					local goldImage = config.Effects.FX.Coin.Image
					
					-- XP FX (blue color) - slightly offset left
					Packets.lootDropFX.sendTo({
						posX = fxPos.X - 0.5,
						posY = fxPos.Y + 1,
						posZ = fxPos.Z,
						config = {
							image = xpImage,
							color = { 66, 135, 245 }, -- Blue for XP
							trailEnabled = true,
							trailColor = { 100, 160, 255 }, -- Light blue trail
							count = math.floor(xpReward / 10), -- 1 part per 10 XP, no limits
						},
					}, instigator)
					
					-- Gold FX (yellow/gold color) - slightly offset right
					Packets.lootDropFX.sendTo({
						posX = fxPos.X + 0.5,
						posY = fxPos.Y + 1,
						posZ = fxPos.Z,
						config = {
							image = goldImage,
							color = { 255, 215, 0 }, -- Gold color
							trailEnabled = true,
							trailColor = { 255, 200, 50 }, -- Gold trail
							count = math.floor(goldReward / 100), -- 1 part per 100 gold, no limits
						},
					}, instigator)
				end
			end
		end
		
		if loggingEnabled then
			local damageHistory = health:GetDamageHistory()
			local totalDamage = 0
			for _, dmg in damageHistory do
				totalDamage += dmg
			end
			
			print("⚔️ Damage Report:")
			for userId, damage in damageHistory do
				local p = Players:GetPlayerByUserId(userId)
				local pName = p and p.Name or tostring(userId)
				local percentage = if totalDamage > 0 then (damage / totalDamage) * 100 else 0
				print(string.format("   - %s: %d dmg (%.1f%%)", pName, damage, percentage))
			end
		end
		-- Stop AI when mob dies
		if mobAI then
			mobAI:Stop()
		end
		
		-- IMMEDIATELY hide the mob to prevent T-pose from being visible
		for _, descendant in brainrot:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Transparency = 1
				descendant.CanCollide = false
			elseif descendant:IsA("Decal") then
				descendant.Transparency = 1
			elseif descendant:IsA("Texture") then
				descendant.Transparency = 1
			end
		end
		
--[[
		-- Spawn death VFX
		if primaryPart then
			local vfxFolder = brainrot:FindFirstChild("VFX")
			if vfxFolder then
				local deathVFX = vfxFolder:FindFirstChild("Death")
				if deathVFX and deathVFX:IsA("Attachment") then
					-- Create invisible part to hold VFX (persists after mob despawns)
					local vfxPart = Instance.new("Part")
					vfxPart.Anchored = true
					vfxPart.CanCollide = false
					vfxPart.Transparency = 1
					vfxPart.Size = Vector3.new(0.1, 0.1, 0.1)
					
					-- Use VfxInstance for positioning if it exists, otherwise PrimaryPart
					local vfxTarget = brainrot:FindFirstChild("VfxInstance") or primaryPart
					if vfxTarget and vfxTarget:IsA("BasePart") then
						vfxPart.CFrame = vfxTarget.CFrame
					else
						vfxPart.CFrame = primaryPart.CFrame
					end
					
					vfxPart.Parent = getEffectsFolder()
					
					-- Clone and attach death VFX to the separate part
					local vfxClone = deathVFX:Clone()
					vfxClone.Parent = vfxPart
					
					-- Wait briefly for particles to load, then emit
					task.wait(0.1)
					for _, Particles in vfxClone:GetDescendants() do
						if Particles:IsA("ParticleEmitter") then
							Particles:Emit(Particles:GetAttribute("EmitCount") :: number or 1)
						end
					end
					
					-- Clean up VFX part after particles finish
					if not isLoggingEnabled() then
						task.delay(3, function()
							vfxPart:Destroy()
						end)
					else
						-- Make visible if keeping for debug
						vfxPart.Transparency = 0.5
						vfxPart.Color = Color3.new(1, 0, 0)
						vfxPart.Material = Enum.Material.Neon
						log("[BrainrotSpawner] Keeping dead VFX part for debug")
					end
				end
			end
		end
		]]
		
		-- Destroy instantly
		if brainrot and brainrot.Parent then
			brainrot:Destroy()
		end
	end)
	
	-- Clean up tracking and AI when destroyed
	brainrot.Destroying:Connect(function()
		if mobAI then
			mobAI:Destroy()
		end
		
		if mobDisplay then
			mobDisplay:Destroy()
		end
		
		local index = table.find(group.spawnedBrainrots, brainrot)
		if index then
			table.remove(group.spawnedBrainrots, index)
		end
	end)
	
	log("[BrainrotSpawner] Spawned brainrot in zone: " .. group.zoneName .. " (" .. #group.spawnedBrainrots .. "/" .. maxPerZone .. ")")
end

local function addPartToZoneGroup(part: BasePart, zoneName: string)
	local group = zoneGroups[zoneName]
	
	if not group then
		group = {
			zoneName = zoneName,
			parts = {},
			spawnedBrainrots = {},
			zoneObjects = {},
		}
		zoneGroups[zoneName] = group
	end
	
	table.insert(group.parts, part)
	
	-- Create ZonePlus object for this part (if we want to use Zone events later)
	local zone = Zone.new(part)
	table.insert(group.zoneObjects, zone)
	
	log("[BrainrotSpawner] Added part " .. part.Name .. " to zone group: " .. zoneName)
end

local function setupZonesForTag(tagName: string)
	local taggedParts = CollectionService:GetTagged(tagName)
	
	for _, part in taggedParts do
		if part:IsA("BasePart") then
			addPartToZoneGroup(part, tagName)
		end
	end
	
	-- Listen for new parts with this tag
	CollectionService:GetInstanceAddedSignal(tagName):Connect(function(part)
		if part:IsA("BasePart") then
			addPartToZoneGroup(part, tagName)
		end
	end)
end

local function startSpawnLoop()
	task.spawn(function()
		while true do
			local spawnInterval = getSpawnInterval()
			task.wait(spawnInterval)
			
			for _, group in zoneGroups do
				spawnBrainrot(group)
			end
		end
	end)
end

function BrainrotSpawner.Init()
	
	-- Get all zone folder names and set up tags for each
	for _, zoneFolder in zonesConfig:GetChildren() do
		if zoneFolder:IsA("Folder") then
			local zoneName = zoneFolder.Name
			setupZonesForTag(zoneName)
			log("[BrainrotSpawner] Registered zone type: " .. zoneName)
		end
	end

	
	-- Start the spawn loop
	startSpawnLoop()
	
	log("[BrainrotSpawner] Initialized!")
end

-- Public API for external control
function BrainrotSpawner.GetZoneGroups(): { [string]: ZoneGroup }
	return zoneGroups
end

function BrainrotSpawner.ClearZone(zoneName: string)
	local group = zoneGroups[zoneName]
	if group then
		for _, brainrot in group.spawnedBrainrots do
			brainrot:Destroy()
		end
		group.spawnedBrainrots = {}
		log("[BrainrotSpawner] Cleared zone group: " .. zoneName)
	end
end

function BrainrotSpawner.ClearAll()
	for _, group in zoneGroups do
		for _, brainrot in group.spawnedBrainrots do
			brainrot:Destroy()
		end
		group.spawnedBrainrots = {}
	end
	log("[BrainrotSpawner] Cleared all zones")
end

--[[
	Spawns a specific brainrot by name in a zone with optional mutation.
	Used by admin command to force-spawn mobs.
	@param zoneName The zone name to spawn in
	@param mobName The mob template name to spawn
	@param mutationName Optional mutation to apply
	@return boolean success
]]
function BrainrotSpawner.SpawnBrainrotWithMutation(zoneName: string, mobName: string, mutationName: string?): boolean
	local group = zoneGroups[zoneName]
	if not group then
		warn("[BrainrotSpawner] Zone not found: " .. zoneName)
		return false
	end
	
	-- Find the mob template
	local zoneFolder = zonesConfig:FindFirstChild(zoneName)
	if not zoneFolder then
		warn("[BrainrotSpawner] Zone folder not found: " .. zoneName)
		return false
	end
	
	local template: Model? = nil
	for _, child in zoneFolder:GetChildren() do
		if child:IsA("Model") and child.Name == mobName then
			template = child
			break
		end
	end
	
	if not template then
		warn("[BrainrotSpawner] Mob not found in zone: " .. mobName)
		return false
	end
	
	-- Clone the mob
	local brainrot = template:Clone()
	
	-- Apply mutation if specified
	if mutationName then
		local mutationData = Mutations.GetMutation(mutationName)
		if mutationData then
			brainrot:SetAttribute("Mutation", mutationName)
			
			-- Apply HP multiplier
			local baseMaxHealth = brainrot:GetAttribute("MaxHealth") or 100
			local newMaxHealth = baseMaxHealth * mutationData.MultiplierModifier
			brainrot:SetAttribute("MaxHealth", newMaxHealth)
			brainrot:SetAttribute("Health", newMaxHealth)
			
			log(string.format("[BrainrotSpawner] Applied mutation %s to %s (HP: %d -> %d)", 
				mutationName, mobName, baseMaxHealth, newMaxHealth))
		else
			warn("[BrainrotSpawner] Unknown mutation: " .. mutationName)
		end
	end
	
	-- Pick a random part from the group for spawn position
	if #group.parts == 0 then
		brainrot:Destroy()
		return false
	end
	local randomPart = group.parts[math.random(1, #group.parts)]
	
	-- Get spawn position
	local spawnPos = getRandomSpawnPosition(randomPart)
	if not spawnPos then
		brainrot:Destroy()
		return false
	end
	
	-- Position the brainrot
	local primaryPart = brainrot.PrimaryPart or brainrot:FindFirstChildWhichIsA("BasePart")
	if primaryPart then
		brainrot:PivotTo(CFrame.new(spawnPos))
	end
	
	-- Track the spawned brainrot
	table.insert(group.spawnedBrainrots, brainrot)
	
	-- Parent to Workspace.Zones.{ZoneName} folder
	local zonesFolder = workspace:FindFirstChild("Zones")
	if zonesFolder then
		local zoneWorkspaceFolder = zonesFolder:FindFirstChild(group.zoneName)
		if zoneWorkspaceFolder then
			brainrot.Parent = zoneWorkspaceFolder
		else
			brainrot.Parent = workspace
		end
	else
		brainrot.Parent = workspace
	end
	
	-- Setup Health and Death logic (same as spawnBrainrot)
	local maxHealthAttr = brainrot:GetAttribute("MaxHealth")
	local maxHealth: number = if typeof(maxHealthAttr) == "number" then maxHealthAttr else 100
	local health = Health.new(brainrot, maxHealth)
	
	-- Setup AI
	local mobAI = MobAI.new(brainrot)
	if mobAI then
		mobAI:Start()
	end
	
	-- Setup Mob Display (UI)
	local mobDisplay = MobDisplay.new(brainrot)
	
	-- Death and cleanup handlers (same as spawnBrainrot)
	health.Died:Connect(function(instigator)
		local healthConfig = config:FindFirstChild("Health")
		local loggingEnabled = healthConfig and healthConfig:GetAttribute("Logging") == true
		
		if instigator then
			local playerData = PlayerManager.GetPlayerData(instigator)
			if playerData then
				local xpRewardAttr = brainrot:GetAttribute("BaseXPReward")
				local xpReward: number = if typeof(xpRewardAttr) == "number" then xpRewardAttr else 10
				playerData:AddExperience(xpReward)
				
				local goldRewardAttr = brainrot:GetAttribute("BaseGoldReward")
				local goldReward: number = if typeof(goldRewardAttr) == "number" then goldRewardAttr else 5
				playerData:AddGold(goldReward)
				
				if primaryPart then
					local fxPos = primaryPart.Position
					local xpImage = config.Effects.FX.XP.Image
					local goldImage = config.Effects.FX.Coin.Image
					
					Packets.lootDropFX.sendTo({
						posX = fxPos.X - 0.5, posY = fxPos.Y + 1, posZ = fxPos.Z,
						config = { image = xpImage, color = { 66, 135, 245 }, trailEnabled = true, trailColor = { 100, 160, 255 }, count = math.floor(xpReward / 10) },
					}, instigator)
					
					Packets.lootDropFX.sendTo({
						posX = fxPos.X + 0.5, posY = fxPos.Y + 1, posZ = fxPos.Z,
						config = { image = goldImage, color = { 255, 215, 0 }, trailEnabled = true, trailColor = { 255, 200, 50 }, count = math.floor(goldReward / 100) },
					}, instigator)
				end
			end
		end
		
		if mobAI then mobAI:Stop() end
		
		for _, descendant in brainrot:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Transparency = 1
				descendant.CanCollide = false
			elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
				descendant.Transparency = 1
			end
		end
		
		if brainrot and brainrot.Parent then
			brainrot:Destroy()
		end
	end)
	
	brainrot.Destroying:Connect(function()
		if mobAI then mobAI:Destroy() end
		if mobDisplay then mobDisplay:Destroy() end
		local index = table.find(group.spawnedBrainrots, brainrot)
		if index then table.remove(group.spawnedBrainrots, index) end
	end)
	
	log(string.format("[BrainrotSpawner] Admin spawned %s in %s", brainrot.Name, zoneName))
	return true
end

return BrainrotSpawner

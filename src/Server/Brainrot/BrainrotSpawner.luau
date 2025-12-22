--!strict
-- BrainrotSpawner: Handles spawning brainrots in tagged zones
-- Zones are tagged parts (e.g., "Forest"), config is in ReplicatedStorage.Config.Brainrots

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Packages = Rojo:WaitForChild("Packages")
local Shared = Rojo:WaitForChild("Shared")
local Server = ServerScriptService:WaitForChild("Rojo"):WaitForChild("Server")
local Zone = require(Packages:WaitForChild("zoneplus"))
local Health = require(Shared:WaitForChild("Health"))
local MobAI = require(Server:WaitForChild("Brainrot"):WaitForChild("MobAI"))
local MobDisplay = require(Server:WaitForChild("Brainrot"):WaitForChild("MobDisplay"))

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
local config: Folder? = nil
local zonesConfig: Folder? = nil

-- Default values (overridden by attributes)
local DEFAULT_SPAWN_INTERVAL = 5
local DEFAULT_MAX_PER_ZONE = 10

local function isLoggingEnabled(): boolean
	local cfg = config or ReplicatedStorage:FindFirstChild("Config") and ReplicatedStorage.Config:FindFirstChild("Brainrots")
	if cfg then
		return cfg:GetAttribute("Logging") == true
	end
	return false
end

local function log(message: string)
	if isLoggingEnabled() then
		print(message)
	end
end

local function getConfig(): Folder?
	if config then return config end
	
	local configFolder = ReplicatedStorage:FindFirstChild("Config")
	if not configFolder then
		warn("[BrainrotSpawner] Config folder not found in ReplicatedStorage")
		return nil
	end
	
	config = configFolder:FindFirstChild("Brainrots") :: Folder?
	if not config then
		warn("[BrainrotSpawner] Brainrots config not found in Config folder")
		return nil
	end
	
	zonesConfig = config:FindFirstChild("Zones") :: Folder?
	if not zonesConfig then
		warn("[BrainrotSpawner] Zones folder not found in Brainrots config")
	end
	
	return config
end

local function getSpawnInterval(): number
	local cfg = getConfig()
	if cfg then
		local interval = cfg:GetAttribute("SpawnInterval")
		if typeof(interval) == "number" then
			return interval
		end
	end
	return DEFAULT_SPAWN_INTERVAL
end

local function getMaxPerZone(): number
	local cfg = getConfig()
	if cfg then
		local max = cfg:GetAttribute("MaxPerZone")
		if typeof(max) == "number" then
			return max
		end
	end
	return DEFAULT_MAX_PER_ZONE
end

local function getZoneModels(zoneName: string): { Model }
	if not zonesConfig then return {} end
	
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
	
	-- Pick random model
	local template = models[math.random(1, #models)]
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

	health.Died:Connect(function()
		-- Stop AI when mob dies
		if mobAI then
			mobAI:Stop()
		end
		
		-- Use VfxInstance for positioning if it exists, otherwise PrimaryPart
		-- Sourced from mob.VFX.Death
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
					
					vfxPart.Parent = workspace
					
					-- Clone and attach death VFX to the separate part
					local vfxClone = deathVFX:Clone()
					vfxClone.Parent = vfxPart
					
					-- Emit all particle emitters
					task.wait(0.1)
					local emittersFound = 0
					for _, Particles in vfxClone:GetDescendants() do
						if Particles:IsA("ParticleEmitter") then
							emittersFound += 1
							Particles:Emit(Particles:GetAttribute("EmitCount") :: number or 1)
						end
					end
					
					-- log("[BrainrotSpawner] Emitted VFX for " .. brainrot.Name .. " (Emitters: " .. emittersFound .. ")")
					
					-- Clean up VFX part after particles finish
					-- If logging is enabled, keep the part for inspection
					if not isLoggingEnabled() then
						task.delay(3, function()
							vfxPart:Destroy()
						end)
					else
						-- Make visible if keeping for debug
						vfxPart.Transparency = 0.5
						vfxPart.Color = Color3.new(1, 0, 0) -- Red debug visualization
						vfxPart.Material = Enum.Material.Neon
						log("[BrainrotSpawner] Keeping dead VFX part for debug: " .. vfxPart:GetFullName())
					end
				end
			end
		end
		
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
	-- Initialize config
	local cfg = getConfig()
	if not cfg then
		warn("[BrainrotSpawner] Failed to initialize - config not found")
		return
	end
	
	-- Get all zone folder names and set up tags for each
	if zonesConfig then
		for _, zoneFolder in zonesConfig:GetChildren() do
			if zoneFolder:IsA("Folder") then
				local zoneName = zoneFolder.Name
				setupZonesForTag(zoneName)
				log("[BrainrotSpawner] Registered zone type: " .. zoneName)
			end
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

return BrainrotSpawner

--!strict
-- BrainrotSpawner: Handles spawning brainrots in tagged zones
-- Zones are tagged parts (e.g., "Forest"), config is in ReplicatedStorage.Config.Brainrots

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Packages = Rojo:WaitForChild("Packages")
local Shared = Rojo:WaitForChild("Shared")
local Zone = require(Packages:WaitForChild("zoneplus"))
local Health = require(Shared:WaitForChild("Health"))

local BrainrotSpawner = {}

-- Types
type ZoneData = {
	zone: any,
	zoneName: string,
	spawnedBrainrots: { Model },
	part: BasePart,
}

-- State
local zones: { ZoneData } = {}
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

local function getRandomSpawnPosition(zoneData: ZoneData): Vector3?
	local part = zoneData.part
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

local function spawnBrainrot(zoneData: ZoneData)
	local models = getZoneModels(zoneData.zoneName)
	if #models == 0 then
		return
	end
	
	-- Check max per zone
	local maxPerZone = getMaxPerZone()
	if #zoneData.spawnedBrainrots >= maxPerZone then
		return
	end
	
	-- Pick random model
	local template = models[math.random(1, #models)]
	local brainrot = template:Clone()
	
	-- Get spawn position
	local spawnPos = getRandomSpawnPosition(zoneData)
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
	table.insert(zoneData.spawnedBrainrots, brainrot)
	
	-- Parent to Workspace.Zones.{ZoneName} folder
	local zonesFolder = workspace:FindFirstChild("Zones")
	if zonesFolder then
		local zoneFolder = zonesFolder:FindFirstChild(zoneData.zoneName)
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
	
	health.Died:Connect(function()
		-- Optional: Play death animation here if you have one
		-- For now, just destroy after a short delay (like ragdoll time)
		task.delay(3, function()
			if brainrot and brainrot.Parent then
				brainrot:Destroy()
			end
		end)
	end)
	
	-- Clean up tracking when destroyed
	brainrot.Destroying:Connect(function()
		local index = table.find(zoneData.spawnedBrainrots, brainrot)
		if index then
			table.remove(zoneData.spawnedBrainrots, index)
		end
	end)
	
	log("[BrainrotSpawner] Spawned brainrot in zone: " .. zoneData.zoneName .. " (" .. #zoneData.spawnedBrainrots .. "/" .. maxPerZone .. ")")
end

local function createZone(part: BasePart, zoneName: string)
	local zone = Zone.new(part)
	
	local zoneData: ZoneData = {
		zone = zone,
		zoneName = zoneName,
		spawnedBrainrots = {},
		part = part,
	}
	
	table.insert(zones, zoneData)
	
	log("[BrainrotSpawner] Created zone: " .. zoneName .. " from part: " .. part.Name)
end

local function setupZonesForTag(tagName: string)
	local taggedParts = CollectionService:GetTagged(tagName)
	
	for _, part in taggedParts do
		if part:IsA("BasePart") then
			createZone(part, tagName)
		end
	end
	
	-- Listen for new parts with this tag
	CollectionService:GetInstanceAddedSignal(tagName):Connect(function(part)
		if part:IsA("BasePart") then
			createZone(part, tagName)
		end
	end)
end

local function startSpawnLoop()
	task.spawn(function()
		while true do
			local spawnInterval = getSpawnInterval()
			task.wait(spawnInterval)
			
			for _, zoneData in zones do
				spawnBrainrot(zoneData)
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
function BrainrotSpawner.GetZones(): { ZoneData }
	return zones
end

function BrainrotSpawner.ClearZone(zoneName: string)
	for _, zoneData in zones do
		if zoneData.zoneName == zoneName then
			for _, brainrot in zoneData.spawnedBrainrots do
				brainrot:Destroy()
			end
			zoneData.spawnedBrainrots = {}
			log("[BrainrotSpawner] Cleared zone: " .. zoneName)
		end
	end
end

function BrainrotSpawner.ClearAll()
	for _, zoneData in zones do
		for _, brainrot in zoneData.spawnedBrainrots do
			brainrot:Destroy()
		end
		zoneData.spawnedBrainrots = {}
	end
	log("[BrainrotSpawner] Cleared all zones")
end

return BrainrotSpawner

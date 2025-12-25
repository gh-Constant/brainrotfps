--!strict
-- GrenadeService: Handles server-side grenade logic (launching, exploding on contact, affecting mobs)

local _Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")
local Packets = require(Shared:WaitForChild("Packets"))
local _Inventory = require(Shared:WaitForChild("Inventory")) -- Prefixed to silence unused warning
local BrainrotSpawner = require(ServerScriptService.Rojo.Server.Brainrot.BrainrotSpawner)
local InventoryManager = require(ServerScriptService.Rojo.Server.Inventory)

local GrenadeService = {}

-- Track active grenades to prevent double explosions
local activeGrenades: {[BasePart]: boolean} = {}

function GrenadeService.Init()
	Packets.throwGrenade.listen(function(data, player)
		if not player then return end
		local origin = Vector3.new(data.originX, data.originY, data.originZ)
		local direction = Vector3.new(data.dirX, data.dirY, data.dirZ)
		local strength = data.strength
		
		GrenadeService.Launch(player, origin, direction, strength)
	end)
	
	print("[GrenadeService] Initialized and listening for throws")
end

function GrenadeService.Launch(player: Player, origin: Vector3, direction: Vector3, strength: number)
	local character = player.Character
	if not character then return end
	
	-- Find the grenade tool and its handle
	local tool = character:FindFirstChildWhichIsA("Tool")
	if not tool or not tool:GetAttribute("IsGrenade") then return end
	
	local handle = tool:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then return end
	
	-- Get inventory item info from the tool
	local inventoryItemId = tool:GetAttribute("InventoryItemId") :: string?
	local isStackable = tool:GetAttribute("IsStackable") :: boolean?
	local _stackTemplateId = tool:GetAttribute("StackTemplateId") :: string? -- Prefixed to silence unused warning
	local currentStackCount = (tool:GetAttribute("StackCount") :: number?) or 1
	
	-- Clone the handle as the projectile
	local grenade = handle:Clone()
	grenade.Name = "Grenade_" .. player.Name
	grenade.Anchored = false
	grenade.CanCollide = false -- Start with collision OFF to prevent immediate self-collision
	grenade.CanTouch = true -- Explicitly enable touch events
	grenade.CanQuery = true -- Allow raycasts to hit it
	grenade.CFrame = CFrame.new(origin)
	grenade.Parent = workspace
	
	-- Track this grenade
	activeGrenades[grenade] = true
	
	-- Add visual trail
	local att0 = Instance.new("Attachment", grenade)
	att0.Position = Vector3.new(0, 0.2, 0)
	local att1 = Instance.new("Attachment", grenade)
	att1.Position = Vector3.new(0, -0.2, 0)
	
	local trail = Instance.new("Trail")
	trail.Attachment0 = att0
	trail.Attachment1 = att1
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 50, 50))
	trail.Enabled = true
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Lifetime = 0.4
	trail.Parent = grenade
	
	-- Launch it
	grenade.AssemblyLinearVelocity = direction * strength
	
	-- === SECURITY: VALIDATE AND CONSUME GRENADE ===
	
	-- CRITICAL: Block tools without inventory tracking (potential exploit)
	if not inventoryItemId then
		warn(string.format("[GrenadeService] BLOCKED: %s tried to throw grenade without InventoryItemId - potential exploit", player.Name))
		grenade:Destroy()
		activeGrenades[grenade] = nil
		return
	end
	
	-- CRITICAL: Verify item exists in player's inventory before consuming
	local inventory = InventoryManager.GetInventory(player)
	if not inventory then
		warn(string.format("[GrenadeService] BLOCKED: %s has no inventory loaded", player.Name))
		grenade:Destroy()
		activeGrenades[grenade] = nil
		return
	end
	
	local foundInInventory = false
	for _, invItem in ipairs(inventory.Items) do
		if invItem.Id == inventoryItemId then
			foundInInventory = true
			break
		end
	end
	
	if not foundInInventory then
		warn(string.format("[GrenadeService] BLOCKED: %s tried to use item %s not in their inventory - potential exploit", 
			player.Name, inventoryItemId:sub(1, 8)))
		grenade:Destroy()
		activeGrenades[grenade] = nil
		return
	end
	
	-- Remove one item from inventory
	local removed = InventoryManager.RemoveItem(player, inventoryItemId)
	
	if not removed then
		warn(string.format("[GrenadeService] BLOCKED: Failed to consume grenade %s - removal failed", inventoryItemId:sub(1, 8)))
		grenade:Destroy()
		activeGrenades[grenade] = nil
		return
	end
	
	print(string.format("[GrenadeService] Consumed grenade %s from %s's inventory", 
		inventoryItemId:sub(1, 8), player.Name))
	
	-- Check if there are more grenades in the stack
	if isStackable and currentStackCount > 1 then
		print(string.format("[GrenadeService] %d grenades remaining in stack", currentStackCount - 1))
	elseif currentStackCount <= 1 then
		print("[GrenadeService] Last grenade used, tool removed")
	end
	
	-- Track if already exploded (declared early so task.delay can reference it)
	local hasExploded = false
	
	-- Enable collision after a short delay (lets grenade move away from thrower first)
	task.delay(0.1, function()
		if grenade and grenade.Parent and not hasExploded then
			grenade.CanCollide = true
		end
	end)
	
	local function doExplode()
		if hasExploded then return end
		hasExploded = true
		activeGrenades[grenade] = nil
		GrenadeService.Explode(grenade, player)
	end
	
	-- Explode on contact with anything (except the player who threw it)
	local touchConnection: RBXScriptConnection
	touchConnection = grenade.Touched:Connect(function(hit)
		if hasExploded then return end
		
		-- Ignore hits with the thrower's character
		if character and hit:IsDescendantOf(character) then return end
		
		-- Ignore other grenades
		if hit.Name:match("^Grenade_") then return end
		
		-- Ignore parts with CanTouch = false (they shouldn't trigger Touched anyway, but safety check)
		if hit:IsA("BasePart") and hit.CanTouch == false then return end
		
		-- Explode immediately!
		touchConnection:Disconnect()
		doExplode()
	end)
	
	-- Also use Heartbeat raycast for instant detection (backup)
	local RunService = game:GetService("RunService")
	local lastPosition = origin
	local heartbeatConnection: RBXScriptConnection
	
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {grenade, character}
	
	heartbeatConnection = RunService.Heartbeat:Connect(function()
		if hasExploded or not grenade.Parent then
			heartbeatConnection:Disconnect()
			return
		end
		
		local currentPos = grenade.Position
		local dir = currentPos - lastPosition
		
		if dir.Magnitude > 0.1 then
			local result = workspace:Raycast(lastPosition, dir, rayParams)
			if result then
				heartbeatConnection:Disconnect()
				touchConnection:Disconnect()
				doExplode()
				return
			end
		end
		
		lastPosition = currentPos
	end)
	
	-- Safety timeout: explode after 5 seconds if somehow nothing was touched
	task.delay(5, function()
		if not hasExploded and grenade and grenade.Parent then
			heartbeatConnection:Disconnect()
			touchConnection:Disconnect()
			doExplode()
		end
	end)
end

function GrenadeService.Explode(grenade: BasePart, instigator: Player)
	local pos = grenade.Position
	
	-- Explosion visuals
	local explosion = Instance.new("Explosion")
	explosion.Position = pos
	explosion.BlastRadius = 15
	explosion.BlastPressure = 0 -- We handle damage manually
	explosion.Parent = workspace
	
	-- Cleanup grenade
	grenade:Destroy()
	
	-- Affect mobs spawned by BrainrotSpawner
	print(string.format("[Grenade] 💥 Explosion at %s by %s", tostring(pos), instigator.Name))
	
	local affectedMobs = {}
	local zoneGroups = BrainrotSpawner.GetZoneGroups()
	
	for _, group in zoneGroups do
		for _, mob in group.spawnedBrainrots do
			if mob and mob.Parent then
				local primaryPart = mob.PrimaryPart or mob:FindFirstChildWhichIsA("BasePart")
				if primaryPart then
					local distance = (primaryPart.Position - pos).Magnitude
					if distance <= 15 then
						table.insert(affectedMobs, mob.Name)
					end
				end
			end
		end
	end
	
	if #affectedMobs > 0 then
		print("[Grenade] Mobs affected: " .. table.concat(affectedMobs, ", "))
	else
		print("[Grenade] No mobs in blast radius.")
	end
end

return GrenadeService

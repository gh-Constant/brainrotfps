--!strict
-- SafezoneManager: Handles safezone detection and godmode using ZonePlus

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Packages = Rojo:WaitForChild("Packages")
local Zone = require(Packages:WaitForChild("zoneplus"))

local SafezoneManager = {}

local SAFEZONE_TAG = "Safezone"
local zones: { any } = {}
local playersInSafezone: { [Player]: boolean } = {}

local function onPlayerEntered(player: Player)
	if playersInSafezone[player] then return end
	
	playersInSafezone[player] = true
	player:SetAttribute("InSafezone", true)
	
	print("[Safezone] " .. player.Name .. " entered safezone")
end

local function onPlayerExited(player: Player)
	if not playersInSafezone[player] then return end
	
	playersInSafezone[player] = nil
	player:SetAttribute("InSafezone", false)
	
	print("[Safezone] " .. player.Name .. " exited safezone")
end

local function createZoneFromPart(part: BasePart)
	local zone = Zone.new(part)
	table.insert(zones, zone)
	
	zone.playerEntered:Connect(function(player: Player)
		onPlayerEntered(player)
	end)
	
	zone.playerExited:Connect(function(player: Player)
		onPlayerExited(player)
	end)
	
	print("[Safezone] Created zone for part: " .. part.Name)
end

local function setupExistingParts()
	local safeParts = CollectionService:GetTagged(SAFEZONE_TAG)
	for _, part in safeParts do
		if part:IsA("BasePart") then
			createZoneFromPart(part)
		end
	end
end

local function onPartTagged(part: Instance)
	if part:IsA("BasePart") then
		createZoneFromPart(part)
	end
end

function SafezoneManager.Init()
	-- Setup existing tagged parts
	setupExistingParts()
	
	-- Listen for newly tagged parts
	CollectionService:GetInstanceAddedSignal(SAFEZONE_TAG):Connect(onPartTagged)
	
	-- Clean up when players leave
	Players.PlayerRemoving:Connect(function(player)
		playersInSafezone[player] = nil
	end)
	
	print("[Safezone] SafezoneManager initialized!")
end

function SafezoneManager.IsInSafezone(player: Player): boolean
	return playersInSafezone[player] == true
end

return SafezoneManager

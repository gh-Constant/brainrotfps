--!strict
--[[
	Packets
	ByteNet packet definitions for all network communication.
	
	This centralizes network structure using ByteNet for optimized,
	buffer-based networking instead of traditional RemoteEvents.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ByteNet = require(ReplicatedStorage.Rojo.Packages.bytenet)

return ByteNet.defineNamespace("game", function()
	return {
		-- Broadcast message packet (Server -> Client)
		-- Used for admin broadcast messages with color and creator info
		broadcast = ByteNet.definePacket({
			value = ByteNet.struct({
				message = ByteNet.string,
				creator = ByteNet.string,
				color = ByteNet.string,
			}),
			reliabilityType = "reliable",
		}),
		
		-- Player death notification packet (Server -> Client)
		-- Triggers death screen, sound, and VFX on client
		playerDeath = ByteNet.definePacket({
			value = ByteNet.struct({}), -- No data needed, just a notification
			reliabilityType = "reliable",
		}),
		
		-- Player respawn request packet (Client -> Server)
		-- Sent when player clicks respawn button on death screen
		playerRespawn = ByteNet.definePacket({
			value = ByteNet.struct({}), -- No data needed, just a notification
			reliabilityType = "reliable",
		}),
		
		-- PvP toggle packet (Client -> Server)
		-- Sent when player toggles PvP mode via UI
		pvpToggle = ByteNet.definePacket({
			value = ByteNet.struct({
				enabled = ByteNet.bool,
			}),
			reliabilityType = "reliable",
		}),
		
		-- Loot drop FX packet (Server -> Client)
		-- Triggers loot drop visual effect when mob dies
		lootDropFX = ByteNet.definePacket({
			value = ByteNet.struct({
				posX = ByteNet.float32,
				posY = ByteNet.float32,
				posZ = ByteNet.float32,
				config = ByteNet.struct({
					image = ByteNet.optional(ByteNet.string),
					color = ByteNet.optional(ByteNet.array(ByteNet.uint8)), -- RGB array
					size = ByteNet.optional(ByteNet.array(ByteNet.float32)), -- {scaleX, offsetX, scaleY, offsetY}
					trailEnabled = ByteNet.optional(ByteNet.bool),
					trailColor = ByteNet.optional(ByteNet.array(ByteNet.uint8)), -- RGB array
					floatDuration = ByteNet.optional(ByteNet.float32),
					floatHeight = ByteNet.optional(ByteNet.float32),
					text = ByteNet.optional(ByteNet.string),
					textColor = ByteNet.optional(ByteNet.array(ByteNet.uint8)), -- RGB array
					count = ByteNet.optional(ByteNet.uint8), -- Number of coins to spawn
				}),
			}),
			reliabilityType = "reliable",
		}),
	}
end)

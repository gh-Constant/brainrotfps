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
	}
end)

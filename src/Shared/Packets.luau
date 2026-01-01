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
                    customColor = ByteNet.optional(ByteNet.string),
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
		
		-- Damage indicator packet (Server -> Client)
		-- Shows damage number at hit position for the shooter
		damageIndicator = ByteNet.definePacket({
			value = ByteNet.struct({
				posX = ByteNet.float32,
				posY = ByteNet.float32,
				posZ = ByteNet.float32,
				damage = ByteNet.float64, -- float64 to support large damage values (3M+)
				didDamage = ByteNet.bool,
				targetId = ByteNet.optional(ByteNet.inst), -- Reference to hit target model for highlight
			}),
			reliabilityType = "unreliable", -- Fast, non-critical
		}),
		
		-- Inventory sync packet (Server -> Client)
		-- Full inventory sync when player joins or major changes
		-- Inventory sync packet (Server -> Client)
		-- Full inventory sync when player joins or major changes
		-- [OPTIMIZED] Groups stackable items to save bandwidth
		inventorySync = ByteNet.definePacket({
			value = ByteNet.struct({
				groupedItems = ByteNet.array(ByteNet.struct({
					templateId = ByteNet.string,
					itemType = ByteNet.string,
					rarity = ByteNet.string,
					metadata = ByteNet.optional(ByteNet.struct({
                        CustomColor = ByteNet.optional(ByteNet.string),
                        Mutations = ByteNet.optional(ByteNet.map(ByteNet.string, ByteNet.float64)), -- MutationName -> Count
                    })),
					-- List of individual instances for this stack group
                    instances = ByteNet.array(ByteNet.struct({
                        id = ByteNet.string,
                    })),
				})),
				toolbarSlots = ByteNet.map(ByteNet.uint8, ByteNet.string), -- Slot -> ItemId
			}),
			reliabilityType = "reliable",
		}),

		-- Toolbar update packet (Server -> Client)
		-- Lightweight update for toolbar changes only
		toolbarUpdate = ByteNet.definePacket({
			value = ByteNet.struct({
				toolbarSlots = ByteNet.map(ByteNet.uint8, ByteNet.string), -- Slot -> ItemId
			}),
			reliabilityType = "reliable",
		}),
		
		-- Inventory update packet (Server -> Client)
		-- Partial update for adding/removing single items
		inventoryUpdate = ByteNet.definePacket({
			value = ByteNet.struct({
				action = ByteNet.string, -- "Add" | "Remove"
				item = ByteNet.struct({
					id = ByteNet.string,
					templateId = ByteNet.string,
					itemType = ByteNet.string,
					rarity = ByteNet.string,
                    metadata = ByteNet.optional(ByteNet.struct({
                        CustomColor = ByteNet.optional(ByteNet.string),
                        Mutations = ByteNet.optional(ByteNet.map(ByteNet.string, ByteNet.float64)), -- MutationName -> Count
                    })),
				}),
			}),
			reliabilityType = "reliable",
		}),

		-- Batch Inventory update packet (Server -> Client)
		-- [OPTIMIZED] Adds multiple items in a single packet to prevent freezing
		inventoryBatchUpdate = ByteNet.definePacket({
			value = ByteNet.struct({
				action = ByteNet.string, -- "Add" | "Remove"
				items = ByteNet.array(ByteNet.struct({
					id = ByteNet.string,
					templateId = ByteNet.string,
					itemType = ByteNet.string,
					rarity = ByteNet.string,
                    maybeDuped = ByteNet.bool,
                    metadata = ByteNet.optional(ByteNet.struct({
                        CustomColor = ByteNet.optional(ByteNet.string),
                        Mutations = ByteNet.optional(ByteNet.map(ByteNet.string, ByteNet.float64)), -- MutationName -> Count
                    })),
                })),
			}),
			reliabilityType = "reliable",
		}),
		
		-- Inventory action packet (Client -> Server)
		-- Player actions like assigning toolbar slots
		inventoryAction = ByteNet.definePacket({
			value = ByteNet.struct({
				action = ByteNet.uint8, -- Constants.ActionType enum
				itemId = ByteNet.optional(ByteNet.string),
				slot = ByteNet.optional(ByteNet.uint8),
				slot2 = ByteNet.optional(ByteNet.uint8), -- For swap operations
			}),
			reliabilityType = "reliable",
		}),

		-- Request Inventory Packet (Client -> Server)
		-- Used to request a full sync when client UI is ready
		requestInventory = ByteNet.definePacket({
			value = ByteNet.struct({}),
			reliabilityType = "reliable",
		}),


		-- Throw grenade packet (Client -> Server)
		throwGrenade = ByteNet.definePacket({
			value = ByteNet.struct({
				originX = ByteNet.float32,
				originY = ByteNet.float32,
				originZ = ByteNet.float32,
				dirX = ByteNet.float32,
				dirY = ByteNet.float32,
				dirZ = ByteNet.float32,
				strength = ByteNet.float32,
			}),
			reliabilityType = "reliable",
		}),

		-- Request Index Data (Client -> Server)
		requestIndexData = ByteNet.definePacket({
			value = ByteNet.struct({}),
			reliabilityType = "reliable",
		}),

		-- Index Data Response (Server -> Client)
		indexData = ByteNet.definePacket({
			value = ByteNet.struct({
				brainrots = ByteNet.array(ByteNet.string),
				weapons = ByteNet.array(ByteNet.string),
			}),
			reliabilityType = "reliable",
		}),

		-- ============================================
		-- LEADERBOARD PACKETS
		-- ============================================

		-- Request leaderboard page (Client -> Server)
		requestLeaderboard = ByteNet.definePacket({
			value = ByteNet.struct({
				valueName = ByteNet.string,
				period = ByteNet.string, -- "Daily" | "Weekly" | "Monthly" | "AllTime"
				page = ByteNet.uint8,
			}),
			reliabilityType = "reliable",
		}),

		-- Leaderboard data response (Server -> Client)
		leaderboardData = ByteNet.definePacket({
			value = ByteNet.struct({
				valueName = ByteNet.string,
				period = ByteNet.string,
				page = ByteNet.uint8,
				totalPages = ByteNet.uint8,
				entries = ByteNet.array(ByteNet.struct({
					rank = ByteNet.uint16,
					userId = ByteNet.float64, -- float64 for userId (no int64 in ByteNet)
					displayName = ByteNet.string,
                    username = ByteNet.string,
					value = ByteNet.float64, -- float64 for large values
				})),
			}),
			reliabilityType = "reliable",
		}),
	}
end)

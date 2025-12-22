--[[
	Broadcast Server Implementation
	Sends a message to all players across all servers using MessagingService.
]]

local TextService = game:GetService("TextService")
local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BROADCAST_TOPIC = "AdminBroadcast"

-- Import ByteNet packets
local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")
local packets = require(Shared:WaitForChild("Packets"))

-- Show message to all players in this server
local function showToLocalPlayers(message: string, creatorName: string, color: string)
	packets.broadcast.sendToAll({
		message = message,
		creator = creatorName,
		color = color,
	})
end

-- Subscribe to cross-server messages
local subscribed = false
local function ensureSubscribed()
	if subscribed then return end
	subscribed = true
	
	pcall(function()
		MessagingService:SubscribeAsync(BROADCAST_TOPIC, function(data)
			local messageData = data.Data
			if messageData and messageData.message and messageData.creator then
				showToLocalPlayers(messageData.message, messageData.creator, messageData.color or "white")
			end
		end)
	end)
end

-- Ensure we're subscribed on load
ensureSubscribed()

return function(context, text, creatorName, color)
	-- Filter the text for safety
	local success, filterResult = pcall(function()
		return TextService:FilterStringAsync(text, context.Executor.UserId, Enum.TextFilterContext.PublicChat)
	end)
	
	local filteredText = text
	if success and filterResult then
		local filterSuccess, filtered = pcall(function()
			return filterResult:GetNonChatStringForBroadcastAsync()
		end)
		if filterSuccess and filtered then
			filteredText = filtered
		end
	end
	
	-- Default color
	color = color or "white"
	
	-- Publish to all servers via MessagingService
	local publishSuccess, publishError = pcall(function()
		MessagingService:PublishAsync(BROADCAST_TOPIC, {
			message = filteredText,
			creator = creatorName,
			color = color,
		})
	end)
	
	if not publishSuccess then
		-- Fallback: at least show to local server
		warn("[Broadcast] MessagingService failed:", publishError)
		showToLocalPlayers(filteredText, creatorName, color)
		return "Broadcast sent to this server only (cross-server failed)."
	end
	
	return "Broadcast sent to all servers!"
end

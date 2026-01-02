local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packets = require(script.Parent.Packets)

local MessageSystem = {}
MessageSystem.__index = MessageSystem

-- Constants
local MESSAGES_FOLDER = ReplicatedStorage:WaitForChild("Messages")

-- types
type MessageType = "Win" | "Error" | "Warn" | "Success"

local lastMessages = {}
local SPAM_COOLDOWN = 2

-- Function to send message
function MessageSystem.Send(playerOrType: Player | MessageType, typeOrMessage: MessageType | string, messageOrNil: string?)
	if RunService:IsServer() then
		-- Server logic
		local player = playerOrType :: Player
		local msgType = typeOrMessage :: MessageType
		local message = messageOrNil :: string
		
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			warn("[MessageSystem] Invalid player argument on Server. Usage: Send(player, type, message)")
			return
		end
		
		Packets.messageSystem.sendTo({
			msgType = msgType :: string,
			message = message,
		}, player)
	else
		-- Client logic
		local msgType = playerOrType :: MessageType
		local message = typeOrMessage :: string
		
		-- Type assertion for Luau
		if typeof(msgType) ~= "string" then
			warn("[MessageSystem] Invalid usage on Client. Usage: Send(type, message)")
			return
		end
		
		MessageSystem.ShowMessage(msgType :: MessageType, message)
	end
end


-- Client Implementation
function MessageSystem.ShowMessage(msgType: MessageType, message: string)
	-- Anti-spam check
	local now = os.clock()
	if lastMessages[message] and now - lastMessages[message] < SPAM_COOLDOWN then
		return
	end
	lastMessages[message] = now

	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local hidTop = playerGui:WaitForChild("Base"):WaitForChild("HID"):WaitForChild("Top")
	
	-- Map types to templates
	local templateName = "Error"
	if msgType == "Success" or msgType == "Win" then
		templateName = "Win"
	elseif msgType == "Warn" then
		-- Fallback for Warn if it doesn't exist
		if MESSAGES_FOLDER:FindFirstChild("Warn") then
			templateName = "Warn"
		else
			templateName = "Error" -- Fallback
		end
	elseif msgType == "Error" then
		templateName = "Error"
	end
	
	local template = MESSAGES_FOLDER:FindFirstChild(templateName)
	if not template then
		warn("[MessageSystem] Template not found for type:", msgType)
		return
	end
	
	local newMsg = template:Clone()
    -- Need to ensure "Message" textlabel exists
	local textLabel = newMsg:FindFirstChild("Message")
	if textLabel and textLabel:IsA("TextLabel") then
		textLabel.Text = message
	else
		warn("[MessageSystem] 'Message' TextLabel not found in template:", templateName)
	end
	
	newMsg.Parent = hidTop
	
	task.delay(3, function()
		if newMsg and newMsg.Parent then
			newMsg:Destroy()
		end
	end)
end

-- Initialize Client Listener
if RunService:IsClient() then
	Packets.messageSystem.listen(function(data)
		-- Cast string to MessageType
		local msgType = data.msgType :: MessageType
		MessageSystem.Send(msgType, data.message)
	end)
end

return MessageSystem

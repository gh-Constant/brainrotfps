--!strict
--[[
	BroadcastUI
	Center-screen broadcast with typewriter animation and color support.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local BroadcastUI = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Configuration
local DISPLAY_DURATION = 5
local FADE_TIME = 0.3
local TYPE_SPEED = 0.03 -- seconds per character

-- Color map
local COLORS = {
	white = Color3.fromRGB(255, 255, 255),
	red = Color3.fromRGB(255, 80, 80),
	green = Color3.fromRGB(80, 255, 80),
	blue = Color3.fromRGB(80, 150, 255),
	yellow = Color3.fromRGB(255, 230, 80),
	purple = Color3.fromRGB(180, 80, 255),
}

-- Active UI reference
local activeGui: ScreenGui? = nil
local rainbowConnection: RBXScriptConnection? = nil
local typewriterThread: thread? = nil

--[[
	Shows a broadcast message on screen with typewriter effect.
]]
function BroadcastUI.Show(message: string, creatorName: string, colorName: string)
	-- Remove existing broadcast if any
	if activeGui then
		activeGui:Destroy()
		activeGui = nil
	end
	if rainbowConnection then
		rainbowConnection:Disconnect()
		rainbowConnection = nil
	end
	if typewriterThread then
		task.cancel(typewriterThread)
		typewriterThread = nil
	end
	
	-- Create UI
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BroadcastUI"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 100
	screenGui.IgnoreGuiInset = true
	
	-- Container (no background)
	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.new(0.8, 0, 0, 0)
	container.Position = UDim2.new(0.5, 0, 0.4, 0)
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.Parent = screenGui
	
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 20)
	padding.PaddingBottom = UDim.new(0, 20)
	padding.PaddingLeft = UDim.new(0, 24)
	padding.PaddingRight = UDim.new(0, 24)
	padding.Parent = container
	
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.Parent = container
	
	-- Message text
	local messageLabel = Instance.new("TextLabel")
	messageLabel.Name = "Message"
	messageLabel.Size = UDim2.new(1, 0, 0, 0)
	messageLabel.AutomaticSize = Enum.AutomaticSize.Y
	messageLabel.BackgroundTransparency = 1
	messageLabel.Font = Enum.Font.GothamBold
	messageLabel.Text = "" -- Start empty for typewriter
	messageLabel.TextSize = 28
	messageLabel.TextWrapped = true
	messageLabel.LayoutOrder = 1
	messageLabel.Parent = container
	
	-- Set color
	local textColor = COLORS[colorName] or COLORS.white
	messageLabel.TextColor3 = textColor
	
	-- Rainbow effect
	if colorName == "rainbow" then
		rainbowConnection = RunService.Heartbeat:Connect(function()
			local hue = (tick() * 0.5) % 1
			messageLabel.TextColor3 = Color3.fromHSV(hue, 1, 1)
		end)
	end
	
	-- Creator text
	local creatorLabel = Instance.new("TextLabel")
	creatorLabel.Name = "Creator"
	creatorLabel.Size = UDim2.new(1, 0, 0, 16)
	creatorLabel.BackgroundTransparency = 1
	creatorLabel.Font = Enum.Font.Gotham
	creatorLabel.Text = "— " .. creatorName
	creatorLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	creatorLabel.TextSize = 14
	creatorLabel.TextTransparency = 1 -- Hidden until typing done
	creatorLabel.LayoutOrder = 2
	creatorLabel.Parent = container
	
	-- Show container immediately
	container.BackgroundTransparency = 0.4
	messageLabel.TextTransparency = 0
	
	screenGui.Parent = playerGui
	activeGui = screenGui
	
	-- Typewriter effect
	typewriterThread = task.spawn(function()
		for i = 1, #message do
			if activeGui ~= screenGui then break end
			messageLabel.Text = string.sub(message, 1, i)
			task.wait(TYPE_SPEED)
		end
		
		-- Show creator after typing
		TweenService:Create(creatorLabel, TweenInfo.new(0.2), { TextTransparency = 0 }):Play()
	end)
	
	-- Schedule removal
	local typingTime = #message * TYPE_SPEED
	task.delay(typingTime + DISPLAY_DURATION, function()
		if activeGui == screenGui then
			if rainbowConnection then
				rainbowConnection:Disconnect()
				rainbowConnection = nil
			end
			
			local fadeOut = TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			TweenService:Create(container, fadeOut, { BackgroundTransparency = 1 }):Play()
			TweenService:Create(messageLabel, fadeOut, { TextTransparency = 1 }):Play()
			local tween = TweenService:Create(creatorLabel, fadeOut, { TextTransparency = 1 })
			tween:Play()
			tween.Completed:Wait()
			screenGui:Destroy()
			activeGui = nil
		end
	end)
end

--[[
	Initialize the BroadcastUI system.
]]
function BroadcastUI.Init()
	-- Import ByteNet packets
	local Rojo = ReplicatedStorage:WaitForChild("Rojo")
	local Shared = Rojo:WaitForChild("Shared")
	local packets = require(Shared:WaitForChild("Packets"))
	
	-- Listen for broadcast packets
	packets.broadcast.listen(function(data)
		BroadcastUI.Show(data.message, data.creator, data.color or "white")
	end)
	
	print("[BroadcastUI] Initialized with ByteNet!")
end

return BroadcastUI

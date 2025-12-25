--!strict
--[[
	DamageIndicator - Client-side damage indicator spawning
	
	Listens for damage indicator packets from server and spawns
	indicators at impact positions for instant feedback.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")
local Packets = require(Shared:WaitForChild("Packets"))

-- Get damage indicator template
local Config = ReplicatedStorage:WaitForChild("Config")
local DamageIndicatorTemplate = Config:WaitForChild("Player"):WaitForChild("UI"):WaitForChild("DamageIndicator")

local DamageIndicator = {}

-- Configuration
local MAX_INDICATORS = 50 -- Maximum number of damage indicators on screen at once

-- Track active indicators
local activeIndicators: {Instance} = {}

-- Tween helper (Linear easing)
local function tween(object: GuiObject, properties: {[string]: any}, duration: number)
	local tweenObj = TweenService:Create(
		object, 
		TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut),
		properties
	)
	tweenObj:Play()
end

-- Spawn a damage indicator at the hit position
local function spawnIndicator(position: Vector3, damage: number, didDamage: boolean)
	-- Only show indicator if damage was actually dealt
	if not didDamage then
		return
	end
	
	-- Check if we're at the limit - remove oldest indicator if so
	if #activeIndicators >= MAX_INDICATORS then
		local oldest = table.remove(activeIndicators, 1)
		if oldest and oldest.Parent then
			oldest:Destroy()
		end
	end
	
	local indicator = DamageIndicatorTemplate:Clone()
	indicator.Parent = workspace
	
	-- Track this indicator
	table.insert(activeIndicators, indicator)
	
	-- Position the BillboardGui's adornee
	local billboardGui = indicator:FindFirstChild("BillboardGui")
	if billboardGui then
		-- Create an anchor part for the BillboardGui
		local anchorPart = Instance.new("Part")
		anchorPart.Name = "DamageAnchor"
		anchorPart.Anchored = true
		anchorPart.CanCollide = false
		anchorPart.CanQuery = false
		anchorPart.CanTouch = false
		anchorPart.Transparency = 1
		anchorPart.Size = Vector3.new(0.1, 0.1, 0.1)
		anchorPart.CFrame = CFrame.new(position)
		anchorPart.Parent = indicator
		
		billboardGui.Adornee = anchorPart
		
		-- Set up damage text
		local frame = billboardGui:FindFirstChild("Frame")
		if frame then
			local damagesLabel = frame:FindFirstChild("Damages")
			if damagesLabel then
				damagesLabel.Text = tostring(damage)
				damagesLabel.Visible = true
			end
			
			-- Animate: expand size
			tween(frame :: GuiObject, { Size = UDim2.new(1, 0, 1, 0) }, 0.3)
			
			-- Random direction: left or right with rotation
			if math.random(0, 1) == 0 then
				tween(frame :: GuiObject, { Rotation = math.random(-30, -10) }, 1)
				tween(frame :: GuiObject, { Position = UDim2.new(math.random(450, 500) / 1000, 0, -1, 0) }, 1)
			else
				tween(frame :: GuiObject, { Rotation = math.random(10, 30)  }, 1)
				tween(frame :: GuiObject, { Position = UDim2.new(math.random(500, 550) / 1000, 0, -1, 0) }, 1)
			end
		end
	end
		
	-- Cleanup after animation
	task.delay(1, function()
		-- Remove from tracking
		local index = table.find(activeIndicators, indicator)
		if index then
			table.remove(activeIndicators, index)
		end
		indicator:Destroy()
	end)
end

function DamageIndicator.Init()
	Packets.damageIndicator.listen(function(data)
		local position = Vector3.new(data.posX, data.posY, data.posZ)
		spawnIndicator(position, data.damage, data.didDamage)
	end)
end

return DamageIndicator

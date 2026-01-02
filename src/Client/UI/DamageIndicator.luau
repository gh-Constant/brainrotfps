--!strict
--[[
	DamageIndicator - Client-side damage indicator spawning
	
	Listens for damage indicator packets from server and spawns
	indicators at impact positions for instant feedback.
	Also spawns a brief highlight on the target for visual feedback.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")
local Packets = require(Shared:WaitForChild("Packets"))
local MoneyLib = require(Shared:WaitForChild("MoneyLib"))

-- Get damage indicator template
local Config = ReplicatedStorage:WaitForChild("Config")
local DamageIndicatorTemplate = Config:WaitForChild("Player"):WaitForChild("UI"):WaitForChild("DamageIndicator")

local DamageIndicator = {}

-- Configuration
local MAX_INDICATORS = 50 -- Maximum number of damage indicators on screen at once
-- Roblox has a hard limit of 31 active Highlights. We stick to 20 to be safe
local MAX_HIGHLIGHTS = 20 
local HIGHLIGHT_DURATION = 0.15 -- Duration of hit highlight in seconds
local HIGHLIGHT_COLOR = Color3.fromRGB(255, 50, 50) -- Red flash
local HIGHLIGHT_OUTLINE_COLOR = Color3.fromRGB(255, 100, 100) -- Lighter red outline

-- Track active indicators
local activeIndicators: {Instance} = {}

-- Track active highlights (simple set for counting)
local activeHighlightCount = 0

-- Tween helper (Linear easing)
local function tween(object: GuiObject, properties: {[string]: any}, duration: number)
	local tweenObj = TweenService:Create(
		object, 
		TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut),
		properties
	)
	tweenObj:Play()
end

-- Spawn a highlight on the hit target (SIMPLIFIED - no animation, just Debris cleanup)
local function spawnHighlight(target: Instance?)
	if not target or not target:IsA("Model") then
		return
	end
	
	-- Check if target already has a highlight from us (skip if so - don't stack)
	local existingHighlight = target:FindFirstChild("HitHighlight")
	if existingHighlight then
		return -- Already has highlight, don't spam more
	end
	
	-- Hard limit on total highlights (Roblox limit is 31, we use 10 for high fire-rate weapons)
	if activeHighlightCount >= MAX_HIGHLIGHTS then
		return -- At limit, skip this one
	end
	
	-- Create the highlight (protected call to avoid crashes)
	local success, highlight = pcall(function()
		local h = Instance.new("Highlight")
		h.Name = "HitHighlight"
		h.FillColor = HIGHLIGHT_COLOR
		h.FillTransparency = 0.5
		h.OutlineColor = HIGHLIGHT_OUTLINE_COLOR
		h.OutlineTransparency = 0
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Adornee = target
		h.Parent = target
		return h
	end)
	
	if not success or not highlight then
		return
	end
	
	-- Track count
	activeHighlightCount = activeHighlightCount + 1
	
	-- Simple cleanup with Debris - no animation, no Heartbeat
	Debris:AddItem(highlight, HIGHLIGHT_DURATION)
	
	-- Decrement count when destroyed
	highlight.Destroying:Once(function()
		activeHighlightCount = activeHighlightCount - 1
	end)
end

-- Spawn a damage indicator at the hit position
local function spawnIndicator(position: Vector3, damage: number, didDamage: boolean, target: Instance?)
	-- Only show indicator if damage was actually dealt
	if not didDamage then
		return
	end
	
	spawnHighlight(target)
	
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
		anchorPart.Transparency = 1
		anchorPart.Size = Vector3.new(0.1, 0.1, 0.1)
		anchorPart.CanCollide = false
		anchorPart.CanQuery = false
		anchorPart.CanTouch = false
		anchorPart.Parent = indicator
		
		-- Always use world space anchoring
		anchorPart.Anchored = true
		anchorPart.CFrame = CFrame.new(position)
		
		billboardGui.Adornee = anchorPart
		
		-- Set up damage text
		local frame = billboardGui:FindFirstChild("Frame")
		if frame then
			local damagesLabel = frame:FindFirstChild("Damages")
			if damagesLabel then
				damagesLabel.Text = MoneyLib.HandleMoney(damage)
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
		spawnIndicator(position, data.damage, data.didDamage, data.targetId)
	end)
end

return DamageIndicator


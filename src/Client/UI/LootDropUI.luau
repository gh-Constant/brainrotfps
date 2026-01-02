--!strict
--[[
	LootDropUI
	Displays looted items with spring animations when player receives items from mob kills.
	
	Shows item slots in Base.HID.Bottom.Drop with:
	- Spring animation on appearance (scale 0 → 1 with overshoot)
	- Items use EXACT inventory styling (no modifications)
	- XP/Gold accumulate if killed multiple mobs quickly
	- Auto-dismiss after delay with fade-out
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")

local Packets = require(Shared:WaitForChild("Packets"))
local ItemSlot = require(script.Parent:WaitForChild("Inventory"):WaitForChild("ItemSlot"))
local InventoryVisibilityManager = require(script.Parent:WaitForChild("Inventory"):WaitForChild("InventoryVisibilityManager"))
local MoneyLib = require(Shared:WaitForChild("MoneyLib"))

local LootDropUI = {}

-- Configuration
local DISPLAY_DURATION = 4 -- Seconds to show each drop
local FADE_DURATION = 0.2 -- Seconds for fade out
local SPRING_DURATION = 0.2 -- Spring animation duration
local MAX_VISIBLE_DROPS = 6 -- Max concurrent drops shown

-- Cached references
local config = ReplicatedStorage:WaitForChild("Config")
local invTemplate = config:WaitForChild("Inventory"):WaitForChild("Templates"):WaitForChild("ItemSlot")

-- State
local dropContainer: GuiObject? = nil
local activeDrops: { any } = {}

-- Track currency slots for accumulation
local activeCurrencySlots: { [string]: { slot: any, frame: GuiObject, amount: number, lastUpdate: number, dismissTask: thread? } } = {}

-- TweenInfo presets
local SPRING_IN = TweenInfo.new(SPRING_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE_OUT = TweenInfo.new(FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local BOUNCE = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

--[[
	Limit drops and remove oldest if needed
]]
--[[
	Limit drops and remove oldest if needed
]]
local function enforceDropLimit()
	if #activeDrops >= MAX_VISIBLE_DROPS then
		local oldest = table.remove(activeDrops, 1)
		if oldest then
			if oldest.slot then
				oldest.slot:Destroy()
			elseif oldest.frame then
				oldest.frame:Destroy()
			end
		end
	end
end

--[[
	Fade out and destroy a slot
]]
local function fadeOutAndDestroy(slot: any, dropInfo: any?)
	if not slot or not slot.Frame or not slot.Frame.Parent then return end
	
	local frame = slot.Frame
	
	local fadeTween = TweenService:Create(frame, FADE_OUT, { 
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 0, 0, 0)
	})
	
	for _, desc in frame:GetDescendants() do
		if desc:IsA("TextLabel") then
			TweenService:Create(desc, FADE_OUT, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		elseif desc:IsA("ImageLabel") or desc:IsA("ImageButton") then
			TweenService:Create(desc, FADE_OUT, { ImageTransparency = 1 }):Play()
		elseif desc:IsA("Frame") then
			TweenService:Create(desc, FADE_OUT, { BackgroundTransparency = 1 }):Play()
		elseif desc:IsA("ViewportFrame") then
			TweenService:Create(desc, FADE_OUT, { ImageTransparency = 1 }):Play()
		elseif desc:IsA("UIStroke") then
			TweenService:Create(desc, FADE_OUT, { Transparency = 1 }):Play()
		end
	end
	
	fadeTween:Play()
	fadeTween.Completed:Wait()
	
	slot:Destroy()
	
	if dropInfo then
		for i, info in activeDrops do
			if info == dropInfo then
				table.remove(activeDrops, i)
				break
			end
		end
	end
end

--[[
	Animate slot in with spring and schedule auto-dismiss
]]
local function animateAndScheduleDismiss(slot: any)
	local frame = slot.Frame
	
	-- Spring animation: start at scale 0
	frame.Size = UDim2.new(0, 0, 0, 0)
	local targetSize = UDim2.new(0.12, 0, 0.8, 0) -- Scale-based size
	
	-- Maintain square aspect ratio
	local aspectRatio = Instance.new("UIAspectRatioConstraint")
	aspectRatio.AspectRatio = 1
	aspectRatio.Parent = frame

	TweenService:Create(frame, SPRING_IN, { Size = targetSize }):Play()
	
	-- Track
	local dropInfo = {
		slot = slot,
		frame = frame,
		createdAt = tick(),
	}
	table.insert(activeDrops, dropInfo)
	
	-- Schedule auto-dismiss
	task.delay(DISPLAY_DURATION, function()
		fadeOutAndDestroy(slot, dropInfo)
	end)
end

--[[
	Show item drop - uses ItemSlot with EXACT inventory styling (no modifications!)
]]
local function showItemDrop(itemData: { templateId: string, itemType: string, rarity: string, metadata: any? })
	if not dropContainer then return end
	
	enforceDropLimit()
	
	local slot = ItemSlot.new(dropContainer, invTemplate)
	-- NOTE: We MUST Unregister from InventoryVisibilityManager.
	-- The visibility manager logic is designed for the scroll inventory and will likely hide these slots.
	InventoryVisibilityManager.Unregister(slot.Frame)
	
	-- Set item data - this applies ALL normal inventory styling
	slot:SetData({
		TemplateId = itemData.templateId,
		Type = itemData.itemType,
		Rarity = itemData.rarity or "Common",
		Count = 1,
		ItemIds = {},
		Metadata = itemData.metadata,
	})
	
	slot.Frame.Visible = true
	
	-- Force viewport visible if needed (ItemSlot usually handles this, but we ensure it)
	local vp = slot.Frame:FindFirstChild("ViewportFrame") :: ViewportFrame?
	if vp then vp.Visible = true end
	
	animateAndScheduleDismiss(slot)
end

--[[
	Show or update currency drop (XP/Gold) with accumulation
]]
local function showOrUpdateCurrencyDrop(currencyType: string, addAmount: number, icon: string?, color: {number}?)
	if not dropContainer then return end
	
	local existing = activeCurrencySlots[currencyType]
	
	if existing and existing.slot and existing.slot.Frame and existing.slot.Frame.Parent then
		-- UPDATE existing slot - accumulate the value
		existing.amount = existing.amount + addAmount
		existing.lastUpdate = tick()
		
		-- Update text (Billboard style: "150 XP" not "+150 XP")
		local suffix = if currencyType == "XP" then " XP" else " Gold"
		local newText = MoneyLib.HandleMoney(existing.amount) .. suffix
		
		-- Update RarityLabel (Billboard uses RarityLabel for name)
		local rarityLabel = existing.slot.Frame:FindFirstChild("RarityLabel") :: TextLabel?
		if rarityLabel then
			rarityLabel.Text = newText
		end
		
		-- Start/restart bounce animation
		-- CRITICAL: Ensure visibility is forced/reset in case of any fade/cull
		existing.slot.Frame.Visible = true
		
		-- Reset Transparencies (just in case a fade was starting or interference occurred)
		existing.slot.Frame.BackgroundTransparency = 0
		if rarityLabel then
			rarityLabel.TextTransparency = 0
			if rarityLabel.TextStrokeTransparency < 1 then rarityLabel.TextStrokeTransparency = 0 end
			
			local stroke = rarityLabel:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Transparency = 0
			end
		end
		local toolIcon = existing.slot.Frame:FindFirstChild("ToolIcon")
		if toolIcon and toolIcon:IsA("ImageLabel") then toolIcon.ImageTransparency = 0 end
		
		-- Cancel any active tweens on the frame to stop "FadeOut" if it was somehow active
		-- activeTweens was unused because simple property sets + new tweens override old ones sufficient here
		-- Plus, due to lifecycle logic, no fade tween should be running if we found the slot in activeCurrencySlots
		
		local currentSize = existing.slot.Frame.Size
		TweenService:Create(existing.slot.Frame, BOUNCE, { 
			Size = UDim2.new(currentSize.X.Scale * 1.1, 0, currentSize.Y.Scale * 1.1, 0) 
		}):Play()
		task.delay(0.15, function()
			if existing.slot and existing.slot.Frame and existing.slot.Frame.Parent then
				TweenService:Create(existing.slot.Frame, BOUNCE, { 
					Size = currentSize 
				}):Play()
			end
		end)
		
		-- Reset dismiss timer
		if existing.dismissTask then
			task.cancel(existing.dismissTask)
		end
		existing.dismissTask = task.delay(DISPLAY_DURATION, function()
			if existing.slot and existing.slot.Frame and existing.slot.Frame.Parent then
				fadeOutAndDestroy(existing.slot, nil)
				activeCurrencySlots[currencyType] = nil
			end
		end)
		
		return
	end
	
	-- CREATE new currency slot
	enforceDropLimit()
	
	local slot = ItemSlot.new(dropContainer, invTemplate)
	-- Keep registered for standard behavior? NO, unregister because we are not in a scroll frame
	InventoryVisibilityManager.Unregister(slot.Frame)
	
	-- Set minimal data
	slot:SetData({
		TemplateId = currencyType,
		Type = "Drop",
		Rarity = "Common",
		Count = 1,
		ItemIds = {},
		Metadata = {},
	})
	
	slot.Frame.Visible = true
	
	-- Apply currency-specific gradient
	local gradient = slot.Frame:FindFirstChildWhichIsA("UIGradient")
	if gradient then
		if currencyType == "XP" then
			gradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 170, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 85, 255))
			})
		else -- Gold/Currency
			gradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 0)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 170, 0))
			})
		end
	end
	
	-- Override icon
	if icon then
		local toolIcon = slot.Frame:FindFirstChild("ToolIcon")
		if toolIcon and toolIcon:IsA("ImageLabel") then
			toolIcon.Image = icon
			toolIcon.Visible = true
			if color then
				toolIcon.ImageColor3 = Color3.fromRGB(color[1], color[2], color[3])
			end
		end
	end
	
	-- Disable viewport for currency
	local viewport = slot.Frame:FindFirstChild("ViewportFrame") :: ViewportFrame?
	if viewport then viewport.Visible = false end
	
	-- Billboard style: "150 XP" not "+150 XP"
	local suffix = if currencyType == "XP" then " XP" else " Gold"
	local displayText = MoneyLib.HandleMoney(addAmount) .. suffix
	
	-- Use RarityLabel for name (like billboard does)
	local rarityLabel = slot.Frame:FindFirstChild("RarityLabel") :: TextLabel?
	if rarityLabel then
		rarityLabel.Visible = true
		rarityLabel.Text = displayText
		rarityLabel.TextColor3 = Color3.new(1, 1, 1) -- White
		rarityLabel.TextSize = 24 -- Bigger like billboard
		rarityLabel.FontFace = Font.new(rarityLabel.FontFace.Family, Enum.FontWeight.Bold, rarityLabel.FontFace.Style)
		
		-- Remove existing visual overrides
		for _, child in rarityLabel:GetChildren() do
			if child:IsA("UIStroke") or child:IsA("UIGradient") then
				child:Destroy()
			end
		end
		
		-- Add clean stroke
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		stroke.Color = Color3.new(0, 0, 0)
		stroke.Transparency = 0
		stroke.Parent = rarityLabel
	end
	
	-- Hide NameLabel (billboard uses RarityLabel)
	local nameLabel = slot.Frame:FindFirstChild("NameLabel") or slot.Frame:FindFirstChild("ToolNameLabel")
	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Visible = false
	end
	
	-- Spring animation
	slot.Frame.Size = UDim2.new(0, 0, 0, 0)
	local targetSize = UDim2.new(0.12, 0, 0.8, 0) -- Scale-based size
	
	-- Maintain square aspect ratio
	local aspectRatio = Instance.new("UIAspectRatioConstraint")
	aspectRatio.AspectRatio = 1
	aspectRatio.Parent = slot.Frame

	TweenService:Create(slot.Frame, SPRING_IN, { Size = targetSize }):Play()
	
	-- Track for accumulation
	local currencyInfo = {
		slot = slot,
		frame = slot.Frame,
		amount = addAmount,
		lastUpdate = tick(),
		dismissTask = nil :: thread?,
	}
	
	-- Track in activeDrops too
	local dropEntry = { slot = slot, frame = slot.Frame, createdAt = tick() }
	table.insert(activeDrops, dropEntry)
	
	-- Schedule auto-dismiss
	currencyInfo.dismissTask = task.delay(DISPLAY_DURATION, function()
		if slot.Frame and slot.Frame.Parent then
			-- Mark as disconnected immediately so new drops create new slots
			activeCurrencySlots[currencyType] = nil
			-- Pass dropEntry to remove from activeDrops list
			fadeOutAndDestroy(slot, dropEntry)
		end
	end)
	
	activeCurrencySlots[currencyType] = currencyInfo
end

--[[
	Parse amount from text like "+150 XP" or "+25 Gold"
]]


--[[
	Initializes the loot drop UI system.
]]
function LootDropUI.Init(context: any)
	local playerGui = context.PlayerGui
	
	-- Find drop container: Base.HID.Bottom.Drop
	local baseGui = playerGui:WaitForChild("Base", 5)
	if not baseGui then
		warn("[LootDropUI] Base UI not found!")
		return
	end
	
	local hid = baseGui:FindFirstChild("HID")
	if not hid then
		warn("[LootDropUI] HID frame not found!")
		return
	end
	
	local bottom = hid:FindFirstChild("Bottom")
	if not bottom then
		warn("[LootDropUI] Bottom frame not found!")
		return
	end
	
	dropContainer = bottom:FindFirstChild("Drop") :: GuiObject?
	if not dropContainer then
		-- Create Drop container
		local dropFrame = Instance.new("Frame")
		dropFrame.Name = "Drop"
		dropFrame.BackgroundTransparency = 1
		dropFrame.Size = UDim2.new(0.6, 0, 0.15, 0) -- 60% of screen width, 15% height
		dropFrame.Position = UDim2.new(0.5, 0, 0.85, 0) -- Centered horizontally, near bottom
		dropFrame.AnchorPoint = Vector2.new(0.5, 0.5)
		dropFrame.Parent = bottom
		
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.Padding = UDim.new(0, 8)
		layout.Parent = dropFrame
		
		dropContainer = dropFrame
	end
	
	-- Listen for inventory updates (when items are added)
	Packets.inventoryUpdate.listen(function(data)
		if data.action == "Add" then
			showItemDrop({
				templateId = data.item.templateId,
				itemType = data.item.itemType,
				rarity = data.item.rarity,
				metadata = data.item.metadata,
			})
		end
	end)
	
	-- Listen for loot FX (coins/XP display) with accumulation
	Packets.lootDropFX.listen(function(data)
		if not data.config.text or data.config.text == "" then return end
		
		-- Determine currency type from text
		local currencyType = "Currency"
		local text = data.config.text
		if string.find(text:lower(), "xp") then
			currencyType = "XP"
		end
		
		-- Parse amount from config or fallback to text parsing if missing (Legacy)
		local amount = data.config.amount
		if not amount or amount <= 0 then
			local numStr = string.match(text, "%d+")
			amount = tonumber(numStr) or 0
		end
		
		if amount <= 0 then return end
		
		showOrUpdateCurrencyDrop(currencyType, amount :: number, data.config.image, data.config.color)
	end)
	
	print("[LootDropUI] Initialized!")
end

return LootDropUI

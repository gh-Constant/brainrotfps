--!strict
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Create container folder for mob billboards
local MobGuisFolder = PlayerGui:FindFirstChild("MobGuis")
if not MobGuisFolder then
	MobGuisFolder = Instance.new("Folder")
	MobGuisFolder.Name = "MobGuis"
	MobGuisFolder.Parent = PlayerGui
end

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")
local Packages = Rojo:WaitForChild("Packages")

local MoneyLib = require(Shared:WaitForChild("MoneyLib"))
local Mutations = require(Shared:WaitForChild("Mutations"))
local ColorSystem = require(Shared:WaitForChild("Inventory"):WaitForChild("ColorSystem"))
local RarityConfig = require(Shared:WaitForChild("Rarity"):WaitForChild("RarityConfig"))
local ItemUtils = require(Shared:WaitForChild("Inventory"):WaitForChild("ItemUtils"))
local ItemSlot = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Inventory"):WaitForChild("ItemSlot"))
local VisualUtils = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Inventory"):WaitForChild("VisualUtils"))
local InventoryVisibilityManager = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Inventory"):WaitForChild("InventoryVisibilityManager"))
local Janitor = require(Packages:WaitForChild("janitor"))

local MobDisplayController = {}
local activeDisplays = {}

-- Cache Config
local config = ReplicatedStorage:WaitForChild("Config")
local brainrotsConfig = config:WaitForChild("Brainrots")
local uiConfig = brainrotsConfig:WaitForChild("UI")
local billboardTemplate = uiConfig:WaitForChild("BillboardGui")



local MOBS_TAG = "BrainrotMob"
local BILLBOARD_MAX_DISTANCE = 150 -- Hide entire billboard if further than this
local LOOT_DISPLAY_DISTANCE = 40   -- Hide loot list if further than this

-- Cached templates and tweens
local invTemplate = config:WaitForChild("Inventory"):WaitForChild("Templates"):WaitForChild("ItemSlot")
local HEALTH_TWEEN_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

type MobDisplay = {
	Janitor: any,
	Model: Model,
	Billboard: BillboardGui,
	NameLabel: TextLabel?,
	RarityLabel: TextLabel?,
	HealthLabel: TextLabel?,
	HealthBar: GuiObject?,
	MutationIcon: ImageLabel?,
	DropContainer: GuiObject?,
}

local function UpdateHealth(display: MobDisplay)
	local health = display.Model:GetAttribute("Health") or 100
	local maxHealth = display.Model:GetAttribute("MaxHealth") or 100
	
	-- Ensure numbers
	if typeof(health) ~= "number" then health = 100 end
	if typeof(maxHealth) ~= "number" then maxHealth = 100 end
	
	-- Update Text
	if display.HealthLabel then
		display.HealthLabel.Text = string.format("%s / %s", 
			MoneyLib.HandleMoney(health), 
			MoneyLib.HandleMoney(maxHealth))
	end
	
	-- Update Bar Tween
	if display.HealthBar then
		local percent = math.clamp(health / maxHealth, 0, 1)
		local goal = { Size = UDim2.fromScale(percent, 1) }
		TweenService:Create(display.HealthBar, HEALTH_TWEEN_INFO, goal):Play()
	end
end

local function UpdateInfo(display: MobDisplay)
	if display.NameLabel then
		display.NameLabel.Text = display.Model.Name
	end
	
	if display.RarityLabel then
		local rarity = display.Model:GetAttribute("Rarity")
		local rarityName = if typeof(rarity) == "string" then rarity else "Common"
		display.RarityLabel.Text = rarityName
		
		-- Use RarityConfig for style lookup (Secret -> Zebra)
		local style = RarityConfig.GetTextStyle(rarityName)
		
		-- User request: remove existing UIStroke if it exists
		local existingStroke = display.RarityLabel:FindFirstChildOfClass("UIStroke")
		if existingStroke then
			existingStroke:Destroy()
		end
		
		-- Update Rarity Color using ColorSystem (Client side supports animations!)
		ColorSystem.ApplyToText(display.RarityLabel, style)
	end
	
	UpdateHealth(display)
end

local function UpdateMutation(display: MobDisplay)
	local mutationName = display.Model:GetAttribute("Mutation")
	
	if not display.MutationIcon then
		return
	end
	
	if mutationName and typeof(mutationName) == "string" then
		local mutationData = Mutations.GetMutation(mutationName)
		if mutationData then
			display.MutationIcon.Image = mutationData.Icon
			display.MutationIcon.Visible = true
		else
			display.MutationIcon.Visible = false
		end
	else
		display.MutationIcon.Visible = false
	end
end

local function UpdateLoot(display: MobDisplay)
	if not display.DropContainer then return end
	
	-- Clear existing
	for _, child in display.DropContainer:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	
	-- Loot Data Collection
	type DropItem = {
		Type: "Item" | "Currency" | "XP",
		Name: string,
		Chance: number, -- 1-100%
		SortChance: number, -- For sorting
		TemplateId: string?,
		Icon: string?,
		Rarity: string?,
		Color: Color3?,
		CustomText: string?,
	}
	
	local drops: {DropItem} = {}
	
	-- 1. XP (Guaranteed)
	local xpReward = display.Model:GetAttribute("BaseXPReward") or 10
	if xpReward > 0 then
		table.insert(drops, {
			Type = "XP",
			Name = tostring(xpReward) .. " XP",
			Chance = 100,
			SortChance = 101, -- Prioritize above items
			Icon = if typeof(config.Effects.FX.XP.Image) == "Instance" and config.Effects.FX.XP.Image:IsA("StringValue") 
				then config.Effects.FX.XP.Image.Value 
				else (config.Effects.FX.XP.Image :: any),
			Color = Color3.fromRGB(85, 255, 127), -- XP Color
			CustomText = "100%",
		})
	end
	
	-- 2. Gold (Guaranteed)
	local goldReward = display.Model:GetAttribute("BaseGoldReward") or 5
	if goldReward > 0 then
		table.insert(drops, {
			Type = "Currency",
			Name = tostring(goldReward) .. " Gold",
			Chance = 100,
			SortChance = 100,
			Icon = if typeof(config.Effects.FX.Coin.Image) == "Instance" and config.Effects.FX.Coin.Image:IsA("StringValue") 
				then config.Effects.FX.Coin.Image.Value 
				else (config.Effects.FX.Coin.Image :: any), -- Fallback directly if it's not a value object?
			Color = Color3.fromRGB(255, 215, 0), -- Gold Color
			CustomText = "100%",
		})
	end
	
	-- 3. Items (Chance based)
	local lootModule = display.Model:FindFirstChild("Loot")
	if lootModule and lootModule:IsA("ModuleScript") then
		local success, lootTable = pcall(require, lootModule)
		if success and lootTable and lootTable.Items then
			for _, item in ipairs(lootTable.Items) do
				local chanceOneIn = item.Chance or 1
				local percent = math.floor((1 / math.max(1, chanceOneIn)) * 100)
				local name = item.Name
				
				local itemConfig = ItemUtils.FindItemConfig(name)
				local rarity = (itemConfig and itemConfig:GetAttribute("Rarity") or "Common") :: string
				
				table.insert(drops, {
					Type = "Item",
					Name = name,
					Chance = percent,
					SortChance = percent,
					TemplateId = name,
					Rarity = rarity,
					CustomText = if percent >= 100 then "100%" else (tostring(percent) .. "%"),
				})
			end
		end
	end
	
	-- Sort: Highest chance first
	table.sort(drops, function(a, b)
		return a.SortChance > b.SortChance
	end)
	
	-- Render
	for _, drop in ipairs(drops) do
		-- Create slot directly in the container (uses cached template)
		local slot = ItemSlot.new(display.DropContainer, invTemplate)
		display.Janitor:Add(slot)
		
		-- IMPORTANT: Unregister from InventoryVisibilityManager because these slots are in World Space (BillboardGui)
		-- The visibility manager logic is designed for 2D ScreenGui inventory and might Cull/Hide these unexpected slots
		InventoryVisibilityManager.Unregister(slot.Frame)
		
		-- Manually ensure visible elements
		slot.Frame.Visible = true
		
		-- Apply layout properties directly to the slot frame
		slot.Frame.Name = "Drop_" .. drop.Name
		slot.Frame.LayoutOrder = 100 - math.floor(drop.SortChance)
		
		-- Remove any drag detectors that might be in the template or cloned
		local dragDetector = slot.Frame:FindFirstChild("DragDetector") or slot.Frame:FindFirstChild("ItemDragDetector")
		if dragDetector then
			dragDetector:Destroy()
		end
		
		local slotData = {
			TemplateId = drop.TemplateId or "Unknown",
			Type = "Drop",
			Rarity = drop.Rarity or "Common",
			Count = 1,
			ItemIds = {},
			Metadata = {
				OverrideEventsText = drop.CustomText,
				CustomColor = if drop.Type ~= "Item" then "Transparent" else nil -- Only items get rarity bg? Or maybe Coins need style?
			}
		}
		
		slot:SetData(slotData)
		
		-- Unregister AGAIN just in case SetData re-registered it
		InventoryVisibilityManager.Unregister(slot.Frame)
		-- Force Viewport Visible if Item
		if drop.Type == "Item" then
			local viewport = slot.Frame:FindFirstChild("ViewportFrame") :: ViewportFrame?
			if viewport then viewport.Visible = true end
		end
		
		-- Custom Overrides for Non-Items
		if drop.Type ~= "Item" then
			-- Override Icon
			if drop.Icon then
				local icon = slot.Frame:FindFirstChild("ToolIcon")
				if icon and icon:IsA("ImageLabel") then
					icon.Image = drop.Icon
					icon.Visible = true
				end
			end
			
			-- Override Name
			local nameLabel = slot.Frame:FindFirstChild("NameLabel") or slot.Frame:FindFirstChild("ToolNameLabel")
			if nameLabel and nameLabel:IsA("TextLabel") then
				nameLabel.Text = drop.Name
			end
			
			-- Disable Viewport
			local viewport = slot.Frame:FindFirstChild("ViewportFrame") :: ViewportFrame?
			if viewport then viewport.Visible = false end
			
			-- Custom Gradients for Coins/XP
			local gradient = slot.Frame:FindFirstChild("UIGradient") :: UIGradient?
			if not gradient then
				-- Try finding it deeper or creating it? ItemSlot usually has it.
				-- If not, ColorSystem might have failed or it's missing.
				-- We'll just try to find it.
				gradient = slot.Frame:FindFirstChildWhichIsA("UIGradient")
			end
			
			if gradient then
				if drop.Type == "XP" then
					-- Blue Gradient
					gradient.Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 170, 255)),
						ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 85, 255))
					})
				elseif drop.Type == "Currency" then
					-- Yellow/Gold Gradient
					gradient.Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 0)),
						ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 170, 0))
					})
				end
			end
		end
		
		-- 2. Styles (User Request)
		-- A. EventsLabel: White with Stroke
		local eventsLabel = slot.Frame:FindFirstChild("EventsLabel") :: TextLabel?
		if eventsLabel then
			eventsLabel.TextColor3 = Color3.new(1, 1, 1) -- White
			eventsLabel.TextStrokeTransparency = 0 -- Enable stroke (default usually black)
			eventsLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
			
			-- Remove conflicting gradients
			for _, child in eventsLabel:GetChildren() do
				if child:IsA("UIGradient") then
					child:Destroy()
				end
			end
		end
		
		-- B. Name Handling: Use RarityLabel for Name (White), Hide original NameLabel
		local nameLabel = slot.Frame:FindFirstChild("NameLabel")
		if not nameLabel then
			nameLabel = slot.Frame:FindFirstChild("ToolNameLabel")
		end
		
		if nameLabel and nameLabel:IsA("TextLabel") then
			nameLabel.Visible = false
		end
		
		local rarityLabel = slot.Frame:FindFirstChild("RarityLabel") :: TextLabel?
		if rarityLabel then
			rarityLabel.Visible = true
			rarityLabel.Text = drop.Name -- Show Name here
			rarityLabel.TextColor3 = Color3.new(1, 1, 1) -- White
			rarityLabel.TextSize = 24 -- "A lot bigger"
			rarityLabel.FontFace = Font.new(rarityLabel.FontFace.Family, Enum.FontWeight.Bold, rarityLabel.FontFace.Style)
			
			-- Remove existing visual overrides on RarityLabel
			for _, child in rarityLabel:GetChildren() do
				if child:IsA("UIStroke") or child:IsA("UIGradient") then
					child:Destroy()
				end
			end
			-- Add clean stroke for readability
			local stroke = Instance.new("UIStroke")
			stroke.Thickness = 2
			stroke.Color = Color3.new(0, 0, 0)
			stroke.Parent = rarityLabel
		end

		-- 4. Viewport Setup (Using VisualUtils - same as Inventory)
		if drop.Type == "Item" then
			local vp = slot.Frame:FindFirstChild("ViewportFrame") :: ViewportFrame?
			local toolIcon = slot.Frame:FindFirstChild("ToolIcon") :: ImageLabel?
			
			if vp then
				-- Use VisualUtils to find and clone model (same as Inventory)
				local itemModel, isCustom = VisualUtils.FindItemModel(drop.Name)
				
				if itemModel then
					local modelClone = VisualUtils.CloneModelForDisplay(itemModel, isCustom)
					
					if modelClone then
						-- Setup WorldModel
						local existingWorldModel = vp:FindFirstChild("WorldModel")
						local worldModel: WorldModel
						if existingWorldModel and existingWorldModel:IsA("WorldModel") then
							-- Clear existing models
							for _, child in existingWorldModel:GetChildren() do
								if child:IsA("Model") or child:IsA("Highlight") then child:Destroy() end
							end
							worldModel = existingWorldModel
						else
							local newWorldModel = Instance.new("WorldModel")
							newWorldModel.Name = "WorldModel"
							newWorldModel.Parent = vp
							worldModel = newWorldModel
						end
						
						modelClone.Name = drop.Name
						modelClone.Parent = worldModel
						
						-- Highlight (same as Inventory ItemSlot)
						local style = RarityConfig.GetBackgroundStyle(drop.Rarity or "Common")
						local highlight = ColorSystem.CreateHighlight(style)
						highlight.Parent = worldModel
						ColorSystem.ApplyToHighlight(highlight, style)
						
						-- Use VisualUtils.SetupModelCamera (same as Inventory)
						-- This handles custom cameras and consistent zoom
						VisualUtils.SetupModelCamera(vp, modelClone)
						
						-- Show viewport, hide icon
						vp.Visible = true
						vp.Ambient = Color3.fromRGB(200, 200, 200)
						vp.LightColor = Color3.new(1, 1, 1)
						if toolIcon then toolIcon.Visible = false end
						
						-- Animation: Play Idle (same as Inventory ItemSlot)
						local animsFolder = ReplicatedStorage:FindFirstChild("BrainrotAnimations")
						if animsFolder then
							local modelAnims = animsFolder:FindFirstChild(drop.Name)
							if modelAnims then
								local idleAnim = modelAnims:FindFirstChild("Idle")
								local animController = modelClone:FindFirstChild("AnimationController") or modelClone:FindFirstChildWhichIsA("Humanoid")
								
								if idleAnim and idleAnim:IsA("Animation") and animController then
									-- Ensure parts are unanchored so Motor6Ds can animate them
									-- except the PrimaryPart/Root which holds it in place
									local root = modelClone.PrimaryPart or modelClone:FindFirstChild("Body") or modelClone:FindFirstChild("HumanoidRootPart")
									
									for _, desc in ipairs(modelClone:GetDescendants()) do
										if desc:IsA("BasePart") then
											if root and desc == root then
												desc.Anchored = true
											else
												desc.Anchored = false
											end
										end
									end

									local animator = (animController :: Instance):FindFirstChild("Animator") :: Animator?
									if not animator then
										animator = Instance.new("Animator")
										animator.Parent = animController :: Instance
									end
									
									if animator then
										local track = animator:LoadAnimation(idleAnim)
										track:Play()
									end
								end
							end
						end
					else
						-- Clone failed, fallback to icon
						warn("[MobDisplay] Clone failed for:", drop.Name)
						if toolIcon then toolIcon.Visible = true end
						vp.Visible = false
					end
				else
					-- No model found, fallback to icon
					if toolIcon then
						toolIcon.Image = VisualUtils.GetItemImage(drop.Name)
						toolIcon.Visible = true
					end
					vp.Visible = false
				end
			end
		end
	end
end

local function onMobAdded(model: Instance)
	if not model:IsA("Model") then return end
	if activeDisplays[model] then return end
	
	-- Wait for model to be fully replicated (prevents race condition with server tagging)
	-- Try to find a valid part to attach the billboard to
	-- We check multiple candidates in order of preference
	local function getBillboardPart(): BasePart?
		return (model:FindFirstChild("Billboard") 
			or model.PrimaryPart 
			or model:FindFirstChild("HumanoidRootPart") 
			or model:FindFirstChild("Head")
			or model:FindFirstChild("Torso")
			or model:FindFirstChild("UpperTorso")) :: BasePart?
	end

	local billboardPart = getBillboardPart()
	
	-- If not found immediately, wait and poll
	-- With Atomic Streaming enabled, this should rarely loop, but we keep it for safety.
	if not billboardPart then
		local maxAttempts = 20 -- 10 seconds total (0.5s interval)
		for _ = 1, maxAttempts do
			if not model.Parent then return end -- Mob destroyed while waiting
			
			billboardPart = getBillboardPart()
			if billboardPart then break end
			
			task.wait(0.5)
		end
	end
	
	if not billboardPart then
		-- Only warn if the model still exists; it might be just streamed out or invalid
		if model.Parent then
			warn("[MobDisplayController] No valid Billboard part found for", model.Name, "(Streaming? Missing Root?)")
		end
		return
	end
	
	-- Clone UI
	-- CRITICAL: Parent to PlayerGui, NOT to the part!
	-- ViewportFrames only render in BillboardGuis when parented to PlayerGui
	local billboardGui = billboardTemplate:Clone()
	billboardGui.Adornee = billboardPart
	billboardGui.Parent = MobGuisFolder
	
	local base = billboardGui:WaitForChild("Base", 5)
	if not base then
		billboardGui:Destroy()
		return
	end
	
	local janitor = Janitor.new()
	janitor:Add(billboardGui)
	
	local display: MobDisplay = {
		Janitor = janitor,
		Model = model,
		Billboard = billboardGui,
		NameLabel = base:FindFirstChild("BrainrotName") :: TextLabel?,
		RarityLabel = base:FindFirstChild("BrainrotRarity") :: TextLabel?,
		HealthLabel = nil,
		HealthBar = nil,
		MutationIcon = base:FindFirstChild("MutationIcon") :: ImageLabel?,
		DropContainer = base:FindFirstChild("Drop") :: GuiObject?,
	}
	
	local healthFrame = base:FindFirstChild("Health") :: GuiObject?
	if healthFrame then
		display.HealthLabel = healthFrame:FindFirstChild("TextLabel") :: TextLabel?
		display.HealthBar = healthFrame:FindFirstChild("HP") :: GuiObject?
	end
	
	-- Initial Update
	UpdateInfo(display)
	UpdateMutation(display)
	UpdateLoot(display)
	
	-- Listeners
	janitor:Add(model.AttributeChanged:Connect(function(attr)
		if attr == "Health" or attr == "MaxHealth" then
			UpdateHealth(display)
		elseif attr == "Mutation" then
			UpdateMutation(display)
		elseif attr == "Rarity" then
			UpdateInfo(display)
		end
	end))
	
	-- Store
	activeDisplays[model] = display
	
	-- Cleanup when model is destroyed (Janitor handles UI destroy)
	janitor:Add(function()
		activeDisplays[model] = nil
	end)
	
	-- If model destroys separately (add to janitor to prevent leak)
	janitor:Add(model.Destroying:Connect(function()
		janitor:Destroy()
	end))
end

local function onMobRemoved(model: Instance)
	local display = activeDisplays[model]
	if display then
		display.Janitor:Destroy()
	end
end

function MobDisplayController.Start()
	-- Connect listeners FIRST to catch any mobs tagged while we're iterating
	CollectionService:GetInstanceAddedSignal(MOBS_TAG):Connect(onMobAdded)
	CollectionService:GetInstanceRemovedSignal(MOBS_TAG):Connect(onMobRemoved)
	
	-- Then process existing mobs with a small delay to ensure they're fully replicated
	task.defer(function()
		for _, mob in CollectionService:GetTagged(MOBS_TAG) do
			task.spawn(onMobAdded, mob)
		end
	end)
	
	print("[MobDisplayController] Started")
	
	-- Optimization Loop
	-- Checks every few frames instead of every frame to save CPU
	local UPDATE_INTERVAL = 0.2
	local lastUpdate = 0
	
	RunService.Heartbeat:Connect(function(dt)
		lastUpdate += dt
		if lastUpdate < UPDATE_INTERVAL then return end
		lastUpdate = 0
		
		local character = LocalPlayer.Character
		local rootPart = if character then character.PrimaryPart else nil
		if not rootPart then return end
		
		local myPos = rootPart.Position
		
		for _, display in activeDisplays do
			if not display.Model.PrimaryPart then continue end
			
			local dist = (display.Model.PrimaryPart.Position - myPos).Magnitude
			
			-- 1. Cull Entire Billboard
			local showBillboard = dist <= BILLBOARD_MAX_DISTANCE
			if display.Billboard.Enabled ~= showBillboard then
				display.Billboard.Enabled = showBillboard
			end
			
			-- 2. Cull Expensive Loot Display (3D Viewports)
			if showBillboard and display.DropContainer then
				local showLoot = dist <= LOOT_DISPLAY_DISTANCE
				if display.DropContainer.Visible ~= showLoot then
					display.DropContainer.Visible = showLoot
				end
			end
		end
	end)
end

return MobDisplayController

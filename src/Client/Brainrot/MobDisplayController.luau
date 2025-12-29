--!strict
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")
local Packages = Rojo:WaitForChild("Packages")

local MoneyLib = require(Shared:WaitForChild("MoneyLib"))
local Mutations = require(Shared:WaitForChild("Mutations"))
local ColorSystem = require(Shared:WaitForChild("Inventory"):WaitForChild("ColorSystem"))
local RarityConfig = require(Shared:WaitForChild("Rarity"):WaitForChild("RarityConfig"))
local Janitor = require(Packages:WaitForChild("janitor"))

local MobDisplayController = {}
local activeDisplays = {}

-- Cache Config
local config = ReplicatedStorage:WaitForChild("Config")
local brainrotsConfig = config:WaitForChild("Brainrots")
local uiConfig = brainrotsConfig:WaitForChild("UI")
local billboardTemplate = uiConfig:WaitForChild("BillboardGui")

local MOBS_TAG = "BrainrotMob"

type MobDisplay = {
	Janitor: any,
	Model: Model,
	Billboard: BillboardGui,
	NameLabel: TextLabel?,
	RarityLabel: TextLabel?,
	HealthLabel: TextLabel?,
	HealthBar: GuiObject?,
	MutationIcon: ImageLabel?,
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
		local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(display.HealthBar, tweenInfo, goal):Play()
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

local function onMobAdded(model: Instance)
	if not model:IsA("Model") then return end
	if activeDisplays[model] then return end
	
	local billboardPart = model:WaitForChild("Billboard", 5)
	if not billboardPart or not billboardPart:IsA("BasePart") then
		warn("[MobDisplayController] No Billboard part found for", model.Name)
		return
	end
	
	-- Clone UI
	local billboardGui = billboardTemplate:Clone()
	billboardGui.Adornee = billboardPart
	billboardGui.Parent = billboardPart
	
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
	}
	
	local healthFrame = base:FindFirstChild("Health") :: GuiObject?
	if healthFrame then
		display.HealthLabel = healthFrame:FindFirstChild("TextLabel") :: TextLabel?
		display.HealthBar = healthFrame:FindFirstChild("HP") :: GuiObject?
	end
	
	-- Initial Update
	UpdateInfo(display)
	UpdateMutation(display)
	
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
	
	-- If model destroys separately
	model.Destroying:Connect(function()
		janitor:Destroy()
	end)
end

local function onMobRemoved(model: Instance)
	local display = activeDisplays[model]
	if display then
		display.Janitor:Destroy()
	end
end

function MobDisplayController.Start()
	-- Listen for existing and new mobs
	for _, mob in CollectionService:GetTagged(MOBS_TAG) do
		task.spawn(onMobAdded, mob)
	end
	
	CollectionService:GetInstanceAddedSignal(MOBS_TAG):Connect(onMobAdded)
	CollectionService:GetInstanceRemovedSignal(MOBS_TAG):Connect(onMobRemoved)
	
	print("[MobDisplayController] Started")
end

return MobDisplayController

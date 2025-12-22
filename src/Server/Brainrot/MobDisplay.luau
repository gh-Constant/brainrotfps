--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local MobDisplay = {}
MobDisplay.__index = MobDisplay

-- Rarity Config Cache
local RarityConfig: Folder? = nil

local function getRarityColor(rarityName: string): Color3?
	if not RarityConfig then
		local config = ReplicatedStorage:FindFirstChild("Config")
		if config then
			RarityConfig = config:FindFirstChild("Rarity")
		end
	end
	
	if RarityConfig then
		local color = RarityConfig:GetAttribute(rarityName)
		if typeof(color) == "Color3" then
			return color
		end
	end
	return nil
end

export type MobDisplayObject = typeof(setmetatable({}, MobDisplay)) & {
	Model: Model,
	Billboard: BillboardGui,
	NameLabel: TextLabel?,
	RarityLabel: TextLabel?,
	HealthLabel: TextLabel?,
	HealthBar: GuiObject?,
	_connections: { RBXScriptConnection },
}

--[[
	Creates a new MobDisplay handler for the given mob model.
	Expected structure:
	Model.Billboard.BillboardGUI.Base.BrainrotName (TextLabel)
	Model.Billboard.BillboardGUI.Base.BrainrotRarity (TextLabel)
	Model.Billboard.BillboardGUI.Base.Health.TextLabel (TextLabel)
	Model.Billboard.BillboardGUI.Base.Health.HP (GuiObject - The bar filling)
]]
function MobDisplay.new(model: Model): MobDisplayObject?
	local billboardPart = model:FindFirstChild("Billboard")
	if not billboardPart then 
		warn("[MobDisplay] Missing 'Billboard' part in mob: " .. model.Name)
		return nil 
	end
	
	local billboardGui = billboardPart:FindFirstChild("BillboardGui") :: BillboardGui?
	if not billboardGui then 
		warn("[MobDisplay] Missing 'BillboardGui' in Billboard part: " .. model.Name)
		return nil 
	end
	
	local base = billboardGui:FindFirstChild("Base") :: GuiObject?
	if not base then 
		warn("[MobDisplay] Missing 'Base' frame in BillboardGUI: " .. model.Name)
		return nil 
	end

	local self = setmetatable({}, MobDisplay)
	self.Model = model
	self.Billboard = billboardGui
	self._connections = {}
	
	-- Find UI Components
	self.NameLabel = base:FindFirstChild("BrainrotName") :: TextLabel?
	if not self.NameLabel then warn("[MobDisplay] Missing 'BrainrotName' label in Base: " .. model.Name) end
	
	self.RarityLabel = base:FindFirstChild("BrainrotRarity") :: TextLabel?
	if not self.RarityLabel then warn("[MobDisplay] Missing 'BrainrotRarity' label in Base: " .. model.Name) end
	
	local healthFrame = base:FindFirstChild("Health") :: GuiObject?
	if healthFrame then
		self.HealthLabel = healthFrame:FindFirstChild("TextLabel") :: TextLabel?
		self.HealthBar = healthFrame:FindFirstChild("HP") :: GuiObject?
	else
		warn("[MobDisplay] Missing 'Health' frame in Base: " .. model.Name)
	end
	
	self:UpdateInfo()
	self:SetupHealthListener()
	
	return self
end

function MobDisplay:UpdateInfo()
	if self.NameLabel then
		self.NameLabel.Text = self.Model.Name
	end
	
	if self.RarityLabel then
		local rarity = self.Model:GetAttribute("Rarity")
		local rarityName = if typeof(rarity) == "string" then rarity else "Common"
		self.RarityLabel.Text = rarityName
		
		-- Update Rarity Color
		local rarityColor = getRarityColor(rarityName)
		if rarityColor then
			self.RarityLabel.TextColor3 = rarityColor
		end
	end
	
	-- Initial health update
	self:UpdateHealth()
end

function MobDisplay:UpdateHealth()
	local health = self.Model:GetAttribute("Health") or 100
	local maxHealth = self.Model:GetAttribute("MaxHealth") or 100
	
	-- Ensure numbers
	if typeof(health) ~= "number" then health = 100 end
	if typeof(maxHealth) ~= "number" then maxHealth = 100 end
	
	-- Update Text: "Health / MaxHealth"
	if self.HealthLabel then
		self.HealthLabel.Text = string.format("%d / %d", math.floor(health), math.floor(maxHealth))
	end
	
	-- Update Bar Tween
	if self.HealthBar then
		local percent = math.clamp(health / maxHealth, 0, 1)
		local goal = { Size = UDim2.fromScale(percent, 1) } 
		-- Assuming horizontal fill, adjust if needed (e.g. Y scale)
		-- Provide a default size expectation or check current size? 
		-- Using Scale X percent and Scale Y 1 is standard for bars.
		
		local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(self.HealthBar, tweenInfo, goal):Play()
	end
end

function MobDisplay:SetupHealthListener()
	-- Listen for Attribute changes on the model since Health module uses attributes
	local conn = self.Model.AttributeChanged:Connect(function(attribute)
		if attribute == "Health" or attribute == "MaxHealth" then
			self:UpdateHealth()
		end
	end)
	table.insert(self._connections, conn)
end

function MobDisplay:Destroy()
	for _, conn in self._connections do
		conn:Disconnect()
	end
	self._connections = {}
	self.Model = nil :: any
	self.Billboard = nil :: any
end

return MobDisplay

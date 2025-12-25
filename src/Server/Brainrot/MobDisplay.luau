--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")
local MoneyLib = require(Shared:WaitForChild("MoneyLib"))
local Mutations = require(Shared:WaitForChild("Mutations"))

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
	MutationIcon: ImageLabel?,
	_connections: { RBXScriptConnection },
}

--[[
	Creates a new MobDisplay handler for the given mob model.
	Clones BillboardGui from Config.Brainrots.UI.BillboardGui and parents it to Model.Billboard
	Expected cloned structure:
	BillboardGUI.Base.BrainrotName (TextLabel)
	BillboardGUI.Base.BrainrotRarity (TextLabel)
	BillboardGUI.Base.Health.TextLabel (TextLabel)
	BillboardGUI.Base.Health.HP (GuiObject - The bar filling)
	BillboardGUI.Base.MutationIcon (ImageLabel) - Hidden when not mutated
]]
function MobDisplay.new(model: Model): MobDisplayObject?
	local billboardPart = model:FindFirstChild("Billboard") :: BasePart?
	if not billboardPart then 
		warn("[MobDisplay] Missing 'Billboard' part in mob: " .. model.Name)
		return nil 
	end
	
	-- Clone BillboardGui from Config
	local config = ReplicatedStorage:FindFirstChild("Config")
	if not config then
		warn("[MobDisplay] Missing 'Config' in ReplicatedStorage")
		return nil
	end
	
	local brainrotsConfig = config:FindFirstChild("Brainrots")
	if not brainrotsConfig then
		warn("[MobDisplay] Missing 'Brainrots' in Config")
		return nil
	end
	
	local uiConfig = brainrotsConfig:FindFirstChild("UI")
	if not uiConfig then
		warn("[MobDisplay] Missing 'UI' in Brainrots config")
		return nil
	end
	
	local billboardTemplate = uiConfig:FindFirstChild("BillboardGui") :: BillboardGui?
	if not billboardTemplate then
		warn("[MobDisplay] Missing 'BillboardGui' template in UI config")
		return nil
	end
	
	-- Clone and parent to billboard part
	local billboardGui = billboardTemplate:Clone()
	billboardGui.Adornee = billboardPart
	billboardGui.Parent = billboardPart
	
	local base = billboardGui:FindFirstChild("Base") :: GuiObject?
	if not base then 
		warn("[MobDisplay] Missing 'Base' frame in cloned BillboardGUI: " .. model.Name)
		billboardGui:Destroy()
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
	
	-- Find Mutation Icon (should be visible=false in template)
	self.MutationIcon = base:FindFirstChild("MutationIcon") :: ImageLabel?
	
	self:UpdateInfo()
	self:UpdateMutation()
	self:SetupListeners()
	
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
	
	-- Update Text with formatted numbers (e.g., "1.2K / 2K")
	if self.HealthLabel then
		self.HealthLabel.Text = string.format("%s / %s", 
			MoneyLib.HandleMoney(health), 
			MoneyLib.HandleMoney(maxHealth))
	end
	
	-- Update Bar Tween
	if self.HealthBar then
		local percent = math.clamp(health / maxHealth, 0, 1)
		local goal = { Size = UDim2.fromScale(percent, 1) }
		local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(self.HealthBar, tweenInfo, goal):Play()
	end
end

function MobDisplay:UpdateMutation()
	local mutationName = self.Model:GetAttribute("Mutation")
	
	if not self.MutationIcon then
		return
	end
	
	if mutationName and typeof(mutationName) == "string" then
		local mutationData = Mutations.GetMutation(mutationName)
		if mutationData then
			self.MutationIcon.Image = mutationData.Icon
			self.MutationIcon.Visible = true
		else
			self.MutationIcon.Visible = false
		end
	else
		self.MutationIcon.Visible = false
	end
end

function MobDisplay:SetupListeners()
	-- Listen for Attribute changes on the model
	local conn = self.Model.AttributeChanged:Connect(function(attribute)
		if attribute == "Health" or attribute == "MaxHealth" then
			self:UpdateHealth()
		elseif attribute == "Mutation" then
			self:UpdateMutation()
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


--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Inventory = require(ReplicatedStorage:WaitForChild("Rojo"):WaitForChild("Shared"):WaitForChild("Inventory"))

type InventoryItem = Inventory.InventoryItem

local Potions_Instant_Infos = {}

-- Helper to find item config
local function getItemConfig(templateId: string): Configuration?
	local config = ReplicatedStorage:FindFirstChild("Config")
	if not config then return nil end
	local items = config:FindFirstChild("Items")
	if not items then return nil end
	
	local function searchRecursive(parent: Instance): Configuration?
		for _, child in parent:GetChildren() do
			if child.Name == templateId and child:IsA("Configuration") then
				return child
			elseif child:IsA("Folder") then
				local found = searchRecursive(child)
				if found then return found end
			end
		end
		return nil
	end
	return searchRecursive(items)
end

-- Helper to find an element by name across multiple instances
local function findElement(instances: {GuiObject}, name: string): GuiObject?
	for _, inst in ipairs(instances) do
		if inst.Name == name then
			return inst
		end
		local child = inst:FindFirstChild(name)
		if child and child:IsA("GuiObject") then
			return child :: GuiObject
		end
	end
	return nil
end

-- Mount can receive either a single GuiObject or an array of GuiObjects (for folder templates)
function Potions_Instant_Infos.Mount(instanceOrInstances: GuiObject | {GuiObject}, item: InventoryItem, props: any)
	local config = getItemConfig(item.TemplateId)
	if not config then return end
	
	-- Normalize to array
	local instances: {GuiObject} = {}
	if typeof(instanceOrInstances) == "table" then
		instances = instanceOrInstances :: {GuiObject}
	else
		instances = {instanceOrInstances :: GuiObject}
	end
	
	-- Find the Tool inside the Configuration
	local tool = config:FindFirstChildWhichIsA("Tool")
	
	-- Get value (percentage) from tool/config attributes
	local valuePercent = (tool and tool:GetAttribute("Value")) 
		or config:GetAttribute("Value") 
		or (tool and tool:GetAttribute("Multi"))
		or config:GetAttribute("Multi")
		or 0
	
	-- Get value type (XP, Coins, etc.)
	local valueType = (tool and tool:GetAttribute("ValueType")) 
		or config:GetAttribute("ValueType")
		or (tool and tool:GetAttribute("Type"))
		or config:GetAttribute("Type")
		or "Unknown"
	
	-- Get value format (% or raw)
	local valueFormat = (tool and tool:GetAttribute("ValueFormat")) 
		or config:GetAttribute("ValueFormat")
		or "%" -- Default to percentage
	
	-- Helper to format value based on ValueFormat
	local function formatValue(val: number): string
		if valueFormat == "%" then
			return tostring(val) .. "%"
		else
			return tostring(val)
		end
	end
	
	-- Update UI elements
	
	-- Description: "Gives X% [Type] instantly to the player." or "Gives X [Type] instantly to the player."
	local descLabel = findElement(instances, "Description") :: TextLabel?
	if descLabel then
		local percentValue = tonumber(valuePercent) or 0
		descLabel.Text = "Gives " .. formatValue(percentValue) .. " " .. tostring(valueType) .. " instantly to the player."
	end
	
	-- Multi label shows "Value : X%" or "Value : X"
	local multiLabel = findElement(instances, "Multi") :: TextLabel?
	if multiLabel then
		local percentValue = tonumber(valuePercent) or 0
		multiLabel.Text = "Value : " .. formatValue(percentValue)
	end
	
	-- Value label with color (same as boost: cyan for XP, gold for Coins)
	local valueLabel = findElement(instances, "Value") :: TextLabel?
	if valueLabel then
		local valueStr = tostring(valueType)
		valueLabel.Text = "Type: " .. valueStr
		
		-- Color based on value type
		local lowerValue = string.lower(valueStr)
		if string.find(lowerValue, "xp") or string.find(lowerValue, "experience") then
			valueLabel.TextColor3 = Color3.fromRGB(0, 200, 255) -- Cyan for XP
		elseif string.find(lowerValue, "coin") or string.find(lowerValue, "gold") or string.find(lowerValue, "money") then
			valueLabel.TextColor3 = Color3.fromRGB(255, 200, 50) -- Gold for Coins
		elseif string.find(lowerValue, "health") or string.find(lowerValue, "hp") then
			valueLabel.TextColor3 = Color3.fromRGB(255, 80, 80) -- Red for Health
		else
			valueLabel.TextColor3 = Color3.fromRGB(255, 255, 255) -- White default
		end
	end
	
	-- TypeLabel (optional, shows potion type name)
	local typeLabel = findElement(instances, "TypeLabel") :: TextLabel?
	if typeLabel then
		local potionType = (tool and tool:GetAttribute("PotionType")) 
			or config:GetAttribute("PotionType") 
			or config:GetAttribute("DisplayName") 
			or "Instant Potion"
		typeLabel.Text = tostring(potionType)
	end
end

return Potions_Instant_Infos

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Inventory = require(ReplicatedStorage:WaitForChild("Rojo"):WaitForChild("Shared"):WaitForChild("Inventory"))

type InventoryItem = Inventory.InventoryItem

local GrenadeInfos = {}

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
function GrenadeInfos.Mount(instanceOrInstances: GuiObject | {GuiObject}, item: InventoryItem, props: any)
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
	
	-- Gather grenade stats from Tool attributes (fallback to config)
	local grenadeType = (tool and tool:GetAttribute("GrenadeType")) 
		or config:GetAttribute("GrenadeType") 
		or config:GetAttribute("DisplayName") 
		or "Grenade"
	
	local multiplier = (tool and tool:GetAttribute("Multiplier")) 
		or config:GetAttribute("Multiplier") 
		or 1
	
	-- Get Luck from Tool
	local luck = (tool and tool:GetAttribute("Luck")) 
		or (tool and tool:GetAttribute("TriggerLuck")) 
		or config:GetAttribute("Luck") 
		or config:GetAttribute("TriggerLuck") 
		or 0
	
	-- Get Mutation from item Metadata
	local mutation: string? = nil
	if item.Metadata and item.Metadata.Mutations then
		-- Get the first mutation name
		for mutName, _ in pairs(item.Metadata.Mutations) do
			mutation = mutName
			break
		end
	end
	
	-- Update UI elements
	local typeLabel = findElement(instances, "TypeLabel") :: TextLabel?
	if typeLabel then
		typeLabel.Text = tostring(grenadeType)
	end
	
	local multiLabel = findElement(instances, "Multi") :: TextLabel?
	if multiLabel then
		multiLabel.Text = "Multiplier: x" .. tostring(multiplier)
	end
	
	local luckLabel = findElement(instances, "Luck") :: TextLabel?
	if luckLabel then
		-- Format luck as percentage
		local luckNum = tonumber(luck) or 0
		local luckPercent: number = luckNum
		if luckNum <= 1 then
			luckPercent = math.floor(luckNum * 100)
		end
		luckLabel.Text = "Trigger luck: " .. tostring(luckPercent) .. "%"
	end
	
	-- Build dynamic description based on luck and mutation
	local descLabel = findElement(instances, "Description") :: TextLabel?
	if descLabel then
		local luckNum = tonumber(luck) or 0
		local luckDisplay: number = luckNum
		if luckNum <= 1 then
			luckDisplay = math.floor(luckNum * 100)
		end
		
		local eventName = mutation or "the associated event"
		local description = "If you throw this grenade at a brainrot, it has a " 
			.. tostring(luckDisplay) .. "% chance to trigger " .. eventName 
			.. ". The success percentage and multiplier are different for each grenade."
		
		descLabel.Text = description
	end
end

return GrenadeInfos

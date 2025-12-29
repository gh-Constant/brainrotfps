--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")
local Inventory = require(Shared:WaitForChild("Inventory"))
local RarityConfig = require(Shared:WaitForChild("Rarity"):WaitForChild("RarityConfig"))
local ColorSystem = require(Shared:WaitForChild("Inventory"):WaitForChild("ColorSystem"))

type InventoryItem = Inventory.InventoryItem

local RarityLabel = {}

-- Helper to find item config (Should be shared utility ideally)
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

function RarityLabel.Mount(instance: GuiObject, item: InventoryItem, props: any)
	local label = instance
	if not label:IsA("TextLabel") then
		local found = label:FindFirstChildWhichIsA("TextLabel")
		if found then label = found end
	end
	
	if label:IsA("TextLabel") then
		local rarity = item.Rarity or "Common"
		label.Text = string.upper(rarity)
		label.BackgroundTransparency = 1
		
		-- Logic: Config CustomTextColor > Tool Attribute CustomTextColor > Rarity Text Style
		local style: string? = nil
        
        -- Check Config
        local config = getItemConfig(item.TemplateId)
        if config then
            style = config:GetAttribute("CustomTextColor") :: string?
        end
        
        -- Fallback to tool attribute (if accessible via metadata mirroring)
		if not style then
			 style = item.Metadata and item.Metadata.CustomTextColor
		end
        
        -- Fallback to Rarity
		if not style then
			 style = RarityConfig.GetTextStyle(rarity)
		end
		
		ColorSystem.ApplyToText(label, style)
	end
end

return RarityLabel

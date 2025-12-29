--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")
local Inventory = require(Shared:WaitForChild("Inventory"))
local RarityConfig = require(Shared:WaitForChild("Rarity"):WaitForChild("RarityConfig"))
local ColorSystem = require(Shared:WaitForChild("Inventory"):WaitForChild("ColorSystem"))

type InventoryItem = Inventory.InventoryItem

local ItemIcon = {}

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

function ItemIcon.Mount(instance: GuiObject, item: InventoryItem, props: any)
	-- 1. Set Name
	local nameLabel = instance:FindFirstChild("NameLabel") :: TextLabel?
	if nameLabel then
		local displayName = item.TemplateId
		local config = getItemConfig(item.TemplateId)
		if config then
			local dn = config:GetAttribute("DisplayName")
			if dn and dn ~= "" then displayName = dn end
		end
		nameLabel.Text = displayName
	end

	-- 2. Set Icon (ToolIcon)
	local toolIcon = instance:FindFirstChild("ToolIcon") :: ImageLabel?
	if toolIcon then
		local textureId = ""
		local config = getItemConfig(item.TemplateId)
		if config then
			textureId = config:GetAttribute("Image") or ""
			if textureId == "" then
				local tool = config:FindFirstChildWhichIsA("Tool")
				if tool then textureId = tool.TextureId end
			end
		end
		
		if textureId ~= "" and not string.find(textureId, "://") then
			textureId = "rbxassetid://" .. textureId
		end
		toolIcon.Image = textureId
	end

	-- 3. Set Rarity Gradient (ItemIcon itself)
	-- Avoid ColorSystem.ApplyToBackground as it forces BackgroundTransparency = 0.
	-- We want to apply the gradient to the UIGradient child but keep background transparent (so it applies to Image/Border).
	
	local rarity = item.Rarity or "Common"
    local styleName = nil
    
    local config = getItemConfig(item.TemplateId)
    if config then
        styleName = config:GetAttribute("CustomColor") :: string?
    end
    
    if not styleName or styleName == "" then
        styleName = RarityConfig.GetBackgroundStyle(rarity)
    end

	local visualConfig = ColorSystem.GetColorConfig(styleName)

	-- Ensure transparency is 1
	instance.BackgroundTransparency = 1
	instance.BackgroundColor3 = Color3.fromRGB(255, 255, 255)

	if visualConfig and visualConfig.Gradient then
		local gradient = instance:FindFirstChildWhichIsA("UIGradient")
		if not gradient then
			gradient = Instance.new("UIGradient")
			gradient.Name = "RarityGradient"
			gradient.Parent = instance
		end
		gradient.Color = visualConfig.Gradient
		gradient.Rotation = visualConfig.GradientRotation or -90
		gradient.Enabled = true
	else
		-- Fallback logic or cleanup if no gradient
        local gradient = instance:FindFirstChildWhichIsA("UIGradient")
        if gradient then gradient.Enabled = false end
	end
end

return ItemIcon

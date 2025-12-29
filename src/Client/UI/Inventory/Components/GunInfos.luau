--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Inventory = require(ReplicatedStorage:WaitForChild("Rojo"):WaitForChild("Shared"):WaitForChild("Inventory"))

type InventoryItem = Inventory.InventoryItem

local GunInfos = {}

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

-- Calculate player damage based on level
local function getPlayerDamage(level: number): number
	-- Player damage formula: 9 + level
	return 9 + level
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
function GunInfos.Mount(instanceOrInstances: GuiObject | {GuiObject}, item: InventoryItem, props: any)
	local config = getItemConfig(item.TemplateId)
	if not config then return end
	
	-- Normalize to array
	local instances: {GuiObject} = {}
	if typeof(instanceOrInstances) == "table" then
		instances = instanceOrInstances :: {GuiObject}
	else
		instances = {instanceOrInstances :: GuiObject}
	end
	
	local tool = config:FindFirstChildWhichIsA("Tool")
	
    -- Helper to get mutation stats
    local damageMult = 1
    local firerateMult = 1
    
    if item.Metadata and item.Metadata.Mutations then
        -- Require Mutations (lazy load or add to top, lazily is safer here to avoid circular dep if any)
        -- Assuming Shared is available via Inventory require path
        local Mutations = require(ReplicatedStorage.Rojo.Shared.Mutations)
        
        for name, count in pairs(item.Metadata.Mutations) do
            local mutationData = Mutations.GetMutation(name)
            if mutationData and mutationData.MultiplierModifier then
                -- MultiplierModifier is percentage (e.g. 5 = 5%)
                -- logic change: NO damage buf, ONLY firerate buff (x2 efficiency)
                local percentBonus = (mutationData.MultiplierModifier * count) / 100
                -- damageMult = damageMult + percentBonus -- Removed
                firerateMult = firerateMult + (percentBonus * 2)
            end
        end
    end

	-- Gather weapon stats
	local bullets = tonumber(config:GetAttribute("raysPerShot") or (tool and tool:GetAttribute("raysPerShot")) or 1) or 1
	local baseFirerate = tonumber(config:GetAttribute("rateOfFire") or (tool and tool:GetAttribute("rateOfFire")) or 0) or 0
	local spread = config:GetAttribute("spread") or (tool and tool:GetAttribute("spread")) or 0
	local weaponType = config:GetAttribute("WeaponType") or (tool and tool:GetAttribute("WeaponType")) or "Weapon"
	
    -- Apply multipliers
    local firerate = math.round(baseFirerate * firerateMult)
    
	-- Update UI
	local bulletsLabel = findElement(instances, "BulletsNumber") :: TextLabel?
	if bulletsLabel then
		bulletsLabel.Text = "Bullets number: " .. tostring(bullets)
	end
	
	local firerateLabel = findElement(instances, "Firerate") :: TextLabel?
	if firerateLabel then
		firerateLabel.Text = "Fire rate: " .. tostring(firerate)
        if firerateMult > 1 then
             firerateLabel.Text = firerateLabel.Text .. " (" .. math.round((firerateMult - 1) * 100) .. "%)"
             firerateLabel.TextColor3 = Color3.fromRGB(100, 255, 100) -- Green for buff
        end
	end
	
	local spreadLabel = findElement(instances, "Spread") :: TextLabel?
	if spreadLabel then
		spreadLabel.Text = "Spread: " .. tostring(spread)
	end
	
	local dpsLabel = findElement(instances, "Dps") :: TextLabel?
	if dpsLabel then
		-- DPS = Level 1 Damage * (FireRate / 60) * BulletCount
		local level1Damage = getPlayerDamage(1) * damageMult
		local shotsPerSecond = firerate / 60
		local dps = math.floor(level1Damage * shotsPerSecond * bullets)
		dpsLabel.Text = "Level 1 DPS: " .. tostring(dps)
        
        if damageMult > 1 or firerateMult > 1 then
             dpsLabel.TextColor3 = Color3.fromRGB(100, 255, 100) -- Green for buff
        end
	end
	
	local typeLabel = findElement(instances, "TypeLabel") :: TextLabel?
	if typeLabel then
		typeLabel.Text = tostring(weaponType)
	end
end

return GunInfos

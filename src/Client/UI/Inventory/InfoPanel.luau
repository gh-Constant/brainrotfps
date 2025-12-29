--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- local RunService = game:GetService("RunService")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Packages = Rojo:WaitForChild("Packages")
local Shared = Rojo:WaitForChild("Shared")

local Janitor = require(Packages:WaitForChild("janitor"))
local Inventory = require(Shared:WaitForChild("Inventory"))
local Packets = require(Shared:WaitForChild("Packets"))

-- Types
type Janitor = typeof(Janitor.new())
type InventoryItem = Inventory.InventoryItem

local InfoPanel = {}
InfoPanel.__index = InfoPanel

-- Cache to avoid repeated lookups (can be GuiObject or Folder)
local componentsCache: {[string]: Instance} = {}

local function getComponentTemplate(name: string): Instance?
	if componentsCache[name] then
		return componentsCache[name]
	end

	local config = ReplicatedStorage:FindFirstChild("Config")
	if config then
		local invConfig = config:FindFirstChild("Inventory")
		if invConfig then
			local uiComponents = invConfig:FindFirstChild("UIComponents")
			if uiComponents then
				local template = uiComponents:FindFirstChild(name)
				-- Accept both GuiObject and Folder
				if template and (template:IsA("GuiObject") or template:IsA("Folder")) then
					componentsCache[name] = template
					return template
				end
			end
		end
	end
	
	warn("[InfoPanel] Component template not found:", name)
	return nil
end

local function getLayoutConfig(item: InventoryItem): {any}?
	local baseLayout: {any}? = nil
	
	-- Helper to find item config
	local function findItemConfig(templateId: string): Configuration?
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
	
	local config = ReplicatedStorage:FindFirstChild("Config")
	if not config then 
		baseLayout = {"ItemIcon", "RarityLabel", "Separator"}
	else
		-- 1. Check Item Specific Layout
		local itemConfig = findItemConfig(item.TemplateId)
		if itemConfig then
			local layoutModule = itemConfig:FindFirstChild("InfoPanelLayout") or itemConfig:FindFirstChild("Layout")
			if layoutModule and layoutModule:IsA("ModuleScript") then
				baseLayout = require(layoutModule) :: {any}
			end
		end
		
		-- 2. Check Type Specific Layout
		if not baseLayout then
			local invConfig = config:FindFirstChild("Inventory")
			if invConfig then
				local layouts = invConfig:FindFirstChild("Layouts")
				if layouts then
					local types = layouts:FindFirstChild("Types")
					if types then
						local typeModule = types:FindFirstChild(item.Type)
						if typeModule and typeModule:IsA("ModuleScript") then
							baseLayout = require(typeModule) :: {any}
						end
					end
					
					-- 3. Check Default Layout
					if not baseLayout then
						local defaultModule = layouts:FindFirstChild("Default")
						if defaultModule and defaultModule:IsA("ModuleScript") then
							baseLayout = require(defaultModule) :: {any}
						end
					end
				end
			end
		end
		
		-- Fallback
		if not baseLayout then
			baseLayout = {"ItemIcon", "RarityLabel", "Separator"}
		end
	end
	
	-- Check ItemType from Configuration attribute for gameplay-specific additions
	local itemConfig = findItemConfig(item.TemplateId)
	if itemConfig then
		local itemType = itemConfig:GetAttribute("ItemType")
		if itemType == "Gun" then
            -- Find Separator index to insert Events before it
            local separatorIndex = nil
            for i, v in ipairs(baseLayout) do
                if v == "Separator" or (type(v) == "table" and (v[1] == "Separator" or (v :: any).Component == "Separator")) then
                    separatorIndex = i
                    break
                end
            end
            
            if separatorIndex then
                table.insert(baseLayout, separatorIndex, "Events")
            else
                table.insert(baseLayout, "Events")
            end
            
			table.insert(baseLayout, "GunInfos")
		elseif itemType == "Grenade" then
			table.insert(baseLayout, "GrenadeInfos")
		elseif itemType == "Potion" then
			-- Check PotionType from tool attribute
			local tool = itemConfig:FindFirstChildWhichIsA("Tool")
			local potionType = (tool and tool:GetAttribute("PotionType")) or itemConfig:GetAttribute("PotionType")
			if potionType == "Boost" then
				table.insert(baseLayout, "Potions_Boost_Infos")
			elseif potionType == "Instant" then
				table.insert(baseLayout, "Potions_Instant_Infos")
			end
		end
	end
	
	return baseLayout
end

function InfoPanel.new(frame: Frame)
	local self = setmetatable({}, InfoPanel)
	
	self.Frame = frame
	self._janitor = Janitor.new()
	self._currentItem = nil :: InventoryItem?
	self._buttonJanitor = Janitor.new() :: Janitor
	
	return self
end

function InfoPanel:Refresh()
	if self._currentItem then
		self:Update(self._currentItem)
	end
end

-- Callback to get toolbar slots (set by init.luau)
InfoPanel.GetToolbarSlots = nil :: (() -> {[number]: string?})?

-- Callback when equip state changes (set by init.luau to refresh toolbar)
InfoPanel.OnEquipChanged = nil :: (() -> ())?

function InfoPanel:Update(item: InventoryItem?)
	self._janitor:Cleanup()
	self._buttonJanitor:Cleanup()
	self._currentItem = item
    
    -- Target the ScrollingFrame inside the InfoPanel
    local container = self.Frame:FindFirstChild("ScrollingFrame")
    if not container then
        warn("[InfoPanel] ScrollingFrame not found in InfoPanel frame")
        return
    end
    
	-- Clear previous items but preserve layout
	for _, child in container:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIGridLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
	
	-- Setup button handlers (EquipButton and DeleteButton are outside ScrollingFrame)
	local equipButton = self.Frame:FindFirstChild("EquipButton") :: GuiButton?
	local deleteButton = self.Frame:FindFirstChild("DeleteButton") :: GuiButton?
	
	if equipButton then
		equipButton.Visible = item ~= nil
		if item then
			-- Check if item is already equipped
			local toolbarSlots: {[number]: string?} = {}
			if InfoPanel.GetToolbarSlots then
				toolbarSlots = InfoPanel.GetToolbarSlots()
			end
			
			local equippedSlot: number? = nil
			for slot, itemId in pairs(toolbarSlots) do
				if itemId == item.Id then
					equippedSlot = slot
					break
				end
			end
			
			local isEquipped = equippedSlot ~= nil
			
			-- Update button appearance
			local textLabel = equipButton:FindFirstChild("TextLabel") :: TextLabel?
			if isEquipped then
				if equipButton:IsA("ImageButton") then
					equipButton.ImageColor3 = Color3.fromRGB(200, 50, 50) -- Red
				end
				if textLabel then
					textLabel.Text = "Unequip"
				end
			else
				if equipButton:IsA("ImageButton") then
					equipButton.ImageColor3 = Color3.fromRGB(50, 200, 50) -- Green
				end
				if textLabel then
					textLabel.Text = "Equip"
				end
			end
			
			self._buttonJanitor:Add(equipButton.Activated:Connect(function()
				if not self._currentItem then return end
				
				if isEquipped and equippedSlot then
					-- Unequip: Remove from toolbar
					Packets.inventoryAction.send({
						action = "RemoveToolbar",
						itemId = self._currentItem.Id,
						slot = equippedSlot,
					})
					
					-- Refresh handled by toolbar update packet
				else
					-- Equip: Find first empty toolbar slot (1-9)
					local currentSlots: {[number]: string?} = {}
					if InfoPanel.GetToolbarSlots then
						currentSlots = InfoPanel.GetToolbarSlots()
					end
					
					local firstEmptySlot: number? = nil
					for i = 1, 9 do
						if not currentSlots[i] or currentSlots[i] == "" then
							firstEmptySlot = i
							break
						end
					end
					
					if firstEmptySlot then
						Packets.inventoryAction.send({
							action = "AssignToolbar",
							itemId = self._currentItem.Id,
							slot = firstEmptySlot,
						})
						
						-- Refresh handled by toolbar update packet
					else
						warn("[InfoPanel] No empty toolbar slot available")
					end
				end
			end), "Disconnect")
		end
	end
	
	if deleteButton then
		deleteButton.Visible = item ~= nil
		if item then
			self._buttonJanitor:Add(deleteButton.Activated:Connect(function()
				if not self._currentItem then return end
				
				Packets.inventoryAction.send({
					action = "DeleteItem",
					itemId = self._currentItem.Id,
				})
				
				-- Clear the panel after delete
				self:Update(nil)
			end), "Disconnect")
		end
	end
	
	if not item then return end
	
	local layout = getLayoutConfig(item)
	if not layout then
		warn("[InfoPanel] No layout found for item:", item.TemplateId)
		return
	end
	
	-- Track layout order across all components
	local currentLayoutOrder = 0
	
	for _, entry in ipairs(layout) do
		local componentName = ""
		local props = {}
		
		if type(entry) == "string" then
			componentName = entry
		elseif type(entry) == "table" then
			componentName = entry[1] or entry.Component
			props = entry
		end
		
		if componentName then
			local template = getComponentTemplate(componentName)
			if template then
				-- Check if template is a Folder (contains multiple children)
				if template:IsA("Folder") then
					-- Clone each child from the folder individually
					local children = template:GetChildren()
					-- Sort by existing LayoutOrder if present
					table.sort(children, function(a, b)
						local orderA = if a:IsA("GuiObject") then a.LayoutOrder else 0
						local orderB = if b:IsA("GuiObject") then b.LayoutOrder else 0
						return orderA < orderB
					end)
					
					-- Store cloned instances for Mount function
					local clonedInstances: {GuiObject} = {}
					
					for _, child in ipairs(children) do
						if child:IsA("GuiObject") then
							currentLayoutOrder += 1
							local instance = child:Clone()
							instance.LayoutOrder = currentLayoutOrder
							instance.Parent = container
							self._janitor:Add(instance)
							table.insert(clonedInstances, instance)
						end
					end
					
					-- Try to run Mount on the component module with all cloned instances
					local componentModuleScript = script.Parent.Components:FindFirstChild(componentName)
					if componentModuleScript and componentModuleScript:IsA("ModuleScript") then
						local componentModule = require(componentModuleScript)
						if componentModule.Mount then
							-- Mount with the array of cloned instances
							componentModule.Mount(clonedInstances, item, props)
						end
					end
				else
					-- Single GuiObject template
					currentLayoutOrder += 1
					local instance = template:Clone() :: GuiObject
					instance.LayoutOrder = currentLayoutOrder
					instance.Parent = container
					self._janitor:Add(instance)
					
					-- Try to identify component logic script
					local componentModuleScript = script.Parent.Components:FindFirstChild(componentName)
					if componentModuleScript and componentModuleScript:IsA("ModuleScript") then
						local componentModule = require(componentModuleScript)
						if componentModule.Mount then
							componentModule.Mount(instance, item, props)
						end
					end
				end
			end
		end
	end
end

function InfoPanel:Destroy()
	self._buttonJanitor:Destroy()
	self._janitor:Destroy()
end

return InfoPanel

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- local RunService = game:GetService("RunService")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Packages = Rojo:WaitForChild("Packages")
local Shared = Rojo:WaitForChild("Shared")

local Janitor = require(Packages:WaitForChild("janitor"))
local Inventory = require(Shared:WaitForChild("Inventory"))

-- Types
type Janitor = typeof(Janitor.new())
type InventoryItem = Inventory.InventoryItem

local InfoPanel = {}
InfoPanel.__index = InfoPanel

-- Cache to avoid repeated lookups
local componentsCache: {[string]: GuiObject} = {}

local function getComponentTemplate(name: string): GuiObject?
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
				if template and template:IsA("GuiObject") then
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
	local config = ReplicatedStorage:FindFirstChild("Config")
	if not config then return nil end
	
	-- 1. Check Item Specific Layout
	-- Assuming structure: Config.Items.Category.ItemName.InfoLayout (ModuleScript)
	-- We need to find the item config first.
	local items = config:FindFirstChild("Items")
	if items then
		-- Recursive search (optimized? no, simple scan)
		-- TODO: Refactor existing config lookup to be shared if possible, but for now:
		local function searchRecursive(parent: Instance): Instance?
			for _, child in parent:GetChildren() do
				if child.Name == item.TemplateId and child:IsA("Configuration") then
					return child
				elseif child:IsA("Folder") then
					local found = searchRecursive(child)
					if found then return found end
				end
			end
			return nil
		end
		
		local itemConfig = searchRecursive(items)
		if itemConfig then
			local layoutModule = itemConfig:FindFirstChild("InfoPanelLayout") or itemConfig:FindFirstChild("Layout")
			if layoutModule and layoutModule:IsA("ModuleScript") then
				return require(layoutModule) :: {any}
			end
		end
	end
	
	-- 2. Check Type Specific Layout
	local invConfig = config:FindFirstChild("Inventory")
	if invConfig then
		local layouts = invConfig:FindFirstChild("Layouts")
		if layouts then
			local types = layouts:FindFirstChild("Types")
			if types then
				local typeModule = types:FindFirstChild(item.Type)
				if typeModule and typeModule:IsA("ModuleScript") then
					return require(typeModule) :: {any}
				end
			end
			
			-- 3. Check Default Layout
			local defaultModule = layouts:FindFirstChild("Default")
			if defaultModule and defaultModule:IsA("ModuleScript") then
				return require(defaultModule) :: {any}
			end
		end
	end
	
	-- Fallback hardcoded if absolutely nothing found (shouldn't happen if user set up config)
	return {"ItemIcon", "RarityLabel", "Separator"}
end

function InfoPanel.new(frame: Frame)
	local self = setmetatable({}, InfoPanel)
	
	self.Frame = frame
	self._janitor = Janitor.new()
	
	return self
end

function InfoPanel:Update(item: InventoryItem?)
	self._janitor:Cleanup()
    
    -- Target the ScrollingFrame inside the InfoPanel
    local container = self.Frame:FindFirstChild("ScrollingFrame")
    if not container then
        warn("[InfoPanel] ScrollingFrame not found in InfoPanel frame")
        return
    end
    
	container:ClearAllChildren()
	
	-- Add Layout
	-- User specified layout already exists, so we don't create one.
	-- local uiList = Instance.new("UIListLayout") ...

	
	if not item then return end
	
	local layout = getLayoutConfig(item)
	if not layout then
		warn("[InfoPanel] No layout found for item:", item.TemplateId)
		return
	end
	
	for i, entry in ipairs(layout) do
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
				local instance = template:Clone()
				instance.LayoutOrder = i
				instance.Parent = container -- Parent to the ScrollingFrame
				self._janitor:Add(instance)
				
				-- Try to identify component logic script
				-- Assuming components are in script.Parent.Components
				local componentModuleScript = script.Parent.Components:FindFirstChild(componentName)
				if componentModuleScript and componentModuleScript:IsA("ModuleScript") then
					local componentModule = require(componentModuleScript)
					if componentModule.Mount then
						-- Mount(instance, item, props, janitor)
						componentModule.Mount(instance, item, props)
					end
				else
					-- No specific logic, generic binding?
					-- Maybe just applying props to attributes?
				end
			end
		end
	end
end

function InfoPanel:Destroy()
	self._janitor:Destroy()
end

return InfoPanel

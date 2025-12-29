--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")
local Inventory = require(Shared:WaitForChild("Inventory"))

type InventoryItem = Inventory.InventoryItem

local Events = {}

function Events.Mount(instance: GuiObject, item: InventoryItem, props: any)
	-- Clear previous children
	for _, child in instance:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIGridLayout") and not child:IsA("UIPadding") and not child:IsA("UIStroke") and not child:IsA("UICorner") then
			child:Destroy()
		end
	end

    -- Check for mutations
	if not item.Metadata or not item.Metadata.Mutations then
		instance.Visible = false
		return
	end

	local mutations = item.Metadata.Mutations
	local hasMutations = false
	
    -- Locate icons folder
	local config = ReplicatedStorage:FindFirstChild("Config")
	local eventsIconsFolder = config 
        and config:FindFirstChild("Inventory") 
        and config.Inventory:FindFirstChild("UIComponents") 
        and config.Inventory.UIComponents:FindFirstChild("EventsIcons")
	
	if not eventsIconsFolder then
		warn("[Events Component] EventsIcons folder not found in Config.Inventory.UIComponents")
		instance.Visible = false
		return
	end

	for mutationName, _ in pairs(mutations) do
        hasMutations = true
		local iconTemplate = eventsIconsFolder:FindFirstChild(mutationName)
		if iconTemplate then
			local icon = iconTemplate:Clone()
			icon.Parent = instance
			icon.Visible = true
		else
			-- Optional: warn if icon missing
			-- warn("[Events Component] Icon for mutation not found:", mutationName)
		end
	end

	instance.Visible = hasMutations
end

return Events

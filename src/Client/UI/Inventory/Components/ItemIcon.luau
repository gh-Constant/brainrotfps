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

    -- 3. Set Rarity Gradient (ItemIcon itself or UIGradient child)
    local rarity = item.Rarity
    local customColor = item.Metadata and item.Metadata.CustomColor
    
    -- Fallback to config rarity if item instance doesn't have it (shouldn't happen for items in inv)
    if not rarity and props.FallbackRarity then
        rarity = props.FallbackRarity
    end

    local style = customColor
    if not style then
       style = RarityConfig.GetBackgroundStyle(rarity or "Common")
    end
    
    -- Does the template have a UIGradient child, or should we apply to background?
    -- User said "ItemIcon uigradiant set to the rarity"
    -- ColorSystem.ApplyToBackground handles finding UIGradient or creating it.
    ColorSystem.ApplyToBackground(instance, style)
    
    -- Also apply to stroke if exists

end

return ItemIcon

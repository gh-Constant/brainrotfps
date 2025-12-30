--!strict
--[[
    Slot Renderer
    Centralized slot UI rendering logic shared between:
    - Inventory grid slots (init.luau)
    - HUD toolbar slots (Toolbar.luau)
    - Integrated toolbar slots (init.luau)
    
    This module handles updating slot UI elements:
    - Icon (ToolIcon ImageLabel)
    - Name (ToolNameLabel/NameLabel TextLabel)
    - Quantity (QuantityLabel TextLabel)
    - Rarity label and colors
    - Events/mutations label
    - Background styling via ColorSystem
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")

local ItemUtils = require(Shared:WaitForChild("Inventory"):WaitForChild("ItemUtils"))
local RarityConfig = require(Shared:WaitForChild("Rarity"):WaitForChild("RarityConfig"))
local ColorSystem = require(Shared:WaitForChild("Inventory"):WaitForChild("ColorSystem"))

-- Types
export type SlotRenderData = {
    TemplateId: string,
    Rarity: string?,
    Count: number?,
    IsEquipped: boolean?,
    EquippedSlot: number?,
    Metadata: {
        CustomColor: string?,
        Mutations: {[string]: number}?,
        [string]: any,
    }?,
}

local SlotRenderer = {}

-- Default icon for empty/missing items
local DEFAULT_ICON = "rbxassetid://6031763426"

--------------------------------------------------------------------------------
-- Private Helpers
--------------------------------------------------------------------------------

--[[
    Gets the effective style for a slot (CustomColor > Rarity-based).
]]
local function getEffectiveStyle(templateId: string, rarity: string?, metadata: {CustomColor: string?, [string]: any}?): string?
    -- Check metadata CustomColor first
    if metadata and metadata.CustomColor and metadata.CustomColor ~= "" then
        return metadata.CustomColor
    end
    
    -- Check config CustomColor
    local configStyle = ItemUtils.GetBackgroundStyle(templateId, rarity)
    if configStyle then
        return configStyle
    end
    
    -- Fall back to rarity-based style
    return RarityConfig.GetBackgroundStyle(rarity) or nil
end

--[[
    Gets the effective text style for a slot.
]]
local function getEffectiveTextStyle(templateId: string, rarity: string?): string?
    -- Check config CustomTextColor first
    local configStyle = ItemUtils.GetTextStyle(templateId)
    if configStyle then
        return configStyle
    end
    
    -- Fall back to rarity-based style
    return RarityConfig.GetTextStyle(rarity or "Common")
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--[[
    Renders item data to a slot frame.
    Updates all UI elements: icon, name, quantity, rarity, events, background.
    
    @param frame - The slot frame (ImageLabel or Frame)
    @param data - The render data, or nil to clear the slot
]]
function SlotRenderer.RenderSlot(frame: GuiObject, data: SlotRenderData?)
    if not data then
        SlotRenderer.ClearSlot(frame)
        return
    end
    
    -- Cache element lookups
    local toolIcon = frame:FindFirstChild("ToolIcon") :: ImageLabel?
    local nameLabel = (frame:FindFirstChild("NameLabel") or frame:FindFirstChild("ToolNameLabel")) :: TextLabel?
    local quantityLabel = frame:FindFirstChild("QuantityLabel") :: TextLabel?
    local eventsLabel = frame:FindFirstChild("EventsLabel") :: TextLabel?
    local rarityLabel = frame:FindFirstChild("RarityLabel") :: TextLabel?
    local toolBarPosLabel = frame:FindFirstChild("ToolBarPos") :: TextLabel?
    local hotkeyLabel = frame:FindFirstChild("HotkeyLabel") :: TextLabel?
    
    -- Update Icon
    if toolIcon then
        local imageId = ItemUtils.GetItemImage(data.TemplateId)
        toolIcon.Image = if imageId ~= "" then imageId else DEFAULT_ICON
        toolIcon.Visible = true
    end
    
    -- Update Name
    if nameLabel then
        nameLabel.Text = ItemUtils.GetDisplayName(data.TemplateId)
        nameLabel.Visible = true
    end
    
    -- Update Quantity
    if quantityLabel then
        local count = data.Count or 1
        if count > 1 then
            quantityLabel.Text = "x" .. tostring(count)
            quantityLabel.Visible = true
        else
            quantityLabel.Text = ""
            quantityLabel.Visible = false
        end
    end
    
    -- Update Rarity Label
    if rarityLabel then
        local rarity = data.Rarity or "Common"
        rarityLabel.Text = rarity
        rarityLabel.Visible = true
        
        local textStyle = getEffectiveTextStyle(data.TemplateId, rarity)
        ColorSystem.ApplyToText(rarityLabel, textStyle)
    end
    
    -- Update Events Label (Mutations)
    if eventsLabel then
        local mutationCount = 0
        if data.Metadata and data.Metadata.Mutations then
            for _ in pairs(data.Metadata.Mutations) do
                mutationCount = mutationCount + 1
            end
        end
        
        if mutationCount > 0 then
            eventsLabel.Text = tostring(mutationCount) .. " " .. (mutationCount == 1 and "Event" or "Events")
            eventsLabel.Visible = true
        else
            eventsLabel.Text = ""
            eventsLabel.Visible = false
        end
    end
    
    -- Update Toolbar Position Label
    if toolBarPosLabel then
        if data.IsEquipped and data.EquippedSlot then
            toolBarPosLabel.Text = tostring(data.EquippedSlot)
            toolBarPosLabel.Visible = true
        else
            toolBarPosLabel.Visible = false
        end
    end
    
    -- Always show hotkey if present and has an equipped slot
    if hotkeyLabel and data.EquippedSlot then
        hotkeyLabel.Text = tostring(data.EquippedSlot)
        hotkeyLabel.Visible = true
    end
    
    -- Apply Background Style
    local style = getEffectiveStyle(data.TemplateId, data.Rarity, data.Metadata)
    ColorSystem.ApplyToBackground(frame :: Frame, style)
    
    frame.Visible = true
end

--[[
    Clears a slot to empty state.
    Resets all UI elements and removes styling.
    
    @param frame - The slot frame to clear
]]
function SlotRenderer.ClearSlot(frame: GuiObject)
    local toolIcon = frame:FindFirstChild("ToolIcon") :: ImageLabel?
    if toolIcon then
        toolIcon.Image = ""
        toolIcon.Visible = false
    end
    
    local nameLabel = (frame:FindFirstChild("NameLabel") or frame:FindFirstChild("ToolNameLabel")) :: TextLabel?
    if nameLabel then
        nameLabel.Text = ""
        nameLabel.Visible = false
    end
    
    local quantityLabel = frame:FindFirstChild("QuantityLabel") :: TextLabel?
    if quantityLabel then
        quantityLabel.Text = ""
        quantityLabel.Visible = false
    end
    
    local eventsLabel = frame:FindFirstChild("EventsLabel") :: TextLabel?
    if eventsLabel then
        eventsLabel.Text = ""
        eventsLabel.Visible = false
    end
    
    local rarityLabel = frame:FindFirstChild("RarityLabel") :: TextLabel?
    if rarityLabel then
        rarityLabel.Visible = false
    end
    
    local toolBarPosLabel = frame:FindFirstChild("ToolBarPos") :: TextLabel?
    if toolBarPosLabel then
        toolBarPosLabel.Visible = false
    end
    
    -- Clear background styling
    ColorSystem.ApplyToBackground(frame :: Frame, nil)
    ColorSystem.ApplyToFrame(frame :: Frame, nil)
end

--[[
    Updates the equipped state visual on a slot.
    Changes the border stroke color.
    
    @param frame - The slot frame
    @param isEquipped - Whether the item is currently equipped
]]
function SlotRenderer.SetEquipState(frame: GuiObject, isEquipped: boolean)
    local stroke = frame:FindFirstChild("BorderStroke") :: UIStroke?
    if not stroke then
        stroke = frame:FindFirstChildWhichIsA("UIStroke") :: UIStroke?
    end
    
    if stroke then
        if isEquipped then
            stroke.Color = Color3.fromRGB(100, 255, 100) -- Green when equipped
        else
            stroke.Color = Color3.fromRGB(48, 48, 48) -- Default gray
        end
    end
end

--[[
    Updates the hotkey label on a slot.
    
    @param frame - The slot frame
    @param hotkey - The hotkey number (1-9) or nil to hide
]]
function SlotRenderer.SetHotkey(frame: GuiObject, hotkey: number?)
    local hotkeyLabel = frame:FindFirstChild("HotkeyLabel") :: TextLabel?
    if hotkeyLabel then
        if hotkey then
            hotkeyLabel.Text = tostring(hotkey)
            hotkeyLabel.Visible = true
        else
            hotkeyLabel.Text = ""
            hotkeyLabel.Visible = false
        end
    end
end

return SlotRenderer

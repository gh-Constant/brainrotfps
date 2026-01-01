--!strict
--[[
    Item Slot Component - PERFORMANCE OPTIMIZED
    Renders a single inventory slot using the EXISTING template elements.
    
    PERFORMANCE OPTIMIZATIONS:
    - Uses ViewportRotationManager for centralized rotation (single Heartbeat loop)
    - No per-slot RenderStepped connections
    - ColorSystem requires moved to top-level
    
    Template Hierarchy (ItemSlot [ImageLabel]):
    ├── ToolIcon [ImageLabel] - Shows tool texture
    ├── ViewportFrame [ViewportFrame] - 3D model display
    ├── UIGradient [UIGradient] - Rarity colors
    ├── UIAspectRatioConstraint
    ├── NameLabel [TextLabel] - Item name
    ├── QuantityLabel [TextLabel] - Stack count (x5)
    └── EventsLabel [TextLabel] - Event tags
    
    This module does NOT create new UI elements - it only modifies existing ones.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Packages = Rojo:WaitForChild("Packages")
local Shared = Rojo:WaitForChild("Shared")

local Janitor = require(Packages:WaitForChild("janitor"))
local Signal = require(Packages:WaitForChild("signal"))
local RarityConfig = require(Shared:WaitForChild("Rarity"):WaitForChild("RarityConfig"))
local ItemUtils = require(Shared:WaitForChild("Inventory"):WaitForChild("ItemUtils"))
local ColorSystem = require(Shared:WaitForChild("Inventory"):WaitForChild("ColorSystem"))
local Logger = require(Shared:WaitForChild("Inventory"):WaitForChild("Logger"))

-- Import centralized visibility manager
local InventoryVisibilityManager = require(script.Parent:WaitForChild("InventoryVisibilityManager"))
local VisualUtils = require(script.Parent:WaitForChild("VisualUtils"))

-- Types
type Janitor = typeof(Janitor.new())

export type ItemSlotData = {
    TemplateId: string,
    Type: string,
    Rarity: string?,
    Count: number,
    ItemIds: {string},
    IsEquipped: boolean?,
    EquippedSlot: number?,
    Metadata: {
        CustomColor: string?,
        [string]: any,
    }?,
    MaybeDuped: boolean?,
}

export type ItemSlot = {
    Frame: GuiObject,
    Data: ItemSlotData?,
    SetData: (self: ItemSlot, data: ItemSlotData?) -> (),
    SetSelected: (self: ItemSlot, selected: boolean) -> (),
    Destroy: (self: ItemSlot) -> (),
    OnDeleteClicked: any, -- Signal
}

local ItemSlotModule = {}
ItemSlotModule.__index = ItemSlotModule

-- Cache for item configs
local function getItemConfig(templateId: string): Configuration?
    return ItemUtils.FindItemConfig(templateId)
end

function ItemSlotModule.new(parent: GuiObject?, template: GuiObject?): ItemSlot
    local self = setmetatable({}, ItemSlotModule)
    
    self._janitor = Janitor.new()
    self._model = nil
    self._viewport = nil
    self._highlight = nil
    
    if template then
        self.Frame = template:Clone()
    else
        warn("[ItemSlot] No template provided! Creating minimal fallback.")
        local fallback = Instance.new("ImageLabel")
        fallback.Name = "ItemSlot"
        fallback.Size = UDim2.fromScale(1, 1)
        fallback.BackgroundTransparency = 1
        self.Frame = fallback
    end
    
    self.Data = nil :: ItemSlotData?
    self.OnDeleteClicked = Signal.new()
    
    if parent then
        self.Frame.Parent = parent
    end
    
    return self :: any
end

function ItemSlotModule:SetData(data: ItemSlotData?)
    if not data then
        self._janitor:Cleanup()
        self.Data = nil
        
        InventoryVisibilityManager.Unregister(self.Frame)
        self._viewport = nil
        
        -- Reset visuals
        local toolIcon = self.Frame:FindFirstChild("ToolIcon") :: ImageLabel?
        if toolIcon then toolIcon.Visible = false end
        local viewport = self.Frame:FindFirstChild("ViewportFrame") :: ViewportFrame?
        if viewport then viewport.Visible = false end
        local quantityLabel = self.Frame:FindFirstChild("QuantityLabel") :: TextLabel?
        if quantityLabel then quantityLabel.Visible = false end
        local nameLabel = self.Frame:FindFirstChild("NameLabel") :: TextLabel?
        if nameLabel then nameLabel.Visible = false end
        local deleteButton = self.Frame:FindFirstChild("DeleteButton") :: TextButton?
        if deleteButton then deleteButton.Visible = false end
        local eventsLabel = self.Frame:FindFirstChild("EventsLabel") :: TextLabel?
        if eventsLabel then eventsLabel.Visible = false end
        local toolBarPosLabel = self.Frame:FindFirstChild("ToolBarPos") :: TextLabel?
        if toolBarPosLabel then toolBarPosLabel.Visible = false end
        local rarityLabel = self.Frame:FindFirstChild("RarityLabel") :: TextLabel?
        if rarityLabel then rarityLabel.Visible = false end
        
        ColorSystem.ApplyToBackground(self.Frame :: Frame, nil)
        
        return
    end
    
    -- Check for reuse
    local isReuse = false
    if self.Data and self.Data.TemplateId == data.TemplateId then
        isReuse = true
        local newStyle = data.Metadata and data.Metadata.CustomColor 
        if not newStyle then newStyle = RarityConfig.GetBackgroundStyle(data.Rarity) end
        local oldStyle = self.Data.Metadata and self.Data.Metadata.CustomColor
        if not oldStyle then oldStyle = RarityConfig.GetBackgroundStyle(self.Data.Rarity) end
        
        if newStyle ~= oldStyle then isReuse = false end
    end

    if isReuse then
        self._janitor:Remove("DeleteButton")
    else
        InventoryVisibilityManager.Unregister(self.Frame)
        self._viewport = nil
        self._janitor:Cleanup()
    end
    
    self.Data = data
    
    -- Cache element lookups
    local toolIcon = self.Frame:FindFirstChild("ToolIcon") :: ImageLabel?
    local viewport = self.Frame:FindFirstChild("ViewportFrame") :: ViewportFrame?
    local quantityLabel = self.Frame:FindFirstChild("QuantityLabel") :: TextLabel?
    local nameLabel = (self.Frame:FindFirstChild("NameLabel") or self.Frame:FindFirstChild("ToolNameLabel")) :: TextLabel?
    local deleteButton = self.Frame:FindFirstChild("DeleteButton") :: TextButton?
    local eventsLabel = self.Frame:FindFirstChild("EventsLabel") :: TextLabel?
    local toolBarPosLabel = self.Frame:FindFirstChild("ToolBarPos") :: TextLabel?
    local rarityLabel = self.Frame:FindFirstChild("RarityLabel") :: TextLabel?
    
    -- Update Lightweight UI (Labels)
    if rarityLabel then
        local rarity = data.Rarity or "Common"
        rarityLabel.Text = rarity
        rarityLabel.Visible = true
        
        -- Style Priority: Config Attribute > Rarity
        local style = nil
        local itemConfig = getItemConfig(data.TemplateId)
        if itemConfig then
            style = itemConfig:GetAttribute("CustomTextColor")
        end
        
        if not style then
             style = RarityConfig.GetTextStyle(rarity)
        end
        
        ColorSystem.ApplyToText(rarityLabel, style)
    end
    if quantityLabel then
        if data.Count > 1 then
            quantityLabel.Text = "x" .. tostring(data.Count)
            quantityLabel.Visible = true
        else
            quantityLabel.Visible = false
        end
    end
    
    if nameLabel then
        local displayName = data.TemplateId
        local itemConfig = getItemConfig(data.TemplateId)
        if itemConfig then
            local dn = itemConfig:GetAttribute("DisplayName")
            if dn and dn ~= "" then displayName = dn end
        end
        nameLabel.Text = displayName
        nameLabel.Visible = true
    end
    
    if eventsLabel then
        local count = 0
        if data.Metadata and data.Metadata.Mutations then
            for _ in pairs(data.Metadata.Mutations) do count = count + 1 end
        end
        
        if data.Metadata and data.Metadata.OverrideEventsText then
            eventsLabel.Text = data.Metadata.OverrideEventsText
            eventsLabel.Visible = true
        elseif count > 0 then
            eventsLabel.Text = tostring(count) .. " " .. (count == 1 and "Event" or "Events")
            eventsLabel.Visible = true
            
            -- Apply dynamic color based on event count
            local eventRarity = RarityConfig.GetEventRarity(count)
            local style = RarityConfig.GetTextStyle(eventRarity)
            ColorSystem.ApplyToText(eventsLabel, style)
        else
            eventsLabel.Visible = false
        end
    end
    
    if toolBarPosLabel then
        if data.IsEquipped and data.EquippedSlot then
            toolBarPosLabel.Text = tostring(data.EquippedSlot)
            toolBarPosLabel.Visible = true
        else
            toolBarPosLabel.Visible = false
        end
    end
    
    if deleteButton then
        deleteButton.Visible = true
        self._janitor:Add(deleteButton.MouseButton1Click:Connect(function()
            self.OnDeleteClicked:Fire(data)
        end), "Disconnect", "DeleteButton")
    end

    -- Update Heavy UI (if not reused)
    if not isReuse then
        -- Style Priority: Config Attribute > Rarity
        local style = nil
        local itemConfig = getItemConfig(data.TemplateId)
        if itemConfig then
            style = itemConfig:GetAttribute("CustomColor")
        end
        
        if not style then
           style = RarityConfig.GetBackgroundStyle(data.Rarity)
        end
        
        ColorSystem.ApplyToBackground(self.Frame :: Frame, style)

        
        -- Model Setup
        local itemModel, isCustom = VisualUtils.FindItemModel(data.TemplateId)
        if itemModel and viewport then
            if toolIcon then toolIcon.Visible = false end
            
            local modelClone = VisualUtils.CloneModelForDisplay(itemModel, isCustom)
            if modelClone then
                local worldModel = viewport:FindFirstChild("WorldModel") :: WorldModel?
                if not worldModel then
                    worldModel = Instance.new("WorldModel"); worldModel.Name = "WorldModel"; worldModel.Parent = viewport
                end
                
                modelClone.Parent = worldModel
                self._model = modelClone
                self._janitor:Add(modelClone, "Destroy", "Model")
                
                -- Highlight
                local highlight = worldModel:FindFirstChild("Highlight")
                if not highlight then
                     highlight = ColorSystem.CreateHighlight(style)
                     highlight.Parent = worldModel
                end
                ColorSystem.ApplyToHighlight(highlight, style)
                
                -- Global Camera Setup (Consistent Zoom)
                local camera = VisualUtils.SetupModelCamera(viewport, modelClone)
                
                -- Play Idle Animation
                local animsFolder = ReplicatedStorage:FindFirstChild("BrainrotAnimations")
                if animsFolder then
                    local modelAnims = animsFolder:FindFirstChild(data.TemplateId)
                    if modelAnims then
                        local idleAnim = modelAnims:FindFirstChild("Idle")
                        local animController = modelClone:FindFirstChild("AnimationController") or modelClone:FindFirstChildWhichIsA("Humanoid")
                        
                        if idleAnim and idleAnim:IsA("Animation") and animController then
                            -- FIX: Ensure parts are unanchored so Motor6Ds can animate them
                            -- except the PrimaryPart/Root which holds it in place
                            local root = modelClone.PrimaryPart or modelClone:FindFirstChild("Body") or modelClone:FindFirstChild("HumanoidRootPart")
                            
                            for _, desc in ipairs(modelClone:GetDescendants()) do
                                if desc:IsA("BasePart") then
                                    if root and desc == root then
                                        desc.Anchored = true
                                    else
                                        desc.Anchored = false
                                    end
                                end
                            end

                            local animator = animController:FindFirstChild("Animator") :: Animator?
                            if not animator then
                                animator = Instance.new("Animator")
                                animator.Parent = animController
                            end
                            
                            if animator then
                                 local track = animator:LoadAnimation(idleAnim)
                                 track:Play()
                            end
                        end
                    end
                end

                local cf, size = modelClone:GetBoundingBox()
                local maxSize = math.max(size.X, size.Y, size.Z)
                local distance = maxSize * 0.8 -- Matches VisualUtils default
                
                -- PERFORMANCE: Register with centralized visibility manager (handles both culling and rotation)
                self._viewport = viewport
                
                InventoryVisibilityManager.Register(self.Frame, {
                    ToolIcon = nil, -- Explicitly hidden for 3D view
                    Viewport = viewport,
                    NameLabel = nameLabel,
                    QuantityLabel = if quantityLabel and quantityLabel.Visible then quantityLabel else nil,
                    EventsLabel = if eventsLabel and eventsLabel.Visible then eventsLabel else nil,
                    RarityLabel = rarityLabel,
                    
                    Camera = camera,
                    Model = modelClone,
                    CenterCF = cf,
                    Distance = distance,
                })
                
                viewport.Visible = true
            else
                 -- Fallback (Icon Only)
                 if viewport then viewport.Visible = false end
                 if toolIcon then toolIcon.Image = VisualUtils.GetItemImage(data.TemplateId); toolIcon.Visible = true end
                 
                 -- Register for 2D culling even if no 3D model
                 InventoryVisibilityManager.Register(self.Frame, {
                    ToolIcon = toolIcon,
                    Viewport = nil,
                    NameLabel = nameLabel,
                    QuantityLabel = if quantityLabel and quantityLabel.Visible then quantityLabel else nil,
                    EventsLabel = if eventsLabel and eventsLabel.Visible then eventsLabel else nil,
                    RarityLabel = rarityLabel,
                 })
            end
        else
            -- No 3D Model logic
            if viewport then viewport.Visible = false end
            if toolIcon then toolIcon.Image = VisualUtils.GetItemImage(data.TemplateId); toolIcon.Visible = true end
            
            -- Register for 2D culling
             InventoryVisibilityManager.Register(self.Frame, {
                ToolIcon = toolIcon,
                Viewport = nil,
                NameLabel = nameLabel,
                QuantityLabel = if quantityLabel and quantityLabel.Visible then quantityLabel else nil,
                EventsLabel = if eventsLabel and eventsLabel.Visible then eventsLabel else nil,
                RarityLabel = rarityLabel,
             })
        end
    end
    
    self.Frame.Visible = true
    
    -- Final sync of 2D visibility state (handles Reuse case and ensures correct elements are managed)
    InventoryVisibilityManager.UpdateVisibleElements(self.Frame, {
        ToolIcon = if (self._model and self._viewport) then nil else toolIcon, -- Hide icon if 3D model active
        NameLabel = nameLabel,
        QuantityLabel = if quantityLabel and quantityLabel.Visible then quantityLabel else nil,
        EventsLabel = if eventsLabel and eventsLabel.Visible then eventsLabel else nil,
        RarityLabel = rarityLabel,
    })
end

--[[
    Sets whether this slot is selected.
]]
function ItemSlotModule:SetSelected(selected: boolean)
    local selection = self.Frame:FindFirstChild("SelectionStroke") :: UIStroke?
    if selection then
        selection.Transparency = if selected then 0 else 1
    end
end

--[[
    Destroys the item slot.
]]
function ItemSlotModule:Destroy()
    -- Unregister from visibility manager
    InventoryVisibilityManager.Unregister(self.Frame)
    self._viewport = nil
    
    -- Stop any color animations
    ColorSystem.StopAnimation(self.Frame)
    
    self._janitor:Cleanup()
    self.Frame:Destroy()
end

return ItemSlotModule

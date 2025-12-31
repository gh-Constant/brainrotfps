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



-- Types
type Janitor = typeof(Janitor.new())

export type ItemSlotData = {
    TemplateId: string,
    Type: string,
    Rarity: string?,
    Count: number,
    ItemIds: {string}, -- All item IDs in this stack
    IsEquipped: boolean?, -- Whether this item is in a toolbar slot
    EquippedSlot: number?, -- Which toolbar slot (1-9) if equipped
    Metadata: {
        CustomColor: string?,
        [string]: any,
    }?,
    MaybeDuped: boolean?, -- Whether this item might be duplicated
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

--[[
    Gets the Tool instance from inside a Configuration.
]]
local function getToolFromConfig(itemConfig: Configuration): Tool?
    return itemConfig:FindFirstChildWhichIsA("Tool") :: Tool?
end

--[[
    Finds the 3D model for an item based on its ToolModel attribute.
]]
local function findItemModel(templateId: string): Instance?
    local itemConfig = getItemConfig(templateId)
    if not itemConfig then return nil end
    
    local toolModelSource = itemConfig:GetAttribute("ToolModel") :: string?
    
    if toolModelSource == "ToolModels" then
        local config = ReplicatedStorage:FindFirstChild("Config")
        if config then
            local toolModels = config:FindFirstChild("ToolModels")
            if toolModels then
                return toolModels:FindFirstChild(templateId)
            end
        end
    elseif toolModelSource == "ViewModel" then
        local blasterFolder = ReplicatedStorage:FindFirstChild("Blaster")
        if blasterFolder then
            local viewModels = blasterFolder:FindFirstChild("ViewModels")
            if viewModels then
                local viewModelFolder = viewModels:FindFirstChild(templateId)
                if viewModelFolder then
                    return viewModelFolder:FindFirstChild("Blaster")
                end
            end
        end
    elseif toolModelSource == "ToolIcon" then
        return nil -- Force use of image
    end
    
    -- No ToolModel attribute: use the Tool child inside Configuration
    local tool = getToolFromConfig(itemConfig)
    if tool then
        return tool
    end
    
    return nil
end

--[[
    Gets the image for an item (for items without 3D model).
]]
local function getItemImage(templateId: string): string
    local itemConfig = getItemConfig(templateId)
    if not itemConfig then return "" end
    
    local image = itemConfig:GetAttribute("Image") :: string?
    if image and image ~= "" then
        if not string.find(image, "://") then
             image = "rbxassetid://" .. image
        end
        return image
    end
    
    local tool = getToolFromConfig(itemConfig)
    if tool then
        local textureId = tool.TextureId
        if textureId and textureId ~= "" and not string.find(textureId, "://") then
             textureId = "rbxassetid://" .. textureId
        end
        return textureId
    end
    
    return ""
end

--[[
    Clones a model for display in viewport (anchored, no collision).
]]
local function cloneModelForDisplay(sourceModel: Instance): Model?
    local modelClone = Instance.new("Model")
    modelClone.Name = "DisplayModel"
    
    for _, part in sourceModel:GetDescendants() do
        if part:IsA("BasePart") then
            local partClone = part:Clone()
            partClone.Anchored = true
            partClone.CanCollide = false
            partClone.Parent = modelClone
        end
    end
    
    for _, child in sourceModel:GetChildren() do
        if child:IsA("BasePart") and not modelClone:FindFirstChild(child.Name) then
            local partClone = child:Clone()
            partClone.Anchored = true
            partClone.CanCollide = false
            partClone.Parent = modelClone
        end
    end
    
    local primaryPartName = "Handle"
    if sourceModel:IsA("Model") and sourceModel.PrimaryPart then
        primaryPartName = sourceModel.PrimaryPart.Name
    end
    modelClone.PrimaryPart = modelClone:FindFirstChild(primaryPartName) :: BasePart?
    
    if #modelClone:GetChildren() == 0 then
        modelClone:Destroy()
        return nil
    end
    
    return modelClone
end

--[[
    Creates a new ItemSlot using a template.
    Does NOT create new UI elements - only uses existing template elements.
    
    @param parent - Parent GUI object
    @param template - Template to clone (ImageLabel or Frame)
    @return ItemSlot
]]
function ItemSlotModule.new(parent: GuiObject?, template: GuiObject?): ItemSlot
    local self = setmetatable({}, ItemSlotModule)
    
    self._janitor = Janitor.new()
    self._model = nil
    self._viewport = nil
    self._highlight = nil
    
    -- Clone template - DO NOT create new elements
    if template then
        self.Frame = template:Clone()
    else
        -- Fallback: create minimal ImageLabel (shouldn't happen with proper templates)
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

--[[
    Sets the data for this slot.
    Only modifies EXISTING template elements.
    
    @param data - The item stack data, or nil to clear
]]
function ItemSlotModule:SetData(data: ItemSlotData?)
    if not data then
        self._janitor:Cleanup()
        self.Data = nil
        
        -- Unregister from visibility manager if we had a viewport/slot
        InventoryVisibilityManager.Unregister(self.Frame)
        self._viewport = nil
        
        -- Reset visuals for empty slot
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
        ColorSystem.ApplyToFrame(self.Frame :: Frame, nil)
        
        return
    end
    
    -- Check for reuse
    local isReuse = false
    if self.Data and self.Data.TemplateId == data.TemplateId then
        isReuse = true
        -- Check if style changed (rarity/custom color)
        local newStyle = data.Metadata and data.Metadata.CustomColor 
        if not newStyle then
             newStyle = RarityConfig.GetBackgroundStyle(data.Rarity)
        end
        local oldStyle = self.Data.Metadata and self.Data.Metadata.CustomColor
        if not oldStyle then
             oldStyle = RarityConfig.GetBackgroundStyle(self.Data.Rarity)
        end
        
        if newStyle ~= oldStyle then
            isReuse = false -- Force rebuild visuals
        end
    end

    if isReuse then
        -- Only clean up connection listeners, keep visuals
        self._janitor:Remove("DeleteButton")
    else
        -- Clean up old visibility registration
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
        if count > 0 then
            eventsLabel.Text = tostring(count) .. " " .. (count == 1 and "Event" or "Events")
            eventsLabel.Visible = true
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
        local itemModel = findItemModel(data.TemplateId)
        if itemModel and viewport then
            if toolIcon then toolIcon.Visible = false end
            
            local modelClone = cloneModelForDisplay(itemModel)
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
                
                -- Camera
                local camera = viewport:FindFirstChild("Camera") :: Camera?
                if not camera then
                    camera = Instance.new("Camera"); camera.Parent = viewport; viewport.CurrentCamera = camera
                end
                
                local cf, size = modelClone:GetBoundingBox()
                local maxSize = math.max(size.X, size.Y, size.Z)
                local distance = maxSize * 0.5
                
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
                    Distance = distance
                })
                
                viewport.Visible = true
            else
                 -- Fallback (Icon Only)
                 if viewport then viewport.Visible = false end
                 if toolIcon then toolIcon.Image = getItemImage(data.TemplateId); toolIcon.Visible = true end
                 
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
            if toolIcon then toolIcon.Image = getItemImage(data.TemplateId); toolIcon.Visible = true end
            
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
    
    self._janitor:Destroy()
    self.Frame:Destroy()
end

return ItemSlotModule

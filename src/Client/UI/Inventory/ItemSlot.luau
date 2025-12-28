--!strict
--[[
    Item Slot Component
    Renders a single inventory slot using the EXISTING template elements:
    
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

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Packages = Rojo:WaitForChild("Packages")
local Shared = Rojo:WaitForChild("Shared")

local Janitor = require(Packages:WaitForChild("janitor"))
local Rarity = require(Shared:WaitForChild("Rarity"))
local RarityConfig = require(Shared:WaitForChild("Rarity"):WaitForChild("RarityConfig"))

-- Logging helper (checks Config.Inventory.Logging attribute)
local function log(message: string)
	local config = ReplicatedStorage:FindFirstChild("Config")
	if config then
		local invConfig = config:FindFirstChild("Inventory")
		if invConfig and invConfig:GetAttribute("Logging") == true then
			print(message)
		end
	end
end

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

-- Constants
local ROTATION_SPEED = 10 -- Rotations per second

local ItemSlotModule = {}
ItemSlotModule.__index = ItemSlotModule

-- Cache for item configs
local itemConfigCache: {[string]: Configuration} = {}

--[[
    Gets item configuration from Config/Items.
]]
local function getItemConfig(templateId: string): Configuration?
    -- Check cache first
    if itemConfigCache[templateId] then
        return itemConfigCache[templateId]
    end
    
    local config = ReplicatedStorage:FindFirstChild("Config")
    if not config then return nil end
    
    local items = config:FindFirstChild("Items")
    if not items then return nil end
    
    -- Recursive search function for nested folders
    local function searchRecursive(parent: Instance): Configuration?
        for _, child in parent:GetChildren() do
            if child:IsA("Configuration") and child.Name == templateId then
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
        itemConfigCache[templateId] = itemConfig
        return itemConfig
    end
    
    return nil
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
        return image
    end
    
    local tool = getToolFromConfig(itemConfig)
    if tool then
        return tool.TextureId
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
    
    self._janitor = Janitor.new() :: Janitor
    self._rotationConnection = nil :: RBXScriptConnection?
    self._model = nil :: Model?
    self._highlight = nil :: Highlight?
    
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
    self.OnDeleteClicked = require(Packages:WaitForChild("signal")).new()
    
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
    -- Cleanup previous
    self._janitor:Cleanup()
    
    if self._rotationConnection then
        self._rotationConnection:Disconnect()
        self._rotationConnection = nil
    end
    
    self.Data = data
    
    -- Find existing template elements (DO NOT CREATE)
    local toolIcon = self.Frame:FindFirstChild("ToolIcon") :: ImageLabel?
    local viewport = self.Frame:FindFirstChild("ViewportFrame") :: ViewportFrame?
    local gradient = self.Frame:FindFirstChild("UIGradient") :: UIGradient?
    local quantityLabel = self.Frame:FindFirstChild("QuantityLabel") :: TextLabel?
    local nameLabel = self.Frame:FindFirstChild("NameLabel") :: TextLabel?
    local deleteButton = self.Frame:FindFirstChild("DeleteButton") :: TextButton?
    
    -- Clear viewport model if exists
    if viewport then
        local worldModel = viewport:FindFirstChild("WorldModel") :: WorldModel?
        if worldModel then
            for _, child in worldModel:GetChildren() do
                child:Destroy()
            end
        end
    end
    
    -- Clear highlight
    if self._highlight then
        Rarity.StopAnimation(self._highlight)
        self._highlight:Destroy()
        self._highlight = nil
    end
    
    -- Handle empty slot
    if not data then
        if toolIcon then
            toolIcon.Image = ""
            toolIcon.Visible = false
        end
        if viewport then
            viewport.Visible = false
        end
        if quantityLabel then
            quantityLabel.Text = ""
            quantityLabel.Visible = false
        end
        if nameLabel then
            nameLabel.Text = ""
            nameLabel.Visible = false
        end
        if deleteButton then
            deleteButton.Visible = false
        end
        -- Hide ToolBarPos for empty slots
        if toolBarPosLabel then
            toolBarPosLabel.Text = ""
            toolBarPosLabel.Visible = false
        end
        local eventsLabel = self.Frame:FindFirstChild("EventsLabel") :: TextLabel?
        if eventsLabel then
            eventsLabel.Text = ""
            eventsLabel.Visible = false
        end
        -- Reset gradient to default
        local ColorSystem = require(Shared:WaitForChild("Inventory"):WaitForChild("ColorSystem"))
        ColorSystem.ApplyToBackground(self.Frame, nil)
        return
    end
    
    log("[ItemSlot] SetData for: " .. data.TemplateId .. " Type: " .. data.Type .. " Count: " .. tostring(data.Count))
    
            -- Apply visuals
    local style = data.Metadata and data.Metadata.CustomColor
    if not style then
       local RarityConfig = require(Shared:WaitForChild("Rarity"):WaitForChild("RarityConfig"))
       style = RarityConfig.RarityToStyle[data.Rarity]
    end
    
    local ColorSystem = require(Shared:WaitForChild("Inventory"):WaitForChild("ColorSystem"))
    ColorSystem.ApplyToBackground(self.Frame, style)
    
    -- Update quantity using existing QuantityLabel
    if quantityLabel then
        if data.Count > 1 then
            quantityLabel.Text = "x" .. tostring(data.Count)
            quantityLabel.Visible = true
        else
            quantityLabel.Text = ""
            quantityLabel.Visible = false
        end
    end
    
    -- Update name using existing NameLabel
    if nameLabel then
        local itemConfig = getItemConfig(data.TemplateId)
        local displayName = data.TemplateId
        if itemConfig then
            local dn = itemConfig:GetAttribute("DisplayName") :: string?
            if dn and dn ~= "" then
                displayName = dn
            end
        end
        nameLabel.Text = displayName
        nameLabel.Visible = true
    end
    
    -- Update EventsLabel (Mutations)
    local eventsLabel = self.Frame:FindFirstChild("EventsLabel") :: TextLabel?
    if eventsLabel then
        if data.Metadata and data.Metadata.Mutations then
            local mutations = data.Metadata.Mutations
            local count = 0
            for _ in pairs(mutations) do
                count = count + 1
            end
            
            if count > 0 then
                eventsLabel.Text = tostring(count) .. " " .. (count == 1 and "Event" or "Events")
                eventsLabel.Visible = true
            else
                eventsLabel.Text = ""
                eventsLabel.Visible = false
            end
        else
            eventsLabel.Text = ""
            eventsLabel.Visible = false
        end
    end
    
    -- Update ToolBarPos label - only show if equipped in hotbar
    local toolBarPosLabel = self.Frame:FindFirstChild("ToolBarPos") :: TextLabel?
    if toolBarPosLabel then
        if data.IsEquipped and data.EquippedSlot then
            toolBarPosLabel.Text = tostring(data.EquippedSlot)
            toolBarPosLabel.Visible = true
        else
            toolBarPosLabel.Text = ""
            toolBarPosLabel.Visible = false
        end
    end
    
    -- Setup delete button
    if deleteButton then
        deleteButton.Visible = true
        local clickConn = deleteButton.MouseButton1Click:Connect(function()
            self.OnDeleteClicked:Fire(data)
        end)
        self._janitor:Add(clickConn)
    end
    
    -- Try to load 3D model (for Tools or items with ToolModel attribute)
    local itemModel = findItemModel(data.TemplateId)
    
    if itemModel and viewport then
        local modelClone = cloneModelForDisplay(itemModel)
        
        if modelClone then
            -- Setup viewport
            local worldModel = viewport:FindFirstChild("WorldModel") :: WorldModel?
            if not worldModel then
                worldModel = Instance.new("WorldModel")
                worldModel.Name = "WorldModel"
                worldModel.Parent = viewport
            end
            
            modelClone.Parent = worldModel
            self._model = modelClone
            
            -- Setup camera
            local camera = viewport:FindFirstChild("Camera") or viewport:FindFirstChildWhichIsA("Camera")
            if not camera then
                camera = Instance.new("Camera")
                camera.Name = "Camera"
                camera.Parent = viewport
                viewport.CurrentCamera = camera :: Camera
            end
            
            local cf, size = modelClone:GetBoundingBox()
            local maxSize = math.max(size.X, size.Y, size.Z)
            local distance = maxSize * 0.5;
            
            (camera :: Camera).CFrame = CFrame.new(cf.Position + Vector3.new(distance, distance * 0.3, distance), cf.Position)
           -- Visuals
    local style = data.Metadata and data.Metadata.CustomColor
    if not style then
       local RarityConfig = require(Shared:WaitForChild("Rarity"):WaitForChild("RarityConfig"))
       style = RarityConfig.RarityToStyle[data.Rarity]
    end
    
    local ColorSystem = require(Shared:WaitForChild("Inventory"):WaitForChild("ColorSystem"))
    ColorSystem.ApplyToFrame(self.Frame, style, {StrokeThickness = 2})

    -- 3D Highlight
    if worldModel and worldModel:FindFirstChild("Highlight") then
        local highlight = worldModel.Highlight
        ColorSystem.ApplyToHighlight(highlight, style)
    else
        -- Create if missing (though CreateItem usually adds it)
         if modelClone then
            local highlight = ColorSystem.CreateHighlight(style)
            highlight.Parent = modelClone
         end
    end
            local startTime = os.clock()
            local rotationConn = RunService.RenderStepped:Connect(function()
                if modelClone and camera then
                    local elapsed = os.clock() - startTime
                    local angle = elapsed * ROTATION_SPEED * math.pi * 2
                    local rotatedCF = cf * CFrame.Angles(0, angle, 0);
                    (camera :: Camera).CFrame = CFrame.new(rotatedCF.Position + Vector3.new(distance, distance * 0.3, distance), rotatedCF.Position)
                end
            end)
            self._rotationConnection = rotationConn
            self._janitor:Add(rotationConn)
            
            viewport.Visible = true
            if toolIcon then
                toolIcon.Visible = false
            end
        else
            -- Model clone failed, use image fallback
            if viewport then
                viewport.Visible = false
            end
            if toolIcon then
                local img = getItemImage(data.TemplateId)
                toolIcon.Image = img
                toolIcon.Visible = img ~= ""
            end
        end
    else
        -- No 3D model, use existing ToolIcon ImageLabel
        if viewport then
            viewport.Visible = false
        end
        if toolIcon then
            local img = getItemImage(data.TemplateId)
            toolIcon.Image = img
            toolIcon.Visible = img ~= ""
        end
    end
    
    self.Frame.Visible = true
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
    if self._highlight then
        Rarity.StopAnimation(self._highlight)
    end
    Rarity.StopAnimation(self.Frame)
    self._janitor:Destroy()
    self.Frame:Destroy()
end

return ItemSlotModule

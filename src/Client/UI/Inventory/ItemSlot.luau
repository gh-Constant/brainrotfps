--!strict
--[[
    Item Slot Component
    Renders a single inventory slot with:
    - ViewportFrame for 3D Tool models (with rotation)
    - ImageLabel fallback for items without models
    - Highlight with rarity colors
    - Quantity label for stacked items
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Packages = Rojo:WaitForChild("Packages")
local Shared = Rojo:WaitForChild("Shared")

local Janitor = require(Packages:WaitForChild("janitor"))
local Rarity = require(Shared:WaitForChild("Rarity"))

-- Types
type Janitor = typeof(Janitor.new())

export type ItemSlotData = {
    TemplateId: string,
    Type: string,
    Rarity: string?,
    Count: number,
    ItemIds: {string}, -- All item IDs in this stack
}

export type ItemSlot = {
    Frame: Frame,
    Data: ItemSlotData?,
    SetData: (self: ItemSlot, data: ItemSlotData?) -> (),
    SetSelected: (self: ItemSlot, selected: boolean) -> (),
    Destroy: (self: ItemSlot) -> (),
}

-- Constants
local SLOT_SIZE = UDim2.fromOffset(80, 80)
local ROTATION_SPEED = 0.5 -- Rotations per second
local _TOOLS_PATH = "Config.Weapons.Tools" -- Path in ReplicatedStorage (for reference)

local ItemSlotModule = {}
ItemSlotModule.__index = ItemSlotModule

--[[
    Item Configuration Structure (in ReplicatedStorage/Config/Items)
    
    Each item is a Configuration with attributes:
    - Type: string (Tool, Consumable, Material, Ticket, Boost, etc.)
    - Rarity: string? (Common, Uncommon, Epic, Legendary, Mythic, Secret, God)
    - Image: string? (AssetId for items without 3D model)
    - ToolModel: string? ("ToolModels" | "ViewModel" | nil)
        - "ToolModels": Look in Config/ToolModels/{itemName}
        - "ViewModel": Look in Blaster/ViewModels/{itemName}/Blaster
        - nil: Use the Tool child inside the Configuration
    
    Structure:
    Config/Items/Sword (Configuration)
    ├── [Attributes] Type, Rarity, ToolModel, Image
    └── Tool (Tool) ← Optional, if it's an equippable tool
]]

-- Cache for item configs
local itemConfigCache: {[string]: Configuration} = {}

--[[
    Gets item configuration from Config/Items.
    
    @param templateId - The item name
    @return Configuration? - The config, or nil
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
    
    local itemConfig = items:FindFirstChild(templateId)
    if itemConfig and itemConfig:IsA("Configuration") then
        itemConfigCache[templateId] = itemConfig :: Configuration
        return itemConfig :: Configuration
    end
    
    return nil
end

--[[
    Gets the Tool instance from inside a Configuration.
    
    @param itemConfig - The Configuration
    @return Tool? - The Tool child, or nil
]]
local function getToolFromConfig(itemConfig: Configuration): Tool?
    return itemConfig:FindFirstChildWhichIsA("Tool") :: Tool?
end

--[[
    Finds the 3D model for an item based on its ToolModel attribute.
    
    @param templateId - The item name
    @return Instance? - The model to display (Tool or Model), or nil
]]
local function findItemModel(templateId: string): Instance?
    local itemConfig = getItemConfig(templateId)
    if not itemConfig then return nil end
    
    local toolModelSource = itemConfig:GetAttribute("ToolModel") :: string?
    
    if toolModelSource == "ToolModels" then
        -- Look in Config/ToolModels/{itemName}
        local config = ReplicatedStorage:FindFirstChild("Config")
        if config then
            local toolModels = config:FindFirstChild("ToolModels")
            if toolModels then
                return toolModels:FindFirstChild(templateId)
            end
        end
    elseif toolModelSource == "ViewModel" then
        -- Look in Blaster/ViewModels/{itemName}/Blaster
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
    
    @param templateId - The item name
    @return string - The image asset ID, or empty string
]]
local function getItemImage(templateId: string): string
    local itemConfig = getItemConfig(templateId)
    if not itemConfig then return "" end
    
    -- Check Image attribute
    local image = itemConfig:GetAttribute("Image") :: string?
    if image and image ~= "" then
        return image
    end
    
    -- Check Tool's TextureId
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
    
    -- Clone all parts from the source
    for _, part in sourceModel:GetDescendants() do
        if part:IsA("BasePart") then
            local partClone = part:Clone()
            partClone.Anchored = true
            partClone.CanCollide = false
            partClone.Parent = modelClone
        end
    end
    
    -- Also clone direct part children
    for _, child in sourceModel:GetChildren() do
        if child:IsA("BasePart") and not modelClone:FindFirstChild(child.Name) then
            local partClone = child:Clone()
            partClone.Anchored = true
            partClone.CanCollide = false
            partClone.Parent = modelClone
        end
    end
    
    -- Try to set primary part
    local primaryPartName = "Handle"
    if sourceModel:IsA("Model") and sourceModel.PrimaryPart then
        primaryPartName = sourceModel.PrimaryPart.Name
    end
    modelClone.PrimaryPart = modelClone:FindFirstChild(primaryPartName) :: BasePart?
    
    -- If no parts were cloned, return nil
    if #modelClone:GetChildren() == 0 then
        modelClone:Destroy()
        return nil
    end
    
    return modelClone
end

--[[
    Creates the slot frame structure.
]]
local function createSlotFrame(): Frame
    local frame = Instance.new("Frame")
    frame.Name = "ItemSlot"
    frame.Size = SLOT_SIZE
    frame.BackgroundColor3 = Color3.fromRGB(30, 34, 48) -- Match UI_CONFIG.SlotBackground
    frame.BorderSizePixel = 0
    
    -- Clean rounded corners
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = frame
    
    -- ViewportFrame for 3D model
    local viewport = Instance.new("ViewportFrame")
    viewport.Name = "Viewport"
    viewport.Size = UDim2.fromScale(0.85, 0.85)
    viewport.Position = UDim2.fromScale(0.5, 0.45)
    viewport.AnchorPoint = Vector2.new(0.5, 0.5)
    viewport.BackgroundTransparency = 1
    viewport.Parent = frame
    
    -- Camera for viewport
    local camera = Instance.new("Camera")
    camera.Name = "ViewportCamera"
    camera.Parent = viewport
    viewport.CurrentCamera = camera
    
    -- WorldModel for the tool
    local worldModel = Instance.new("WorldModel")
    worldModel.Name = "WorldModel"
    worldModel.Parent = viewport
    
    -- Image fallback (for non-Tool items)
    local imageLabel = Instance.new("ImageLabel")
    imageLabel.Name = "ImageLabel"
    imageLabel.Size = UDim2.fromScale(0.7, 0.7)
    imageLabel.Position = UDim2.fromScale(0.5, 0.45)
    imageLabel.AnchorPoint = Vector2.new(0.5, 0.5)
    imageLabel.BackgroundTransparency = 1
    imageLabel.ScaleType = Enum.ScaleType.Fit
    imageLabel.Visible = false
    imageLabel.Parent = frame
    
    -- Quantity label
    local quantityLabel = Instance.new("TextLabel")
    quantityLabel.Name = "QuantityLabel"
    quantityLabel.Size = UDim2.fromOffset(30, 20)
    quantityLabel.Position = UDim2.fromScale(1, 1)
    quantityLabel.AnchorPoint = Vector2.new(1, 1)
    quantityLabel.BackgroundTransparency = 1
    quantityLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    quantityLabel.TextSize = 14
    quantityLabel.Font = Enum.Font.GothamBold
    quantityLabel.TextXAlignment = Enum.TextXAlignment.Right
    quantityLabel.Text = ""
    quantityLabel.Visible = false
    quantityLabel.Parent = frame
    
    -- Add drop shadow to quantity for readability
    local quantityStroke = Instance.new("UIStroke")
    quantityStroke.Color = Color3.fromRGB(0, 0, 0)
    quantityStroke.Thickness = 1
    quantityStroke.Parent = quantityLabel
    
    -- Selection indicator (hidden by default)
    local selection = Instance.new("UIStroke")
    selection.Name = "SelectionStroke"
    selection.Color = Color3.fromRGB(255, 255, 255)
    selection.Thickness = 3
    selection.Transparency = 1
    selection.Parent = frame
    
    return frame
end

--[[
    Creates a new ItemSlot.
    
    @param parent - Parent GUI object
    @return ItemSlot
]]
function ItemSlotModule.new(parent: GuiObject?): ItemSlot
    local self = setmetatable({}, ItemSlotModule)
    
    self._janitor = Janitor.new() :: Janitor
    self._rotationConnection = nil :: RBXScriptConnection?
    self._model = nil :: Model?
    self._highlight = nil :: Highlight?
    
    -- Create UI
    self.Frame = createSlotFrame()
    self.Data = nil :: ItemSlotData?
    
    if parent then
        self.Frame.Parent = parent
    end
    
    return self :: any
end

--[[
    Sets the data for this slot.
    
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
    
    local viewport = self.Frame:FindFirstChild("Viewport") :: ViewportFrame
    local worldModel = viewport:FindFirstChild("WorldModel") :: WorldModel
    local imageLabel = self.Frame:FindFirstChild("ImageLabel") :: ImageLabel
    local quantityLabel = self.Frame:FindFirstChild("QuantityLabel") :: TextLabel
    local camera = viewport:FindFirstChild("ViewportCamera") :: Camera
    
    -- Clear existing model
    for _, child in worldModel:GetChildren() do
        child:Destroy()
    end
    
    if self._highlight then
        Rarity.StopAnimation(self._highlight)
        self._highlight:Destroy()
        self._highlight = nil
    end
    
    if not data then
        -- Empty slot
        viewport.Visible = false
        imageLabel.Visible = false
        quantityLabel.Visible = false
        Rarity.ApplyToFrame(self.Frame, nil)
        return
    end
    
    print("[ItemSlot] SetData for:", data.TemplateId, "Type:", data.Type, "Count:", data.Count)
    
    -- Apply rarity border
    Rarity.ApplyToFrame(self.Frame, data.Rarity, { StrokeThickness = 2 })
    
    -- Update quantity
    if data.Count > 1 then
        quantityLabel.Text = "x" .. tostring(data.Count)
        quantityLabel.Visible = true
    else
        quantityLabel.Visible = false
    end
    
    -- Try to load 3D model (for Tools or items with ToolModel attribute)
    local itemModel = findItemModel(data.TemplateId)
    print("[ItemSlot] findItemModel result:", itemModel and itemModel.Name or "nil")
    
    if itemModel then
        local modelClone = cloneModelForDisplay(itemModel)
        
        if modelClone then
            modelClone.Parent = worldModel
            self._model = modelClone
            
            -- Setup camera to view the model
            local cf, size = modelClone:GetBoundingBox()
            local maxSize = math.max(size.X, size.Y, size.Z)
            local distance = maxSize * 1.5
            
            camera.CFrame = CFrame.new(cf.Position + Vector3.new(distance, distance * 0.5, distance), cf.Position)
            
            -- Add highlight
            local highlight = Rarity.CreateHighlight(data.Rarity)
            highlight.Adornee = modelClone
            highlight.Parent = viewport
            self._highlight = highlight
            
            -- Setup rotation
            local startTime = os.clock()
            local rotationConn = RunService.RenderStepped:Connect(function()
                if modelClone and modelClone.PrimaryPart then
                    local elapsed = os.clock() - startTime
                    local angle = elapsed * ROTATION_SPEED * math.pi * 2
                    local rotatedCF = cf * CFrame.Angles(0, angle, 0)
                    camera.CFrame = CFrame.new(rotatedCF.Position + Vector3.new(distance, distance * 0.5, distance), rotatedCF.Position)
                end
            end)
            self._rotationConnection = rotationConn
            self._janitor:Add(rotationConn)
            
            viewport.Visible = true
            imageLabel.Visible = false
            self.Frame.Visible = true
            print("[ItemSlot] Model loaded! Frame visible:", self.Frame.Visible, "Parent:", self.Frame.Parent and self.Frame.Parent.Name or "nil")
        else
            -- Model clone failed, use image fallback
            viewport.Visible = false
            local img = getItemImage(data.TemplateId)
            imageLabel.Image = img
            imageLabel.Visible = img ~= ""
        end
    else
        -- No 3D model, use image
        viewport.Visible = false
        local img = getItemImage(data.TemplateId)
        imageLabel.Image = img
        imageLabel.Visible = img ~= ""
    end
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

--!strict
--[[
    VisualUtils - Centralized logic for retrieving and preparing item visuals (3D models/Icons).
    Handles ToolModel attribute support and model orientation resetting.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Rojo"):WaitForChild("Shared")
local ItemUtils = require(Shared:WaitForChild("Inventory"):WaitForChild("ItemUtils"))

local VisualUtils = {}

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
    Finds the 3D model for an item.
    Priority:
    1. ReplicatedStorage.Config.Inventory.ViewportModels (Custom Manual Setup)
    2. ToolModel Attribute (Legacy/Auto)
    3. ViewModel Attribute
    4. Tool child in Configuration
    
    Returns:
    - Model (Instance?)
    - IsCustom (boolean) - If true, use model as-is (don't reset orientation)
]]
function VisualUtils.FindItemModel(templateId: string): (Instance?, boolean)
    -- 1. Check Custom ViewportModels (Manual Override)
    local config = ReplicatedStorage:FindFirstChild("Config")
    if config then
        local invConfig = config:FindFirstChild("Inventory")
        if invConfig then
             local viewportModels = invConfig:FindFirstChild("ViewportModels")
             if viewportModels then
                 local customModel = viewportModels:FindFirstChild(templateId)
                 if customModel then
                     return customModel, true -- IsCustom = true
                 else
                     -- Debug: List available models if not found
                     -- print(`[VisualUtils] No custom model for {templateId}. Available:`, viewportModels:GetChildren())
                 end
             else
                 warn("[VisualUtils] Config.Inventory.ViewportModels folder NOT found!")
             end
        end
    end

    local itemConfig = getItemConfig(templateId)
    if not itemConfig then return nil, false end
    
    local toolModelSource = itemConfig:GetAttribute("ToolModel") :: string?
    
    if toolModelSource == "ToolModels" then
        if config then
            local toolModels = config:FindFirstChild("ToolModels")
            if toolModels then
                return toolModels:FindFirstChild(templateId), false
            end
        end
    elseif toolModelSource == "ViewModel" then
        local blasterFolder = ReplicatedStorage:FindFirstChild("Blaster")
        if blasterFolder then
            local viewModels = blasterFolder:FindFirstChild("ViewModels")
            if viewModels then
                local viewModelFolder = viewModels:FindFirstChild(templateId)
                if viewModelFolder then
                    return viewModelFolder:FindFirstChild("Blaster"), false
                end
            end
        end
    elseif toolModelSource == "ToolIcon" then
        return nil, false -- Force use of image
    end
    
    -- No ToolModel attribute: use the Tool child inside Configuration
    local tool = getToolFromConfig(itemConfig)
    if tool then
        return tool, false
    end
    
    return nil, false
end

--[[
    Gets the image for an item (for items without 3D model).
]]
function VisualUtils.GetItemImage(templateId: string): string
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
    Clones a model for display in viewport.
    
    @param sourceModel - The model to clone
    @param isCustom - If true, clones as-is (preserves hierarchy/transform/camera). 
                      If false, reconstructs hierarchy and resets Pivot to 0,0,0.
]]
function VisualUtils.CloneModelForDisplay(sourceModel: Instance, isCustom: boolean?): Model?
    if isCustom then
        -- Simple clone for custom models (preserves Camera, Parts, Transform)
        local modelClone = sourceModel:Clone()
        if not modelClone then return nil end
        
        -- Reset Layout to 0,0,0 (Requested by User)
        if modelClone:IsA("Model") then
             -- Ensure PrimaryPart is set for reliable pivoting
             if not modelClone.PrimaryPart then
                 modelClone.PrimaryPart = modelClone:FindFirstChild("HumanoidRootPart") or 
                                          modelClone:FindFirstChild("RootPart") or 
                                          modelClone:FindFirstChild("FakeRootPart") or
                                          modelClone:FindFirstChild("Handle") or
                                          modelClone:FindFirstChildWhichIsA("BasePart") :: BasePart?
             end
             modelClone:PivotTo(modelClone:GetPivot().Rotation)
        end

        -- Ensure anchored and non-collidable
        for _, desc in modelClone:GetDescendants() do
            if desc:IsA("BasePart") then
                desc.Anchored = true
                desc.CanCollide = false
            end
        end
        
        return modelClone :: Model
    end

    -- Construct fresh model for auto-gen
    local modelClone = Instance.new("Model")
    modelClone.Name = "DisplayModel"
    
    -- Recursively clone parts
    for _, part in sourceModel:GetDescendants() do
        if part:IsA("BasePart") then
            local partClone = part:Clone()
            partClone.Anchored = true
            partClone.CanCollide = false
            partClone.Parent = modelClone
        end
    end
    
    -- Check direct children (for flat models)
    for _, child in sourceModel:GetChildren() do
        if child:IsA("BasePart") and not modelClone:FindFirstChild(child.Name) then
            local partClone = child:Clone()
            partClone.Anchored = true
            partClone.CanCollide = false
            partClone.Parent = modelClone
        end
    end
    
    -- Set PrimaryPart
    local primaryPartName = "Handle"
    if sourceModel:IsA("Model") and sourceModel.PrimaryPart then
        primaryPartName = sourceModel.PrimaryPart.Name
    end
    modelClone.PrimaryPart = modelClone:FindFirstChild(primaryPartName) :: BasePart?
    
    if #modelClone:GetChildren() == 0 then
        modelClone:Destroy()
        return nil
    end
    
    -- Reset Orientation to 0,0,0 (Identity)
    if modelClone.PrimaryPart then
        modelClone:PivotTo(CFrame.new())
    end
    
    return modelClone
end

--[[
    Sets up a Camera for a ViewportFrame to view the model.
    Applies a consistent zoom level.
]]
function VisualUtils.SetupModelCamera(viewport: ViewportFrame, model: Model)
    local camera = viewport:FindFirstChild("Camera") :: Camera?
    if not camera then
        camera = Instance.new("Camera")
        camera.Name = "Camera"
        camera.Parent = viewport
        viewport.CurrentCamera = camera
    end

    -- Check if model has a custom camera embedded
    local customCamera = model:FindFirstChildWhichIsA("Camera", true) 
        or model:FindFirstChild("Cam", true) 
        or model:FindFirstChild("Camera", true)

    if customCamera and (customCamera:IsA("Camera") or customCamera:IsA("BasePart")) then
        camera.CFrame = customCamera.CFrame
        viewport.CurrentCamera = camera
        return camera
    end
    
    local cf, size = model:GetBoundingBox()
    local maxSize = math.max(size.X, size.Y, size.Z)
    
    -- Zoom Factor: Lower is closer.
    -- 0.5 fits tight. 0.8 adds some padding. 1.5 is far.
    -- User requested "zoom on the model", so we choose a tight fit.
    local ZOOM_FACTOR = 0.8 
    local distance = maxSize * ZOOM_FACTOR
    
    -- Ensure minimum distance to avoid clipping
    if distance < 1 then distance = 1 end
    
    local center = cf.Position
    local cameraPos = center + Vector3.new(distance/2, distance/2, distance)
    
    camera.CFrame = CFrame.lookAt(cameraPos, center)
    
    return camera
end

return VisualUtils

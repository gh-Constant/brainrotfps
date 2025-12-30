--!strict
--[[
    IndexController.luau
    Manages the Index UI (Brainrots/Weapons list).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")
local IndexConstants = require(Shared:WaitForChild("IndexConstants"))
local Packets = require(Shared:WaitForChild("Packets"))
local RarityConfig = require(Shared:WaitForChild("Rarity"):WaitForChild("RarityConfig"))

-- Relative require since we are on client
local UI = script.Parent.Parent
local ItemSlotModule = require(UI:WaitForChild("Inventory"):WaitForChild("ItemSlot"))

local IndexController = {}

-- UI References
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local indexGui = playerGui:WaitForChild("Index")
local hub = indexGui:WaitForChild("Hub")
local main = hub:WaitForChild("Index"):WaitForChild("Main")

-- Containers
local listContainer = main:WaitForChild("Brainrots"):WaitForChild("ScrollingFrame")
local zoneButtonsContainer = main:WaitForChild("Rarity"):WaitForChild("ScrollingFrame")

local function getButton(name: string): GuiButton?
    return zoneButtonsContainer:FindFirstChild(name) :: GuiButton?
end

-- Config
local config = ReplicatedStorage:WaitForChild("Config")
local brainrotsConfig = config:WaitForChild("Brainrots")
local zonesConfig = brainrotsConfig:WaitForChild("Zones")

-- State
local currentTab = IndexConstants.Categories.Brainrots
local currentZone = "Forest" 
local knownData = {
    Brainrots = {} :: {[string]: boolean},
    Weapons = {} :: {[string]: boolean},
}

-- Colors
local COLOR_SELECTED = Color3.new(1, 1, 1) -- White
local COLOR_UNSELECTED = Color3.fromRGB(30, 30, 30)

-- Forward declaration
local refreshList

--[[
    Requests index data from server.
]]
local function fetchIndexData()
    Packets.requestIndexData.send({})
end

--[[
    Updates button visuals (UIStroke).
]]
local function updateButtonVisuals()
    -- Tab Buttons (Brainrots, Weapons)
    for _, tabName in {IndexConstants.Categories.Brainrots, IndexConstants.Categories.Weapons} do
        local btn = getButton(tabName)
        if btn then
            local stroke = btn:FindFirstChild("UIStroke") :: UIStroke?
            if stroke then
                if currentTab == tabName then
                    stroke.Color = COLOR_SELECTED
                else
                    stroke.Color = COLOR_UNSELECTED
                end
            end
        end
    end
    
    -- Zone Buttons
    for _, zoneFolder in zonesConfig:GetChildren() do
        local btn = getButton(zoneFolder.Name)
        if btn then
            local stroke = btn:FindFirstChild("UIStroke") :: UIStroke?
            if stroke then
                if currentZone == zoneFolder.Name then
                    stroke.Color = COLOR_SELECTED
                else
                    stroke.Color = COLOR_UNSELECTED
                end
            end
        end
    end
end

--[[
    Recursive search for items in a folder/config.
]]
local function getItemsInFolder(folder: Folder, category: string): {Instance}
    local items = {}
    
    local function recurse(parent: Instance)
        for _, child in parent:GetChildren() do
            if child:IsA("Model") then
                -- Models in Config.Brainrots are the item definitions
                table.insert(items, child)
            elseif child:IsA("Folder") then
                recurse(child)
            end
        end
    end
    
    recurse(folder)
    return items
end

--[[
    Refreshes the list.
]]
refreshList = function()
    -- Clear current list
    for _, child in listContainer:GetChildren() do
        if child:IsA("GuiObject") then 
            child:Destroy() 
        end
    end
    
    local items = {}
    
    print("[IndexController] Refreshing list... Zone:", currentZone, "Tab:", currentTab)
    
    if currentTab == IndexConstants.Categories.Brainrots then
        -- Find zone folder
        local zoneFolder = zonesConfig:FindFirstChild(currentZone)
        if zoneFolder then
            items = getItemsInFolder(zoneFolder, currentTab)
            print("[IndexController] Found zone folder:", zoneFolder.Name, "Items found:", #items)
        else
            warn("[IndexController] Zone folder not found:", currentZone)
            print("[IndexController] Available zones:")
            for _, c in zonesConfig:GetChildren() do
                print(" - " .. c.Name)
            end
        end
    else
        -- Weapons - logic not fully defined where to find them, skipping for now
        items = {}
        print("[IndexController] Weapons tab selected (empty for now)")
    end
    
    -- Sort Items: Least Rare -> Rarest
    local rarityRank = {}
    for i, r in RarityConfig.RarityOrder do
        rarityRank[r] = i
    end
    
    table.sort(items, function(a, b)
        local rA = a:GetAttribute("Rarity") or "Common"
        local rB = b:GetAttribute("Rarity") or "Common"
        local rankA = rarityRank[rA] or 0
        local rankB = rarityRank[rB] or 0
        return rankA < rankB 
    end)
    
    -- Populate
    -- Find template or nil (ItemSlotModule creates fallback, but we really want a template)
    local template = listContainer:FindFirstChild("ItemSlot") or listContainer:FindFirstChild("Template")
    
    if not template then
        -- Fallback: Try to grab from Config.Inventory.Templates
        local inventoryConfig = config:FindFirstChild("Inventory")
        local templates = inventoryConfig and inventoryConfig:FindFirstChild("Templates")
        local configTemplate = templates and templates:FindFirstChild("ItemSlot") :: GuiObject?
        
        if configTemplate then
            -- We don't clone efficiently here for every item, we just use it as source
            -- But ItemSlot.new(..., source) expects source to be in place or we pass it
            -- Actually ItemSlot.new(container, template) clones the template.
            template = configTemplate
        else
            warn("[IndexController] No ItemSlot template found in UI or Config!")
        end
    else
        template.Visible = false 
    end
    
    local templateCloneSrc = template

    -- Clones folder reference
    local clonesFolder = ReplicatedStorage:WaitForChild("BrainrotsClones", 5)

    for _, itemConfig in items do
        local itemName = itemConfig.Name
        local ItemSlot = ItemSlotModule.new(listContainer, templateCloneSrc)
        
        -- Create Data
        local rarity = itemConfig:GetAttribute("Rarity") or "Common"
        
        local isDiscovered = false
        if currentTab == IndexConstants.Categories.Brainrots then
            isDiscovered = knownData.Brainrots[itemName] == true
        end
        
        local slotData = {
            TemplateId = itemName,
            Type = "Brainrot",
            Rarity = rarity,
            Count = 1,
            ItemIds = {},
        }
        
        ItemSlot:SetData(slotData)
        
        -- Post-processing for Index requirements
        local frame = ItemSlot.Frame
        
        -- Remove unnecessary elements
        local deadElements = {"ToolBarPos", "ItemDragDetector", "EventsLabel", "SelectionStroke"}
        for _, name in deadElements do
            local el = frame:FindFirstChild(name)
            if el then el:Destroy() end
        end
        
        -- Handle ViewportFrame
        local vp = frame:FindFirstChild("ViewportFrame") :: ViewportFrame?
        local icon = frame:FindFirstChild("ToolIcon") :: ImageLabel?
        
        if vp then
            vp.BackgroundColor3 = Color3.new(0, 0, 0)
            vp.BackgroundTransparency = 0
            vp.Visible = true 
            if icon then icon.Visible = false end -- Prefer 3D model
            
            -- Setup WorldModel
            local worldModel = vp:FindFirstChild("WorldModel")
            if not worldModel then
                worldModel = Instance.new("WorldModel")
                worldModel.Name = "WorldModel"
                worldModel.Parent = vp
            end
            
            -- Clone Mob Model
            local sourceModel = clonesFolder and clonesFolder:FindFirstChild(itemName) :: Model?
            if sourceModel then
                local clone = sourceModel:Clone()
                
                -- Cleanup Billboard (User request: remove billboard part)
                local billboard = clone:FindFirstChild("Billboard")
                if billboard then billboard:Destroy() end
                
                clone.Parent = worldModel
                
                -- Cleanup for Viewport (User request: Keep Humanoid, Anchor HRP)
                local humanoid = clone:FindFirstChildOfClass("Humanoid")
                local hrp = clone:FindFirstChild("HumanoidRootPart")
                
                if hrp then 
                    hrp.Transparency = 1 
                    hrp.Anchored = true 
                end
                
                clone.Parent = worldModel
                
                -- Position Camera
                local cam = Instance.new("Camera")
                cam.Parent = vp
                vp.CurrentCamera = cam
                
                -- Center model
                local cf, size = clone:GetBoundingBox()
                local dist = math.max(size.X, size.Y, size.Z) * 0.9
                local center = cf.Position
                
                -- Adjust height based on HipHeight
                -- User said "it's a little bit too high", so we reduce the baseline from 4.5 to 3.0
                -- Decreasing baseline raises the camera target (center - (3-6) = center+3), which lowers the model on screen.
                if humanoid then
                    local hipHeight = humanoid.HipHeight
                    local heightAdjustment = 3.0 - hipHeight
                    center = center - Vector3.new(0, heightAdjustment, 0)
                end
                
                cam.CFrame = CFrame.new(center + Vector3.new(-dist * 0.7, 0, dist * 0.7), center)
                
                -- Animation (Load from BrainrotAnimations like MobAI does)
                local brainrotAnimations = ReplicatedStorage:FindFirstChild("BrainrotAnimations")
                local animFolder = brainrotAnimations and brainrotAnimations:FindFirstChild(itemName)
                
                if humanoid and animFolder then
                    local animator = humanoid:FindFirstChildOfClass("Animator")
                    if not animator then
                        animator = Instance.new("Animator")
                        animator.Parent = humanoid
                    end
                    
                    -- User request: Change Idle to Walk
                    local walkAnim = animFolder:FindFirstChild("Walk")
                    if walkAnim and walkAnim:IsA("Animation") then
                        local track = animator:LoadAnimation(walkAnim)
                        track.Looped = true
                        track:Play()
                    end
                end
                
                -- Discovery State: Silhouette
                if not isDiscovered then
                    vp.BackgroundTransparency = 1
                    
                    for _, obj in clone:GetDescendants() do
                        if obj:IsA("BasePart") then
                            -- Only turn visible parts black
                            if obj.Transparency < 0.95 then
                                obj.Color = Color3.new(0, 0, 0)
                                obj.Material = Enum.Material.Plastic
                                obj.Transparency = 0 
                            else
                                obj.Transparency = 1 
                            end
                        elseif obj:IsA("Texture") or obj:IsA("Decal") then
                            obj.Transparency = 1
                        elseif obj:IsA("SurfaceAppearance") then
                            -- Hide SurfaceAppearance (User request)
                            obj:Destroy()
                        elseif obj:IsA("MeshPart") then
                             obj.TextureID = ""
                             if obj.Transparency < 0.95 then
                                 obj.Color = Color3.new(0, 0, 0)
                                 obj.Material = Enum.Material.Plastic
                             end
                        end
                    end
                    
                    -- Lighting override for silhouette
                    vp.Ambient = Color3.new(0, 0, 0)
                    vp.LightColor = Color3.new(0, 0, 0)
                else
                     -- Normal Lighting
                     vp.BackgroundTransparency = 1
                     vp.Ambient = Color3.fromRGB(200, 200, 200)
                     vp.LightColor = Color3.new(1, 1, 1)
                end
                
                vp.Visible = true 
                if icon then icon.Visible = false end
            else
                -- Fallback if model not found
                if icon then icon.Visible = true end
            end
        else
             -- Fallback if no viewport
             if icon then icon.Visible = true end
        end
        
        -- ToolNameLabel styling
        local toolNameLabel = frame:FindFirstChild("ToolNameLabel") :: TextLabel?
        if toolNameLabel then
            if not isDiscovered then
                toolNameLabel.Text = "???"
                toolNameLabel.TextColor3 = Color3.new(0, 0, 0)
            else
                toolNameLabel.Text = itemName
                toolNameLabel.TextColor3 = Color3.new(1, 1, 1) -- White for discovered
            end
        end
    end
end

--[[
    Initializes the controller.
]]
function IndexController.Init()
    -- Connect UI Buttons
    -- Zones
    for _, zoneFolder in zonesConfig:GetChildren() do
        local btn = getButton(zoneFolder.Name)
        if btn then
            btn.MouseButton1Click:Connect(function()
                currentZone = zoneFolder.Name
                updateButtonVisuals()
                refreshList()
            end)
        end
    end
    
    -- Tabs
    local btnWeapons = getButton(IndexConstants.Categories.Weapons)
    if btnWeapons then
        btnWeapons.MouseButton1Click:Connect(function()
            currentTab = IndexConstants.Categories.Weapons
            updateButtonVisuals()
            refreshList()
        end)
    end
    
    local btnBrainrots = getButton(IndexConstants.Categories.Brainrots)
    if btnBrainrots then
        btnBrainrots.MouseButton1Click:Connect(function()
            currentTab = IndexConstants.Categories.Brainrots
            updateButtonVisuals()
            refreshList()
        end)
    end
    
    -- Packet Listener
    Packets.indexData.listen(function(data)
        -- Convert arrays to maps
        knownData.Brainrots = {}
        for _, name in data.brainrots do
            knownData.Brainrots[name] = true
        end
        
        knownData.Weapons = {}
        for _, name in data.weapons do
            knownData.Weapons[name] = true
        end
        
        refreshList()
    end)
    
    -- Initial Fetch
    task.spawn(function()
        fetchIndexData()
        updateButtonVisuals()
        -- refreshList() -- Wait for packet to refresh list efficiently, or refresh empty first
        refreshList() 
    end)
    
    print("[IndexController] Initialized")
end

return IndexController

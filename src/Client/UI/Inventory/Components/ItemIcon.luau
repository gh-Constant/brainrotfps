--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")
local Inventory = require(Shared:WaitForChild("Inventory"))
local RarityConfig = require(Shared:WaitForChild("Rarity"):WaitForChild("RarityConfig"))
local ColorSystem = require(Shared:WaitForChild("Inventory"):WaitForChild("ColorSystem"))

type InventoryItem = Inventory.InventoryItem

local VisualUtils = require(script.Parent.Parent:WaitForChild("VisualUtils"))

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
			local dn = config:GetAttribute("DisplayName") :: string?
			if dn and dn ~= "" then displayName = dn end
		end
		nameLabel.Text = displayName
	end

	-- 2. Visuals (3D Model or Icon)
	local toolIcon = instance:FindFirstChild("ToolIcon") :: ImageLabel?
    local viewport = instance:FindFirstChild("ViewportFrame") :: ViewportFrame?

    -- Create Viewport if missing
    if not viewport then
        viewport = Instance.new("ViewportFrame")
        viewport.Name = "ViewportFrame"
        viewport.Size = UDim2.fromScale(1, 1)
        viewport.BackgroundTransparency = 1
        viewport.ZIndex = 2
        viewport.Parent = instance
    end
    
    -- Try 3D Model first
    local itemModel, isCustom = VisualUtils.FindItemModel(item.TemplateId)
    local setupSuccessful = false
    
    if itemModel then
        viewport.Visible = true
        if toolIcon then toolIcon.Visible = false end
        
        -- Clear old model
        viewport:ClearAllChildren()
        
        local modelClone = VisualUtils.CloneModelForDisplay(itemModel, isCustom)
        if modelClone then
            local worldModel = Instance.new("WorldModel")
            worldModel.Parent = viewport
            modelClone.Parent = worldModel
            
            -- Global Camera Setup (Consistent Zoom)
            VisualUtils.SetupModelCamera(viewport, modelClone)
            
            -- Play Idle Animation
            local animsFolder = ReplicatedStorage:FindFirstChild("BrainrotAnimations")
            if animsFolder then
                local modelAnims = animsFolder:FindFirstChild(item.TemplateId)
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
                        else
                            warn("ItemIcon: Failed to create Animator for", item.TemplateId)
                        end
                    else
                        -- warn("ItemIcon: Missing Idle Anim or Controller for", item.TemplateId)
                    end
                end
            end
            
            setupSuccessful = true
        end
    end
    
    if not setupSuccessful then
        -- Fallback to Icon
        if viewport then viewport.Visible = false end
        if toolIcon then
            toolIcon.Image = VisualUtils.GetItemImage(item.TemplateId)
            toolIcon.Visible = true
        end
    end

	-- 3. Set Rarity Gradient (ItemIcon itself)
	-- Avoid ColorSystem.ApplyToBackground as it forces BackgroundTransparency = 0.
	-- We want to apply the gradient to the UIGradient child but keep background transparent (so it applies to Image/Border).
	
	local rarity = item.Rarity or "Common"
    local styleName = nil
    
    local config = getItemConfig(item.TemplateId)
    if config then
        styleName = config:GetAttribute("CustomColor") :: string?
    end
    
    if not styleName or styleName == "" then
        styleName = RarityConfig.GetBackgroundStyle(rarity)
    end

	local visualConfig = if styleName then ColorSystem.GetColorConfig(styleName) else nil

	-- Ensure transparency is 1
	instance.BackgroundTransparency = 1
	instance.BackgroundColor3 = Color3.fromRGB(255, 255, 255)

	if visualConfig and visualConfig.Gradient then
		local gradient = instance:FindFirstChildWhichIsA("UIGradient")
		if not gradient then
			gradient = Instance.new("UIGradient")
			gradient.Name = "RarityGradient"
			gradient.Parent = instance
		end
		gradient.Color = visualConfig.Gradient
		gradient.Rotation = visualConfig.GradientRotation or -90
		gradient.Enabled = true
	else
		-- Fallback logic or cleanup if no gradient
        local gradient = instance:FindFirstChildWhichIsA("UIGradient")
        if gradient then gradient.Enabled = false end
	end
end

return ItemIcon

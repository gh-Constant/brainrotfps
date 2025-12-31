local Selection = game:GetService("Selection")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local selectedObjects = Selection:Get()

-- Configuration Paths
local TEMPLATE_PATH = ReplicatedStorage:WaitForChild("Config"):WaitForChild("Items"):WaitForChild("Guns"):WaitForChild("MatteoGun")
local OUTPUT_FOLDER_NAME = "ToolsCreated"

-- Ensure output folder exists
local outputFolder = Workspace:FindFirstChild(OUTPUT_FOLDER_NAME)
if not outputFolder then
	outputFolder = Instance.new("Folder")
	outputFolder.Name = OUTPUT_FOLDER_NAME
	outputFolder.Parent = Workspace
end

-- Ensure VM Check folder exists in Workspace
local VM_CHECK_FOLDER_NAME = "ViewModelsCreated"
local vmCheckFolder = Workspace:FindFirstChild(VM_CHECK_FOLDER_NAME)
if not vmCheckFolder then
    vmCheckFolder = Instance.new("Folder")
    vmCheckFolder.Name = VM_CHECK_FOLDER_NAME
    vmCheckFolder.Parent = Workspace
end

ChangeHistoryService:SetWaypoint("StartCreateWeapons")

for _, brainrotModel in ipairs(selectedObjects) do
	if not brainrotModel:IsA("Model") then
		warn("Skipping " .. brainrotModel.Name .. ": Not a Model")
		continue
	end
	
	print("Processing: " .. brainrotModel.Name)
	
	-- 1. Clone Template Configuration
	local newConfig = TEMPLATE_PATH:Clone()
	newConfig.Name = brainrotModel.Name
	
	-- 2. Rename Tool
	local tool = newConfig:FindFirstChildWhichIsA("Tool")
	if tool then
		tool.Name = brainrotModel.Name
	else
		warn("No Tool found in template for " .. brainrotModel.Name)
		continue
	end
	
	-- 3. Prepare Brainrot Model
	local newModel = brainrotModel:Clone()
	newModel.Name = brainrotModel.Name
	newModel.Parent = tool
	
	-- Remove VfxInstance if it exists
	local vfxInstance = newModel:FindFirstChild("VfxInstance")
	if vfxInstance then
		vfxInstance:Destroy()
	end
	
	-- 4. Find & Setup Root Part (Set PrimaryPart for correct Pivoting)
	local rootPart = newModel:FindFirstChild("FakeRootPart")
	if rootPart then
		rootPart.Name = "Body"
	else
		rootPart = newModel:FindFirstChild("RootPart")
		if rootPart then
			rootPart.Name = "Body"
		else
			rootPart = newModel:FindFirstChild("HumanoidRootPart")
			if rootPart then
				rootPart.Name = "Body"
			end
		end
	end
	
	if rootPart then
		newModel.PrimaryPart = rootPart
	else
		warn("No FakeRootPart/RootPart found in " .. brainrotModel.Name)
	end
	
	-- 5. Resize Model
	newModel:ScaleTo(0.6)
	
	-- 6. Copy Position/Orientation from Matteo
	local templateModel = TEMPLATE_PATH:FindFirstChild("Matteo", true)
	if not templateModel and tool:FindFirstChild("Matteo") then
		templateModel = tool:FindFirstChild("Matteo")
	end
    
    local originalTool = TEMPLATE_PATH:FindFirstChildWhichIsA("Tool")
    if originalTool then
        templateModel = originalTool:FindFirstChild("Matteo")
    end

	if templateModel and templateModel:IsA("Model") then
		-- Robust Alignment: Align RootPart to RootPart
		local templateRoot = templateModel:FindFirstChild("Body") or templateModel:FindFirstChild("FakeRootPart") or templateModel:FindFirstChild("RootPart")
		
		if templateRoot and newModel.PrimaryPart then
			newModel:PivotTo(templateRoot.CFrame)
		else
			-- Fallback to Model Pivot
			local pivot = templateModel:GetPivot()
			newModel:PivotTo(pivot)
		end
	else
		warn("Could not find 'Matteo' model in template to copy position from.")
	end
	
	-- Remove the original 'Matteo' model
	local oldMatteo = tool:FindFirstChild("Matteo")
	if oldMatteo then
		oldMatteo:Destroy()
	end
	
	-- 7. Set Physics Properties
	for _, desc in ipairs(newModel:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.CanCollide = false
			desc.Massless = true
			desc.CanTouch = false
		end
	end
	
	-- 8. Copy Muzzle Attachment
	if rootPart and templateModel then
		local templateBody = templateModel:FindFirstChild("Body")
		if templateBody then
			local muzzle = templateBody:FindFirstChild("MuzzleAttachment")
			if muzzle then
				local newMuzzle = muzzle:Clone()
				newMuzzle.Parent = rootPart
			else
				warn("No MuzzleAttachment found in Template Body of Tool")
			end
		end
	end
	
	-- 9. Weld Handle to Body
	local handle = tool:FindFirstChild("Handle")
	if handle and rootPart then
		local weld = Instance.new("WeldConstraint")
		weld.Name = "HandleToBody"
		weld.Part0 = handle
		weld.Part1 = rootPart
		weld.Parent = rootPart
	else
		warn("Could not create weld: Handle or Body missing.")
	end
	
	-- 10. Move to Output
	newConfig.Parent = outputFolder
    
    -------------------------------------------------------------------------------
    -- VIEWMODEL CREATION
    -------------------------------------------------------------------------------
    print("Creating ViewModel for: " .. brainrotModel.Name)
    
    local VM_TEMPLATE_PATH = ReplicatedStorage:WaitForChild("Blaster"):WaitForChild("ViewModels"):WaitForChild("MatteoGun")
    local VM_OUTPUT_FOLDER_NAME = "ViewModelsCreated"
    
    -- Ensure output folder exists in ReplicatedStorage or Workspace? 
    -- User said "move the new viewport in the rpelicatedstorage in a special folder"
    local vmOutputFolder = ReplicatedStorage:FindFirstChild(VM_OUTPUT_FOLDER_NAME)
    if not vmOutputFolder then
        vmOutputFolder = Instance.new("Folder")
        vmOutputFolder.Name = VM_OUTPUT_FOLDER_NAME
        vmOutputFolder.Parent = ReplicatedStorage
    end
    
    -- 1. Clone Template ViewModel
    local newViewModel = VM_TEMPLATE_PATH:Clone()
    
    -- Update Shoot animation ID
    local animations = newViewModel:FindFirstChild("Animations")
    if animations then
        local shootAnim = animations:FindFirstChild("Shoot")
        if shootAnim and shootAnim:IsA("Animation") then
            shootAnim.AnimationId = "rbxassetid://89549817013461"
        end
    end
    
    -- 2. Clone Brainrot Model into ViewModel
    -- The template likely has the gun model inside (e.g. named "Matteo" or "Blaster")
    -- We need to find the reference model in the *template* to copy transforms from
    local vmTemplateModel = newViewModel:FindFirstChild("Matteo") or newViewModel:FindFirstChild("Blaster") 
    -- Note: If we use newViewModel ("Blaster" is usually the grouping), the gun might be a child. 
    -- The user says "clone again the branrotmodel inside the template".
    
    local vmNewModel = brainrotModel:Clone()
    vmNewModel.Name = brainrotModel.Name
    vmNewModel.Parent = newViewModel
    
    -- Remove VfxInstance from VM model
    local vmVfx = vmNewModel:FindFirstChild("VfxInstance")
    if vmVfx then vmVfx:Destroy() end
    
    -- 3. Find & Setup Root Part (Set PrimaryPart) (Moved up)
    local vmRootPart = vmNewModel:FindFirstChild("FakeRootPart")
    if vmRootPart then
        vmRootPart.Name = "Body"
    else
        vmRootPart = vmNewModel:FindFirstChild("RootPart") or vmNewModel:FindFirstChild("HumanoidRootPart")
        if vmRootPart then
            vmRootPart.Name = "Body"
        end
    end
    
    if vmRootPart then
        vmNewModel.PrimaryPart = vmRootPart
    else
        warn("No RootPart found in ViewModel brainrot model")
    end
    
    -- 4. Physics Cleanup
    for _, desc in ipairs(vmNewModel:GetDescendants()) do
        if desc:IsA("BasePart") then
            desc.CanCollide = false
            desc.Massless = true
            desc.CanTouch = false
        end
    end

    -- 5. Copy Transform (Scale/Pos/Rot) & Muzzle
    if vmTemplateModel and vmTemplateModel:IsA("Model") then
        local pivot = vmTemplateModel:GetPivot()
        
        -- Resize
        vmNewModel:ScaleTo(0.6)
        
        -- Robust Alignment: Align RootPart to RootPart
        local templateRoot = vmTemplateModel:FindFirstChild("Body") or vmTemplateModel:FindFirstChild("FakeRootPart") or vmTemplateModel:FindFirstChild("RootPart")
        if templateRoot and vmNewModel.PrimaryPart then
             vmNewModel:PivotTo(templateRoot.CFrame)
        else
             vmNewModel:PivotTo(pivot)
        end
        
        -- Copy Muzzle Attachment BEFORE destroying
        local vmTemplateBody = vmTemplateModel:FindFirstChild("Body")
        if vmTemplateBody then
            local vmMuzzle = vmTemplateBody:FindFirstChild("MuzzleAttachment")
            if vmMuzzle and vmRootPart then
                vmMuzzle:Clone().Parent = vmRootPart
            elseif not vmMuzzle then
                warn("No MuzzleAttachment found in ViewModel Template Body")
            end
        end
        
        vmTemplateModel:Destroy() 
    else
        warn("Could not find reference gun model (Matteo/Blaster) in ViewModel template")
        vmNewModel:ScaleTo(0.6)
    end
    
    -- 6. Copy Muzzle Attachment from VIEWMODEL Template's Body
    -- "copy the muzzle attachment from the viewmodel clone bc it's not the same and paste it into body"
    -- Since we destroyed vmTemplateModel above, we should have grabbed Muzzle first... 
    -- Actually, wait. vmTemplateModel was the *clone's* child. destroy removes it from newViewModel.
    -- We need to act carefully.
    
    -- Let's re-clone or grab before destroy.
    -- Refactoring the order above:
    -- Find vmTemplateModel -> Grab Muzzle -> Destroy vmTemplateModel
    
    -- NOTE: I put destroy logic above. I should move it or just use the reference before destroy.
    -- However, "vmTemplateModel" variable holds the reference even if parent is set to nil (destroyed), 
    -- BUT children might be gone if Destroy() is fully recursive immediately? 
    -- Actually, Destroy() locks parent and disconnects. Children are accessible? Yes usually.
    -- But safer to grab muzzle BEFORE destroying.
    
    -- Let's adjust the code flow in the actual replacement
    
    -- 7. Motor6D Setup: LeftArm, RightArm in Body
    if vmRootPart then
        -- LeftArm
        local leftArm = newViewModel:FindFirstChild("LeftArm")
        if leftArm then
            local m6d = Instance.new("Motor6D")
            m6d.Name = "LeftArm"
            m6d.Part0 = vmRootPart
            m6d.Part1 = leftArm
            -- Calculate C0 to preserve current relative position
            m6d.C0 = m6d.Part0.CFrame:Inverse() * m6d.Part1.CFrame
            m6d.Parent = vmRootPart
        end
        
        -- RightArm
        local rightArm = newViewModel:FindFirstChild("RightArm")
        if rightArm then
            local m6d = Instance.new("Motor6D")
            m6d.Name = "RightArm"
            m6d.Part0 = vmRootPart
            m6d.Part1 = rightArm
            -- Calculate C0 to preserve current relative position
            m6d.C0 = m6d.Part0.CFrame:Inverse() * m6d.Part1.CFrame
            m6d.Parent = vmRootPart
        end
        
        -- 8. Root Weld/Motor
        local vmRoot = newViewModel:FindFirstChild("Root") -- The "HumanoidRootPart" equivalent of VM
        if vmRoot then
             -- Remove existing welds/motors to old gun
             for _, child in ipairs(vmRoot:GetChildren()) do
                 if child:IsA("Motor6D") or child:IsA("Weld") then
                     child:Destroy() -- Clean up old motors
                 end
             end
             
             local rootMotor = Instance.new("Motor6D")
             rootMotor.Name = "RootToBody"
             rootMotor.Part0 = vmRoot
             rootMotor.Part1 = vmRootPart
             
             -- Preserves the alignment we set via PivotTo (Template's position)
             rootMotor.C0 = rootMotor.Part0.CFrame:Inverse() * rootMotor.Part1.CFrame
             
             rootMotor.Parent = vmRoot
        end
    end
    
    -- 9. Rename ViewModel
    newViewModel.Name = brainrotModel.Name
    
    -- 10. Move to ReplicatedStorage
    newViewModel.Parent = vmOutputFolder
    
    -- 11. Also put in Workspace (Cone)
    local vmClone = newViewModel:Clone()
    vmClone.Parent = vmCheckFolder
    
    -- 12. Update Item Configuration Attribute (On the Tool inside Config)
    if tool then
        tool:SetAttribute("viewModel", brainrotModel.Name)
    end
end

ChangeHistoryService:SetWaypoint("EndCreateWeapons")
print("Finished creating weapons (Tools + ViewModels)")

local Selection = game:GetService("Selection")
local selectedObjects = Selection:Get()

local exportFolder = workspace:FindFirstChild("BrainrotVFXExported")
if not exportFolder then
	exportFolder = Instance.new("Folder")
	exportFolder.Name = "BrainrotVFXExported"
	exportFolder.Parent = workspace
end

local clonesFolder = workspace:FindFirstChild("BrainrotsClones")
if not clonesFolder then
	clonesFolder = Instance.new("Folder")
	clonesFolder.Name = "BrainrotsClones"
	clonesFolder.Parent = workspace
end

local vfxClasses = {
	"ParticleEmitter"
}

print("--- Exporting VFX (Particles ONLY) to BrainrotVFXExported ---")

if #selectedObjects == 0 then
	warn("Please select one or more Models to export VFX from.")
else
	for _, obj in ipairs(selectedObjects) do
		if obj:IsA("Model") then
			print("Exporting VFX from: " .. obj.Name)
			
			-- Replace existing export part if it already exists
			local existingPart = exportFolder:FindFirstChild(obj.Name)
			if existingPart then
				existingPart:Destroy()
			end
			
			-- Replace existing clone if it already exists
			local existingClone = clonesFolder:FindFirstChild(obj.Name)
			if existingClone then
				existingClone:Destroy()
			end

			-- Clone the model to keep the base intact
			local clone = obj:Clone()
			clone.Name = obj.Name
			clone.Parent = clonesFolder

			-- Copy attributes from AttributesTemplate
			local replicatedStorage = game:GetService("ReplicatedStorage")
			local attributesTemplate = replicatedStorage:FindFirstChild("Config") 
				and replicatedStorage.Config:FindFirstChild("Inventory") 
				and replicatedStorage.Config.Inventory:FindFirstChild("AttributesTemplate")

			if attributesTemplate then
				for name, value in pairs(attributesTemplate:GetAttributes()) do
					clone:SetAttribute(name, value)
				end
			end

			-- Setup HumanoidRootPart and Humanoid
			local root = clone:FindFirstChild("RootPart", true) or clone:FindFirstChild("FakeRootPart", true)
			if root and root:IsA("BasePart") then
				local hrp = root:Clone()
				hrp:ClearAllChildren()
				hrp.Name = "HumanoidRootPart"
				hrp.Transparency = 1
				hrp.Parent = clone
				
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = hrp
				weld.Part1 = root
				weld.Parent = hrp
				
				clone.PrimaryPart = hrp
			else
				warn("No RootPart or FakeRootPart found in " .. obj.Name .. ". HumanoidRootPart not created.")
			end



			local humanoid = clone:FindFirstChildOfClass("Humanoid")
			if not humanoid then
				humanoid = Instance.new("Humanoid")
				humanoid.Parent = clone
			end

			local animController = clone:FindFirstChildOfClass("AnimationController")
			if animController then
				animController:Destroy()
			end

			humanoid.HipHeight = 2

			-- Setup Animations folder and copy animations
			local animsFolder = Instance.new("Folder")
			animsFolder.Name = "Animations"
			animsFolder.Parent = clone

			local animationsDone = workspace:FindFirstChild("AnimationsDONE")
			if animationsDone then
				local targetAnims = animationsDone:FindFirstChild(obj.Name)
				if targetAnims then
					local idle = targetAnims:FindFirstChild("Idle")
					if idle then
						idle:Clone().Parent = animsFolder
					end

					local walk = targetAnims:FindFirstChild("Walk")
					if walk then
						walk:Clone().Parent = animsFolder
					end
				end
			end

			-- Configure physics properties for all parts
			for _, descendant in ipairs(clone:GetDescendants()) do
				if descendant:IsA("BasePart") then
					if descendant.Name == "HumanoidRootPart" or descendant.Name == "RootPart" or descendant.Name == "FakeRootPart" then
						descendant.CanCollide = false
						descendant.Massless = true
					else
						descendant.CanCollide = true
						descendant.Massless = false
					end
					descendant.CanQuery = true
					descendant.CanTouch = true
					descendant.Anchored = false
				end
			end

			-- Setup/Fix Billboard Part
			local billboardPart = clone:FindFirstChild("Billboard")
			if not billboardPart then
				billboardPart = Instance.new("Part")
				billboardPart.Name = "Billboard"
				billboardPart.Parent = clone
			end

			billboardPart.Transparency = 1
			billboardPart.CanCollide = false
			billboardPart.CanTouch = false
			billboardPart.CanQuery = false
			billboardPart.Massless = true
			billboardPart.Size = Vector3.new(1, 1, 1)
			
			-- Position it above the model (a little higher than top)
			local modelPivot = clone:GetPivot()
			local modelSize = clone:GetExtentsSize()
			billboardPart.CFrame = modelPivot * CFrame.new(0, (modelSize.Y / 2) + 5, 0)
			
			-- Clear existing welds on Billboard and weld to HRP
			for _, child in ipairs(billboardPart:GetChildren()) do
				if child:IsA("WeldConstraint") or child:IsA("Weld") or child:IsA("ManualWeld") then
					child:Destroy()
				end
			end

			local hrp = clone:FindFirstChild("HumanoidRootPart")
			if hrp and hrp:IsA("BasePart") then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = hrp
				weld.Part1 = billboardPart
				weld.Parent = billboardPart
			end

			local vfxPart = Instance.new("Part")
			vfxPart.Name = obj.Name
			vfxPart.Transparency = 1
			vfxPart.Anchored = true
			vfxPart.CanCollide = false
			vfxPart.Size = Vector3.new(1, 1, 1)
			vfxPart.CFrame = clone:GetPivot()
			vfxPart.Parent = exportFolder

			local foundVFX = {}
			for _, descendant in ipairs(clone:GetDescendants()) do
				local isVFX = false
				for _, className in ipairs(vfxClasses) do
					if descendant:IsA(className) then
						isVFX = true
						break
					end
				end
				
				if isVFX then
					table.insert(foundVFX, descendant)
				end
			end
			
			for _, item in ipairs(foundVFX) do
				if item:IsA("Attachment") then
					local worldCFrame = item.WorldCFrame
					item.Parent = vfxPart
					item.WorldCFrame = worldCFrame
				else
					item.Parent = vfxPart
				end
			end
			
			print("Successfully exported " .. #foundVFX .. " particles from " .. obj.Name .. " (using clone)")
		else
			print("Skipped: " .. obj.Name .. " (Not a Model)")
		end
	end
end
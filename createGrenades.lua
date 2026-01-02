--[[
    createGrenades.lua
    Automatically generates grenade configurations for all mutations defined in Mutations.luau.
    
    Usage:
    1. Run this script in Roblox Studio (via Command Bar or as a plugin)
    2. Ensure at least one grenade exists in ReplicatedStorage.Config.Items.Grenades as a template
    3. The script will clone the template for each mutation that doesn't already have a grenade
    
    Each grenade Tool has:
    - A "Mutation" attribute matching the mutation name
    - The mutation icon in Tool.Handle.BillboardGui.Frame.ImageButton.Image
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

-- Path Configuration
local CONFIG_PATH = ReplicatedStorage:WaitForChild("Config"):WaitForChild("Items"):WaitForChild("Grenades")

-- Import Mutations (adjust path if needed when running as plugin)
-- In normal Rojo structure: ReplicatedStorage.Rojo.Shared.Mutations
local Mutations
local success, err = pcall(function()
    Mutations = require(ReplicatedStorage:WaitForChild("Rojo"):WaitForChild("Shared"):WaitForChild("Mutations"))
end)

if not success then
    warn("[CreateGrenades] Failed to load Mutations module: " .. tostring(err))
    warn("[CreateGrenades] Attempting alternative path...")
    -- Fallback: try direct path if Rojo folder doesn't exist
    pcall(function()
        Mutations = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Mutations"))
    end)
end

if not Mutations then
    error("[CreateGrenades] Could not load Mutations module! Ensure Mutations.luau is accessible.")
end

print("[CreateGrenades] Starting grenade generation...")

ChangeHistoryService:SetWaypoint("StartCreateGrenades")

-------------------------------------------------------------------------------
-- STEP 1: Find a template grenade in the folder
-------------------------------------------------------------------------------
local templateGrenade: Configuration? = nil

for _, child in CONFIG_PATH:GetChildren() do
    if child:IsA("Configuration") then
        local tool = child:FindFirstChildWhichIsA("Tool")
        if tool then
            templateGrenade = child
            print("[CreateGrenades] Using template: " .. child.Name)
            break
        end
    end
end

if not templateGrenade then
    error("[CreateGrenades] No valid grenade template found in " .. CONFIG_PATH:GetFullName())
end

-------------------------------------------------------------------------------
-- STEP 2: Build a set of existing mutations (grenades already created)
-------------------------------------------------------------------------------
local existingMutations: {[string]: boolean} = {}

for _, child in CONFIG_PATH:GetChildren() do
    if child:IsA("Configuration") then
        local tool = child:FindFirstChildWhichIsA("Tool")
        if tool then
            local mutation = tool:GetAttribute("Mutation")
            if mutation and typeof(mutation) == "string" then
                existingMutations[mutation] = true
                print("[CreateGrenades] Found existing grenade for mutation: " .. mutation)
            end
        end
    end
end

-------------------------------------------------------------------------------
-- STEP 3: Get all mutations from the Mutations module
-------------------------------------------------------------------------------
local allMutations = Mutations.GetAllMutations()

-------------------------------------------------------------------------------
-- STEP 4: Create grenades for missing mutations
-------------------------------------------------------------------------------
local createdCount = 0
local skippedCount = 0

for mutationName, mutationData in pairs(allMutations) do
    if existingMutations[mutationName] then
        print("[CreateGrenades] Skipping " .. mutationName .. " (already exists)")
        skippedCount = skippedCount + 1
        continue
    end
    
    print("[CreateGrenades] Creating grenade for: " .. mutationName)
    
    -- Clone the template
    local newGrenade = templateGrenade:Clone()
    newGrenade.Name = mutationName .. "Grenade"
    
    -- Find the Tool inside
    local tool = newGrenade:FindFirstChildWhichIsA("Tool")
    if not tool then
        warn("[CreateGrenades] No Tool found in cloned template for " .. mutationName)
        newGrenade:Destroy()
        continue
    end
    
    -- Set the Mutation attribute on the Tool
    tool:SetAttribute("Mutation", mutationName)
    tool.Name = mutationName .. "Grenade"
    
    -- Set the Tool icon (TextureId) to the mutation image
    tool.TextureId = mutationData.Icon
    print("[CreateGrenades]   Set Tool icon to: " .. mutationData.Icon)
    
    -- Update the BillboardGui image
    -- Path: Tool.Handle.BillboardGui.Frame.ImageButton.Image
    local handle = tool:FindFirstChild("Handle")
    if handle then
        local billboard = handle:FindFirstChild("BillboardGui")
        if billboard then
            local frame = billboard:FindFirstChild("Frame")
            if frame then
                local imageButton = frame:FindFirstChild("ImageButton")
                if imageButton and imageButton:IsA("ImageButton") then
                    imageButton.Image = mutationData.Icon
                    print("[CreateGrenades]   Set image to: " .. mutationData.Icon)
                else
                    -- Try ImageLabel as fallback
                    local imageLabel = frame:FindFirstChild("ImageLabel")
                    if imageLabel and imageLabel:IsA("ImageLabel") then
                        imageLabel.Image = mutationData.Icon
                        print("[CreateGrenades]   Set image (ImageLabel) to: " .. mutationData.Icon)
                    else
                        warn("[CreateGrenades]   Could not find ImageButton or ImageLabel in Frame")
                    end
                end
            else
                warn("[CreateGrenades]   Could not find Frame in BillboardGui")
            end
        else
            warn("[CreateGrenades]   Could not find BillboardGui in Handle")
        end
    else
        warn("[CreateGrenades]   Could not find Handle in Tool")
    end
    
    -- Optional: Update DisplayName attribute if it exists
    local displayName = mutationData.Display .. " Grenade"
    if tool:GetAttribute("DisplayName") ~= nil then
        tool:SetAttribute("DisplayName", displayName)
    end
    
    -- Optional: Set color-related attributes if they exist on the template
    if tool:GetAttribute("Color") ~= nil then
        tool:SetAttribute("Color", mutationData.Color)
    end
    
    -- Parent the new grenade to the Grenades folder
    newGrenade.Parent = CONFIG_PATH
    
    createdCount = createdCount + 1
    print("[CreateGrenades] ✓ Created: " .. newGrenade.Name)
end

-------------------------------------------------------------------------------
-- STEP 5: Summary
-------------------------------------------------------------------------------
ChangeHistoryService:SetWaypoint("EndCreateGrenades")

print("=====================================")
print("[CreateGrenades] COMPLETE!")
print("  Created: " .. createdCount .. " new grenades")
print("  Skipped: " .. skippedCount .. " (already existed)")
print("  Total mutations: " .. #Mutations.GetMutationNames())
print("=====================================")

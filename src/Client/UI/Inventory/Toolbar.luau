--!strict
--[[
    Toolbar Module
    Custom toolbar that replaces the default Roblox backpack.
    
    Features:
    - Custom slot templates with hotkey display
    - Visual feedback for equipped items (UIStroke)
    - Maintains consistent slot order
    - Supports hotkey-based equipping (1-9)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Packages = Rojo:WaitForChild("Packages")
local Shared = Rojo:WaitForChild("Shared")
local Janitor = require(Packages:WaitForChild("janitor"))
local RarityConfig = require(Shared:WaitForChild("Rarity"):WaitForChild("RarityConfig"))
local ColorSystem = require(Shared:WaitForChild("Inventory"):WaitForChild("ColorSystem"))
local ItemUtils = require(Shared:WaitForChild("Inventory"):WaitForChild("ItemUtils"))
local _Logger = require(Shared:WaitForChild("Inventory"):WaitForChild("Logger"))
local InventoryStore = require(script.Parent:WaitForChild("InventoryStore"))

local LocalPlayer = Players.LocalPlayer

-- Types
type ToolSlot = {
    Tool: Tool,
    Frame: Frame,
    Index: number,
}

-- Module
local Toolbar = {}

-- Configuration
local CONFIG = {
    EquippedBorderColor = Color3.fromRGB(255, 200, 50),
    BorderColor = Color3.fromRGB(80, 80, 90),
    BorderThickness = 2,
    EquippedBorderThickness = 3,
    MaxSlots = 9,
}

-- Get the weapon template from ReplicatedStorage
local WeaponTemplate = ReplicatedStorage:WaitForChild("Config"):WaitForChild("Player"):WaitForChild("UI"):WaitForChild("Toolbar"):WaitForChild("WeaponTemplate") :: Frame

-- State
local toolSlots: {[Tool]: ToolSlot} = {}
local slotOrder: {Tool?} = {}
local equippedTool: Tool? = nil
local toolbarFrame: Frame? = nil
local janitor = Janitor.new()

--------------------------------------------------------------------------------
-- Private Functions
--------------------------------------------------------------------------------

--[[
    Creates a slot frame for a tool by cloning the WeaponTemplate.
]]
local function createSlotFrame(index: number): Frame
    local slot = WeaponTemplate:Clone()
    slot.Name = "Slot" .. index
    slot.LayoutOrder = index
    slot.Visible = true
    
    -- Update hotkey label (directly on slot, no Background)
    local hotkeyLabel = slot:FindFirstChild("HotkeyLabel") :: TextLabel?
    if hotkeyLabel then
        hotkeyLabel.Text = tostring(index)
    end
    
    -- Ensure ClickButton exists for interaction
    local clickButton = slot:FindFirstChild("ClickButton") :: TextButton?
    if not clickButton then
        clickButton = Instance.new("TextButton")
        clickButton.Name = "ClickButton"
        clickButton.BackgroundTransparency = 1
        clickButton.Size = UDim2.fromScale(1, 1)
        clickButton.Text = ""
        clickButton.ZIndex = 10 -- Ensure it's on top
        clickButton.Parent = slot
    end
    
    return slot
end

--[[
    Updates the visual state of a slot based on whether its tool is equipped.
]]
local function updateSlotEquipState(slot: ToolSlot, isEquipped: boolean)
    local frame = slot.Frame
    
    -- BorderStroke is directly on slot (no Background)
    local stroke = frame:FindFirstChild("BorderStroke") :: UIStroke?
    
    if stroke then
        if isEquipped then
            stroke.Color = Color3.fromRGB(100, 255, 100) -- Green when selected
        else
            stroke.Color = CONFIG.BorderColor -- Default border color
        end
        -- Don't change thickness
    end
end

--[[
    Updates a slot's display with tool information.
]]
local VisualUtils = require(script.Parent:WaitForChild("VisualUtils"))

-- ...

--[[
    Updates a slot's display with tool information.
]]
local function updateSlotDisplay(slot: ToolSlot)
    local frame = slot.Frame
    local tool = slot.Tool
    
    -- All elements are directly on slot (no Background child)
    local toolIcon = frame:FindFirstChild("ToolIcon") :: ImageLabel?
    local nameLabel = frame:FindFirstChild("ToolNameLabel") :: TextLabel?
    
    -- Visuals (3D Model or Icon)
    -- Determine TemplateId (InventoryItemId > Attribute > StackTemplateId > Name)
    local templateId = (tool:GetAttribute("TemplateId") :: string?) or (tool:GetAttribute("StackTemplateId") :: string?) or tool.Name
    
    -- Cleanup Name if it has stack suffix (fallback for tools without attributes)
    if not (tool:GetAttribute("TemplateId") or tool:GetAttribute("StackTemplateId")) then
        templateId = string.gsub(templateId, "%s%(x%d+%)", "")
    end
    if tool:GetAttribute("InventoryItemId") then
         -- (Optional) Fetch true template ID from inventory if needed, but Attribute should be reliable
    end
    
    -- Create Viewport if missing
    local viewport = frame:FindFirstChild("ViewportFrame") :: ViewportFrame?
    if not viewport then
        viewport = Instance.new("ViewportFrame")
        viewport.Name = "ViewportFrame"
        viewport.Size = UDim2.fromScale(1, 1)
        viewport.BackgroundTransparency = 1
        viewport.ZIndex = 2
        viewport.Parent = frame
    end
    
    -- Try 3D Model
    local itemModel, isCustom = VisualUtils.FindItemModel(templateId)
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
                local modelAnims = animsFolder:FindFirstChild(templateId)
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
            
            setupSuccessful = true
        end
    end
    
    if not setupSuccessful then
         -- Fallback to Icon
         if viewport then viewport.Visible = false end
         if toolIcon then
             local textureId = VisualUtils.GetItemImage(templateId)
             if textureId == "" then
                  -- Fallback to tool texture or default
                  if tool.TextureId ~= "" then
                      textureId = tool.TextureId
                  else
                      textureId = "rbxassetid://6031763426"
                  end
             end
             toolIcon.Image = textureId
             toolIcon.Visible = true
         end
    end
    
    if nameLabel then
        -- Prefer Config DisplayName, fallback to tool Name
        local finalName = ItemUtils.GetDisplayName(templateId)
        
        nameLabel.Text = finalName
        nameLabel.Visible = true
    end
    
    -- Show stack count using existing QuantityLabel
    local quantityLabel = frame:FindFirstChild("QuantityLabel") :: TextLabel?
    if quantityLabel then
        local stackCount = tool:GetAttribute("StackCount") :: number?
        if stackCount and stackCount > 1 then
            quantityLabel.Text = "x" .. tostring(stackCount)
            quantityLabel.Visible = true
        else
            quantityLabel.Text = ""
            quantityLabel.Visible = false
        end
    end
    
    -- Use ItemUtils for config lookup (replaces 20-line inline function)
    local function getItemConfig(templateId: string): Configuration?
        return ItemUtils.FindItemConfig(templateId)
    end

    -- Apply rarity visuals using ColorSystem
    local rarity: string? = nil
    local customColor: string? = nil
    
    -- Try to get rarity/customColor/TemplateId from inventory data
    local inventoryItemId = tool:GetAttribute("InventoryItemId") :: string?
    local invTemplateId = nil
    
    if inventoryItemId then
        -- Access inventory store to get actual item data
        local invItem = InventoryStore.FindById(inventoryItemId)
        if invItem then
            rarity = invItem.Rarity :: string?
            invTemplateId = invItem.TemplateId
        end
    end
    
    -- Fallback to tool attributes
    if not rarity or rarity == "" then
        rarity = tool:GetAttribute("Rarity") :: string?
    end
    
    -- Check Config for CustomColor (Highest Priority)
    local colorTemplateId = invTemplateId or (tool:GetAttribute("TemplateId") :: string?) or tool.Name
    local itemConfig = getItemConfig(colorTemplateId)
    if itemConfig then
        customColor = itemConfig:GetAttribute("CustomColor") :: string?
    end

    -- Tool attribute fallback (Lowest Priority)
    if not customColor or customColor == "" then
        customColor = tool:GetAttribute("CustomColor") :: string?
    end
    
    local style = customColor
    if not style or style == "" then
        style = RarityConfig.GetBackgroundStyle(rarity)
    end
    
    ColorSystem.ApplyToBackground(frame, style or "Common")


    -- Update EventsLabel (Mutations)
    local eventsLabel = frame:FindFirstChild("EventsLabel") :: TextLabel?
    if eventsLabel then
        local mutationsJson = tool:GetAttribute("Mutations") :: string?
        if mutationsJson then
             local HttpService = game:GetService("HttpService")
              local success, mutations = pcall(function()
                  return HttpService:JSONDecode(mutationsJson)
              end)

              if success and mutations then
                   local count = 0
                   for _ in pairs(mutations) do
                       count = count + 1
                   end
                   if count > 0 then
                        eventsLabel.Text = tostring(count) .. " " .. (count == 1 and "Event" or "Events")
                        eventsLabel.Visible = true
                        
                        -- Apply dynamic color based on event count
                        local eventRarity = RarityConfig.GetEventRarity(count)
                        local eventStyle = RarityConfig.GetTextStyle(eventRarity)
                        ColorSystem.ApplyToText(eventsLabel, eventStyle)
                   else
                        eventsLabel.Text = ""
                        eventsLabel.Visible = false
                   end
              else
                 eventsLabel.Text = ""
                 eventsLabel.Visible = false
              end
        else
            eventsLabel.Text = ""
            eventsLabel.Visible = false
        end
    end

    -- Update RarityLabel
    local rarityLabel = frame:FindFirstChild("RarityLabel") :: TextLabel?
    if rarityLabel then
        rarityLabel.Text = rarity or "Common"
        rarityLabel.Visible = true
        
        local textStyle = nil
        if itemConfig then
             textStyle = itemConfig:GetAttribute("CustomTextColor") :: string?
        end
        
        if not textStyle then
             -- Check for specific custom text color attribute on tool (fallback)
             textStyle = tool:GetAttribute("CustomTextColor") :: string?
        end
        
        if not textStyle then
             textStyle = RarityConfig.GetTextStyle(rarity or "Common")
        end
        
        ColorSystem.ApplyToText(rarityLabel, textStyle)
    end
end

--[[
    Finds the first available slot index.
]]
local function findAvailableSlotIndex(): number?
    for i = 1, CONFIG.MaxSlots do
        if slotOrder[i] == nil then
            return i
        end
    end
    return nil
end

--[[
    Gets the weapons container from the existing player UI.
]]
local function getToolbarContainer(): Frame
    local playerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
    
    -- Navigate to the existing UI: playerui.Base.HID.Bottom.Weapons
    local base = playerGui:WaitForChild("Base")
    local hid = base:WaitForChild("HID")
    local bottom = hid:WaitForChild("Bottom")
    local weapons = bottom:WaitForChild("Weapons") :: Frame
    
    -- Clear any existing weapon slots (but keep UI layout components)
    for _, child in ipairs(weapons:GetChildren()) do
        if child:IsA("Frame") and child.Name:match("^Slot%d+$") then
            child:Destroy()
        end
    end
    
    return weapons
end

--[[
    Adds a tool to the toolbar.
]]
local function addTool(tool: Tool)
    if toolSlots[tool] then
        return -- Already added
    end
    
    -- First check if the tool has a ToolbarSlot attribute (assigned by inventory system)
    local rawAssignedSlot = tool:GetAttribute("ToolbarSlot")
    local assignedSlot = if type(rawAssignedSlot) == "number" then rawAssignedSlot else tonumber(rawAssignedSlot)
    local slotIndex: number?
    
    if assignedSlot and assignedSlot >= 1 and assignedSlot <= CONFIG.MaxSlots then
        -- Server-assigned slot is authoritative - forcefully use it
        local existingTool = slotOrder[assignedSlot]
        if existingTool and existingTool ~= tool then
            -- Another tool is in our assigned slot - it will be removed by server
            -- Clear it from our tracking to make room (server is source of truth)
            local existingSlot = toolSlots[existingTool]
            if existingSlot then
                existingSlot.Frame:Destroy()
                toolSlots[existingTool] = nil
            end
            slotOrder[assignedSlot] = nil
        end
        slotIndex = assignedSlot
    else
        -- No assignment, find first available
        slotIndex = findAvailableSlotIndex()
    end
    
    if not slotIndex then
        warn("[Toolbar] No available slots for tool:", tool.Name)
        return
    end
    
    local frame = createSlotFrame(slotIndex)
    
    if toolbarFrame then
        frame.Parent = toolbarFrame
    end
    
    local slot: ToolSlot = {
        Tool = tool,
        Frame = frame,
        Index = slotIndex,
    }
    
    toolSlots[tool] = slot
    slotOrder[slotIndex] = tool
    
    updateSlotDisplay(slot)
    
    -- Check if this tool is currently equipped
    local character = LocalPlayer.Character
    if character and tool.Parent == character then
        equippedTool = tool
        updateSlotEquipState(slot, true)
    end
    
    -- Setup click handler
    local clickButton = frame:FindFirstChild("ClickButton") :: TextButton?
    if clickButton then
        clickButton.MouseButton1Click:Connect(function()
            local humanoid = character and character:FindFirstChild("Humanoid") :: Humanoid?
            if humanoid then
                if equippedTool == tool then
                    humanoid:UnequipTools()
                else
                    humanoid:EquipTool(tool)
                end
            end
        end)
    end
    
    -- Listen for StackCount changes to update display
    tool:GetAttributeChangedSignal("StackCount"):Connect(function()
        if toolSlots[tool] then
            updateSlotDisplay(toolSlots[tool])
        end
    end)
end

--[[
    Removes a tool from the toolbar.
]]
local function removeTool(tool: Tool)
    local slot = toolSlots[tool]
    if not slot then
        -- Check if it's in slotOrder still (sometimes tool instance might be lost but slot remains)
        for i = 1, CONFIG.MaxSlots do
            if slotOrder[i] == tool then
                slotOrder[i] = nil
            end
        end
        return
    end
    
    -- Clear equipped state if this was the equipped tool
    if equippedTool == tool then
        equippedTool = nil
    end
    
    -- Destroy the frame
    if slot.Frame then
        slot.Frame:Destroy()
    end
    
    -- Clear from tracking
    if slotOrder[slot.Index] == tool then
        slotOrder[slot.Index] = nil
    end
    toolSlots[tool] = nil
end

--[[
    Handles tool equipped event.
]]
local function onToolEquipped(tool: Tool)
    -- Unequip visual from previous tool
    if equippedTool and toolSlots[equippedTool] then
        updateSlotEquipState(toolSlots[equippedTool], false)
    end
    
    equippedTool = tool
    
    -- Update visual for newly equipped tool
    if toolSlots[tool] then
        updateSlotEquipState(toolSlots[tool], true)
    end
end

--[[
    Handles tool unequipped event.
]]
local function onToolUnequipped(tool: Tool)
    if equippedTool == tool then
        equippedTool = nil
        
        if toolSlots[tool] then
            updateSlotEquipState(toolSlots[tool], false)
        end
    end
end

--[[
    Sets up character connections.
]]
local function setupCharacter(character: Model)
    -- Clear previous state
    for tool, _ in pairs(toolSlots) do
        removeTool(tool)
    end
    equippedTool = nil
    
    -- Get backpack
    local backpack = LocalPlayer:WaitForChild("Backpack") :: Backpack
    
    -- Add existing tools in backpack
    for _, child in ipairs(backpack:GetChildren()) do
        if child:IsA("Tool") then
            addTool(child)
        end
    end
    
    -- Add equipped tools (in character)
    for _, child in ipairs(character:GetChildren()) do
        if child:IsA("Tool") then
            addTool(child)
            onToolEquipped(child)
        end
    end
    
    -- Listen for new tools in backpack
    local backpackConnection = backpack.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then
            addTool(child)
        end
    end)
    janitor:Add(backpackConnection)
    
    -- Listen for tools removed from backpack
    local backpackRemoveConnection = backpack.ChildRemoved:Connect(function(child)
        if child:IsA("Tool") then
            -- Only remove if not moving to character (equipping)
            task.defer(function()
                if child.Parent ~= character then
                    removeTool(child)
                end
            end)
        end
    end)
    janitor:Add(backpackRemoveConnection)
    
    -- Listen for tools equipped (moved to character)
    local characterAddConnection = character.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then
            -- Make sure tool is in our slots
            if not toolSlots[child] then
                addTool(child)
            end
            onToolEquipped(child)
        end
    end)
    janitor:Add(characterAddConnection)
    
    -- Listen for tools unequipped (moved from character)
    local characterRemoveConnection = character.ChildRemoved:Connect(function(child)
        if child:IsA("Tool") then
            onToolUnequipped(child)
            -- Only remove if not going back to backpack
            task.defer(function()
                if child.Parent ~= backpack then
                    removeTool(child)
                end
            end)
        end
    end)
    janitor:Add(characterRemoveConnection)
end

--[[
    Gets the current equipped slot index, or nil if nothing is equipped.
]]
local function getEquippedSlotIndex(): number?
    if equippedTool then
        local slot = toolSlots[equippedTool]
        if slot then
            return slot.Index
        end
    end
    return nil
end

--[[
    Finds the next occupied slot in a given direction.
    @param direction - 1 for next, -1 for previous
    @return The slot index of the next/previous tool, or nil if no tools exist
]]
local function findNextOccupiedSlot(currentIndex: number, direction: number): number?
    for i = 1, CONFIG.MaxSlots do
        local nextIndex = ((currentIndex - 1 + direction * i) % CONFIG.MaxSlots) + 1
        if slotOrder[nextIndex] then
            return nextIndex
        end
    end
    return nil
end

--[[
    Equips a tool at the specified slot index.
]]
local lastEquipTime = 0
local EQUIP_DEBOUNCE = 0.1

local function equipSlot(slotIndex: number)
    -- Prevent spamming equip which causes network lag
    local now = tick()
    if now - lastEquipTime < EQUIP_DEBOUNCE then
        return
    end
    
    local tool = slotOrder[slotIndex]
    if tool then
        local character = LocalPlayer.Character
        local humanoid = character and character:FindFirstChild("Humanoid") :: Humanoid?
        
        if humanoid then
            lastEquipTime = now
            if equippedTool == tool then
                humanoid:UnequipTools()
            else
                humanoid:EquipTool(tool)
            end
        end
    end
end

--[[
    Handles hotkey input for tool selection.
]]
local function setupHotkeyInput()
    -- Keyboard input for number keys 1-9
    local inputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then
            return
        end
        
        -- Check for number keys 1-9
        local keyNumber: number? = nil
        
        if input.KeyCode == Enum.KeyCode.One then
            keyNumber = 1
        elseif input.KeyCode == Enum.KeyCode.Two then
            keyNumber = 2
        elseif input.KeyCode == Enum.KeyCode.Three then
            keyNumber = 3
        elseif input.KeyCode == Enum.KeyCode.Four then
            keyNumber = 4
        elseif input.KeyCode == Enum.KeyCode.Five then
            keyNumber = 5
        elseif input.KeyCode == Enum.KeyCode.Six then
            keyNumber = 6
        elseif input.KeyCode == Enum.KeyCode.Seven then
            keyNumber = 7
        elseif input.KeyCode == Enum.KeyCode.Eight then
            keyNumber = 8
        elseif input.KeyCode == Enum.KeyCode.Nine then
            keyNumber = 9
        end
        
        if keyNumber then
            equipSlot(keyNumber)
        end
    end)
    janitor:Add(inputConnection)
    
    -- Mouse scroll input for cycling through weapons (only for Gun type)
    local scrollConnection = UserInputService.InputChanged:Connect(function(input, gameProcessed)
        if gameProcessed then
            return
        end
        
        if input.UserInputType == Enum.UserInputType.MouseWheel then
            -- Only allow scroll switching if equipped tool is ItemType "Gun"
            if equippedTool then
                -- Use ItemUtils for config lookup (replaces 25-line inline pattern)
                local gunTemplateId = (equippedTool:GetAttribute("TemplateId") :: string?) or equippedTool.Name
                local itemType = ItemUtils.GetItemType(gunTemplateId)
                if itemType ~= "Gun" then
                    return -- Don't allow scroll for non-Gun items
                end
            else
                -- Nothing equipped, do nothing
                return
            end
            
            local scrollDirection = input.Position.Z -- Positive = scroll up, Negative = scroll down
            
            local currentSlotIndex = getEquippedSlotIndex()
            local nextSlotIndex: number?
            
            if currentSlotIndex then
                -- Find next occupied slot in the scroll direction
                -- Scroll up (positive) = next slot (direction 1)
                -- Scroll down (negative) = previous slot (direction -1)
                local direction = if scrollDirection > 0 then 1 else -1
                
                -- Ensure we don't pick the same slot if only 1 weapon is available
                -- And finding next slot should cycle correctly
                nextSlotIndex = findNextOccupiedSlot(currentSlotIndex, direction)
                
                -- Only switch if we found a different valid slot
                if nextSlotIndex and nextSlotIndex ~= currentSlotIndex then
                    equipSlot(nextSlotIndex)
                end
            end
        end
    end)
    janitor:Add(scrollConnection)
end

--[[
    Disables the default Roblox backpack.
]]
local function disableDefaultBackpack()
    local success = pcall(function()
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
    end)
    
    if not success then
        -- Retry after a delay (sometimes fails on first try)
        task.delay(1, function()
            pcall(function()
                StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
            end)
        end)
    end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--[[
    Initializes the custom toolbar with the given client context.
    @param context - ClientContext with Player, PlayerGui, Character, etc.
]]
function Toolbar.Init(context: any)
    -- Update module reference to use the provided player
    LocalPlayer = context.Player
    
    -- Disable default backpack
    disableDefaultBackpack()
    
    -- Get toolbar container from existing player UI
    toolbarFrame = getToolbarContainer()
    
    -- Setup hotkey input
    setupHotkeyInput()
    
    -- Handle current character
    setupCharacter(context.Character)
    
    -- Handle future characters
    LocalPlayer.CharacterAdded:Connect(function(character)
        -- Clean up old connections with Janitor
        janitor:Cleanup()
        
        setupCharacter(character)
        setupHotkeyInput()
    end)
    
    print("[Toolbar] Custom toolbar initialized!")
end

--[[
    Gets the currently equipped tool.
]]
function Toolbar.GetEquippedTool(): Tool?
    return equippedTool
end

--[[
    Refreshes all toolbar slots.
    Useful when inventory data changes that affects visuals (like rarity colors).
]]
function Toolbar.Refresh()
    -- Authoritative sync with InventoryStore to catch any desyncs from Roblox tool events
    local currentToolbarSlots = InventoryStore.GetToolbarSlots()
    
    -- Create map of assigned item IDs for O(1) check
    local assignedIds = {}
    for _, id in pairs(currentToolbarSlots) do
        assignedIds[id] = true
    end
    
    -- Prune tools that are no longer in inventory or unassigned
    for tool, slot in pairs(toolSlots) do
        local invId = tool:GetAttribute("InventoryItemId") :: string?
        if invId then
            -- If it's an inventory item, check if it's still assigned to toolbar AND exists in inventory
            local existsInInventory = InventoryStore.FindById(invId) ~= nil
            if not assignedIds[invId] or not existsInInventory or tool.Parent == nil then
                removeTool(tool)
            end
        end
    end
    

    -- Re-verify slotOrder to ensure no ghost slots
    for i = 1, CONFIG.MaxSlots do
        local tool = slotOrder[i]
        if tool then
            if tool.Parent == nil or not tool:IsDescendantOf(game) then
                removeTool(tool)
            end
        end
    end
    
    -- RESCAN: Check for tools that might have been dropped or seem new due to ID updates
    -- This handles the race condition where "Remove" packet processed before "ToolbarUpdate"
    -- causing the tool to be pruned because it holds the old ID.
    local function checkAndRecoverTools(container: Instance)
        for _, child in ipairs(container:GetChildren()) do
            if child:IsA("Tool") and not toolSlots[child] then
                addTool(child)
            end
        end
    end

    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if backpack then checkAndRecoverTools(backpack) end

    local character = LocalPlayer.Character
    if character then checkAndRecoverTools(character) end

    -- Update visuals for all active slots
    for _, slot in pairs(toolSlots) do
        updateSlotDisplay(slot)
    end
end

--[[
    Gets the tool at a specific slot index.
]]
function Toolbar.GetToolAtSlot(index: number): Tool?
    return slotOrder[index]
end

--[[
    Gets all toolbar slot data for display in inventory UI.
    Returns array of {slotIndex, tool, isFromInventory}
]]
function Toolbar.GetToolbarData(): {{SlotIndex: number, Tool: Tool?, InventoryItemId: string?}}
    local data = {}
    for i = 1, CONFIG.MaxSlots do
        local tool = slotOrder[i]
        local inventoryItemId = nil
        
        -- Check if tool has inventory item ID attribute
        if tool then
            inventoryItemId = tool:GetAttribute("InventoryItemId") :: string?
        end
        
        table.insert(data, {
            SlotIndex = i,
            Tool = tool,
            InventoryItemId = inventoryItemId,
        })
    end
    return data
end

--[[
    Checks if a tool is from the inventory system (has InventoryItemId attribute).
]]
function Toolbar.IsInventoryItem(tool: Tool): boolean
    return tool:GetAttribute("InventoryItemId") ~= nil
end

--[[
    Sets the visibility of the toolbar.
    @param visible - Whether to show or hide the toolbar
]]
function Toolbar.SetVisible(visible: boolean)
    if toolbarFrame then
        toolbarFrame.Visible = visible
    end
end

--[[
    Gets the toolbar frame reference.
]]
function Toolbar.GetFrame(): Frame?
    return toolbarFrame
end

return Toolbar

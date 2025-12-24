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
local Janitor = require(Packages:WaitForChild("janitor"))

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
    
    -- Update hotkey label if it exists
    local hotkeyLabel = slot:FindFirstChild("HotkeyLabel") :: TextLabel?
    if hotkeyLabel then
        hotkeyLabel.Text = tostring(index)
    end
    
    return slot
end

--[[
    Updates the visual state of a slot based on whether its tool is equipped.
]]
local function updateSlotEquipState(slot: ToolSlot, isEquipped: boolean)
    local frame = slot.Frame
    local stroke = frame:FindFirstChild("BorderStroke") :: UIStroke?
    
    if stroke then
        if isEquipped then
            stroke.Color = CONFIG.EquippedBorderColor
            stroke.Thickness = CONFIG.EquippedBorderThickness
        else
            stroke.Color = CONFIG.BorderColor
            stroke.Thickness = CONFIG.BorderThickness
        end
    end
end

--[[
    Updates a slot's display with tool information.
]]
local function updateSlotDisplay(slot: ToolSlot)
    local frame = slot.Frame
    local tool = slot.Tool
    
    local toolIcon = frame:FindFirstChild("ToolIcon") :: ImageLabel?
    local nameLabel = frame:FindFirstChild("ToolNameLabel") :: TextLabel?
    
    if toolIcon then
        -- Try to use tool's TextureId, fallback to a placeholder
        if tool.TextureId ~= "" then
            toolIcon.Image = tool.TextureId
        else
            toolIcon.Image = "rbxassetid://6031763426" -- Default tool icon
        end
    end
    
    if nameLabel then
        nameLabel.Text = tool.Name
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
    
    local slotIndex = findAvailableSlotIndex()
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
end

--[[
    Removes a tool from the toolbar.
]]
local function removeTool(tool: Tool)
    local slot = toolSlots[tool]
    if not slot then
        return
    end
    
    -- Clear equipped state if this was the equipped tool
    if equippedTool == tool then
        equippedTool = nil
    end
    
    -- Destroy the frame
    slot.Frame:Destroy()
    
    -- Clear from tracking
    slotOrder[slot.Index] = nil
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
    Handles hotkey input for tool selection.
]]
local function setupHotkeyInput()
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
            local tool = slotOrder[keyNumber]
            if tool then
                local character = LocalPlayer.Character
                local humanoid = character and character:FindFirstChild("Humanoid") :: Humanoid?
                
                if humanoid then
                    if equippedTool == tool then
                        humanoid:UnequipTools()
                    else
                        humanoid:EquipTool(tool)
                    end
                end
            end
        end
    end)
    janitor:Add(inputConnection)
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

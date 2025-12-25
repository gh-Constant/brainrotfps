--!strict
--[[
    ButtonToggles Module
    Handles UI button toggles for left sidebar buttons (Shop, Inventory, etc.)
    
    Each button toggles the visibility of its corresponding ScreenGui/Frame.
]]

local ButtonToggles = {}

-- Store for registered toggles (no longer stores state, just the references)
local registeredToggles: {[string]: {
    button: GuiButton,
    targetFrame: GuiObject,
    onToggle: ((boolean) -> ())?
}} = {}

--[[
    Registers a toggle button that controls frame visibility.
    
    @param name - Unique identifier for this toggle
    @param button - The button that triggers the toggle
    @param targetFrame - The frame to show/hide
    @param startVisible - Initial visibility state (default: false)
    @param onToggle - Optional callback when toggled
]]
function ButtonToggles.Register(
    name: string,
    button: GuiButton,
    targetFrame: GuiObject,
    startVisible: boolean?,
    onToggle: ((boolean) -> ())?
)
    local visible = startVisible or false
    targetFrame.Visible = visible
    
    registeredToggles[name] = {
        button = button,
        targetFrame = targetFrame,
        onToggle = onToggle,
    }
    
    button.Activated:Connect(function()
        ButtonToggles.Toggle(name)
    end)
    
    print(string.format("[ButtonToggles] Registered '%s' toggle", name))
end

--[[
    Toggles a registered UI element.
    Uses the inverse of the current Visible property.
    
    @param name - The toggle identifier
    @param state - Optional explicit state (true/false), nil to toggle current
]]
function ButtonToggles.Toggle(name: string, state: boolean?)
    local toggle = registeredToggles[name]
    if not toggle then
        warn(string.format("[ButtonToggles] Toggle '%s' not registered", name))
        return
    end
    
    -- Use inverse of current visible state, or explicit state if provided
    local newState = if state ~= nil then state else not toggle.targetFrame.Visible
    toggle.targetFrame.Visible = newState
    
    if toggle.onToggle then
        toggle.onToggle(newState)
    end
    
    print(string.format("[ButtonToggles] '%s' toggled: %s", name, tostring(newState)))
end

--[[
    Gets the current state of a toggle.
    
    @param name - The toggle identifier
    @return boolean - Current visibility state
]]
function ButtonToggles.IsOpen(name: string): boolean
    local toggle = registeredToggles[name]
    return toggle and toggle.targetFrame.Visible or false
end

--[[
    Closes all registered toggles.
]]
function ButtonToggles.CloseAll()
    for name, _ in registeredToggles do
        ButtonToggles.Toggle(name, false)
    end
end

--[[
    Initializes button toggles by finding and registering UI elements.
    
    @param context - UI context with PlayerGui and frame references
]]
function ButtonToggles.Init(context: any)
    local playerGui = context.PlayerGui :: PlayerGui
    local hidFrame = context.HIDFrame
    
    if not hidFrame then
        warn("[ButtonToggles] HID frame not found in context")
        return
    end
    
    local leftFrame = hidFrame:FindFirstChild("Left")
    if not leftFrame then
        warn("[ButtonToggles] Left frame not found in HID")
        return
    end
    
    local buttons = leftFrame:FindFirstChild("Buttons")
    if not buttons then
        warn("[ButtonToggles] Buttons container not found in Left frame")
        return
    end
    
    -- Register Shop toggle
    task.spawn(function()
        local shopButton = buttons:FindFirstChild("Shop") :: GuiButton?
        if shopButton then
            local shopGui = playerGui:WaitForChild("Shop", 10)
            if shopGui then
                local shopFrame = shopGui:FindFirstChild("Shop") :: GuiObject?
                if shopFrame then
                    ButtonToggles.Register("Shop", shopButton, shopFrame, false)
                else
                    warn("[ButtonToggles] Shop frame not found in Shop ScreenGui")
                end
            else
                warn("[ButtonToggles] Shop ScreenGui not found")
            end
        else
            warn("[ButtonToggles] Shop button not found")
        end
    end)
    
    -- Register Inventory toggle
    -- Note: Inventory has its own module, but we can still register the button here
    -- for consistency if needed. Currently InventoryUI handles its own button.
    
    print("[ButtonToggles] Initialized")
end

return ButtonToggles

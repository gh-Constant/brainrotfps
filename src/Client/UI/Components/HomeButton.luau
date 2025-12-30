--!strict
local Workspace = game:GetService("Workspace")

local HomeButton = {}

--[[
    Initializes the Home Button component.
    @param uiContext - The UI context containing frame references
]]
function HomeButton.Init(uiContext: any)
    local leftFrame = uiContext.LeftFrame
    if not leftFrame then return end
    
    local buttons = leftFrame:FindFirstChild("Buttons")
    if not buttons then return end
    
    local homeButton = buttons:FindFirstChild("Home") :: GuiButton?
    if not homeButton then return end
    
    homeButton.MouseButton1Click:Connect(function()

        print("Home button clicked")

        local character = uiContext.Character
        if not character then return end
        
        -- Check combat status
        local inCombat = character:GetAttribute("InCombat") == true
        if inCombat then
             -- Optional: Feedback for player? User didn't specify, just doing nothing as requested ("when not in combat we get tp")
            return
        end
        
        -- Find SpawnLocations
        local spawns = {}
        for _, child in Workspace:GetDescendants() do
            if child:IsA("SpawnLocation") then
                table.insert(spawns, child)
            end
        end
        
        if #spawns > 0 then
            local randomSpawn = spawns[math.random(1, #spawns)]
            -- Teleport slightly above spawn to avoid sticking
            character:PivotTo(randomSpawn.CFrame + Vector3.new(0, 3, 0))
        end
    end)
end

return HomeButton

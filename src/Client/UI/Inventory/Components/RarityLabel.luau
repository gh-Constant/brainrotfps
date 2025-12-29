--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Shared = Rojo:WaitForChild("Shared")
local Inventory = require(Shared:WaitForChild("Inventory"))
local RarityConfig = require(Shared:WaitForChild("Rarity"):WaitForChild("RarityConfig"))
local ColorSystem = require(Shared:WaitForChild("Inventory"):WaitForChild("ColorSystem"))

type InventoryItem = Inventory.InventoryItem

local RarityLabel = {}

function RarityLabel.Mount(instance: GuiObject, item: InventoryItem, props: any)
    local label = instance
    if not label:IsA("TextLabel") then
        -- Maybe it's a frame containing the label?
        -- User said "RarityLabel layoutorder 1 with the color and name of the rairty"
        local foundLabel = instance:FindFirstChildWhichIsA("TextLabel")
        if foundLabel then label = foundLabel end
    end
    
    if label:IsA("TextLabel") then
        local rarity = item.Rarity or "Common"
        label.Text = string.upper(rarity)
        
        -- Apply color using text style (which may differ from background style)
        local style = RarityConfig.GetTextStyle(rarity)
        -- Usually RarityLabel text color matches the rarity
        -- We can try to get the ColorSequence Keypoint 0 color? 
        -- Or simply use white text with gradient?
        
        -- User said "color and name of the rairty". 
        -- If it has a UIGradient child, we apply the style to it.
        if instance:FindFirstChild("UIGradient") then
             ColorSystem.ApplyToBackground(instance, style)
        else
            -- If no gradient, maybe set TextColor3?
            -- But ColorSystem deals with Gradients. 
            -- Let's try applying to background/gradient first as that's the system standard.
             ColorSystem.ApplyToBackground(instance, style)
        end
    end
end

return RarityLabel

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")


local GrenadeController = require(script.Parent.Parent.Parent.Weapons.GrenadeController)

local MobileControls = {}

function MobileControls.Init(context: any)
	-- Only run on touch devices
	if not UserInputService.TouchEnabled then
		return
	end
	
	local playerGui = context.PlayerGui
	local baseGui = playerGui:WaitForChild("Base", 10)
	if not baseGui then return end
	
	-- container
	local controlsFrame = Instance.new("Frame")
	controlsFrame.Name = "MobileControls"
	controlsFrame.Size = UDim2.new(1, 0, 1, 0)
	controlsFrame.BackgroundTransparency = 1
	controlsFrame.Parent = baseGui
	
	-- Helper to create circular buttons
	local function createButton(name: string, position: UDim2, iconId: string, color: Color3)
		local button = Instance.new("ImageButton")
		button.Name = name
		button.Size = UDim2.fromOffset(60, 60)
		button.Position = position
		button.AnchorPoint = Vector2.new(0.5, 0.5)
		button.BackgroundColor3 = color
		button.BackgroundTransparency = 0.3
		button.Image = iconId -- "rbxassetid://..."
		button.Parent = controlsFrame
		button.Visible = false -- Hidden by default
		
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = button
		
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = Color3.new(1, 1, 1)
		stroke.Transparency = 0.5
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = button
		
		-- Icon (Text for now if icon missing)
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Text = name
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.Parent = button
		
		if iconId ~= "" then
			label.Visible = false
		end
		
		return button
	end
	
	-- Jump Button (Always visible)
	local jumpBtn = createButton("Jump", UDim2.new(0.85, 0, 0.7, 0), "", Color3.fromRGB(0, 150, 255))
	jumpBtn.Visible = true
	
	jumpBtn.MouseButton1Down:Connect(function()
		local hum = context.Humanoid or Players.LocalPlayer.Character:FindFirstChild("Humanoid")
		if hum then
			hum.Jump = true
		end
	end)
	
	-- Grenade Button
	local grenadeBtn = createButton("USE", UDim2.new(0.72, 0, 0.7, 0), "", Color3.fromRGB(255, 50, 50))
	
	grenadeBtn.MouseButton1Down:Connect(function()
		GrenadeController.StartCharge()
	end)
	
	grenadeBtn.MouseButton1Up:Connect(function()
		GrenadeController.EndCharge()
	end)
	grenadeBtn.MouseLeave:Connect(function()
		GrenadeController.EndCharge()
	end)
	
	-- Potion Button 
	local potionBtn = createButton("USE", UDim2.new(0.72, 0, 0.7, 0), "", Color3.fromRGB(255, 50, 50))
    
    potionBtn.MouseButton1Click:Connect(function()
        local char = Players.LocalPlayer.Character
		if char then
            local tool = char:FindFirstChildWhichIsA("Tool")
            if tool and tool:GetAttribute("IsPotion") then
                tool:Activate()
            end
        end
    end)
	
    -- State Management
    local function updateButtons()
        grenadeBtn.Visible = false
        potionBtn.Visible = false
        
        local char = Players.LocalPlayer.Character
        if not char then return end
        
        local tool = char:FindFirstChildWhichIsA("Tool")
        if tool then
            if tool:GetAttribute("IsGrenade") then
                grenadeBtn.Visible = true
            elseif tool:GetAttribute("IsPotion") then
                potionBtn.Visible = true
            end
        end
    end
    
    -- Connections
    local toolConnections = {}
    
    local function onCharacterAdded(char)
        table.clear(toolConnections)
        
        table.insert(toolConnections, char.ChildAdded:Connect(updateButtons))
        table.insert(toolConnections, char.ChildRemoved:Connect(updateButtons))
        
        updateButtons()
    end
    
    if Players.LocalPlayer.Character then
        onCharacterAdded(Players.LocalPlayer.Character)
    end
    
	Players.LocalPlayer.CharacterAdded:Connect(onCharacterAdded)

	print("[MobileControls] Initialized")
end

return MobileControls

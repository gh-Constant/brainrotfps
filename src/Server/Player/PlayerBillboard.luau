--!strict
--[[
    PlayerBillboard.luau
    Server-side module that creates and manages player billboard UI (name, level, health, PVP status).
    Clones the PlayerBillboard template from ReplicatedStorage.Config.Player.UI into the player's HumanoidRootPart.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Packages = Rojo:WaitForChild("Packages")
local Janitor = require(Packages:WaitForChild("janitor"))
local MoneyLib = require(Rojo:WaitForChild("Shared"):WaitForChild("MoneyLib"))

local PlayerBillboard = {}
PlayerBillboard.__index = PlayerBillboard

-- Template cache
local BillboardTemplate: BillboardGui? = nil

local function getTemplate(): BillboardGui?
    if BillboardTemplate then
        return BillboardTemplate
    end
    
    local config = ReplicatedStorage:FindFirstChild("Config")
    if not config then
        warn("[PlayerBillboard] Missing 'Config' in ReplicatedStorage")
        return nil
    end
    
    local playerConfig = config:FindFirstChild("Player")
    if not playerConfig then
        warn("[PlayerBillboard] Missing 'Player' in Config")
        return nil
    end
    
    local uiConfig = playerConfig:FindFirstChild("UI")
    if not uiConfig then
        warn("[PlayerBillboard] Missing 'UI' in Player config")
        return nil
    end
    
    local template = uiConfig:FindFirstChild("PlayerBillboard")
    if not template or not template:IsA("BillboardGui") then
        warn("[PlayerBillboard] Missing or invalid 'PlayerBillboard' template")
        return nil
    end
    
    BillboardTemplate = template
    return template
end

export type PlayerBillboardObject = typeof(setmetatable({}, PlayerBillboard)) & {
    Character: Model,
    Billboard: BillboardGui,
    PlayerNameLabel: TextLabel?,
    LevelLabel: TextLabel?,
    HealthLabel: TextLabel?,
    HealthBar: GuiObject?,
    HostileGradient: UIGradient?,
    PeacefulGradient: UIGradient?,
    HostileImage: ImageLabel?,
    PeacefulImage: ImageLabel?,
    HostileLabel: TextLabel?,
    PeacefulLabel: TextLabel?,
    _janitor: typeof(Janitor.new()),
}

--[[
    Creates a new PlayerBillboard for the given character.
    Expected structure (from uploaded image):
    PlayerBillboard (BillboardGui)
      └ Base (Frame)
          ├ Health (Frame)
          │   ├ HP (Frame - the filling bar)
          │   │   ├ HostileGradient (UIGradient)
          │   │   └ PeacefulGradient (UIGradient)
          │   └ TextLabel (TextLabel - health text)
          ├ Level (Frame)
          │   └ Level (TextLabel)
          ├ PlayerName (Frame)
          │   └ PlayerName (TextLabel)
          ├ HostileImage (ImageLabel)
          ├ PeacefulImage (ImageLabel)
          ├ Hostile (TextLabel)
          └ Peaceful (TextLabel)
]]
function PlayerBillboard.new(character: Model, playerData: any): PlayerBillboardObject?
    local template = getTemplate()
    if not template then
        return nil
    end
    
    local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    local head = character:FindFirstChild("Head") :: BasePart?
    if not rootPart then
        warn("[PlayerBillboard] Character missing HumanoidRootPart")
        return nil
    end
    
    -- Create an invisible part welded above the head for the billboard
    local billboardPart = Instance.new("Part")
    billboardPart.Name = "BillboardAnchor"
    billboardPart.Size = Vector3.new(0.1, 0.1, 0.1)
    billboardPart.Transparency = 1
    billboardPart.CanCollide = false
    billboardPart.CanQuery = false
    billboardPart.CanTouch = false
    billboardPart.Massless = true
    billboardPart.Anchored = false
    
    -- Position above head (head is ~1.5 studs above rootPart, add ~3 studs higher for visibility)
    local headHeight = if head then (head.Position.Y - rootPart.Position.Y) + 3 else 4.5
    billboardPart.CFrame = rootPart.CFrame * CFrame.new(0, headHeight, 0)
    billboardPart.Parent = character
    
    -- Weld to HumanoidRootPart
    local weld = Instance.new("Weld")
    weld.Part0 = rootPart
    weld.Part1 = billboardPart
    weld.C0 = CFrame.new(0, headHeight, 0)
    weld.Parent = billboardPart
    
    -- Clone and parent billboard to the welded part
    local billboard = template:Clone()
    billboard.Adornee = billboardPart
    billboard.Parent = billboardPart
    
    -- Hide billboard from the local player (only others can see it)
    local player = Players:GetPlayerFromCharacter(character)
    if player then
        billboard.PlayerToHideFrom = player
    end
    
    local base = billboard:FindFirstChild("Base") :: Frame?
    if not base then
        warn("[PlayerBillboard] Billboard missing 'Base' frame")
        billboard:Destroy()
        return nil
    end
    
    local self = setmetatable({}, PlayerBillboard)
    self.Character = character
    self.Billboard = billboard
    self._janitor = Janitor.new()
    self._playerData = playerData
    
    -- Find UI components
    -- Player Name
    local playerNameFrame = base:FindFirstChild("PlayerName") :: Frame?
    if playerNameFrame then
        self.PlayerNameLabel = playerNameFrame:FindFirstChild("PlayerName") :: TextLabel?
    end
    
    -- Level
    local levelFrame = base:FindFirstChild("Level") :: Frame?
    if levelFrame then
        self.LevelLabel = levelFrame:FindFirstChild("Level") :: TextLabel?
    end
    
    -- Health
    local healthFrame = base:FindFirstChild("Health") :: Frame?
    if healthFrame then
        self.HealthLabel = healthFrame:FindFirstChild("TextLabel") :: TextLabel?
        self.HealthBar = healthFrame:FindFirstChild("HP") :: Frame?
        
        if self.HealthBar then
            self.HostileGradient = self.HealthBar:FindFirstChild("HostileGradient") :: UIGradient?
            self.PeacefulGradient = self.HealthBar:FindFirstChild("PeacefulGradient") :: UIGradient?
        end
    end
    
    -- PVP Status elements
    self.HostileImage = base:FindFirstChild("HostileImage") :: ImageLabel?
    self.PeacefulImage = base:FindFirstChild("PeacefulImage") :: ImageLabel?
    self.HostileLabel = base:FindFirstChild("Hostile") :: TextLabel?
    self.PeacefulLabel = base:FindFirstChild("Peaceful") :: TextLabel?
    
    -- Initialize display
    self:UpdatePlayerName()
    self:UpdateLevel()
    self:UpdateHealth()
    self:UpdatePVPStatus()
    
    -- Setup listeners
    self:SetupListeners()
    
    return self
end

function PlayerBillboard:UpdatePlayerName()
    if not self.PlayerNameLabel then return end
    
    local player = game:GetService("Players"):GetPlayerFromCharacter(self.Character)
    if player then
        self.PlayerNameLabel.Text = player.DisplayName
    end
end

function PlayerBillboard:UpdateLevel()
    if not self.LevelLabel then return end
    
    local level: number = 1
    if self._playerData then
        level = self._playerData.Level
    else
        -- Fallback to attribute
        local levelAttr = self.Character:GetAttribute("Level")
        level = if typeof(levelAttr) == "number" then levelAttr else 1
    end
    
    -- Format level with commas (keeps all digits)
    self.LevelLabel.Text = MoneyLib.FormatWithCommas(level)
end

function PlayerBillboard:UpdateHealth()
    local healthAttr = self.Character:GetAttribute("Health")
    local maxHealthAttr = self.Character:GetAttribute("MaxHealth")
    
    local health: number = if typeof(healthAttr) == "number" then healthAttr else 100
    local maxHealth: number = if typeof(maxHealthAttr) == "number" then maxHealthAttr else 100
    
    -- Update health text with abbreviated MoneyLib formatting
    if self.HealthLabel then
        self.HealthLabel.Text = string.format("%s / %s", MoneyLib.HandleMoney(health), MoneyLib.HandleMoney(maxHealth))
    end
    
    -- Tween health bar
    if self.HealthBar then
        local percent = math.clamp(health / maxHealth, 0, 1)
        local goal = { Size = UDim2.fromScale(percent, 1) }
        local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        TweenService:Create(self.HealthBar, tweenInfo, goal):Play()
    end
end

function PlayerBillboard:UpdatePVPStatus()
    local isPvPEnabled = self.Character:GetAttribute("IsPvPEnabled") == true
    
    -- Toggle hostile/peaceful images
    if self.HostileImage then
        self.HostileImage.Visible = isPvPEnabled
    end
    if self.PeacefulImage then
        self.PeacefulImage.Visible = not isPvPEnabled
    end
    
    -- Toggle hostile/peaceful labels
    if self.HostileLabel then
        self.HostileLabel.Visible = isPvPEnabled
    end
    if self.PeacefulLabel then
        self.PeacefulLabel.Visible = not isPvPEnabled
    end
    
    -- Toggle gradients
    if self.HostileGradient then
        self.HostileGradient.Enabled = isPvPEnabled
    end
    if self.PeacefulGradient then
        self.PeacefulGradient.Enabled = not isPvPEnabled
    end
end

function PlayerBillboard:SetupListeners()
    -- Listen for attribute changes
    self._janitor:Add(self.Character.AttributeChanged:Connect(function(attribute)
        if attribute == "Health" or attribute == "MaxHealth" then
            self:UpdateHealth()
        elseif attribute == "IsPvPEnabled" then
            self:UpdatePVPStatus()
        elseif attribute == "Level" then
            self:UpdateLevel()
        end
    end))
    
    -- Listen for level up from playerData if available
    if self._playerData and self._playerData.OnLevelUp then
        self._janitor:Add(self._playerData.OnLevelUp:Connect(function()
            self:UpdateLevel()
        end))
    end
    
    -- Link janitor to character for automatic cleanup
    self._janitor:LinkToInstance(self.Character)
end

function PlayerBillboard:Destroy()
    self._janitor:Cleanup()
    
    if self.Billboard then
        self.Billboard:Destroy()
    end
    
    self.Character = nil :: any
    self.Billboard = nil :: any
    self._playerData = nil
end

return PlayerBillboard

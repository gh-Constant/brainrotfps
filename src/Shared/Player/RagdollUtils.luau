--!strict
--[[
    RagdollUtils
    Utility module for enabling/disabling ragdoll physics on characters.
    
    Works on both client and server. Ragdolling disables the humanoid's
    motor joints and lets physics take over.
]]

local RagdollUtils = {}

-- Store original motor6D states for restoration
local ragdollStates: {[Model]: {[Motor6D]: boolean}} = {}

--[[
    Gets all Motor6D joints in a character.
    
    @param character - The character model
    @return {Motor6D} - Array of Motor6D instances
]]
local function getMotors(character: Model): {Motor6D}
    local motors: {Motor6D} = {}
    
    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:IsA("Motor6D") then
            table.insert(motors, descendant)
        end
    end
    
    return motors
end

--[[
    Creates a BallSocketConstraint to replace a Motor6D during ragdoll.
    
    @param motor - The Motor6D to create a constraint for
    @return BallSocketConstraint - The created constraint
]]
local function createRagdollConstraint(motor: Motor6D): BallSocketConstraint
    local part0 = motor.Part0
    local part1 = motor.Part1
    
    if not part0 or not part1 then
        error("Motor6D has nil Part0 or Part1")
    end
    
    -- Create attachments
    local attachment0 = Instance.new("Attachment")
    attachment0.Name = "RagdollAttachment0"
    attachment0.CFrame = motor.C0
    attachment0.Parent = part0
    
    local attachment1 = Instance.new("Attachment")
    attachment1.Name = "RagdollAttachment1"
    attachment1.CFrame = motor.C1
    attachment1.Parent = part1
    
    -- Create ball socket constraint
    local constraint = Instance.new("BallSocketConstraint")
    constraint.Name = "RagdollConstraint"
    constraint.Attachment0 = attachment0
    constraint.Attachment1 = attachment1
    constraint.LimitsEnabled = true
    constraint.TwistLimitsEnabled = true
    constraint.UpperAngle = 45
    constraint.TwistLowerAngle = -45
    constraint.TwistUpperAngle = 45
    constraint.Parent = part0
    
    return constraint
end

--[[
    Removes ragdoll constraints from a character.
    
    @param character - The character model
]]
local function removeRagdollConstraints(character: Model)
    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant.Name == "RagdollConstraint" or 
           descendant.Name == "RagdollAttachment0" or 
           descendant.Name == "RagdollAttachment1" then
            descendant:Destroy()
        end
    end
end

--[[
    Enables ragdoll physics on a character.
    
    @param character - The character model to ragdoll
    @param preserveVelocity - Optional, whether to keep current velocity (default: true)
]]
function RagdollUtils.EnableRagdoll(character: Model, preserveVelocity: boolean?)
    if preserveVelocity == nil then
        preserveVelocity = true
    end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    
    if not humanoid then
        warn("[RagdollUtils] No Humanoid found in character")
        return
    end
    
    -- Store current velocity if needed
    local velocity: Vector3 = Vector3.zero
    if preserveVelocity and rootPart then
        velocity = rootPart.AssemblyLinearVelocity
    end
    
    -- Disable humanoid states that interfere with ragdoll
    humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
    humanoid:ChangeState(Enum.HumanoidStateType.Physics)
    
    -- Store motor states and disable them
    local motors = getMotors(character)
    ragdollStates[character] = {}
    
    for _, motor in ipairs(motors) do
        -- Skip the root joint (keeps character together)
        if motor.Name ~= "Root" then
            ragdollStates[character][motor] = motor.Enabled
            
            -- Create constraint before disabling motor
            createRagdollConstraint(motor)
            motor.Enabled = false
        end
    end
    
    -- Apply preserved velocity
    if preserveVelocity and rootPart then
        rootPart.AssemblyLinearVelocity = velocity
    end
    
    -- Make parts non-collidable with each other to prevent jittering
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
            part.CanCollide = true
        end
    end
    
    print("[RagdollUtils] Ragdoll enabled for", character.Name)
end

--[[
    Disables ragdoll physics and restores normal character control.
    
    @param character - The character model to unragdoll
]]
function RagdollUtils.DisableRagdoll(character: Model)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    
    if not humanoid then
        warn("[RagdollUtils] No Humanoid found in character")
        return
    end
    
    -- Remove ragdoll constraints
    removeRagdollConstraints(character)
    
    -- Restore motor states
    if ragdollStates[character] then
        for motor, wasEnabled in pairs(ragdollStates[character]) do
            if motor and motor.Parent then
                motor.Enabled = wasEnabled
            end
        end
        ragdollStates[character] = nil
    else
        -- If no stored state, just re-enable all motors
        local motors = getMotors(character)
        for _, motor in ipairs(motors) do
            motor.Enabled = true
        end
    end
    
    -- Re-enable humanoid states
    humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
    humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
    
    print("[RagdollUtils] Ragdoll disabled for", character.Name)
end

--[[
    Checks if a character is currently ragdolled.
    
    @param character - The character model to check
    @return boolean - True if ragdolled
]]
function RagdollUtils.IsRagdolled(character: Model): boolean
    return ragdollStates[character] ~= nil
end

--[[
    Toggles ragdoll state on a character.
    
    @param character - The character model
    @param preserveVelocity - Optional, whether to keep velocity when enabling
]]
function RagdollUtils.ToggleRagdoll(character: Model, preserveVelocity: boolean?)
    if RagdollUtils.IsRagdolled(character) then
        RagdollUtils.DisableRagdoll(character)
    else
        RagdollUtils.EnableRagdoll(character, preserveVelocity)
    end
end

--[[
    Applies an impulse force to a ragdolled character.
    
    @param character - The character model
    @param force - The force vector to apply
    @param position - Optional world position to apply force at (default: root part)
]]
function RagdollUtils.ApplyImpulse(character: Model, force: Vector3, position: Vector3?)
    local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
    
    if not rootPart then
        warn("[RagdollUtils] No HumanoidRootPart found")
        return
    end
    
    if position then
        rootPart:ApplyImpulseAtPosition(force, position)
    else
        rootPart:ApplyImpulse(force)
    end
end

--[[
    Sets up automatic ragdoll on death for a character.
    
    @param character - The character model
    @param duration - Optional duration before auto-unragdoll (nil = permanent until respawn)
]]
function RagdollUtils.SetupDeathRagdoll(character: Model, duration: number?)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    
    if not humanoid then
        warn("[RagdollUtils] No Humanoid found in character")
        return
    end
    
    humanoid.Died:Connect(function()
        RagdollUtils.EnableRagdoll(character, true)
        
        if duration then
            task.delay(duration, function()
                if character and character.Parent then
                    RagdollUtils.DisableRagdoll(character)
                end
            end)
        end
    end)
end

--[[
    Cleans up ragdoll state for a character (call when character is removed).
    
    @param character - The character model
]]
function RagdollUtils.Cleanup(character: Model)
    ragdollStates[character] = nil
end

return RagdollUtils

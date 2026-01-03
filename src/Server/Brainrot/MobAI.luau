local Players = game:GetService("Players")
local BrainrotAnimations = game.ReplicatedStorage:WaitForChild("BrainrotAnimations")

local MobAI = {}
MobAI.__index = MobAI



function MobAI.new(model)
	local h = model:FindFirstChildWhichIsA("Humanoid")
	local p = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if not h or not p then return nil end

	local self = setmetatable({
		Model = model,
		Humanoid = h,
		PrimaryPart = p,
		_isActive = false,
	}, MobAI)

	return self
end

local function getClosestPlayer(position)
	local closestDist = math.huge
	local closestPlayer = nil
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character and player.Character.PrimaryPart then
			local dist = (player.Character.PrimaryPart.Position - position).Magnitude
			if dist < closestDist then
				closestDist = dist
				closestPlayer = player
			end
		end
	end
	return closestPlayer
end

function MobAI:Start()
	if self._isActive then return end
	self._isActive = true

	local animFolder = BrainrotAnimations:FindFirstChild(self.Model.Name)
	if animFolder then
		local idleAnim = animFolder:FindFirstChild("Idle")
		if idleAnim and idleAnim:IsA("Animation") then
			self._animTrack = self.Humanoid:LoadAnimation(idleAnim)
			self._animTrack:Play()
			self._animTrack:AdjustSpeed(1)
		end
	end

	-- IKControl Setup
	local animator = self.Humanoid:FindFirstChildWhichIsA("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = self.Humanoid
	end

	local ikControl = Instance.new("IKControl")
	ikControl.Name = "LookAtIK"
	ikControl.Type = Enum.IKControlType.LookAt
	ikControl.SmoothTime = 0.2
	
	-- Determine chain (R6 vs R15 vs Custom)
	local head = self.Model:FindFirstChild("Head")
	local torso = self.Model:FindFirstChild("UpperTorso") or self.Model:FindFirstChild("Torso")
	
	if head and torso then
		ikControl.EndEffector = head
		ikControl.ChainRoot = torso
		ikControl.Parent = self.Humanoid
		self._ikControl = ikControl
	else
		-- Fallback or warning if rig is non-standard
		ikControl:Destroy()
	end

	self._heartbeat = game:GetService("RunService").Heartbeat:Connect(function(deltaTime)
		if not self._isActive or not self.Model.Parent then return end

		-- Update Target
		if self._ikControl then
			local targetPlayer = getClosestPlayer(self.PrimaryPart.Position)
			if targetPlayer and targetPlayer.Character then
				local targetPart = targetPlayer.Character:FindFirstChild("Head") or targetPlayer.Character.PrimaryPart
				self._ikControl.Target = targetPart
			else
				self._ikControl.Target = nil
			end
		end
	end)
end


function MobAI:Stop()
	if not self._isActive then return end
	self._isActive = false
	if self._heartbeat then
		self._heartbeat:Disconnect()
		self._heartbeat = nil
	end
	
	if self._ikControl then
		self._ikControl:Destroy()
		self._ikControl = nil
	end
	
	if self._animTrack then
		self._animTrack:Stop()
		self._animTrack = nil
	end
end

function MobAI:Destroy()
	self:Stop()
	self.Model:Destroy()
end

return MobAI

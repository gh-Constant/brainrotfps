local Players = game:GetService("Players")
local BrainrotAnimations = game.ReplicatedStorage:WaitForChild("BrainrotAnimations")

local MobAI = {}
MobAI.__index = MobAI

local ROTATE_SPEED = 10

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

	self._heartbeat = game:GetService("RunService").Heartbeat:Connect(function(deltaTime)
		if not self._isActive or not self.Model.Parent then return end

		local targetPlayer = getClosestPlayer(self.PrimaryPart.Position)
		if targetPlayer and targetPlayer.Character and targetPlayer.Character.PrimaryPart then
			local targetPos = targetPlayer.Character.PrimaryPart.Position
			local currentCFrame = self.PrimaryPart.CFrame
			local lookAt = CFrame.new(currentCFrame.Position, Vector3.new(targetPos.X, currentCFrame.Position.Y, targetPos.Z))
			self.PrimaryPart.CFrame = currentCFrame:Lerp(lookAt, ROTATE_SPEED * deltaTime)
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
end

function MobAI:Destroy()
	self:Stop()
	self.Model:Destroy()
end

return MobAI

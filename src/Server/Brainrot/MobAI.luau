--!optimize 2
--[[
	MobAI.luau - Simple mob wandering AI
	- Model with Humanoid, PrimaryPart
	- Model.Animations.Walk, Model.Animations.Idle
]]

local MobAI = {}
MobAI.__index = MobAI

-- Configuration
local WANDER_RANGE = 50
local WANDER_WAIT_MIN = 2
local WANDER_WAIT_MAX = 5

function MobAI.new(model)
	local humanoid = model:FindFirstChildWhichIsA("Humanoid")
	local primaryPart = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	
	if not humanoid or not primaryPart then
		return nil
	end
	
	local self = setmetatable({
		Model = model,
		Humanoid = humanoid,
		PrimaryPart = primaryPart,
		WalkAnim = nil,
		IdleAnim = nil,
		_spawnPos = primaryPart.Position,
		_thread = nil,
		_isActive = false,
		_currentAnim = "Idle",
		_name = model.Name,
	}, MobAI)
	
	-- Load animations
	local animFolder = model:FindFirstChild("Animations")
	if animFolder then
		local animator = humanoid:FindFirstChildWhichIsA("Animator") or Instance.new("Animator", humanoid)
		
		local walkAnim = animFolder:FindFirstChild("Walk")
		if walkAnim and walkAnim:IsA("Animation") then
			self.WalkAnim = animator:LoadAnimation(walkAnim)
			self.WalkAnim.Looped = true
		end
		
		local idleAnim = animFolder:FindFirstChild("Idle")
		if idleAnim and idleAnim:IsA("Animation") then
			self.IdleAnim = animator:LoadAnimation(idleAnim)
			self.IdleAnim.Looped = true
		end
	end
	
	return self
end

-- Get random wander point (uses spawn Y level)
function MobAI:_getWanderPoint(): Vector3?
	local angle = math.random() * math.pi * 2
	local dist = math.random() * WANDER_RANGE
	return self._spawnPos + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
end

-- Play animation
function MobAI:_playAnim(anim: string)
	if self._currentAnim == anim then return end
	self._currentAnim = anim
	
	if anim == "Walk" then
		if self.IdleAnim then self.IdleAnim:Stop() end
		if self.WalkAnim then self.WalkAnim:Play() end
	else
		if self.WalkAnim then self.WalkAnim:Stop() end
		if self.IdleAnim then self.IdleAnim:Play() end
	end
end

-- Move to destination
function MobAI:_moveTo(dest: Vector3): boolean
	if not self._isActive then 
		return false 
	end
	
	self:_playAnim("Walk")
	self.Humanoid:MoveTo(dest)
	
	local finished = false
	local reached = false
	
	local conn = self.Humanoid.MoveToFinished:Connect(function(r)
		finished = true
		reached = r
	end)
	
	-- Poll for activity
	while not finished and self._isActive do
		task.wait(0.1)
	end
	
	conn:Disconnect()
	self:_playAnim("Idle")
	return reached
end

-- Start AI
function MobAI:Start()
	if self._isActive then return end
	self._isActive = true
	
	if self.IdleAnim then self.IdleAnim:Play() end
	
	-- Main loop
	self._thread = task.spawn(function()
		while self._isActive and self.Model.Parent do
			local dest = self:_getWanderPoint()
			self:_moveTo(dest)
			-- Wait at destination
			if self._isActive then
				local waitTime = WANDER_WAIT_MIN + math.random() * (WANDER_WAIT_MAX - WANDER_WAIT_MIN)
				task.wait(waitTime)
			end
		end
	end)
end

-- Stop AI
function MobAI:Stop()
	if not self._isActive then return end
	self._isActive = false
	
	if self._thread then
		task.cancel(self._thread)
		self._thread = nil
	end
	
	if self.WalkAnim and self.WalkAnim.IsPlaying then self.WalkAnim:Stop() end
	if self.IdleAnim and self.IdleAnim.IsPlaying then self.IdleAnim:Stop() end
	
	self.Humanoid:MoveTo(self.PrimaryPart.Position)
end

-- Destroy AI
function MobAI:Destroy()
	self:Stop()
	self.WalkAnim = nil
	self.IdleAnim = nil
end

return MobAI

--!strict
--[[
    SystemLoader - Manages independent client system initialization
    Tracks initialization state of each system and provides signals for loading screen integration.
]]

local Signal = require(game:GetService("ReplicatedStorage").Rojo.Packages.signal)

export type System = {
    Name: string,
    Init: (context: any) -> (),
    Priority: number?, -- Optional: lower = init first
}

export type SystemLoaderImpl = {
    __index: SystemLoaderImpl,
    new: () -> SystemLoader,
    RegisterSystem: (self: SystemLoader, system: System) -> (),
    InitializeAll: (self: SystemLoader, context: any) -> (),
    GetProgress: (self: SystemLoader) -> (number, number),
    IsComplete: (self: SystemLoader) -> boolean,
}

export type SystemLoader = typeof(setmetatable({} :: {
    _systems: { System },
    _completed: { [string]: boolean },
    _completedCount: number,
    _totalCount: number,
    _isInitializing: boolean,
    OnSystemLoaded: typeof(Signal.new()),
    OnAllComplete: typeof(Signal.new()),
}, {} :: SystemLoaderImpl))

local SystemLoader: SystemLoaderImpl = {} :: SystemLoaderImpl
SystemLoader.__index = SystemLoader

--[[
    Creates a new SystemLoader instance.
]]
function SystemLoader.new(): SystemLoader
    local self = setmetatable({
        _systems = {},
        _completed = {},
        _completedCount = 0,
        _totalCount = 0,
        _isInitializing = false,
        OnSystemLoaded = Signal.new(),
        OnAllComplete = Signal.new(),
    }, SystemLoader)
    
    return self
end

--[[
    Registers a system to be initialized.
    @param system - System definition with Name, Init function, and optional Priority
]]
function SystemLoader:RegisterSystem(system: System)
    if self._isInitializing then
        warn("[SystemLoader] Cannot register systems while initializing!")
        return
    end
    
    table.insert(self._systems, system)
end

--[[
    Sorts systems by priority and initializes them all.
    Each system runs in its own task.spawn for independent loading.
    @param context - ClientContext to pass to each system's Init function
]]
function SystemLoader:InitializeAll(context: any)
    if self._isInitializing then
        warn("[SystemLoader] Already initializing!")
        return
    end
    
    self._isInitializing = true
    self._totalCount = #self._systems
    self._completedCount = 0
    self._completed = {}
    
    -- Sort by priority (lower = first)
    table.sort(self._systems, function(a, b)
        local priorityA = a.Priority or 100
        local priorityB = b.Priority or 100
        return priorityA < priorityB
    end)
    
    print("[SystemLoader] Initializing", self._totalCount, "systems...")
    
    -- Initialize each system independently
    for _, system in self._systems do
        task.spawn(function()
            local success, err = pcall(function()
                system.Init(context)
            end)
            
            if success then
                print("[SystemLoader] ✓", system.Name, "initialized")
            else
                warn("[SystemLoader] ✗", system.Name, "failed:", err)
            end
            
            -- Mark as complete regardless of success
            self._completed[system.Name] = true
            self._completedCount += 1
            
            -- Fire signal for this system
            self.OnSystemLoaded:Fire(system.Name, success)
            
            -- Check if all complete
            if self._completedCount >= self._totalCount then
                print("[SystemLoader] All systems initialized!")
                self.OnAllComplete:Fire()
            end
        end)
    end
end

--[[
    Returns the current loading progress.
    @return completed - Number of systems that have finished initializing
    @return total - Total number of systems
]]
function SystemLoader:GetProgress(): (number, number)
    return self._completedCount, self._totalCount
end

--[[
    Returns whether all systems have finished initializing.
]]
function SystemLoader:IsComplete(): boolean
    return self._completedCount >= self._totalCount and self._totalCount > 0
end

return SystemLoader

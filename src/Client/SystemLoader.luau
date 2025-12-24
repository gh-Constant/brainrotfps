--!strict
--[[
    SystemLoader - Manages independent client system initialization
    Tracks initialization state of each system and provides signals for loading screen integration.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Packages = Rojo:WaitForChild("Packages")
local Signal = require(Packages:WaitForChild("signal"))
local Promise = require(Packages:WaitForChild("promise"))

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
    Sorts systems by priority and initializes them all using Promise.
    Each system runs in parallel with Promise.allSettled for independent loading.
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
    
    print("[SystemLoader] Initializing", self._totalCount, "systems with Promise...")
    
    -- Create a Promise for each system
    local promises = {}
    for _, system in self._systems do
        local promise = Promise.new(function(resolve, reject)
            local success, err = pcall(function()
                system.Init(context)
            end)
            
            if success then
                print("[SystemLoader] ✓", system.Name, "initialized")
                resolve(system.Name)
            else
                warn("[SystemLoader] ✗", system.Name, "failed:", err)
                reject(err)
            end
        end):finally(function()
            -- Mark as complete regardless of success/failure
            self._completed[system.Name] = true
            self._completedCount += 1
            self.OnSystemLoaded:Fire(system.Name, self._completed[system.Name])
        end)
        
        table.insert(promises, promise)
    end
    
    -- Wait for all systems using allSettled (doesn't fail if one rejects)
    Promise.allSettled(promises):andThen(function()
        print("[SystemLoader] All systems initialized!")
        self.OnAllComplete:Fire()
    end)
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

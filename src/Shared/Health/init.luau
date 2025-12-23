--[[
    Health System
    
    Modules:
    - Health: Core health system with damage, healing, regeneration
    - PVPManager: Player vs Player damage validation
    - CombatManager: Combat state and timer management
    
    Usage:
    local Health = require(Shared.Health) -- Returns Health module directly
    -- Or access sub-modules directly:
    local PVPManager = require(Shared.Health.PVPManager)
    local CombatManager = require(Shared.Health.CombatManager)
]]

return require(script.Health)

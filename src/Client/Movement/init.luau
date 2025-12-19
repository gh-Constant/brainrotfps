--!strict
-- Movement module entry point
-- Exposes all movement-related classes

local Movement = {}

Movement.MovementController = require(script.MovementController)
Movement.MovementSettings = require(script.MovementSettings)
Movement.GroundCheck = require(script.GroundCheck)
Movement.SlideController = require(script.SlideController)

return Movement

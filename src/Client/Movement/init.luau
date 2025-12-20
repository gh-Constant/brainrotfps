--!strict

local Movement = {}

Movement.MovementController = require(script.MovementController)
Movement.MovementSettings = require(script.MovementSettings)
Movement.GroundCheck = require(script.GroundCheck)
Movement.SlideController = require(script.SlideController)
Movement.WallJump = require(script.WallJump)

return Movement

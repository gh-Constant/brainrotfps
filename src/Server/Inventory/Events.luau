--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rojo = ReplicatedStorage:WaitForChild("Rojo")
local Packages = Rojo:WaitForChild("Packages")

local Signal = require(Packages:WaitForChild("signal"))

local Events = {}

Events.OnItemAdded = Signal.new()
Events.OnItemRemoved = Signal.new()
Events.OnInventoryChanged = Signal.new()

return Events

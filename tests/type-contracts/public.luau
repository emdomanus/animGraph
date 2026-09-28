--!strict
-- selene: allow(incorrect_standard_library_use)
local AnimGraph = require("../../src")
type Layer = "body"
type State = "idle"
type Param = "speed"
type Clip = "idleClip"
type Controller = AnimGraph.AnimationController<Layer, State, Param, Clip, AnimGraph.RobloxLayerBackend>
local function check(controller: Controller, reader: AnimGraph.TimeReader)
	controller:setLayerWeight("body" :: Layer, 1)
	controller:setLayerTimeReader("body" :: Layer, reader)
	controller:setTrackPosition("track", { kind = "normalized", value = 0.5 } :: AnimGraph.AnimationPosition)
	controller:update(10)
	controller:destroy()
end
return check

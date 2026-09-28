--!strict
-- selene: allow(incorrect_standard_library_use)
local AnimGraph = require("../../src")
type Layer = "body"
type State = "idle"
type Param = "speed"
type Clip = "idleClip"
type Controller = AnimGraph.AnimationController<Layer, State, Param, Clip, AnimGraph.RobloxLayerBackend>
local function reject(controller: Controller)
	controller:setLayerWeight("unknownLayer", 1) -- EXPECT_ERROR
	controller:update("now") -- EXPECT_ERROR
	controller.update = controller.update -- EXPECT_ERROR
	local position: AnimGraph.AnimationPosition = { kind = "frames", value = 1 } -- EXPECT_ERROR
	local invalidReader = function(_time: number): number
		return 1
	end
	local reader: AnimGraph.TimeReader = invalidReader -- EXPECT_ERROR
	return position, reader
end
return reject

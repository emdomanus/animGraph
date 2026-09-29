--!strict
-- selene: allow(incorrect_standard_library_use)
local AnimGraph = require("../../src")
type Layer = "body"
type State = "idle"
type Param = "speed"
type Clip = "idleClip"

type Controller = AnimGraph.AnimationController<Layer, State, Param, Clip, AnimGraph.RobloxLayerBackend>
type DebugSnapshot = AnimGraph.AnimationControllerDebugSnapshot<Layer, State, Param, AnimGraph.RobloxLayerBackend>

local function createController(
	backend: AnimGraph.AnimationBackend<Layer, State, Clip, AnimGraph.RobloxLayerBackend>,
	reader: AnimGraph.TimeReader
): Controller
	local config: AnimGraph.AnimationControllerConfig<Layer, State, Clip, AnimGraph.RobloxLayerBackend> = {
		backend = backend,
		timeReader = reader,
	}
	local newController = AnimGraph.new :: (
		AnimGraph.AnimationControllerConfig<Layer, State, Clip, AnimGraph.RobloxLayerBackend>
	) -> Controller
	local controller: Controller = newController(config)
	return controller
end

local function check(controller: Controller, reader: AnimGraph.TimeReader)
	controller:setLayerWeight("body" :: Layer, 1)
	controller:setLayerTimeReader("body" :: Layer, reader)
	controller:setFloat("speed" :: Param, 1)
	controller:setTrackPosition("track", { kind = "normalized", value = 0.5 } :: AnimGraph.AnimationPosition)
	controller:update(10)
	local snapshot: DebugSnapshot = controller:getDebugSnapshot()
	local layer: Layer = snapshot.layers[1].id
	local state: State? = snapshot.layers[1].state
	local parameter: AnimGraph.ParameterValue = snapshot.parameters["speed" :: Param]
	local layerBackend: AnimGraph.RobloxLayerBackend? = snapshot.layers[1].layerBackend
	controller:destroy()
	return layer, state, parameter, layerBackend
end
return { createController = createController, check = check }

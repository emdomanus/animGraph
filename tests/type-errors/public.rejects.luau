--!strict
--!optimize 2
-- selene: allow(incorrect_standard_library_use)
local AnimGraph = require("../../src")
type Layer = "body"
type State = "idle"
type Param = "speed"
type Clip = "idleClip"

type Controller = AnimGraph.AnimationController<Layer, State, Param, Clip, AnimGraph.RobloxLayerBackend>
local function reject(
	controller: Controller,
	wrongMotion: AnimGraph.MotionNode<Layer, State, Param, "otherClip", AnimGraph.RobloxLayerBackend>
)
	controller:setLayerWeight("unknownLayer", 1) -- EXPECT_ERROR
	controller:setFloat("unknownParameter", 1) -- EXPECT_ERROR
	controller:play("body" :: Layer, wrongMotion) -- EXPECT_ERROR
	controller:setLayerBackend("body" :: Layer, "notBackendData") -- EXPECT_ERROR
	local snapshot: AnimGraph.AnimationControllerDebugSnapshot<Layer, State, Param, AnimGraph.RobloxLayerBackend> =
		controller:getDebugSnapshot()
	local wrongLayer: "unknownLayer" = snapshot.layers[1].id -- EXPECT_ERROR
	local wrongState: "unknownState" = snapshot.layers[1].state -- EXPECT_ERROR
	local wrongValue: Vector3 = snapshot.parameters["speed" :: Param] -- EXPECT_ERROR
	controller:onTrackMarker("track", "Cue", function(value)
		local wrongMarkerValue: number = value -- EXPECT_ERROR
		print(wrongMarkerValue)
	end)
	controller:onMarker("Cue", function(track, value)
		local wrongMarkerLayer: "other" = track:getLayer() -- EXPECT_ERROR
		local wrongMarkerClip: "otherClip" = track:getClip() -- EXPECT_ERROR
		track.getLayer = track.getLayer -- EXPECT_ERROR
		print(wrongMarkerLayer, wrongMarkerClip, value)
	end)
	controller:update("now") -- EXPECT_ERROR
	controller.update = controller.update -- EXPECT_ERROR
	local position: AnimGraph.AnimationPosition = { kind = "frames", value = 1 } -- EXPECT_ERROR
	local invalidReader = function(_time: number): number
		return 1
	end
	local reader: AnimGraph.TimeReader = invalidReader -- EXPECT_ERROR
	return position, reader, wrongLayer, wrongState, wrongValue
end
local function rejectDefaults(
	backend: AnimGraph.AnimationBackend<Layer, State, Clip, AnimGraph.RobloxLayerBackend>,
	reader: AnimGraph.TimeReader
)
	local config: AnimGraph.AnimationControllerConfig<Layer, State, Param, Clip, AnimGraph.RobloxLayerBackend> = {
		backend = backend,
		timeReader = reader,
		parameterDefaults = { speed = 0 },
	}
	local controller = AnimGraph.new(config)
	controller:setFloat("unknownParameter", 1) -- EXPECT_ERROR
	local defaults = config.parameterDefaults
	assert(defaults ~= nil, "defaults are present in this fixture")
	defaults["speed" :: Param] = Vector3.new() -- EXPECT_ERROR
	defaults["unknownParameter"] = 0 -- EXPECT_ERROR
end

return { reject = reject, rejectDefaults = rejectDefaults }

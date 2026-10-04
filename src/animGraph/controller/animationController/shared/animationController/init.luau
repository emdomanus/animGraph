--!strict
--!optimize 2
--!native

local AnimationPosition = require(script.Parent.Parent.Parent.Parent.utils.animationPosition.shared.animationPosition)
local EventBus = require(script.eventBus)
local LayerRuntime = require(script.Parent.Parent.Parent.Parent.runtime.layerRuntime.shared.layerRuntime)
local ParameterStore = require(script.parameterStore)
local RequestValidation = require(script.Parent.Parent.Parent.Parent.utils.requestValidation.shared.requestValidation)
local Types =
	require(script.Parent.Parent.Parent.Parent.types.controller.animationController.shared.animationController)
local TrackMarkerSourceTypes =
	require(script.Parent.Parent.Parent.Parent.types.ports.backends.animationPlayback.shared.trackMarkerSource)
local DefTypes = require(script.Parent.Parent.Parent.Parent.types.def.animation.shared.animation)
local EventBusTypes =
	require(script.Parent.Parent.Parent.Parent.types.controller.animationController.shared.animationController.eventBus)
local LayerRuntimeTypes = require(script.Parent.Parent.Parent.Parent.types.runtime.layerRuntime.shared.layerRuntime)
local MotionNodeTypes = require(script.Parent.Parent.Parent.Parent.types.motions.motionNode.shared.motionNode)
local ParameterStoreTypes = require(
	script.Parent.Parent.Parent.Parent.types.controller.animationController.shared.animationController.parameterStore
)

type AnimationControllerConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT> = Types.AnimationControllerConfig<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
>
type AnimationControllerDebugSnapshot<LayerT, StateT, ParamT, LayerBackendT> = Types.AnimationControllerDebugSnapshot<
	LayerT,
	StateT,
	ParamT,
	LayerBackendT
>
type AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT> = Types.AnimationController<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
>
type AnimationControllerImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT> = Types.AnimationControllerImpl<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
>

type TrackMarkerSource<LayerT, StateT, ClipT> = TrackMarkerSourceTypes.TrackMarkerSource<LayerT, StateT, ClipT>
type GraphIntentCommand<LayerT, StateT, ParamT, ClipT, LayerBackendT> = Types.GraphIntentCommand<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
>

type PendingBackendStop<LayerT> = Types.PendingBackendStop<LayerT>

local AnimationController = {}
AnimationController.__index = AnimationController

local function assertFiniteNumber(value: number, name: string): number
	assert(typeof(value) == "number", name .. " must be a number")
	assert(value == value and value > -math.huge and value < math.huge, name .. " must be finite")
	return value
end

local function assertNonNegative(value: number, name: string): number
	assertFiniteNumber(value, name)
	assert(value >= 0, name .. " must be non-negative")
	return value
end

local function assertReader(reader: DefTypes.TimeReader?, name: string): ()
	if reader ~= nil then
		assert(typeof(reader) == "function", name .. " must be a function")
	end
end

local function assertRequiredReader(reader: DefTypes.TimeReader, name: string): DefTypes.TimeReader
	assert(typeof(reader) == "function", name .. " must be a function")
	return reader
end

local function copyPosition(position: DefTypes.AnimationPosition?): DefTypes.AnimationPosition?
	if position == nil then
		return nil
	end

	if position.kind == "seconds" then
		return { kind = "seconds", value = position.value }
	end

	return { kind = "normalized", value = position.value }
end

local function copyPlayOptions<StateT, LayerBackendT>(
	options: LayerRuntimeTypes.LayerPlayOptions<StateT, LayerBackendT>?
): LayerRuntimeTypes.LayerPlayOptions<StateT, LayerBackendT>?
	if options == nil then
		return nil
	end

	return {
		state = options.state,
		fadeTime = options.fadeTime,
		fadeIn = options.fadeIn,
		timeReader = options.timeReader,
		trackKey = options.trackKey,
		weight = options.weight,
		speed = options.speed,
		looped = options.looped,
		logicalPriority = options.logicalPriority,
		layerBackend = options.layerBackend,
		initialPosition = copyPosition(options.initialPosition),
		forceRestart = options.forceRestart,
	}
end

local function assertPlayOptions<StateT, LayerBackendT>(options: LayerRuntimeTypes.LayerPlayOptions<StateT, LayerBackendT>?): ()
	if options == nil then
		return
	end
	if options.initialPosition ~= nil then
		AnimationPosition.assertValid(options.initialPosition)
	end
	assertReader(options.timeReader, "timeReader")
	if options.fadeTime ~= nil then
		assertNonNegative(options.fadeTime, "fadeTime")
	end
	if options.fadeIn ~= nil then
		assertNonNegative(options.fadeIn, "fadeIn")
	end
	if options.weight ~= nil then
		assertFiniteNumber(options.weight, "weight")
	end
	if options.speed ~= nil then
		assertFiniteNumber(options.speed, "speed")
	end
	if options.logicalPriority ~= nil then
		assertFiniteNumber(options.logicalPriority, "logicalPriority")
	end
end

local function updateWasInvalidated<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>,
	lifecycleEpoch: number
): boolean
	return self._destroyed or self._lifecycleEpoch ~= lifecycleEpoch
end

local function readTimeSample(
	reader: DefTypes.TimeReader,
	sampleTime: number,
	updateInvalidated: () -> boolean
): DefTypes.TimeSample?
	local sample = reader(sampleTime)
	if updateInvalidated() then
		return nil
	end
	assert(typeof(sample) == "table", "timeReader result must be a table")
	return {
		position = assertFiniteNumber(sample.position, "timeReader position"),
		rate = assertFiniteNumber(sample.rate, "timeReader rate"),
	}
end

function AnimationController.new<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	config: AnimationControllerConfig<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>
): AnimationController<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
>
	assertRequiredReader(config.timeReader, "timeReader")

	local self: AnimationControllerImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
		setmetatable({}, AnimationController) :: any

	self._backend = config.backend
	self._timeReader = config.timeReader
	self._lastSampleTime = nil
	self._pendingCommands = {}
	self._layers = {}
	self._layerOrder = {}
	self._parameters = ParameterStore.new(config.parameterDefaults)
	self._eventBus = EventBus.new() :: any
	self._readParameter = function(parameter: ParamT): ParameterStoreTypes.ParameterValue?
		return self._parameters:get(parameter)
	end
	self._consumeTrigger = function(parameter: ParamT): boolean
		return self._parameters:consumeTrigger(parameter)
	end
	self._emitEvent = function(event)
		self._eventBus:emit(event)
	end
	self._lifecycleEpoch = 0
	self._destroyed = false
	self._releaseBackendCompletion = nil

	if config.layers ~= nil then
		for _, layer in config.layers do
			self:addLayer(layer)
		end
	end

	self._releaseBackendCompletion = self._backend:bindToTrackCompleted(function(event)
		self._eventBus:emit(event)
	end)

	return self
end

function AnimationController.addLayer<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>,
	definition: LayerRuntimeTypes.LayerDefinition<
		LayerT,
		LayerBackendT
	>
): ()
	assert(not self._destroyed, "AnimationController is destroyed")
	assert(self._layers[definition.id] == nil, "layer already exists")

	self._layers[definition.id] = LayerRuntime.new(definition) :: any
	self._layerOrder[#self._layerOrder + 1] = definition.id
end

function AnimationController.hasLayer<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>,
	layer: LayerT
): boolean
	return self._layers[layer] ~= nil
end

local function requireLayer<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>,
	layer: LayerT
): LayerRuntimeTypes.LayerRuntimeImpl<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
>
	local layerRuntime = self._layers[layer]
	assert(layerRuntime ~= nil, "unknown layer")
	return layerRuntime
end

function AnimationController.play<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>,
	layer: LayerT,
	motion: MotionNodeTypes.MotionNode<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>,
	options: LayerRuntimeTypes.LayerPlayOptions<
		StateT,
		LayerBackendT
	>?
): ()
	if self._destroyed then
		return
	end
	requireLayer(self, layer)
	assertPlayOptions(options)

	self._pendingCommands[#self._pendingCommands + 1] = {
		kind = "play",
		layer = layer,
		motion = motion,
		options = copyPlayOptions(options),
	}
end

function AnimationController.setTrackPosition<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>,
	trackKey: string,
	position: DefTypes.AnimationPosition
): boolean
	AnimationPosition.assertValid(position)
	if self._destroyed then
		return false
	end

	return self._backend:setTrackPosition(trackKey, position)
end

function AnimationController.offsetTrackPosition<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>,
	trackKey: string,
	deltaSeconds: number
): boolean
	AnimationPosition.assertFiniteSeconds(deltaSeconds, "deltaSeconds")
	if self._destroyed then
		return false
	end

	return self._backend:offsetTrackPosition(trackKey, deltaSeconds)
end

function AnimationController.stopLayer<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>,
	layer: LayerT,
	fadeTime: number?
): ()
	if self._destroyed then
		return
	end

	local layerRuntime = self._layers[layer]
	if layerRuntime == nil then
		return
	end
	local resolvedFadeTime = assertNonNegative(fadeTime or layerRuntime:getDefaultFadeOut(), "fadeTime")
	self._pendingCommands[#self._pendingCommands + 1] = {
		kind = "stop",
		layer = layer,
		fadeTime = resolvedFadeTime,
	}
end

function AnimationController.setLayerWeight<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>,
	layer: LayerT,
	weight: number
): ()
	if self._destroyed then
		return
	end
	requireLayer(self, layer)
	self._pendingCommands[#self._pendingCommands + 1] = {
		kind = "setLayerWeight",
		layer = layer,
		weight = assertNonNegative(weight, "weight"),
	}
end

function AnimationController.getLayerWeight<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>,
	layer: LayerT
): number?
	local layerRuntime = self._layers[layer]
	return if layerRuntime ~= nil then layerRuntime:getWeight() else nil
end

function AnimationController.setLayerSpeed<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>,
	layer: LayerT,
	speed: number
): ()
	if self._destroyed then
		return
	end
	requireLayer(self, layer)
	self._pendingCommands[#self._pendingCommands + 1] = {
		kind = "setLayerSpeed",
		layer = layer,
		speed = assertFiniteNumber(speed, "speed"),
	}
end

function AnimationController.getLayerSpeed<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>,
	layer: LayerT
): number?
	local layerRuntime = self._layers[layer]
	return if layerRuntime ~= nil then layerRuntime:getSpeed() else nil
end

function AnimationController.setLayerLogicalPriority<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>,
	layer: LayerT,
	logicalPriority: number
): ()
	if self._destroyed then
		return
	end
	requireLayer(self, layer)
	self._pendingCommands[#self._pendingCommands + 1] = {
		kind = "setLayerLogicalPriority",
		layer = layer,
		logicalPriority = assertFiniteNumber(logicalPriority, "logicalPriority"),
	}
end

function AnimationController.getLayerLogicalPriority<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>,
	layer: LayerT
): number?
	local layerRuntime = self._layers[layer]
	return if layerRuntime ~= nil then layerRuntime:getLogicalPriority() else nil
end

function AnimationController.setLayerBackend<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>,
	layer: LayerT,
	layerBackend: LayerBackendT?
): ()
	if self._destroyed then
		return
	end
	requireLayer(self, layer)
	self._pendingCommands[#self._pendingCommands + 1] = {
		kind = "setLayerBackend" :: "setLayerBackend",
		layer = layer,
		layerBackend = layerBackend,
	}
end

function AnimationController.getLayerBackend<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>,
	layer: LayerT
): LayerBackendT?
	local layerRuntime = self._layers[layer]
	return if layerRuntime ~= nil then layerRuntime:getLayerBackend() else nil
end

function AnimationController.setDefaultTimeReader<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>,
	reader: DefTypes.TimeReader
): ()
	if self._destroyed then
		return
	end
	assertRequiredReader(reader, "timeReader")
	self._pendingCommands[#self._pendingCommands + 1] = {
		kind = "setDefaultTimeReader",
		reader = reader,
	}
end

function AnimationController.setLayerTimeReader<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>,
	layer: LayerT,
	reader: DefTypes.TimeReader?
): ()
	if self._destroyed then
		return
	end
	requireLayer(self, layer)
	assertReader(reader, "timeReader")
	self._pendingCommands[#self._pendingCommands + 1] = {
		kind = "setLayerTimeReader" :: "setLayerTimeReader",
		layer = layer,
		reader = reader,
	}
end

function AnimationController.setActivePlayTimeReader<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>,
	layer: LayerT,
	reader: DefTypes.TimeReader?
): ()
	if self._destroyed then
		return
	end
	requireLayer(self, layer)
	assertReader(reader, "timeReader")
	self._pendingCommands[#self._pendingCommands + 1] = {
		kind = "setActivePlayTimeReader" :: "setActivePlayTimeReader",
		layer = layer,
		reader = reader,
	}
end

function AnimationController.setParameter<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>,
	parameter: ParamT,
	value: ParameterStoreTypes.ParameterValue
): ()
	if self._destroyed then
		return
	end
	self._pendingCommands[#self._pendingCommands + 1] = {
		kind = "setParameter",
		parameter = parameter,
		value = value,
	}
end

function AnimationController.getParameter<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>,
	parameter: ParamT
): ParameterStoreTypes.ParameterValue?
	return self._parameters:get(parameter)
end

function AnimationController.setFloat<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>,
	parameter: ParamT,
	value: number
): ()
	self:setParameter(parameter, value)
end

function AnimationController.getFloat<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>,
	parameter: ParamT,
	fallback: number?
): number
	return self._parameters:getFloat(parameter, fallback)
end

function AnimationController.setBool<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>,
	parameter: ParamT,
	value: boolean
): ()
	self:setParameter(parameter, value)
end

function AnimationController.getBool<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>,
	parameter: ParamT,
	fallback: boolean?
): boolean
	return self._parameters:getBool(parameter, fallback)
end

function AnimationController.setTrigger<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>,
	parameter: ParamT
): ()
	if self._destroyed then
		return
	end
	self._pendingCommands[#self._pendingCommands + 1] = {
		kind = "setTrigger",
		parameter = parameter,
	}
end

function AnimationController.consumeTrigger<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>,
	parameter: ParamT
): boolean
	return self._parameters:consumeTrigger(parameter)
end

function AnimationController.onMarker<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>,
	markerName: string,
	callback: (
		track: TrackMarkerSource<LayerT, StateT, ClipT>,
		value: string
	) -> ()
): DefTypes.Release
	assert(not self._destroyed, "cannot subscribe to markers on a destroyed controller")
	assert(self._backend:getCapabilities().trackMarkers, "backend does not support track markers")
	return self._backend:bindToMarker(markerName, callback)
end

function AnimationController.onTrackMarker<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>,
	trackKey: string,
	markerName: string,
	callback: (value: string) -> ()
): DefTypes.Release
	assert(not self._destroyed, "cannot subscribe to markers on a destroyed controller")
	assert(self._backend:getCapabilities().trackMarkers, "backend does not support track markers")
	return self._backend:bindToTrackMarker(trackKey, markerName, callback)
end

function AnimationController.on<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>,
	name: EventBusTypes.AnimationEventName,
	callback: EventBusTypes.AnimationEventCallback<
		LayerT,
		StateT
	>
): EventBusTypes.Release
	return self._eventBus:on(name, callback)
end

local function finalDefaultReader<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>,
	commands: {
		GraphIntentCommand<
			LayerT,
			StateT,
			ParamT,
			ClipT,
			LayerBackendT
		>
	},
	commandCount: number
): DefTypes.TimeReader
	local reader = self._timeReader
	for index = 1, commandCount do
		local command = commands[index]
		if command.kind == "setDefaultTimeReader" then
			reader = command.reader
		end
	end
	return reader
end

local function readLayerTimeSample<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	layer: LayerT,
	layerRuntime: LayerRuntimeTypes.LayerRuntimeImpl<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>,
	defaultReader: DefTypes.TimeReader,
	commands: {
		GraphIntentCommand<
			LayerT,
			StateT,
			ParamT,
			ClipT,
			LayerBackendT
		>
	},
	commandCount: number,
	sampleTime: number,
	samplesByReader: {
		[DefTypes.TimeReader]: DefTypes.TimeSample,
	},
	updateInvalidated: () -> boolean
): DefTypes.TimeSample?
	local playing = layerRuntime._playing
	local layerReader = layerRuntime._timeReader
	local playReader = layerRuntime._playTimeReader

	for index = 1, commandCount do
		local command = commands[index]
		if command.kind == "play" and command.layer == layer then
			playing = true
			playReader = if command.options ~= nil then command.options.timeReader else nil
		elseif command.kind == "stop" and command.layer == layer then
			playing = false
			playReader = nil
		elseif command.kind == "setLayerTimeReader" and command.layer == layer then
			layerReader = command.reader
		elseif command.kind == "setActivePlayTimeReader" and command.layer == layer then
			playReader = command.reader
		end
	end

	if not playing then
		return nil
	end

	local reader = playReader or layerReader or defaultReader
	local cachedSample: DefTypes.TimeSample? = samplesByReader[reader]
	local sample: DefTypes.TimeSample
	if cachedSample == nil then
		local readSample = readTimeSample(reader, sampleTime, updateInvalidated)
		if readSample == nil then
			return nil
		end
		samplesByReader[reader] = readSample
		sample = readSample
	else
		sample = cachedSample
	end

	return sample
end

local function commitCommands<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>,
	commands: {
		GraphIntentCommand<
			LayerT,
			StateT,
			ParamT,
			ClipT,
			LayerBackendT
		>
	},
	commandCount: number
): { PendingBackendStop<LayerT> }
	local backendStops: { PendingBackendStop<LayerT> } = {}
	for index = 1, commandCount do
		local command = commands[index]
		if command.kind == "play" then
			requireLayer(self, command.layer):play(command.motion, command.options)
		elseif command.kind == "stop" then
			requireLayer(self, command.layer):stop()
			backendStops[#backendStops + 1] = {
				layer = command.layer,
				fadeTime = command.fadeTime,
			}
		elseif command.kind == "setLayerWeight" then
			requireLayer(self, command.layer):setWeight(command.weight)
		elseif command.kind == "setLayerSpeed" then
			requireLayer(self, command.layer):setSpeed(command.speed)
		elseif command.kind == "setLayerLogicalPriority" then
			requireLayer(self, command.layer):setLogicalPriority(command.logicalPriority)
		elseif command.kind == "setLayerBackend" then
			requireLayer(self, command.layer):setLayerBackend(command.layerBackend)
		elseif command.kind == "setDefaultTimeReader" then
			self._timeReader = command.reader
		elseif command.kind == "setLayerTimeReader" then
			requireLayer(self, command.layer):setTimeReader(command.reader)
		elseif command.kind == "setActivePlayTimeReader" then
			requireLayer(self, command.layer):setActivePlayTimeReader(command.reader)
		elseif command.kind == "setParameter" then
			self._parameters:set(command.parameter, command.value)
		elseif command.kind == "setTrigger" then
			self._parameters:setTrigger(command.parameter)
		end
	end
	return backendStops
end

function AnimationController.update<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>,
	sampleTime: number
): ()
	if self._destroyed then
		return
	end

	assertFiniteNumber(sampleTime, "sampleTime")
	local lastSampleTime = self._lastSampleTime
	assert(lastSampleTime == nil or sampleTime >= lastSampleTime, "sampleTime moved backward")
	local lifecycleEpoch = self._lifecycleEpoch

	local pendingCommands = self._pendingCommands
	local commandCount = #pendingCommands
	-- Commands are append-only; a fixed prefix preserves the update snapshot without copying it.
	local commands = pendingCommands
	local defaultReader = finalDefaultReader(self, commands, commandCount)
	local samplesByReader: { [DefTypes.TimeReader]: DefTypes.TimeSample } = {}
	local samplesByLayer: { [LayerT]: DefTypes.TimeSample } = {}
	local updateInvalidated = function(): boolean
		return updateWasInvalidated(self, lifecycleEpoch)
	end

	for _, layer in self._layerOrder do
		local layerRuntime = self._layers[layer]
		if layerRuntime ~= nil then
			local sample = readLayerTimeSample(
				layer,
				layerRuntime,
				defaultReader,
				commands,
				commandCount,
				sampleTime,
				samplesByReader,
				updateInvalidated
			)
			if updateWasInvalidated(self, lifecycleEpoch) then
				return
			end
			if sample ~= nil then
				samplesByLayer[layer] = sample
			end
		end
	end

	local nextCommands: { GraphIntentCommand<LayerT, StateT, ParamT, ClipT, LayerBackendT> } = {}
	for index = commandCount + 1, #pendingCommands do
		nextCommands[#nextCommands + 1] = pendingCommands[index]
	end
	self._pendingCommands = nextCommands
	local backendStops = commitCommands(self, commands, commandCount)
	self._lastSampleTime = sampleTime

	for _, stop in backendStops do
		self._backend:stopLayer(stop.layer, stop.fadeTime)
		if updateWasInvalidated(self, lifecycleEpoch) then
			return
		end
	end

	local requests: { MotionNodeTypes.ClipRequest<LayerT, StateT, ClipT, LayerBackendT> } = {}

	for _, layer in self._layerOrder do
		local layerRuntime = self._layers[layer]
		local timeSample = samplesByLayer[layer]
		if layerRuntime ~= nil and timeSample ~= nil then
			local layerRequests =
				layerRuntime:evaluate(timeSample, self._readParameter, self._consumeTrigger, self._emitEvent)
			if updateWasInvalidated(self, lifecycleEpoch) then
				return
			end
			for _, request in layerRequests do
				requests[#requests + 1] = request
			end
		end
	end

	RequestValidation.validate(requests)
	if updateWasInvalidated(self, lifecycleEpoch) then
		return
	end
	self._backend:apply(sampleTime, requests)
end

function AnimationController.clear<LayerT, StateT, ParamT, ClipT, LayerBackendT>(self: AnimationControllerImpl<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
>): ()
	self._lifecycleEpoch += 1
	self._pendingCommands = {}
	for _, layerRuntime in self._layers do
		layerRuntime:stop()
	end

	self._parameters:clear()
	self._backend:clear()
end

function AnimationController.destroy<LayerT, StateT, ParamT, ClipT, LayerBackendT>(self: AnimationControllerImpl<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
>): ()
	if self._destroyed then
		return
	end

	self._destroyed = true
	local releaseBackendCompletion = self._releaseBackendCompletion
	self._releaseBackendCompletion = nil
	if releaseBackendCompletion ~= nil then
		releaseBackendCompletion()
	end
	self:clear()
	self._eventBus:clear()
	self._backend:destroy()
end

function AnimationController.getDebugSnapshot<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>
): AnimationControllerDebugSnapshot<
	LayerT,
	StateT,
	ParamT,
	LayerBackendT
>
	local layers: { LayerRuntimeTypes.LayerDebugSnapshot<LayerT, StateT, LayerBackendT> } = {}
	for _, layer in self._layerOrder do
		local layerRuntime = self._layers[layer]
		if layerRuntime ~= nil then
			layers[#layers + 1] = layerRuntime:getDebugSnapshot()
		end
	end

	return {
		parameters = self._parameters:getDebugSnapshot(),
		layers = layers,
		backend = self._backend:getDebugSnapshot(),
	}
end

return { new = AnimationController.new }

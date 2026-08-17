--!strict
--!optimize 2
--!native

local Types = require(script.Parent.Parent.types.runtime.layerRuntime)
local AnimationPosition = require(script.Parent.Parent.utils.animationPosition)
local DefTypes = require(script.Parent.Parent.types.def)
local MotionNodeTypes = require(script.Parent.Parent.types.motions.motionNode)

export type LayerDefinition<LayerT, LayerBackendT> = Types.LayerDefinition<LayerT, LayerBackendT>
export type LayerPlayOptions<StateT, LayerBackendT> = Types.LayerPlayOptions<StateT, LayerBackendT>
export type LayerDebugSnapshot<LayerT, StateT, LayerBackendT> =
	Types.LayerDebugSnapshot<LayerT, StateT, LayerBackendT>
export type LayerRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT> = Types.LayerRuntime<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
>
export type LayerRuntimeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT> = Types.LayerRuntimeImpl<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
>

local DEFAULT_WEIGHT = 1
local DEFAULT_SPEED = 1
local DEFAULT_LOGICAL_PRIORITY = 0
local DEFAULT_FADE_IN = 0.2
local DEFAULT_FADE_OUT = 0.2

local function optionNumber(value: number?, fallback: number): number
	return if value ~= nil then value else fallback
end

local function assertFinite(value: number, name: string): number
	assert(typeof(value) == "number", name .. " must be a number")
	assert(value == value and value > -math.huge and value < math.huge, name .. " must be finite")
	return value
end

local function assertNonNegative(value: number, name: string): number
	assertFinite(value, name)
	assert(value >= 0, name .. " must be non-negative")
	return value
end

local function assertReader(reader: DefTypes.TimeReader?, name: string): ()
	if reader ~= nil then
		assert(typeof(reader) == "function", name .. " must be a function")
	end
end

local function copyOverrides<StateT, LayerBackendT>(
	options: LayerPlayOptions<StateT, LayerBackendT>?
): MotionNodeTypes.MotionRequestOverrides<LayerBackendT>?
	if options == nil then
		return nil
	end

	return {
		trackKey = options.trackKey,
		weight = options.weight,
		speed = options.speed,
		looped = options.looped,
		logicalPriority = options.logicalPriority,
		layerBackend = options.layerBackend,
		initialPosition = options.initialPosition,
		forceRestart = options.forceRestart,
	}
end

local LayerRuntime = {}
LayerRuntime.__index = LayerRuntime

function LayerRuntime.new<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	definition: LayerDefinition<LayerT, LayerBackendT>
): LayerRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>
	assertReader(definition.timeReader, "timeReader")

	local self: LayerRuntimeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
		setmetatable({}, LayerRuntime) :: any

	self._id = definition.id
	self._weight = assertNonNegative(optionNumber(definition.weight, DEFAULT_WEIGHT), "weight")
	self._speed = assertFinite(optionNumber(definition.speed, DEFAULT_SPEED), "speed")
	self._logicalPriority = assertFinite(
		optionNumber(definition.logicalPriority, DEFAULT_LOGICAL_PRIORITY),
		"logicalPriority"
	)
	self._layerBackend = definition.layerBackend
	self._defaultFadeIn = assertNonNegative(optionNumber(definition.defaultFadeIn, DEFAULT_FADE_IN), "defaultFadeIn")
	self._defaultFadeOut = assertNonNegative(
		optionNumber(definition.defaultFadeOut, DEFAULT_FADE_OUT),
		"defaultFadeOut"
	)
	self._timeReader = definition.timeReader
	self._motion = nil
	self._state = nil
	self._fadeTime = self._defaultFadeIn
	self._overrides = nil
	self._playTimeReader = nil
	self._playing = false

	return self
end

function LayerRuntime.getId<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: LayerRuntimeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>
): LayerT
	return self._id
end

function LayerRuntime.play<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: LayerRuntimeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	motion: MotionNodeTypes.MotionNode<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	options: LayerPlayOptions<StateT, LayerBackendT>?
): ()
	if options ~= nil and options.initialPosition ~= nil then
		AnimationPosition.assertValid(options.initialPosition)
	end
	if options ~= nil then
		assertReader(options.timeReader, "timeReader")
	end

	self._motion = motion
	self._state = if options ~= nil then options.state else nil
	self._fadeTime = assertNonNegative(
		if options ~= nil
		then optionNumber(options.fadeTime, optionNumber(options.fadeIn, self._defaultFadeIn))
		else self._defaultFadeIn,
		"fadeTime"
	)
	self._overrides = copyOverrides(options)
	self._playTimeReader = if options ~= nil then options.timeReader else nil
	self._playing = true
end

function LayerRuntime.stop<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: LayerRuntimeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>
): ()
	self._motion = nil
	self._state = nil
	self._overrides = nil
	self._playTimeReader = nil
	self._playing = false
end

function LayerRuntime._selectTimeReader<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: LayerRuntimeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	defaultReader: DefTypes.TimeReader
): DefTypes.TimeReader?
	if not self._playing then
		return nil
	end

	return self._playTimeReader or self._timeReader or defaultReader
end

function LayerRuntime.evaluate<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: LayerRuntimeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	timeSample: DefTypes.TimeSample,
	getParameter: (parameter: ParamT) -> any,
	consumeTrigger: (parameter: ParamT) -> boolean,
	emitEvent: (event: any) -> ()
): { MotionNodeTypes.ClipRequest<LayerT, StateT, ClipT, LayerBackendT> }
	local motion = self._motion
	if not self._playing or motion == nil or self._weight <= 0 then
		return {}
	end

	local context: MotionNodeTypes.MotionEvaluateContext<LayerT, StateT, ParamT, ClipT, LayerBackendT> = {
		layer = self._id,
		state = self._state,
		timePosition = timeSample.position,
		timeRate = timeSample.rate,
		fadeTime = self._fadeTime,
		layerWeight = self._weight,
		layerSpeed = self._speed,
		logicalPriority = self._logicalPriority,
		layerBackend = self._layerBackend,
		overrides = self._overrides,
		getParameter = getParameter,
		consumeTrigger = consumeTrigger,
		emitEvent = emitEvent,
	}

	local requests = motion:evaluate(context)
	for _, request in requests do
		request.weight *= self._weight
		request.speed *= self._speed
	end

	local overrides = self._overrides
	if overrides ~= nil and #requests > 0 then
		overrides.initialPosition = nil
		overrides.forceRestart = false
	end

	return requests
end

function LayerRuntime.setWeight<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: LayerRuntimeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	weight: number
): ()
	self._weight = assertNonNegative(weight, "weight")
end

function LayerRuntime.getWeight<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: LayerRuntimeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>
): number
	return self._weight
end

function LayerRuntime.setSpeed<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: LayerRuntimeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	speed: number
): ()
	self._speed = assertFinite(speed, "speed")
end

function LayerRuntime.getSpeed<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: LayerRuntimeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>
): number
	return self._speed
end

function LayerRuntime.setLogicalPriority<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: LayerRuntimeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	logicalPriority: number
): ()
	self._logicalPriority = assertFinite(logicalPriority, "logicalPriority")
end

function LayerRuntime.getLogicalPriority<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: LayerRuntimeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>
): number
	return self._logicalPriority
end

function LayerRuntime.setLayerBackend<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: LayerRuntimeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	layerBackend: LayerBackendT?
): ()
	self._layerBackend = layerBackend
end

function LayerRuntime.getLayerBackend<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: LayerRuntimeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>
): LayerBackendT?
	return self._layerBackend
end

function LayerRuntime.setTimeReader<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: LayerRuntimeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	reader: DefTypes.TimeReader?
): ()
	assertReader(reader, "timeReader")
	self._timeReader = reader
end

function LayerRuntime.setActivePlayTimeReader<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: LayerRuntimeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	reader: DefTypes.TimeReader?
): ()
	assertReader(reader, "timeReader")
	self._playTimeReader = reader
end

function LayerRuntime.getDefaultFadeOut<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: LayerRuntimeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>
): number
	return self._defaultFadeOut
end

function LayerRuntime.getDebugSnapshot<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: LayerRuntimeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>
): LayerDebugSnapshot<LayerT, StateT, LayerBackendT>
	return {
		id = self._id,
		state = self._state,
		weight = self._weight,
		speed = self._speed,
		logicalPriority = self._logicalPriority,
		layerBackend = self._layerBackend,
		isPlaying = self._playing,
		motion = if self._motion ~= nil then self._motion:getDebugSnapshot() else nil,
	}
end

return LayerRuntime

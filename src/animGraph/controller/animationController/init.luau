--!strict
--!optimize 2
--!native

local AnimationPosition = require(script.Parent.Parent.utils.animationPosition)
local EventBus = require(script.eventBus)
local LayerRuntime = require(script.Parent.Parent.runtime.layerRuntime)
local ParameterStore = require(script.parameterStore)
local RequestValidation = require(script.Parent.Parent.utils.requestValidation)
local Types = require(script.Parent.Parent.types.controller.animationController)
local DefTypes = require(script.Parent.Parent.types.def)
local EventBusTypes = require(script.Parent.Parent.types.controller.eventBus)
local LayerRuntimeTypes = require(script.Parent.Parent.types.runtime.layerRuntime)
local MotionNodeTypes = require(script.Parent.Parent.types.motions.motionNode)
local ParameterStoreTypes = require(script.Parent.Parent.types.controller.parameterStore)

export type AnimationControllerConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	Types.AnimationControllerConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT>
export type AnimationControllerDebugSnapshot<LayerT, StateT, ParamT, LayerBackendT> =
	Types.AnimationControllerDebugSnapshot<LayerT, StateT, ParamT, LayerBackendT>
export type AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	Types.AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>
export type AnimationControllerImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	Types.AnimationControllerImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>

type PreparedLogicalSample<LayerT, StateT, ParamT, ClipT, LayerBackendT> = {
	layerRuntime: LayerRuntimeTypes.LayerRuntimeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	position: number,
}

local AnimationController = {}
AnimationController.__index = AnimationController

local function assertFiniteTime(value: number, name: string): number
	assert(typeof(value) == "number", name .. " must be a number")
	assert(value == value and value > -math.huge and value < math.huge, name .. " must be finite")
	return value
end

function AnimationController.new<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	config: AnimationControllerConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT>
): AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>
	assert(typeof(config.timeSource) == "function", "timeSource must be a function")
	assert(typeof(config.logicalTimeReader) == "function", "logicalTimeReader must be a function")

	local self: AnimationControllerImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT> = setmetatable(
		{},
		AnimationController
	) :: any

	self._backend = config.backend
	self._timeSource = config.timeSource
	self._logicalTimeReader = config.logicalTimeReader
	self._layers = {}
	self._layerOrder = {}
	self._parameters = ParameterStore.new() :: any
	self._eventBus = EventBus.new() :: any
	self._destroyed = false

	if config.layers ~= nil then
		for _, layer in config.layers do
			self:addLayer(layer)
		end
	end

	return self
end

function AnimationController.addLayer<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	definition: LayerRuntimeTypes.LayerDefinition<LayerT, LayerBackendT>
): ()
	assert(not self._destroyed, "AnimationController is destroyed")
	assert(self._layers[definition.id] == nil, "layer already exists")

	self._layers[definition.id] = LayerRuntime.new(definition) :: any
	self._layerOrder[#self._layerOrder + 1] = definition.id
end

function AnimationController.hasLayer<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	layer: LayerT
): boolean
	return self._layers[layer] ~= nil
end

function AnimationController.play<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	layer: LayerT,
	motion: MotionNodeTypes.MotionNode<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	options: LayerRuntimeTypes.LayerPlayOptions<StateT, LayerBackendT>?
): ()
	if self._destroyed then
		return
	end

	local layerRuntime = self._layers[layer]
	assert(layerRuntime ~= nil, "unknown layer")
	if options ~= nil and options.initialPosition ~= nil then
		AnimationPosition.assertValid(options.initialPosition)
	end

	layerRuntime:play(motion, options)
end

function AnimationController.stopLayer<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
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

	layerRuntime:stop()
	self._backend:stopLayer(layer, fadeTime or layerRuntime:getDefaultFadeOut())
end

function AnimationController.setLayerWeight<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	layer: LayerT,
	weight: number
): ()
	local layerRuntime = self._layers[layer]
	assert(layerRuntime ~= nil, "unknown layer")

	layerRuntime:setWeight(weight)
end

function AnimationController.getLayerWeight<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	layer: LayerT
): number?
	local layerRuntime = self._layers[layer]
	return if layerRuntime ~= nil then layerRuntime:getWeight() else nil
end

function AnimationController.setLayerSpeed<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	layer: LayerT,
	speed: number
): ()
	local layerRuntime = self._layers[layer]
	assert(layerRuntime ~= nil, "unknown layer")

	layerRuntime:setSpeed(speed)
end

function AnimationController.getLayerSpeed<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	layer: LayerT
): number?
	local layerRuntime = self._layers[layer]
	return if layerRuntime ~= nil then layerRuntime:getSpeed() else nil
end

function AnimationController.setLayerLogicalPriority<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	layer: LayerT,
	logicalPriority: number
): ()
	local layerRuntime = self._layers[layer]
	assert(layerRuntime ~= nil, "unknown layer")

	layerRuntime:setLogicalPriority(logicalPriority)
end

function AnimationController.getLayerLogicalPriority<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	layer: LayerT
): number?
	local layerRuntime = self._layers[layer]
	return if layerRuntime ~= nil then layerRuntime:getLogicalPriority() else nil
end

function AnimationController.setLayerBackend<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	layer: LayerT,
	layerBackend: LayerBackendT?
): ()
	local layerRuntime = self._layers[layer]
	assert(layerRuntime ~= nil, "unknown layer")

	layerRuntime:setLayerBackend(layerBackend)
end

function AnimationController.getLayerBackend<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	layer: LayerT
): LayerBackendT?
	local layerRuntime = self._layers[layer]
	return if layerRuntime ~= nil then layerRuntime:getLayerBackend() else nil
end

function AnimationController.setParameter<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	parameter: ParamT,
	value: ParameterStoreTypes.ParameterValue
): ()
	self._parameters:set(parameter, value)
end

function AnimationController.getParameter<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	parameter: ParamT
): ParameterStoreTypes.ParameterValue?
	return self._parameters:get(parameter)
end

function AnimationController.setFloat<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	parameter: ParamT,
	value: number
): ()
	self._parameters:setFloat(parameter, value)
end

function AnimationController.getFloat<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	parameter: ParamT,
	fallback: number?
): number
	return self._parameters:getFloat(parameter, fallback)
end

function AnimationController.setBool<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	parameter: ParamT,
	value: boolean
): ()
	self._parameters:setBool(parameter, value)
end

function AnimationController.getBool<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	parameter: ParamT,
	fallback: boolean?
): boolean
	return self._parameters:getBool(parameter, fallback)
end

function AnimationController.setTrigger<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	parameter: ParamT
): ()
	self._parameters:setTrigger(parameter)
end

function AnimationController.consumeTrigger<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	parameter: ParamT
): boolean
	return self._parameters:consumeTrigger(parameter)
end

function AnimationController.on<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	name: EventBusTypes.AnimationEventName,
	callback: EventBusTypes.AnimationEventCallback<LayerT, StateT>
): EventBusTypes.Release
	return self._eventBus:on(name, callback)
end

function AnimationController.update<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>
): ()
	if self._destroyed then
		return
	end

	local frameNow = assertFiniteTime(self._timeSource(), "timeSource result")
	local readerSamples: { [DefTypes.LogicalTimeReader]: number } = {}
	local logicalDeltasByLayer: { [LayerT]: number } = {}
	local preparedSamples: { PreparedLogicalSample<LayerT, StateT, ParamT, ClipT, LayerBackendT> } = {}

	for _, layer in self._layerOrder do
		local layerRuntime = self._layers[layer]
		if layerRuntime ~= nil then
			local reader = layerRuntime:_selectLogicalTimeReader(self._logicalTimeReader)
			if reader ~= nil then
				local position = readerSamples[reader]
				if position == nil then
					position = assertFiniteTime(reader(frameNow), "logicalTimeReader result")
					readerSamples[reader] = position
				end

				local baseline = layerRuntime:_getLogicalTimeBaseline()
				assert(
					baseline == nil or position >= baseline,
					"logicalTimeReader moved backward for layer " .. tostring(layer)
				)
				local deltaTime = if baseline == nil
					then 0
					else assertFiniteTime(position - baseline, "logical time delta")
				logicalDeltasByLayer[layer] = deltaTime
				preparedSamples[#preparedSamples + 1] = {
					layerRuntime = layerRuntime,
					position = position,
				}
			end
		end
	end

	for _, prepared in preparedSamples do
		prepared.layerRuntime:_commitLogicalTimeSample(prepared.position)
	end

	local requests: { MotionNodeTypes.ClipRequest<LayerT, StateT, ClipT, LayerBackendT> } = {}
	local getParameter = function(parameter: ParamT): any
		return self._parameters:get(parameter)
	end
	local consumeTrigger = function(parameter: ParamT): boolean
		return self._parameters:consumeTrigger(parameter)
	end
	local emitEvent = function(event: any): ()
		self._eventBus:emit(event)
	end

	for _, layer in self._layerOrder do
		local layerRuntime = self._layers[layer]
		if layerRuntime ~= nil then
			local deltaTime = logicalDeltasByLayer[layer]
			if deltaTime == nil then
				deltaTime = 0
			end
			local layerRequests = layerRuntime:evaluate(deltaTime, getParameter, consumeTrigger, emitEvent)
			for _, request in layerRequests do
				requests[#requests + 1] = request
			end
		end
	end

	RequestValidation.validate(requests)
	self._backend:apply(requests)
end

function AnimationController.clear<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>
): ()
	for _, layerRuntime in self._layers do
		layerRuntime:stop()
	end

	self._parameters:clear()
	self._backend:clear()
end

function AnimationController.destroy<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>
): ()
	if self._destroyed then
		return
	end

	self._destroyed = true
	self:clear()
	self._eventBus:clear()
	self._backend:destroy()
end

function AnimationController.getDebugSnapshot<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>
): AnimationControllerDebugSnapshot<LayerT, StateT, ParamT, LayerBackendT>
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

return AnimationController

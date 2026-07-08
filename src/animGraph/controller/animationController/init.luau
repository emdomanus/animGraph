--!strict
--!optimize 2
--!native

local RunService = game:GetService("RunService")

local EventBus = require(script.eventBus)
local LayerRuntime = require(script.Parent.Parent.runtime.layerRuntime)
local ParameterStore = require(script.parameterStore)
local Types = require(script.Parent.Parent.types.controller.animationController)
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

local AnimationController = {}
AnimationController.__index = AnimationController

function AnimationController.new<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	config: AnimationControllerConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT>
): AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>
	local self: AnimationControllerImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT> = setmetatable(
		{},
		AnimationController
	) :: any

	self._backend = config.backend
	self._layers = {}
	self._layerOrder = {}
	self._parameters = ParameterStore.new() :: any
	self._eventBus = EventBus.new() :: any
	self._updateConnection = nil
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
	self: AnimationControllerImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	dt: number
): ()
	if self._destroyed then
		return
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
			local layerRequests = layerRuntime:evaluate(dt, getParameter, consumeTrigger, emitEvent)
			for _, request in layerRequests do
				requests[#requests + 1] = request
			end
		end
	end

	self._backend:apply(requests, dt)
end

function AnimationController.bindToPreAnimation<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: AnimationControllerImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>
): () -> ()
	if self._updateConnection ~= nil then
		self._updateConnection:Disconnect()
	end

	self._updateConnection = RunService.PreAnimation:Connect(function(deltaTimeSim)
		self:update(deltaTimeSim)
	end)

	local released = false
	return function()
		if released then
			return
		end
		released = true

		local connection = self._updateConnection
		if connection ~= nil then
			connection:Disconnect()
			self._updateConnection = nil
		end
	end
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
	local connection = self._updateConnection
	if connection ~= nil then
		connection:Disconnect()
		self._updateConnection = nil
	end

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

--!strict
--!optimize 2
--!native

local Types = require(script.Parent.Parent.Parent.Parent.types.motions.clipNode.shared.clipNode)
local AnimationPosition = require(script.Parent.Parent.Parent.Parent.utils.animationPosition.shared.animationPosition)
local MotionNodeTypes = require(script.Parent.Parent.Parent.Parent.types.motions.motionNode.shared.motionNode)

type ClipNodeConfig<LayerBackendT> = Types.ClipNodeConfig<LayerBackendT>
type ClipNode<LayerT, StateT, ParamT, ClipT, LayerBackendT> = Types.ClipNode<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
>
type ClipNodeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT> = Types.ClipNodeImpl<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
>

local DEFAULT_WEIGHT = 1
local DEFAULT_SPEED = 1
local DEFAULT_LOOPED = false

local function optionNumber(value: number?, fallback: number): number
	return if value ~= nil then value else fallback
end

local function optionBoolean(value: boolean?, fallback: boolean): boolean
	return if value ~= nil then value else fallback
end

local function valueKey(value: any): string
	if typeof(value) == "string" then
		return value
	end

	return tostring(value)
end

local function makeTrackKey<LayerT, StateT, ClipT>(layer: LayerT, state: StateT?, clip: ClipT): string
	local stateKey = if state ~= nil then valueKey(state) else "manual"
	return valueKey(layer) .. "/" .. stateKey .. "/" .. valueKey(clip)
end

local ClipNode = {}
ClipNode.__index = ClipNode

function ClipNode.new<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	clip: ClipT,
	config: ClipNodeConfig<LayerBackendT>?
): ClipNode<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
>
	if config ~= nil and config.initialPosition ~= nil then
		AnimationPosition.assertValid(config.initialPosition)
	end

	local self: ClipNodeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT> = setmetatable({}, ClipNode) :: any

	self._clip = clip
	self._name = if config ~= nil and config.name ~= nil then config.name else valueKey(clip)
	self._trackKey = if config ~= nil then config.trackKey else nil
	self._weight = if config ~= nil and config.weight ~= nil then config.weight else DEFAULT_WEIGHT
	self._speed = if config ~= nil and config.speed ~= nil then config.speed else DEFAULT_SPEED
	self._looped = if config ~= nil and config.looped ~= nil then config.looped else DEFAULT_LOOPED
	self._logicalPriority = if config ~= nil then config.logicalPriority else nil
	self._layerBackend = if config ~= nil then config.layerBackend else nil
	self._initialPosition = if config ~= nil then config.initialPosition else nil

	return self
end

function ClipNode.evaluate<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: ClipNodeImpl<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>,
	context: MotionNodeTypes.MotionEvaluateContext<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>
): {
	MotionNodeTypes.ClipRequest<
		LayerT,
		StateT,
		ClipT,
		LayerBackendT
	>
}
	local overrides = context.overrides
	local trackKey = if overrides ~= nil and overrides.trackKey ~= nil then overrides.trackKey else self._trackKey

	local layerBackend = context.layerBackend
	if self._layerBackend ~= nil then
		layerBackend = self._layerBackend
	end
	if overrides ~= nil and overrides.layerBackend ~= nil then
		layerBackend = overrides.layerBackend
	end

	local request: MotionNodeTypes.ClipRequest<LayerT, StateT, ClipT, LayerBackendT> = {
		trackKey = if trackKey ~= nil then trackKey else makeTrackKey(context.layer, context.state, self._clip),
		layer = context.layer,
		state = context.state,
		clip = self._clip,
		weight = optionNumber(if overrides ~= nil then overrides.weight else nil, self._weight),
		speed = optionNumber(if overrides ~= nil then overrides.speed else nil, self._speed),
		timePosition = context.timePosition,
		timeRate = context.timeRate,
		initialPosition = if overrides ~= nil and overrides.initialPosition ~= nil
			then overrides.initialPosition
			else self._initialPosition,
		looped = optionBoolean(if overrides ~= nil then overrides.looped else nil, self._looped),
		logicalPriority = optionNumber(
			if overrides ~= nil and overrides.logicalPriority ~= nil
				then overrides.logicalPriority
				else self._logicalPriority,
			context.logicalPriority
		),
		layerBackend = layerBackend,
		fadeTime = context.fadeTime,
		forceRestart = if overrides ~= nil and overrides.forceRestart ~= nil then overrides.forceRestart else false,
	}

	return { request }
end

function ClipNode.getDebugSnapshot<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: ClipNodeImpl<
		LayerT,
		StateT,
		ParamT,
		ClipT,
		LayerBackendT
	>
): MotionNodeTypes.MotionDebugSnapshot
	return {
		kind = "Clip",
		name = self._name,
	}
end

return { new = ClipNode.new }

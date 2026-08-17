--!strict
--!optimize 2
--!native

local BackendTypes = require(script.Parent.Parent.backends.animationBackend)
local DefTypes = require(script.Parent.Parent.def)
local EventBusTypes = require(script.Parent.eventBus)
local LayerRuntimeTypes = require(script.Parent.Parent.runtime.layerRuntime)
local MotionNodeTypes = require(script.Parent.Parent.motions.motionNode)
local ParameterStoreTypes = require(script.Parent.parameterStore)

export type AnimationControllerConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT> = {
	backend: BackendTypes.AnimationBackend<LayerT, StateT, ClipT, LayerBackendT>,
	timeReader: DefTypes.TimeReader,
	layers: { LayerRuntimeTypes.LayerDefinition<LayerT, LayerBackendT> }?,
}

export type AnimationControllerDebugSnapshot<LayerT, StateT, ParamT, LayerBackendT> = {
	parameters: { [ParamT]: ParameterStoreTypes.ParameterValue },
	layers: { LayerRuntimeTypes.LayerDebugSnapshot<LayerT, StateT, LayerBackendT> },
	backend: BackendTypes.BackendDebugSnapshot,
}

export type GraphIntentCommand<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	{
		kind: "play",
		layer: LayerT,
		motion: MotionNodeTypes.MotionNode<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		options: LayerRuntimeTypes.LayerPlayOptions<StateT, LayerBackendT>?,
	}
	| { kind: "stop", layer: LayerT, fadeTime: number }
	| { kind: "setLayerWeight", layer: LayerT, weight: number }
	| { kind: "setLayerSpeed", layer: LayerT, speed: number }
	| { kind: "setLayerLogicalPriority", layer: LayerT, logicalPriority: number }
	| { kind: "setLayerBackend", layer: LayerT, layerBackend: LayerBackendT? }
	| { kind: "setDefaultTimeReader", reader: DefTypes.TimeReader }
	| { kind: "setLayerTimeReader", layer: LayerT, reader: DefTypes.TimeReader? }
	| { kind: "setActivePlayTimeReader", layer: LayerT, reader: DefTypes.TimeReader? }
	| { kind: "setParameter", parameter: ParamT, value: ParameterStoreTypes.ParameterValue }
	| { kind: "setTrigger", parameter: ParamT }

export type AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT> = {
	addLayer: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		definition: LayerRuntimeTypes.LayerDefinition<LayerT, LayerBackendT>
	) -> (),
	hasLayer: (self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>, layer: LayerT) -> boolean,
	play: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		layer: LayerT,
		motion: MotionNodeTypes.MotionNode<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		options: LayerRuntimeTypes.LayerPlayOptions<StateT, LayerBackendT>?
	) -> (),
	setTrackPosition: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		trackKey: string,
		position: DefTypes.AnimationPosition
	) -> boolean,
	offsetTrackPosition: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		trackKey: string,
		deltaSeconds: number
	) -> boolean,
	stopLayer: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		layer: LayerT,
		fadeTime: number?
	) -> (),
	setLayerWeight: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		layer: LayerT,
		weight: number
	) -> (),
	getLayerWeight: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		layer: LayerT
	) -> number?,
	setLayerSpeed: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		layer: LayerT,
		speed: number
	) -> (),
	getLayerSpeed: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		layer: LayerT
	) -> number?,
	setLayerLogicalPriority: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		layer: LayerT,
		logicalPriority: number
	) -> (),
	getLayerLogicalPriority: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		layer: LayerT
	) -> number?,
	setLayerBackend: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		layer: LayerT,
		layerBackend: LayerBackendT?
	) -> (),
	getLayerBackend: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		layer: LayerT
	) -> LayerBackendT?,
	setDefaultTimeReader: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		reader: DefTypes.TimeReader
	) -> (),
	setLayerTimeReader: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		layer: LayerT,
		reader: DefTypes.TimeReader?
	) -> (),
	setActivePlayTimeReader: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		layer: LayerT,
		reader: DefTypes.TimeReader?
	) -> (),

	setParameter: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		parameter: ParamT,
		value: ParameterStoreTypes.ParameterValue
	) -> (),
	getParameter: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		parameter: ParamT
	) -> ParameterStoreTypes.ParameterValue?,
	setFloat: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		parameter: ParamT,
		value: number
	) -> (),
	getFloat: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		parameter: ParamT,
		fallback: number?
	) -> number,
	setBool: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		parameter: ParamT,
		value: boolean
	) -> (),
	getBool: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		parameter: ParamT,
		fallback: boolean?
	) -> boolean,
	setTrigger: (self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>, parameter: ParamT) -> (),
	consumeTrigger: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		parameter: ParamT
	) -> boolean,
	on: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		name: EventBusTypes.AnimationEventName,
		callback: EventBusTypes.AnimationEventCallback<LayerT, StateT>
	) -> EventBusTypes.Release,

	update: (self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>, sampleTime: number) -> (),
	clear: (self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>) -> (),
	destroy: (self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>) -> (),
	getDebugSnapshot: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>
	) -> AnimationControllerDebugSnapshot<LayerT, StateT, ParamT, LayerBackendT>,
}

export type AnimationControllerImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT> & {
		_backend: BackendTypes.AnimationBackend<LayerT, StateT, ClipT, LayerBackendT>,
		_timeReader: DefTypes.TimeReader,
		_lastSampleTime: number?,
		_pendingCommands: { GraphIntentCommand<LayerT, StateT, ParamT, ClipT, LayerBackendT> },
		_layers: { [LayerT]: LayerRuntimeTypes.LayerRuntimeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT> },
		_layerOrder: { LayerT },
		_parameters: ParameterStoreTypes.ParameterStoreImpl<ParamT>,
		_eventBus: EventBusTypes.EventBusImpl<LayerT, StateT>,
		_releaseBackendCompletion: DefTypes.Release?,
		_lifecycleEpoch: number,
		_destroyed: boolean,
	}

return {}

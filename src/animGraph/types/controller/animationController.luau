--!strict
--!optimize 2
--!native

local BackendTypes = require(script.Parent.Parent.backends.animationBackend)
local DefTypes = require(script.Parent.Parent.def)
local EventBusTypes = require(script.Parent.eventBus)
local LayerRuntimeTypes = require(script.Parent.Parent.runtime.layerRuntime)
local MotionNodeTypes = require(script.Parent.Parent.motions.motionNode)
local ParameterStoreTypes = require(script.Parent.parameterStore)

export type AnimationControllerConfig<LayerT, StateT, ClipT, LayerBackendT> = {
	backend: BackendTypes.AnimationBackend<LayerT, StateT, ClipT, LayerBackendT>,
	timeReader: DefTypes.TimeReader,
	layers: { LayerRuntimeTypes.LayerDefinition<LayerT, LayerBackendT> }?,
}

export type AnimationControllerDebugSnapshot<GraphTypes> = {
	parameters: { [index<GraphTypes, "Param">]: ParameterStoreTypes.ParameterValue },
	layers: {
		LayerRuntimeTypes.LayerDebugSnapshot<
			index<GraphTypes, "Layer">,
			index<GraphTypes, "State">,
			index<GraphTypes, "LayerBackend">
		>
	},
	backend: BackendTypes.BackendDebugSnapshot,
}

export type GraphIntentCommand<LayerT, StateT, ParamT, ClipT, LayerBackendT> = {
	kind: "play",
	layer: LayerT,
	motion: MotionNodeTypes.MotionNode<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	options: LayerRuntimeTypes.LayerPlayOptions<StateT, LayerBackendT>?,
} | {
	kind: "stop",
	layer: LayerT,
	fadeTime: number,
} | {
	kind: "setLayerWeight",
	layer: LayerT,
	weight: number,
} | {
	kind: "setLayerSpeed",
	layer: LayerT,
	speed: number,
} | {
	kind: "setLayerLogicalPriority",
	layer: LayerT,
	logicalPriority: number,
} | {
	kind: "setLayerBackend",
	layer: LayerT,
	layerBackend: LayerBackendT?,
} | {
	kind: "setDefaultTimeReader",
	reader: DefTypes.TimeReader,
} | {
	kind: "setLayerTimeReader",
	layer: LayerT,
	reader: DefTypes.TimeReader?,
} | {
	kind: "setActivePlayTimeReader",
	layer: LayerT,
	reader: DefTypes.TimeReader?,
} | {
	kind: "setParameter",
	parameter: ParamT,
	value: ParameterStoreTypes.ParameterValue,
} | {
	kind: "setTrigger",
	parameter: ParamT,
}

export type AnimationController<GraphTypes> = {
	read addLayer: (
		self: AnimationController<GraphTypes>,
		definition: LayerRuntimeTypes.LayerDefinition<index<GraphTypes, "Layer">, index<GraphTypes, "LayerBackend">>
	) -> (),
	read hasLayer: (self: AnimationController<GraphTypes>, layer: index<GraphTypes, "Layer">) -> boolean,
	read play: (
		self: AnimationController<GraphTypes>,
		layer: index<GraphTypes, "Layer">,
		motion: MotionNodeTypes.MotionNode<
			index<GraphTypes, "Layer">,
			index<GraphTypes, "State">,
			index<GraphTypes, "Param">,
			index<GraphTypes, "Clip">,
			index<GraphTypes, "LayerBackend">
		>,
		options: LayerRuntimeTypes.LayerPlayOptions<index<GraphTypes, "State">, index<GraphTypes, "LayerBackend">>?
	) -> (),
	read setTrackPosition: (
		self: AnimationController<GraphTypes>,
		trackKey: string,
		position: DefTypes.AnimationPosition
	) -> boolean,
	read offsetTrackPosition: (
		self: AnimationController<GraphTypes>,
		trackKey: string,
		deltaSeconds: number
	) -> boolean,
	read stopLayer: (
		self: AnimationController<GraphTypes>,
		layer: index<GraphTypes, "Layer">,
		fadeTime: number?
	) -> (),
	read setLayerWeight: (
		self: AnimationController<GraphTypes>,
		layer: index<GraphTypes, "Layer">,
		weight: number
	) -> (),
	read getLayerWeight: (self: AnimationController<GraphTypes>, layer: index<GraphTypes, "Layer">) -> number?,
	read setLayerSpeed: (
		self: AnimationController<GraphTypes>,
		layer: index<GraphTypes, "Layer">,
		speed: number
	) -> (),
	read getLayerSpeed: (self: AnimationController<GraphTypes>, layer: index<GraphTypes, "Layer">) -> number?,
	read setLayerLogicalPriority: (
		self: AnimationController<GraphTypes>,
		layer: index<GraphTypes, "Layer">,
		logicalPriority: number
	) -> (),
	read getLayerLogicalPriority: (
		self: AnimationController<GraphTypes>,
		layer: index<GraphTypes, "Layer">
	) -> number?,
	read setLayerBackend: (
		self: AnimationController<GraphTypes>,
		layer: index<GraphTypes, "Layer">,
		layerBackend: index<GraphTypes, "LayerBackend">?
	) -> (),
	read getLayerBackend: (
		self: AnimationController<GraphTypes>,
		layer: index<GraphTypes, "Layer">
	) -> index<GraphTypes, "LayerBackend">?,
	read setDefaultTimeReader: (self: AnimationController<GraphTypes>, reader: DefTypes.TimeReader) -> (),
	read setLayerTimeReader: (
		self: AnimationController<GraphTypes>,
		layer: index<GraphTypes, "Layer">,
		reader: DefTypes.TimeReader?
	) -> (),
	read setActivePlayTimeReader: (
		self: AnimationController<GraphTypes>,
		layer: index<GraphTypes, "Layer">,
		reader: DefTypes.TimeReader?
	) -> (),

	read setParameter: (
		self: AnimationController<GraphTypes>,
		parameter: index<GraphTypes, "Param">,
		value: ParameterStoreTypes.ParameterValue
	) -> (),
	read getParameter: (
		self: AnimationController<GraphTypes>,
		parameter: index<GraphTypes, "Param">
	) -> ParameterStoreTypes.ParameterValue?,
	read setFloat: (
		self: AnimationController<GraphTypes>,
		parameter: index<GraphTypes, "Param">,
		value: number
	) -> (),
	read getFloat: (
		self: AnimationController<GraphTypes>,
		parameter: index<GraphTypes, "Param">,
		fallback: number?
	) -> number,
	read setBool: (
		self: AnimationController<GraphTypes>,
		parameter: index<GraphTypes, "Param">,
		value: boolean
	) -> (),
	read getBool: (
		self: AnimationController<GraphTypes>,
		parameter: index<GraphTypes, "Param">,
		fallback: boolean?
	) -> boolean,
	read setTrigger: (self: AnimationController<GraphTypes>, parameter: index<GraphTypes, "Param">) -> (),
	read consumeTrigger: (
		self: AnimationController<GraphTypes>,
		parameter: index<GraphTypes, "Param">
	) -> boolean,
	read on: (
		self: AnimationController<GraphTypes>,
		name: EventBusTypes.AnimationEventName,
		callback: EventBusTypes.AnimationEventCallback<index<GraphTypes, "Layer">, index<GraphTypes, "State">>
	) -> EventBusTypes.Release,

	read update: (self: AnimationController<GraphTypes>, sampleTime: number) -> (),
	read clear: (self: AnimationController<GraphTypes>) -> (),
	read destroy: (self: AnimationController<GraphTypes>) -> (),
	read getDebugSnapshot: (self: AnimationController<GraphTypes>) -> AnimationControllerDebugSnapshot<GraphTypes>,
}

export type AnimationControllerImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	AnimationController<{ Layer: LayerT, State: StateT, Param: ParamT, Clip: ClipT, LayerBackend: LayerBackendT }>
	& {
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

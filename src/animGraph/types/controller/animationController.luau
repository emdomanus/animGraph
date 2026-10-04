--!strict
--!optimize 2
--!native

local BackendTypes = require(script.Parent.Parent.backends.animationBackend)
local TrackMarkerSourceTypes = require(script.Parent.Parent.ports.backends.animationPlayback.shared.trackMarkerSource)
local DefTypes = require(script.Parent.Parent.def)
local EventBusTypes = require(script.Parent.eventBus)
local LayerRuntimeTypes = require(script.Parent.Parent.runtime.layerRuntime)
local MotionNodeTypes = require(script.Parent.Parent.motions.motionNode)
local ParameterStoreTypes = require(script.Parent.parameterStore)

export type AnimationControllerConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT> = {
	backend: BackendTypes.AnimationBackend<LayerT, StateT, ClipT, LayerBackendT>,
	timeReader: DefTypes.TimeReader,
	layers: { LayerRuntimeTypes.LayerDefinition<LayerT, LayerBackendT> }?,
	parameterDefaults: { [ParamT]: ParameterStoreTypes.ParameterValue }?,
}

export type AnimationControllerDebugSnapshot<LayerT, StateT, ParamT, LayerBackendT> = {
	parameters: { [ParamT]: ParameterStoreTypes.ParameterValue },
	layers: { LayerRuntimeTypes.LayerDebugSnapshot<LayerT, StateT, LayerBackendT> },
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

export type AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT> = {
	read onMarker: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		markerName: string,
		callback: (track: TrackMarkerSourceTypes.TrackMarkerSource<LayerT, StateT, ClipT>, value: string) -> ()
	) -> DefTypes.Release,
	read onTrackMarker: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		trackKey: string,
		markerName: string,
		callback: (value: string) -> ()
	) -> DefTypes.Release,
	read addLayer: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		definition: LayerRuntimeTypes.LayerDefinition<LayerT, LayerBackendT>
	) -> (),
	read hasLayer: (self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>, layer: LayerT) -> boolean,
	read play: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		layer: LayerT,
		motion: MotionNodeTypes.MotionNode<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		options: LayerRuntimeTypes.LayerPlayOptions<StateT, LayerBackendT>?
	) -> (),
	read setTrackPosition: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		trackKey: string,
		position: DefTypes.AnimationPosition
	) -> boolean,
	read offsetTrackPosition: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		trackKey: string,
		deltaSeconds: number
	) -> boolean,
	read stopLayer: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		layer: LayerT,
		fadeTime: number?
	) -> (),
	read setLayerWeight: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		layer: LayerT,
		weight: number
	) -> (),
	read getLayerWeight: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		layer: LayerT
	) -> number?,
	read setLayerSpeed: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		layer: LayerT,
		speed: number
	) -> (),
	read getLayerSpeed: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		layer: LayerT
	) -> number?,
	read setLayerLogicalPriority: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		layer: LayerT,
		logicalPriority: number
	) -> (),
	read getLayerLogicalPriority: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		layer: LayerT
	) -> number?,
	read setLayerBackend: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		layer: LayerT,
		layerBackend: LayerBackendT?
	) -> (),
	read getLayerBackend: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		layer: LayerT
	) -> LayerBackendT?,
	read setDefaultTimeReader: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		reader: DefTypes.TimeReader
	) -> (),
	read setLayerTimeReader: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		layer: LayerT,
		reader: DefTypes.TimeReader?
	) -> (),
	read setActivePlayTimeReader: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		layer: LayerT,
		reader: DefTypes.TimeReader?
	) -> (),

	read setParameter: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		parameter: ParamT,
		value: ParameterStoreTypes.ParameterValue
	) -> (),
	read getParameter: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		parameter: ParamT
	) -> ParameterStoreTypes.ParameterValue?,
	read setFloat: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		parameter: ParamT,
		value: number
	) -> (),
	read getFloat: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		parameter: ParamT,
		fallback: number?
	) -> number,
	read setBool: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		parameter: ParamT,
		value: boolean
	) -> (),
	read getBool: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		parameter: ParamT,
		fallback: boolean?
	) -> boolean,
	read setTrigger: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		parameter: ParamT
	) -> (),
	read consumeTrigger: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		parameter: ParamT
	) -> boolean,
	read on: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		name: EventBusTypes.AnimationEventName,
		callback: EventBusTypes.AnimationEventCallback<LayerT, StateT>
	) -> EventBusTypes.Release,

	read update: (self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>, sampleTime: number) -> (),
	read clear: (self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>) -> (),
	read destroy: (self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>) -> (),
	read getDebugSnapshot: (
		self: AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>
	) -> AnimationControllerDebugSnapshot<LayerT, StateT, ParamT, LayerBackendT>,
}

export type AnimationControllerImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT> = AnimationController<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
> & {
	_backend: BackendTypes.AnimationBackend<LayerT, StateT, ClipT, LayerBackendT>,
	_timeReader: DefTypes.TimeReader,
	_lastSampleTime: number?,
	_pendingCommands: { GraphIntentCommand<LayerT, StateT, ParamT, ClipT, LayerBackendT> },
	_layers: { [LayerT]: LayerRuntimeTypes.LayerRuntimeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT> },
	_layerOrder: { LayerT },
	_parameters: ParameterStoreTypes.ParameterStoreImpl<ParamT>,
	_eventBus: EventBusTypes.EventBusImpl<LayerT, StateT>,
	_readParameter: (parameter: ParamT) -> ParameterStoreTypes.ParameterValue?,
	_consumeTrigger: (parameter: ParamT) -> boolean,
	_emitEvent: EventBusTypes.AnimationEventCallback<LayerT, StateT>,
	_releaseBackendCompletion: DefTypes.Release?,
	_lifecycleEpoch: number,
	_destroyed: boolean,
}

return {}

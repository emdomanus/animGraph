--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.def)
local MotionNodeTypes = require(script.Parent.Parent.motions.motionNode)

export type LayerDefinition<LayerT, LayerBackendT> = {
	id: LayerT,
	weight: number?,
	speed: number?,
	logicalPriority: number?,
	layerBackend: LayerBackendT?,
	defaultFadeIn: number?,
	defaultFadeOut: number?,
	timeReader: DefTypes.TimeReader?,
}

export type LayerPlayOptions<StateT, LayerBackendT> = MotionNodeTypes.MotionRequestOverrides<LayerBackendT> & {
	state: StateT?,
	fadeTime: number?,
	fadeIn: number?,
	timeReader: DefTypes.TimeReader?,
}

export type LayerDebugSnapshot<LayerT, StateT, LayerBackendT> = {
	id: LayerT,
	state: StateT?,
	weight: number,
	speed: number,
	logicalPriority: number,
	layerBackend: LayerBackendT?,
	isPlaying: boolean,
	motion: MotionNodeTypes.MotionDebugSnapshot?,
}

export type LayerRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT> = {
	read getId: (self: LayerRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>) -> LayerT,
	read play: (
		self: LayerRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		motion: MotionNodeTypes.MotionNode<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		options: LayerPlayOptions<StateT, LayerBackendT>?
	) -> (),
	read stop: (self: LayerRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>) -> (),
	read evaluate: (
		self: LayerRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		timeSample: DefTypes.TimeSample,
		getParameter: (parameter: ParamT) -> any,
		consumeTrigger: (parameter: ParamT) -> boolean,
		emitEvent: (event: any) -> ()
	) -> { MotionNodeTypes.ClipRequest<LayerT, StateT, ClipT, LayerBackendT> },
	read setWeight: (self: LayerRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>, weight: number) -> (),
	read getWeight: (self: LayerRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>) -> number,
	read setSpeed: (self: LayerRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>, speed: number) -> (),
	read getSpeed: (self: LayerRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>) -> number,
	read setLogicalPriority: (
		self: LayerRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		logicalPriority: number
	) -> (),
	read getLogicalPriority: (self: LayerRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>) -> number,
	read setLayerBackend: (
		self: LayerRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		layerBackend: LayerBackendT?
	) -> (),
	read getLayerBackend: (self: LayerRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>) -> LayerBackendT?,
	read setTimeReader: (
		self: LayerRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		reader: DefTypes.TimeReader?
	) -> (),
	read setActivePlayTimeReader: (
		self: LayerRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		reader: DefTypes.TimeReader?
	) -> (),
	read getDefaultFadeOut: (self: LayerRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>) -> number,
	read getDebugSnapshot: (
		self: LayerRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>
	) -> LayerDebugSnapshot<LayerT, StateT, LayerBackendT>,
}

export type LayerRuntimeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT> = LayerRuntime<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
> & {
	_id: LayerT,
	_weight: number,
	_speed: number,
	_logicalPriority: number,
	_layerBackend: LayerBackendT?,
	_defaultFadeIn: number,
	_defaultFadeOut: number,
	_timeReader: DefTypes.TimeReader?,
	_motion: MotionNodeTypes.MotionNode<LayerT, StateT, ParamT, ClipT, LayerBackendT>?,
	_state: StateT?,
	_fadeTime: number,
	_overrides: MotionNodeTypes.MotionRequestOverrides<LayerBackendT>?,
	_playTimeReader: DefTypes.TimeReader?,
	_playing: boolean,
	_selectTimeReader: (
		self: LayerRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		defaultReader: DefTypes.TimeReader
	) -> DefTypes.TimeReader?,
}

return {}

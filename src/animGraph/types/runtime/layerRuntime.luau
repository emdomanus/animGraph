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
	getId: (self: LayerRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>) -> LayerT,
	play: (
		self: LayerRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		motion: MotionNodeTypes.MotionNode<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		options: LayerPlayOptions<StateT, LayerBackendT>?
	) -> (),
	stop: (self: LayerRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>) -> (),
	evaluate: (
		self: LayerRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		timeSample: DefTypes.TimeSample,
		getParameter: (parameter: ParamT) -> any,
		consumeTrigger: (parameter: ParamT) -> boolean,
		emitEvent: (event: any) -> ()
	) -> { MotionNodeTypes.ClipRequest<LayerT, StateT, ClipT, LayerBackendT> },
	setWeight: (self: LayerRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>, weight: number) -> (),
	getWeight: (self: LayerRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>) -> number,
	setSpeed: (self: LayerRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>, speed: number) -> (),
	getSpeed: (self: LayerRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>) -> number,
	setLogicalPriority: (
		self: LayerRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		logicalPriority: number
	) -> (),
	getLogicalPriority: (self: LayerRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>) -> number,
	setLayerBackend: (
		self: LayerRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		layerBackend: LayerBackendT?
	) -> (),
	getLayerBackend: (self: LayerRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>) -> LayerBackendT?,
	setTimeReader: (
		self: LayerRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		reader: DefTypes.TimeReader?
	) -> (),
	setActivePlayTimeReader: (
		self: LayerRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		reader: DefTypes.TimeReader?
	) -> (),
	getDefaultFadeOut: (self: LayerRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>) -> number,
	getDebugSnapshot: (
		self: LayerRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>
	) -> LayerDebugSnapshot<LayerT, StateT, LayerBackendT>,
}

export type LayerRuntimeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	LayerRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT> & {
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

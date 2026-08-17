--!strict
--!optimize 2
--!native

local DefTypes = require(script.Parent.Parent.def)

export type MotionRequestOverrides<LayerBackendT> = {
	trackKey: string?,
	weight: number?,
	speed: number?,
	looped: boolean?,
	logicalPriority: number?,
	layerBackend: LayerBackendT?,
	initialPosition: DefTypes.AnimationPosition?,
	forceRestart: boolean?,
}

export type MotionEvaluateContext<LayerT, StateT, ParamT, ClipT, LayerBackendT> = {
	layer: LayerT,
	state: StateT?,
	timePosition: number,
	timeRate: number,
	fadeTime: number,
	layerWeight: number,
	layerSpeed: number,
	logicalPriority: number,
	layerBackend: LayerBackendT?,
	overrides: MotionRequestOverrides<LayerBackendT>?,
	getParameter: (parameter: ParamT) -> any,
	consumeTrigger: (parameter: ParamT) -> boolean,
	emitEvent: (event: any) -> (),
}

export type ClipRequest<LayerT, StateT, ClipT, LayerBackendT> = {
	trackKey: string,
	layer: LayerT,
	state: StateT?,
	clip: ClipT,
	weight: number,
	speed: number,
	timePosition: number,
	timeRate: number,
	initialPosition: DefTypes.AnimationPosition?,
	looped: boolean,
	logicalPriority: number,
	layerBackend: LayerBackendT?,
	fadeTime: number,
	forceRestart: boolean,
}

export type MotionDebugSnapshot = {
	kind: string,
	name: string,
	details: { [string]: any }?,
	children: { MotionDebugSnapshot }?,
}

export type MotionNode<LayerT, StateT, ParamT, ClipT, LayerBackendT> = {
	evaluate: (
		self: MotionNode<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		context: MotionEvaluateContext<LayerT, StateT, ParamT, ClipT, LayerBackendT>
	) -> { ClipRequest<LayerT, StateT, ClipT, LayerBackendT> },
	getDebugSnapshot: (self: MotionNode<LayerT, StateT, ParamT, ClipT, LayerBackendT>) -> MotionDebugSnapshot,
}

return {}

--!strict
--!optimize 2

local MotionNodeTypes = require(script.Parent.Parent.Parent.motionNode.shared.motionNode)

export type Blend2DCandidate = {
	index: number,
	distanceSquared: number,
}

export type Blend2DEvaluationScratch = {
	weights: { number },
	candidates: { Blend2DCandidate },
}

export type Blend2DSample<LayerT, StateT, ParamT, ClipT, LayerBackendT> = {
	x: number,
	y: number,
	motion: MotionNodeTypes.MotionNode<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
}

export type Blend2DNodeConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT> = {
	name: string?,
	defaultX: number?,
	defaultY: number?,
	maxInfluences: number?,
	samples: { Blend2DSample<LayerT, StateT, ParamT, ClipT, LayerBackendT> },
}

export type Blend2DNode<LayerT, StateT, ParamT, ClipT, LayerBackendT> = MotionNodeTypes.MotionNode<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
>

export type Blend2DNodeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT> = Blend2DNode<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
> & {
	_parameterX: ParamT,
	_parameterY: ParamT,
	_name: string,
	_defaultX: number,
	_defaultY: number,
	_maxInfluences: number,
	_samples: { Blend2DSample<LayerT, StateT, ParamT, ClipT, LayerBackendT> },
	_lastX: number,
	_lastY: number,
	_lastWeights: { number },
	_spareEvaluationScratch: Blend2DEvaluationScratch?,
}

return {}

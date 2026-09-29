--!strict
--!optimize 2
--!native

local MotionNodeTypes = require(script.Parent.motionNode)

export type Blend1DSample<LayerT, StateT, ParamT, ClipT, LayerBackendT> = {
	threshold: number,
	motion: MotionNodeTypes.MotionNode<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
}

export type Blend1DNodeConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT> = {
	name: string?,
	defaultValue: number?,
	samples: { Blend1DSample<LayerT, StateT, ParamT, ClipT, LayerBackendT> },
}

export type Blend1DNode<LayerT, StateT, ParamT, ClipT, LayerBackendT> = MotionNodeTypes.MotionNode<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
>

export type Blend1DNodeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT> = Blend1DNode<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
> & {
	_parameter: ParamT,
	_name: string,
	_defaultValue: number,
	_samples: { Blend1DSample<LayerT, StateT, ParamT, ClipT, LayerBackendT> },
	_lastValue: number,
	_lastWeights: { number },
	_spareWeights: { number }?,
}

return {}

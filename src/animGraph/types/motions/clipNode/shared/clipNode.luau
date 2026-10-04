--!strict
--!optimize 2

local MotionNodeTypes = require(script.Parent.Parent.Parent.motionNode.shared.motionNode)
local DefTypes = require(script.Parent.Parent.Parent.Parent.def.animation.shared.animation)

export type ClipNodeConfig<LayerBackendT> = {
	name: string?,
	trackKey: string?,
	weight: number?,
	speed: number?,
	looped: boolean?,
	logicalPriority: number?,
	layerBackend: LayerBackendT?,
	initialPosition: DefTypes.AnimationPosition?,
}

export type ClipNode<LayerT, StateT, ParamT, ClipT, LayerBackendT> = MotionNodeTypes.MotionNode<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
>

export type ClipNodeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT> = ClipNode<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
> & {
	_clip: ClipT,
	_name: string,
	_trackKey: string?,
	_weight: number,
	_speed: number,
	_looped: boolean,
	_logicalPriority: number?,
	_layerBackend: LayerBackendT?,
	_initialPosition: DefTypes.AnimationPosition?,
}

return {}

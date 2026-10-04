--!strict
--!optimize 2

local MotionNodeTypes = require(script.Parent.Parent.Parent.Parent.motions.motionNode.shared.motionNode)
local TransitionRuntimeTypes = require(script.Parent.Parent.Parent.transitionRuntime.shared.transitionRuntime)

export type StateDefinition<LayerT, StateT, ParamT, ClipT, LayerBackendT> = {
	id: StateT,
	motion: MotionNodeTypes.MotionNode<LayerT, StateT, ParamT, ClipT, LayerBackendT>?,
}

export type StateMachineConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT> = {
	name: string?,
	initialState: StateT,
	states: { StateDefinition<LayerT, StateT, ParamT, ClipT, LayerBackendT> },
	transitions: { TransitionRuntimeTypes.TransitionDefinition<StateT, ParamT> }?,
}

export type StateMachineDebugSnapshot<StateT> = MotionNodeTypes.MotionDebugSnapshot & {
	details: {
		activeState: StateT,
		transition: TransitionRuntimeTypes.TransitionDebugSnapshot<StateT>?,
	},
}

export type StateMachineRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT> = MotionNodeTypes.MotionNode<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
>

export type StateMachineRuntimeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT> = StateMachineRuntime<
	LayerT,
	StateT,
	ParamT,
	ClipT,
	LayerBackendT
> & {
	_name: string,
	_initialState: StateT,
	_activeState: StateT,
	_states: { [StateT]: StateDefinition<LayerT, StateT, ParamT, ClipT, LayerBackendT> },
	_stateOrder: { StateT },
	_transitions: { TransitionRuntimeTypes.TransitionDefinition<StateT, ParamT> },
	_transition: TransitionRuntimeTypes.TransitionRuntimeImpl<StateT, ParamT>?,
	_previousState: StateT?,

	_getState: (
		self: StateMachineRuntimeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		state: StateT
	) -> StateDefinition<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	_findTransition: (
		self: StateMachineRuntimeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		context: MotionNodeTypes.MotionEvaluateContext<LayerT, StateT, ParamT, ClipT, LayerBackendT>
	) -> TransitionRuntimeTypes.TransitionDefinition<StateT, ParamT>?,
	_startTransition: (
		self: StateMachineRuntimeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		context: MotionNodeTypes.MotionEvaluateContext<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		transition: TransitionRuntimeTypes.TransitionDefinition<StateT, ParamT>
	) -> (),
}

return {}

--!strict
--!optimize 2
--!native

local ParameterStoreTypes = require(script.Parent.Parent.controller.parameterStore)

export type TransitionConditionOp = "==" | "~=" | ">" | ">=" | "<" | "<=" | "truthy" | "falsy" | "trigger"

export type TransitionCondition<ParamT> = {
	parameter: ParamT,
	op: TransitionConditionOp,
	value: ParameterStoreTypes.ParameterValue?,
}

export type TransitionDefinition<StateT, ParamT> = {
	name: string?,
	from: StateT?,
	to: StateT,
	duration: number?,
	priority: number?,
	conditions: { TransitionCondition<ParamT> }?,
}

export type TransitionDebugSnapshot<StateT> = {
	name: string,
	fromState: StateT,
	toState: StateT,
	duration: number,
	elapsed: number,
	progress: number,
}

export type TransitionRuntime<StateT, ParamT> = {
	read update: (self: TransitionRuntime<StateT, ParamT>, timePosition: number) -> (),
	read getAlpha: (self: TransitionRuntime<StateT, ParamT>) -> number,
	read isComplete: (self: TransitionRuntime<StateT, ParamT>) -> boolean,
	read getDebugSnapshot: (self: TransitionRuntime<StateT, ParamT>) -> TransitionDebugSnapshot<StateT>,
}

export type TransitionRuntimeImpl<StateT, ParamT> = TransitionRuntime<StateT, ParamT> & {
	_definition: TransitionDefinition<StateT, ParamT>,
	_fromState: StateT,
	_toState: StateT,
	_duration: number,
	_startPosition: number,
	_timePosition: number,
}

return {}

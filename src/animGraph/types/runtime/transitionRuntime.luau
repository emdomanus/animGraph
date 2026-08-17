--!strict
--!optimize 2
--!native

local ParameterStoreTypes = require(script.Parent.Parent.controller.parameterStore)

export type TransitionConditionOp =
	"=="
	| "~="
	| ">"
	| ">="
	| "<"
	| "<="
	| "truthy"
	| "falsy"
	| "trigger"

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
	update: (self: TransitionRuntime<StateT, ParamT>, logicalPosition: number) -> (),
	getAlpha: (self: TransitionRuntime<StateT, ParamT>) -> number,
	isComplete: (self: TransitionRuntime<StateT, ParamT>) -> boolean,
	getDebugSnapshot: (self: TransitionRuntime<StateT, ParamT>) -> TransitionDebugSnapshot<StateT>,
}

export type TransitionRuntimeImpl<StateT, ParamT> = TransitionRuntime<StateT, ParamT> & {
	_definition: TransitionDefinition<StateT, ParamT>,
	_fromState: StateT,
	_toState: StateT,
	_duration: number,
	_startPosition: number,
	_logicalPosition: number,
}

return {}

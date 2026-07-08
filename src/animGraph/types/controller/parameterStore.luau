--!strict
--!optimize 2
--!native

export type ParameterValue = number | boolean | string

export type ParameterStore<ParamT> = {
	set: (self: ParameterStore<ParamT>, parameter: ParamT, value: ParameterValue) -> (),
	get: (self: ParameterStore<ParamT>, parameter: ParamT) -> ParameterValue?,
	setFloat: (self: ParameterStore<ParamT>, parameter: ParamT, value: number) -> (),
	getFloat: (self: ParameterStore<ParamT>, parameter: ParamT, fallback: number?) -> number,
	setBool: (self: ParameterStore<ParamT>, parameter: ParamT, value: boolean) -> (),
	getBool: (self: ParameterStore<ParamT>, parameter: ParamT, fallback: boolean?) -> boolean,
	setTrigger: (self: ParameterStore<ParamT>, parameter: ParamT) -> (),
	consumeTrigger: (self: ParameterStore<ParamT>, parameter: ParamT) -> boolean,
	clear: (self: ParameterStore<ParamT>) -> (),
	getDebugSnapshot: (self: ParameterStore<ParamT>) -> { [ParamT]: ParameterValue },
}

export type ParameterStoreImpl<ParamT> = ParameterStore<ParamT> & {
	_values: { [ParamT]: ParameterValue },
	_triggers: { [ParamT]: true },
}

return {}

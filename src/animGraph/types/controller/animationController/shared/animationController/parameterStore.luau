--!strict
--!optimize 2

export type ParameterValue = number | boolean | string

export type ParameterStore<ParamT> = {
	read set: (self: ParameterStore<ParamT>, parameter: ParamT, value: ParameterValue) -> (),
	read get: (self: ParameterStore<ParamT>, parameter: ParamT) -> ParameterValue?,
	read setFloat: (self: ParameterStore<ParamT>, parameter: ParamT, value: number) -> (),
	read getFloat: (self: ParameterStore<ParamT>, parameter: ParamT, fallback: number?) -> number,
	read setBool: (self: ParameterStore<ParamT>, parameter: ParamT, value: boolean) -> (),
	read getBool: (self: ParameterStore<ParamT>, parameter: ParamT, fallback: boolean?) -> boolean,
	read setTrigger: (self: ParameterStore<ParamT>, parameter: ParamT) -> (),
	read consumeTrigger: (self: ParameterStore<ParamT>, parameter: ParamT) -> boolean,
	read clear: (self: ParameterStore<ParamT>) -> (),
	read getDebugSnapshot: (self: ParameterStore<ParamT>) -> { [ParamT]: ParameterValue },
}

export type ParameterStoreImpl<ParamT> = ParameterStore<ParamT> & {
	_values: { [ParamT]: ParameterValue },
	_triggers: { [ParamT]: true },
}

return {}

--!strict
--!optimize 2
--!native

local Types = require(script.Parent.Parent.Parent.types.controller.parameterStore)

export type ParameterValue = Types.ParameterValue
export type ParameterStore<ParamT> = Types.ParameterStore<ParamT>
export type ParameterStoreImpl<ParamT> = Types.ParameterStoreImpl<ParamT>

local ParameterStore = {}
ParameterStore.__index = ParameterStore

function ParameterStore.new<ParamT>(defaults: { [ParamT]: ParameterValue }?): ParameterStoreImpl<ParamT>
	local self: ParameterStoreImpl<ParamT> = setmetatable({}, ParameterStore) :: any

	self._values = if defaults ~= nil then table.clone(defaults) else {}
	self._triggers = {}

	return self
end

function ParameterStore.set<ParamT>(self: ParameterStoreImpl<ParamT>, parameter: ParamT, value: ParameterValue): ()
	self._values[parameter] = value
	if self._triggers[parameter] then
		self._triggers[parameter] = nil
	end
end

function ParameterStore.get<ParamT>(self: ParameterStoreImpl<ParamT>, parameter: ParamT): ParameterValue?
	return self._values[parameter]
end

function ParameterStore.setFloat<ParamT>(self: ParameterStoreImpl<ParamT>, parameter: ParamT, value: number): ()
	self:set(parameter, value)
end

function ParameterStore.getFloat<ParamT>(self: ParameterStoreImpl<ParamT>, parameter: ParamT, fallback: number?): number
	local value = self._values[parameter]
	return if typeof(value) == "number" then value else fallback or 0
end

function ParameterStore.setBool<ParamT>(self: ParameterStoreImpl<ParamT>, parameter: ParamT, value: boolean): ()
	self:set(parameter, value)
end

function ParameterStore.getBool<ParamT>(self: ParameterStoreImpl<ParamT>, parameter: ParamT, fallback: boolean?): boolean
	local value = self._values[parameter]
	return if typeof(value) == "boolean" then value else fallback or false
end

function ParameterStore.setTrigger<ParamT>(self: ParameterStoreImpl<ParamT>, parameter: ParamT): ()
	self._values[parameter] = true
	self._triggers[parameter] = true
end

function ParameterStore.consumeTrigger<ParamT>(self: ParameterStoreImpl<ParamT>, parameter: ParamT): boolean
	if not self._triggers[parameter] then
		return false
	end

	self._triggers[parameter] = nil
	self._values[parameter] = false
	return true
end

function ParameterStore.clear<ParamT>(self: ParameterStoreImpl<ParamT>): ()
	self._values = {}
	self._triggers = {}
end

function ParameterStore.getDebugSnapshot<ParamT>(self: ParameterStoreImpl<ParamT>): { [ParamT]: ParameterValue }
	return table.clone(self._values)
end

return ParameterStore

--!strict
--!optimize 2
--!native

local Types = require(script.Parent.Parent.types.runtime.transitionRuntime)

export type TransitionConditionOp = Types.TransitionConditionOp
export type TransitionCondition<ParamT> = Types.TransitionCondition<ParamT>
export type TransitionDefinition<StateT, ParamT> = Types.TransitionDefinition<StateT, ParamT>
export type TransitionDebugSnapshot<StateT> = Types.TransitionDebugSnapshot<StateT>
export type TransitionRuntime<StateT, ParamT> = Types.TransitionRuntime<StateT, ParamT>
export type TransitionRuntimeImpl<StateT, ParamT> = Types.TransitionRuntimeImpl<StateT, ParamT>

local DEFAULT_DURATION = 0.2

local function optionNumber(value: number?, fallback: number): number
	return if value ~= nil then value else fallback
end

local TransitionRuntime = {}
TransitionRuntime.__index = TransitionRuntime

function TransitionRuntime.new<StateT, ParamT>(
	definition: TransitionDefinition<StateT, ParamT>,
	fromState: StateT
): TransitionRuntime<StateT, ParamT>
	local duration = math.max(optionNumber(definition.duration, DEFAULT_DURATION), 0)
	local self: TransitionRuntimeImpl<StateT, ParamT> = setmetatable({}, TransitionRuntime) :: any

	self._definition = definition
	self._fromState = fromState
	self._toState = definition.to
	self._duration = duration
	self._elapsed = if duration <= 0 then duration else 0

	return self
end

function TransitionRuntime.update<StateT, ParamT>(
	self: TransitionRuntimeImpl<StateT, ParamT>,
	dt: number
): ()
	self._elapsed = math.min(self._elapsed + math.max(dt, 0), self._duration)
end

function TransitionRuntime.getAlpha<StateT, ParamT>(
	self: TransitionRuntimeImpl<StateT, ParamT>
): number
	if self._duration <= 0 then
		return 1
	end

	return math.clamp(self._elapsed / self._duration, 0, 1)
end

function TransitionRuntime.isComplete<StateT, ParamT>(
	self: TransitionRuntimeImpl<StateT, ParamT>
): boolean
	return self:getAlpha() >= 1
end

function TransitionRuntime.getDebugSnapshot<StateT, ParamT>(
	self: TransitionRuntimeImpl<StateT, ParamT>
): TransitionDebugSnapshot<StateT>
	return {
		name = self._definition.name or (tostring(self._fromState) .. " -> " .. tostring(self._toState)),
		fromState = self._fromState,
		toState = self._toState,
		duration = self._duration,
		elapsed = self._elapsed,
		progress = self:getAlpha(),
	}
end

return TransitionRuntime

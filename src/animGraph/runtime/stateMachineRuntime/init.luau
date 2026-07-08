--!strict
--!optimize 2
--!native

local TransitionRuntime = require(script.Parent.Parent.runtime.transitionRuntime)
local Types = require(script.Parent.Parent.types.runtime.stateMachineRuntime)
local MotionNodeTypes = require(script.Parent.Parent.types.motions.motionNode)
local TransitionRuntimeTypes = require(script.Parent.Parent.types.runtime.transitionRuntime)

export type StateDefinition<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	Types.StateDefinition<LayerT, StateT, ParamT, ClipT, LayerBackendT>
export type StateMachineConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	Types.StateMachineConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT>
export type StateMachineRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	Types.StateMachineRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>
export type StateMachineRuntimeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT> =
	Types.StateMachineRuntimeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>

local StateMachineRuntime = {}
StateMachineRuntime.__index = StateMachineRuntime

local function compareValues(left: any, op: TransitionRuntimeTypes.TransitionConditionOp, right: any): boolean
	if op == "==" then
		return left == right
	elseif op == "~=" then
		return left ~= right
	elseif op == "truthy" then
		return left == true
	elseif op == "falsy" then
		return left == false or left == nil
	end

	if typeof(left) ~= "number" or typeof(right) ~= "number" then
		return false
	end

	if op == ">" then
		return left > right
	elseif op == ">=" then
		return left >= right
	elseif op == "<" then
		return left < right
	elseif op == "<=" then
		return left <= right
	end

	return false
end

local function transitionConditionsPass<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	transition: TransitionRuntimeTypes.TransitionDefinition<StateT, ParamT>,
	context: MotionNodeTypes.MotionEvaluateContext<LayerT, StateT, ParamT, ClipT, LayerBackendT>
): boolean
	local conditions = transition.conditions
	if conditions == nil or #conditions == 0 then
		return true
	end

	for _, condition in conditions do
		if condition.op ~= "trigger" then
			local value = context.getParameter(condition.parameter)
			if not compareValues(value, condition.op, condition.value) then
				return false
			end
		end
	end

	for _, condition in conditions do
		if condition.op == "trigger" and not context.consumeTrigger(condition.parameter) then
			return false
		end
	end

	return true
end

local function copyContextWithState<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	context: MotionNodeTypes.MotionEvaluateContext<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	state: StateT
): MotionNodeTypes.MotionEvaluateContext<LayerT, StateT, ParamT, ClipT, LayerBackendT>
	return {
		layer = context.layer,
		state = state,
		dt = context.dt,
		fadeTime = context.fadeTime,
		layerWeight = context.layerWeight,
		layerSpeed = context.layerSpeed,
		logicalPriority = context.logicalPriority,
		layerBackend = context.layerBackend,
		overrides = context.overrides,
		getParameter = context.getParameter,
		consumeTrigger = context.consumeTrigger,
		emitEvent = context.emitEvent,
	}
end

local function appendStateRequests<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	requests: { MotionNodeTypes.ClipRequest<LayerT, StateT, ClipT, LayerBackendT> },
	state: StateDefinition<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	context: MotionNodeTypes.MotionEvaluateContext<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	weight: number,
	fadeTime: number
): ()
	if weight <= 0 or state.motion == nil then
		return
	end

	local stateContext = copyContextWithState(context, state.id)
	stateContext.fadeTime = fadeTime

	local stateRequests = state.motion:evaluate(stateContext)
	for _, request in stateRequests do
		request.weight *= weight
		request.fadeTime = fadeTime
		requests[#requests + 1] = request
	end
end

local function sortTransitions<StateT, ParamT>(
	transitions: { TransitionRuntimeTypes.TransitionDefinition<StateT, ParamT> }
): { TransitionRuntimeTypes.TransitionDefinition<StateT, ParamT> }
	local sorted = table.clone(transitions)
	table.sort(sorted, function(left, right)
		return (left.priority or 0) > (right.priority or 0)
	end)

	return sorted
end

function StateMachineRuntime.new<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	config: StateMachineConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT>
): StateMachineRuntime<LayerT, StateT, ParamT, ClipT, LayerBackendT>
	local states: { [StateT]: StateDefinition<LayerT, StateT, ParamT, ClipT, LayerBackendT> } = {}
	local stateOrder: { StateT } = {}
	for _, state in config.states do
		assert(states[state.id] == nil, "duplicate state id")
		states[state.id] = state
		stateOrder[#stateOrder + 1] = state.id
	end
	assert(states[config.initialState] ~= nil, "initialState must exist in states")

	local self: StateMachineRuntimeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT> = setmetatable(
		{},
		StateMachineRuntime
	) :: any
	self._name = config.name or "StateMachine"
	self._initialState = config.initialState
	self._activeState = config.initialState
	self._states = states
	self._stateOrder = stateOrder
	self._transitions = sortTransitions(config.transitions or {})
	self._transition = nil
	self._previousState = nil

	return self
end

function StateMachineRuntime._getState<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: StateMachineRuntimeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	state: StateT
): StateDefinition<LayerT, StateT, ParamT, ClipT, LayerBackendT>
	local definition = self._states[state]
	assert(definition ~= nil, "unknown state")

	return definition
end

function StateMachineRuntime._findTransition<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: StateMachineRuntimeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	context: MotionNodeTypes.MotionEvaluateContext<LayerT, StateT, ParamT, ClipT, LayerBackendT>
): TransitionRuntimeTypes.TransitionDefinition<StateT, ParamT>?
	for _, transition in self._transitions do
		if
			transition.from == nil or transition.from == self._activeState
		then
			if transition.to == self._activeState then
				transitionConditionsPass(transition, context)
			elseif transitionConditionsPass(transition, context) then
				return transition
			end
		end
	end

	return nil
end

function StateMachineRuntime._startTransition<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: StateMachineRuntimeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	context: MotionNodeTypes.MotionEvaluateContext<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	transition: TransitionRuntimeTypes.TransitionDefinition<StateT, ParamT>
): ()
	local fromState = self._activeState
	local toState = transition.to

	self._previousState = fromState
	self._activeState = toState
	self._transition = TransitionRuntime.new(transition, fromState) :: any

	local transitionName = transition.name or (tostring(fromState) .. " -> " .. tostring(toState))
	context.emitEvent({
		name = "transitionStarted",
		layer = context.layer,
		fromState = fromState,
		toState = toState,
		transition = transitionName,
		progress = 0,
	})
	context.emitEvent({
		name = "stateExited",
		layer = context.layer,
		state = fromState,
		fromState = fromState,
		toState = toState,
		transition = transitionName,
	})
	context.emitEvent({
		name = "stateEntered",
		layer = context.layer,
		state = toState,
		fromState = fromState,
		toState = toState,
		transition = transitionName,
	})
end

function StateMachineRuntime.evaluate<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: StateMachineRuntimeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
	context: MotionNodeTypes.MotionEvaluateContext<LayerT, StateT, ParamT, ClipT, LayerBackendT>
): { MotionNodeTypes.ClipRequest<LayerT, StateT, ClipT, LayerBackendT> }
	local transition = self._transition
	if transition == nil then
		local nextTransition = self:_findTransition(context)
		if nextTransition ~= nil then
			self:_startTransition(context, nextTransition)
			transition = self._transition
		end
	end

	local requests: { MotionNodeTypes.ClipRequest<LayerT, StateT, ClipT, LayerBackendT> } = {}
	if transition ~= nil then
		transition:update(context.dt)

		local alpha = transition:getAlpha()
		local fromState = self._previousState
		if fromState ~= nil then
			appendStateRequests(requests, self:_getState(fromState), context, 1 - alpha, 0)
		end
		appendStateRequests(requests, self:_getState(self._activeState), context, alpha, 0)

		if transition:isComplete() then
			local snapshot = transition:getDebugSnapshot()
			context.emitEvent({
				name = "transitionEnded",
				layer = context.layer,
				fromState = snapshot.fromState,
				toState = snapshot.toState,
				transition = snapshot.name,
				progress = 1,
			})
			self._transition = nil
			self._previousState = nil
		end

		return requests
	end

	appendStateRequests(requests, self:_getState(self._activeState), context, 1, context.fadeTime)
	return requests
end

function StateMachineRuntime.getDebugSnapshot<LayerT, StateT, ParamT, ClipT, LayerBackendT>(
	self: StateMachineRuntimeImpl<LayerT, StateT, ParamT, ClipT, LayerBackendT>
): MotionNodeTypes.MotionDebugSnapshot
	local children: { MotionNodeTypes.MotionDebugSnapshot } = {}
	local previousState = self._previousState
	if previousState ~= nil then
		local previousDefinition = self._states[previousState]
		if previousDefinition ~= nil and previousDefinition.motion ~= nil then
			local child = previousDefinition.motion:getDebugSnapshot()
			local details: { [string]: any } = child.details or {}
			child.details = details
			details.state = previousState
			details.role = "previous"
			children[#children + 1] = child
		end
	end

	local activeDefinition = self._states[self._activeState]
	if activeDefinition ~= nil and activeDefinition.motion ~= nil then
		local child = activeDefinition.motion:getDebugSnapshot()
		local details: { [string]: any } = child.details or {}
		child.details = details
		details.state = self._activeState
		details.role = "active"
		children[#children + 1] = child
	end

	return {
		kind = "StateMachine",
		name = self._name,
		details = {
			activeState = self._activeState,
			transition = if self._transition ~= nil then self._transition:getDebugSnapshot() else nil,
		},
		children = if #children > 0 then children else nil,
	}
end

return StateMachineRuntime

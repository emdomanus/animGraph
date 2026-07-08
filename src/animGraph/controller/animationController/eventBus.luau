--!strict
--!optimize 2
--!native

local Types = require(script.Parent.Parent.Parent.types.controller.eventBus)

export type Release = Types.Release
export type AnimationEventName = Types.AnimationEventName
export type AnimationEvent<LayerT, StateT> = Types.AnimationEvent<LayerT, StateT>
export type AnimationEventCallback<LayerT, StateT> = Types.AnimationEventCallback<LayerT, StateT>
export type EventBus<LayerT, StateT> = Types.EventBus<LayerT, StateT>
export type EventBusImpl<LayerT, StateT> = Types.EventBusImpl<LayerT, StateT>

local EventBus = {}
EventBus.__index = EventBus

function EventBus.new<LayerT, StateT>(): EventBusImpl<LayerT, StateT>
	local self: EventBusImpl<LayerT, StateT> = setmetatable({}, EventBus) :: any

	self._listeners = {}

	return self
end

function EventBus.on<LayerT, StateT>(
	self: EventBusImpl<LayerT, StateT>,
	name: AnimationEventName,
	callback: AnimationEventCallback<LayerT, StateT>
): Release
	local listeners = self._listeners[name]
	if listeners == nil then
		listeners = {}
		self._listeners[name] = listeners
	end

	listeners[#listeners + 1] = callback

	local released = false
	return function()
		if released then
			return
		end
		released = true

		local activeListeners = self._listeners[name]
		if activeListeners == nil then
			return
		end

		for index = #activeListeners, 1, -1 do
			if activeListeners[index] == callback then
				table.remove(activeListeners, index)
				break
			end
		end
	end
end

function EventBus.emit<LayerT, StateT>(
	self: EventBusImpl<LayerT, StateT>,
	event: AnimationEvent<LayerT, StateT>
): ()
	local listeners = self._listeners[event.name]
	if listeners == nil then
		return
	end

	local snapshot = table.clone(listeners)
	for _, callback in snapshot do
		callback(event)
	end
end

function EventBus.clear<LayerT, StateT>(self: EventBusImpl<LayerT, StateT>): ()
	self._listeners = {}
end

return EventBus

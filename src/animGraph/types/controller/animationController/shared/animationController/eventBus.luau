--!strict
--!optimize 2

local DefTypes = require(script.Parent.Parent.Parent.Parent.Parent.def.animation.shared.animation)

export type Release = DefTypes.Release

export type AnimationEventName =
	"stateEntered"
	| "stateExited"
	| "transitionStarted"
	| "transitionEnded"
	| "trackCompleted"

export type AnimationEvent<LayerT, StateT> = {
	name: "stateEntered",
	layer: LayerT,
	state: StateT,
	fromState: StateT?,
	toState: StateT,
	transition: string,
} | {
	name: "stateExited",
	layer: LayerT,
	state: StateT,
	fromState: StateT?,
	toState: StateT,
	transition: string,
} | {
	name: "transitionStarted",
	layer: LayerT,
	fromState: StateT?,
	toState: StateT,
	transition: string,
	progress: number,
} | {
	name: "transitionEnded",
	layer: LayerT,
	fromState: StateT?,
	toState: StateT,
	transition: string,
	progress: number,
} | DefTypes.TrackCompletedEvent<LayerT, StateT>

export type AnimationEventCallback<LayerT, StateT> = (event: AnimationEvent<LayerT, StateT>) -> ()

export type EventBus<LayerT, StateT> = {
	read on: (
		self: EventBus<LayerT, StateT>,
		name: AnimationEventName,
		callback: AnimationEventCallback<LayerT, StateT>
	) -> Release,
	read emit: (self: EventBus<LayerT, StateT>, event: AnimationEvent<LayerT, StateT>) -> (),
	read clear: (self: EventBus<LayerT, StateT>) -> (),
}

export type EventBusImpl<LayerT, StateT> = EventBus<LayerT, StateT> & {
	_listeners: { [AnimationEventName]: { AnimationEventCallback<LayerT, StateT> } },
}

return {}

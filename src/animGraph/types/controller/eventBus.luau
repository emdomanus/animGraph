--!strict
--!optimize 2
--!native

export type Release = () -> ()

export type AnimationEventName =
	"stateEntered"
	| "stateExited"
	| "transitionStarted"
	| "transitionEnded"
	| "motionRequested"

export type AnimationEvent<LayerT, StateT> = {
	name: AnimationEventName,
	layer: LayerT,
	state: StateT?,
	fromState: StateT?,
	toState: StateT?,
	transition: string?,
	progress: number?,
}

export type AnimationEventCallback<LayerT, StateT> = (event: AnimationEvent<LayerT, StateT>) -> ()

export type EventBus<LayerT, StateT> = {
	on: (
		self: EventBus<LayerT, StateT>,
		name: AnimationEventName,
		callback: AnimationEventCallback<LayerT, StateT>
	) -> Release,
	emit: (self: EventBus<LayerT, StateT>, event: AnimationEvent<LayerT, StateT>) -> (),
	clear: (self: EventBus<LayerT, StateT>) -> (),
}

export type EventBusImpl<LayerT, StateT> = EventBus<LayerT, StateT> & {
	_listeners: { [AnimationEventName]: { AnimationEventCallback<LayerT, StateT> } },
}

return {}

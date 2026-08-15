--!strict
--!optimize 2
--!native

export type AnimationPosition =
	{ kind: "seconds", value: number }
	| { kind: "normalized", value: number }

export type TimeSource = () -> number

export type LogicalPositionReader = (time: number) -> number

export type Release = () -> ()

export type TrackCompletedEvent<LayerT, StateT> = {
	name: "trackCompleted",
	trackKey: string,
	layer: LayerT,
	state: StateT?,
}

return {}

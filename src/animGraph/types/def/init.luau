--!strict
--!optimize 2
--!native

export type AnimationPosition =
	{ kind: "seconds", value: number }
	| { kind: "normalized", value: number }

export type LogicalTimeSample = {
	position: number,
	addressRevision: number,
}

export type LogicalTimeReader = (sampleTime: number) -> LogicalTimeSample

export type Release = () -> ()

export type TrackCompletedEvent<LayerT, StateT> = {
	name: "trackCompleted",
	trackKey: string,
	layer: LayerT,
	state: StateT?,
}

return {}

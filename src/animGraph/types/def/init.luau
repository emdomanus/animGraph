--!strict
--!optimize 2
--!native

export type AnimationPosition = { kind: "seconds", value: number } | { kind: "normalized", value: number }

export type TimeSample = {
	position: number,
	rate: number,
}

export type TimeReader = (sampleTime: number) -> TimeSample

export type Release = () -> ()

export type TrackCompletedEvent<LayerT, StateT> = {
	name: "trackCompleted",
	trackKey: string,
	layer: LayerT,
	state: StateT?,
}

return {}

# Canonical Definitions

Source: `src/animGraph/types/def/init.luau`

These definitions are declared once and re-exported through the package type
barrels.

## AnimationPosition

```luau
export type AnimationPosition =
	{ kind: "seconds", value: number }
	| { kind: "normalized", value: number }
```

Seconds are finite and non-negative. Normalized values are finite and within
`[0, 1]`. This union addresses physical clip position; it is not logical graph
phase. `offsetTrackPosition` instead accepts finite signed clip seconds.

## LogicalTimeSample and LogicalTimeReader

```luau
export type LogicalTimeSample = {
	position: number,
	addressRevision: number,
}

export type LogicalTimeReader = (sampleTime: number) -> LogicalTimeSample
```

The caller passes one finite monotonic coordinate to
`controller:update(sampleTime)`. Each distinct selected reader receives it once
and must return finite fields.

`position` is the reader's source address. `addressRevision` changes only for a
discontinuous re-address, not an ordinary continuous rate change. The layer
runtime turns reader samples into monotonic logical graph phase:

- first sample: phase remains zero;
- forward movement with the same revision: add the exact difference;
- stationary/backward movement: hold phase and rebase the source baseline;
- revision or reader change: hold phase and rebase.

## TrackCompletedEvent

```luau
export type TrackCompletedEvent<LayerT, StateT> = {
	name: "trackCompleted",
	trackKey: string,
	layer: LayerT,
	state: StateT?,
}
```

The event identifies one completed non-looping physical generation without
exposing a Roblox track. Native and sampled backend strategies share the same
event contract.

## Release

```luau
export type Release = () -> ()
```

Completion and controller-event bindings return idempotent release functions.

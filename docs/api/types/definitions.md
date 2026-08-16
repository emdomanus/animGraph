# Canonical Definitions

Source: `src/animGraph/types/def/init.luau`

These definitions are declared once and re-exported through the type and package
barrels.

## AnimationPosition

```luau
export type AnimationPosition =
	{ kind: "seconds", value: number }
	| { kind: "normalized", value: number }
```

Seconds are finite and non-negative. Normalized values are finite and in the
inclusive interval `[0, 1]`. The union addresses native clip position for
initial materialization or live backend positioning; it is not the graph's
logical-position sample.

`offsetTrackPosition` deliberately adds no new public position type. Its
`deltaSeconds` argument is a finite signed number of native clip seconds and is
an atomic relative mutation of one eligible active generation. Each delta and
any accumulated unresolved offset must remain finite and representable. It is
distinct from the absolute `AnimationPosition` union. AnimGraph exposes neither a public
position getter nor pending/physical track state.

## TimeSource

```luau
export type TimeSource = () -> number
```

A controller samples its source exactly once per successful update attempt. The
finite result is one shared time passed to all selected readers. AnimGraph does
not integrate it, treat it as a logical position, or own its lifetime.

## LogicalPositionReader

```luau
export type LogicalPositionReader = (time: number) -> number
```

A reader converts the supplied time into one finite logical position. Each
distinct selected function is sampled at most once per update. AnimGraph derives
delta from consecutive per-activation positions; it does not accept a rate,
timescale, clock, mutable timeline, or reset/rebase operation.

## TrackCompletedEvent

```luau
export type TrackCompletedEvent<LayerT, StateT> = {
	name: "trackCompleted",
	trackKey: string,
	layer: LayerT,
	state: StateT?,
}
```

The event identifies one completed non-looping materialized generation without
exposing a Roblox track or signal. Natural forward upper-end playback, natural
reverse lower-end playback, and accepted initial/live boundaries whose desired
signed speed points outward emit it exactly once after backend state is
committed. Inward or zero-speed boundary placement, looping addressing, and
explicit retirement do not emit it.

## Release

```luau
export type Release = () -> ()
```

Completion and controller-event bindings return an idempotent release function.

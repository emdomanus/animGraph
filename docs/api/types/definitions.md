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
logical-time sample.

## TimeSource

```luau
export type TimeSource = () -> number
```

A controller samples its source exactly once per successful update attempt. The
finite result is a shared coordinate passed to all selected readers. AnimGraph
does not integrate it, treat it as a logical position, or own its lifetime.

## LogicalTimeReader

```luau
export type LogicalTimeReader = (frameNow: number) -> number
```

A reader returns one finite logical position. Each distinct selected function is
sampled at most once per update. AnimGraph derives delta from consecutive
per-activation samples; it does not accept a rate, timescale, clock, mutable
timeline, or reset/rebase operation.

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
exposing a Roblox track or signal. Natural terminal playback and accepted
initial/live terminal positioning emit it exactly once after backend state is
committed. Explicit retirement does not emit it.

## Release

```luau
export type Release = () -> ()
```

Completion and controller-event bindings return an idempotent release function.

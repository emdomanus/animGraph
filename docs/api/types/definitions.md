# Canonical Definitions

Source: `src/animGraph/types/def/animation/shared/animation.luau`

These definitions are declared once and re-exported directly by the package
root. Roblox playback descriptors (`AssetId`, `RobloxLayerBackend`, and
`LogicalPriorityBand`) live in
`src/animGraph/types/def/animationPlayback/shared/robloxPlayback.luau`.

## AnimationPosition

```luau
export type AnimationPosition =
	{ kind: "seconds", value: number }
	| { kind: "normalized", value: number }
```

Seconds are finite and non-negative. Normalized values are finite and within
`[0, 1]`. This union addresses physical clip position; it is not the graph's
time-basis position. `offsetTrackPosition` instead accepts finite signed clip
seconds.

## TimeSample and TimeReader

```luau
export type TimeSample = {
	position: number,
	rate: number,
}

export type TimeReader = (sampleTime: number) -> TimeSample
```

The caller passes one finite monotonic coordinate to
`controller:update(sampleTime)`. Each distinct selected reader receives it once
and must return finite fields.

`position` is the literal coordinate used by graph, transition, custom-motion,
and sampled physical evaluation. `rate` is the caller's atomic rate sample; it
composes optimized native playback and terminal direction. AnimGraph does not
derive one field from the other or attach discontinuity semantics to either.
The caller owns continuity mapping and any native physical re-addressing.

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

## TrackMarkerSource

`TrackMarkerSource<LayerT, StateT, ClipT>` is the backend-independent observation
surface passed to `onMarker` callbacks. It exposes readonly methods
`getTrackKey(): string`, `getGeneration(): number`, `getLayer(): LayerT`,
`getState(): StateT?`, and `getClip(): ClipT`. The existing playback object implements
this surface directly. It provides no playback mutations or Roblox instances.

Specific-track callbacks receive only `value: string`; all-track callbacks receive
`(track: TrackMarkerSource<LayerT, StateT, ClipT>, value: string)`. There is no marker
event record type or per-event wrapper. Both subscription methods return `Release`.

# VoxelMMO Migration Research

This document records the consumer boundary. It does not authorize edits in
VoxelMMO or import game systems into AnimGraph.

## Ownership boundary

```text
Tempo <- TemporalService <- presentation/CharacterAnimator -> AnimGraph
```

VoxelMMO owns:

- the RunService/TemporalService pump and `sampleTime` selection;
- clock-domain binding and atomic `TimeReader` construction;
- whether discontinuities are filtered, preserved, or continuity-mapped;
- character/layer/content policy and already-resolved physical speed;
- explicit native physical seeks/offsets after a clock re-address;
- any pre-materialization physical position command and retry;
- target rematerialization and stable game-facing playback handles.

AnimGraph owns transactional graph evaluation, literal time-sample propagation,
physical generations, and the selected backend strategy. It imports nothing from
VoxelMMO.

## Integration shape

`CharacterAnimator` should construct one default character reader and optional
layer or active-play overrides, then schedule:

```luau
controller:update(sampleTime)
```

The same coordinate reaches `backend:apply(sampleTime, requests)`. A reader
returns one atomic position/rate sample:

```luau
local reader: AnimGraph.TimeReader = function(sampleTime)
	local timing = binding:sample(sampleTime)
	return {
		position = timing.position,
		rate = timing.rate,
	}
end
```

AnimGraph observes both fields literally. `CharacterAnimator` or its timing
binding must decide whether a timeline jump should remain visible or be
continuity-mapped. In `nativeRate` mode, a position jump alone cannot safely
re-address an existing Roblox track; issue `setTrackPosition` or
`offsetTrackPosition` when physical playback must move.

Graph-intent operations are visible on the next update. `CharacterAnimator`
should not assume that `play` immediately creates a physical generation. If it
has a pre-materialization position command, retain it and issue
`setTrackPosition` once the update has materialized the generation. That call
remains synchronous and its boolean identifies acceptance by the current
generation.

## Layer and speed composition

VoxelMMO categories such as base locomotion, stance, block, action, and reaction
map to caller-defined AnimGraph layers. Reader precedence is controller default,
then layer override, then active-play override.

Graph time position and physical clip speed are independent:

- a discrete action may use an action-clock reader and one already-resolved
  signed clip speed;
- locomotion may use character/world time position and velocity-derived
  physical speed;
- two characters may share an action reader without sharing unrelated layers;
- negative physical speed never means reverse state-machine traversal.

The request's pre-clock signed speed contains authored clip speed, layer speed,
and ordinary playback modifiers. Native playback then uses
`request.speed * timeSample.rate`; sampled playback uses position differences
and request speed, with rate supplying terminal direction. Do not derive rate
from successive positions.

## Backend selection

Execution strategy belongs to backend construction, not authored content:

- use `nativeRate` when Roblox native advancement and marker behavior are
  desired;
- use `sampledPosition` when exact coordinate-to-physical-position evaluation
  is required and its Studio constraints are acceptable.

The choice does not alter graph evaluation semantics. VoxelMMO should choose a
strategy per backend/Animator lifetime rather than switch individual layers or
plays.

## Out of scope

- editing TemporalService, CharacterAnimator, or network schemas here;
- stable VoxelMMO handles or end-reason policy;
- marker/root-motion emulation for sampled playback;
- package publication or dependency-pin updates.

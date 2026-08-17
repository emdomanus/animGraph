# VoxelMMO Migration Research

This document records the consumer boundary. It does not authorize edits in
VoxelMMO or import game systems into AnimGraph.

## Ownership boundary

```text
Tempo <- TemporalService <- presentation/CharacterAnimator -> AnimGraph
```

VoxelMMO owns:

- the RunService/TemporalService pump and `sampleTime` selection;
- clock-domain binding, continuous rate policy, and discontinuity detection;
- `LogicalTimeReader` construction and `addressRevision` increments;
- character/layer/content policy and already-resolved physical speed;
- any pre-materialization physical position command and retry;
- target rematerialization and stable game-facing playback handles.

AnimGraph owns transactional graph evaluation, logical phase rebasing, physical
generations, and the selected backend strategy. It imports nothing from
VoxelMMO.

## Integration shape

`CharacterAnimator` should construct one default character reader and optional
layer or active-play overrides, then schedule:

```luau
controller:update(sampleTime)
```

The same coordinate reaches `backend:apply(sampleTime, requests)`. A reader
returns its logical source address and revision:

```luau
local reader: AnimGraph.LogicalTimeReader = function(sampleTime)
	local timing = binding:sample(sampleTime)
	return {
		position = timing.position,
		addressRevision = timing.addressRevision,
	}
end
```

Ordinary rate changes must remain continuous and keep the same revision.
Teleporting/re-addressing a timeline increments the revision. AnimGraph then
holds graph phase and adopts the new source baseline.

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

Logical graph phase and physical clip speed are independent:

- a discrete action may use an action-clock reader and one already-resolved
  signed clip speed;
- locomotion may use character/world logical phase and velocity-derived
  physical speed;
- two characters may share an action reader without sharing unrelated layers;
- negative physical speed never means reverse state-machine traversal.

Do not multiply a reader's source movement by the physical speed again.

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

# VoxelMMO Migration Research

This document records consumer context. It does not expand AnimGraph's package
policy or authorize changes in VoxelMMO.

## Dependency Boundary

VoxelMMO should own character timing bindings, clock selection, effective native
speed, discontinuity classification, target rematerialization, and stable
content-facing playback handles. It adapts that state to AnimGraph's plain
`TimeSource`, `LogicalPositionReader`, layer/play options, and already-resolved
request speeds.

```text
Tempo <- TemporalService <- VoxelMMO presentation -> CharacterAnimator -> AnimGraph
```

AnimGraph imports nothing from the consumer side of that boundary.

## Layer Mapping

VoxelMMO categories such as base locomotion, stance, block, action, and reaction
map to caller-defined AnimGraph layers. Clip keys, animation asset resolution,
procedural selection, hitstop policy, and combat semantics remain game-owned.

## Sampled Timing Composition

`CharacterAnimator` should provide a default character reader and select any
layer or active-entry replacement. It schedules `controller:update()` every
frame, even when animation intent is otherwise unchanged.

Graph logical delta and native playback speed are separate:

- a discrete animation can select a logical reader backed by its timing binding
  and submit a native speed already resolved from authored speed and timing rate;
- motion-derived locomotion can submit a velocity-derived native speed without
  multiplying the character timing rate again;
- a sequence can give two characters one shared action reader without changing
  either character's unrelated layer readers.

On a classified discontinuity, VoxelMMO will eventually rebase its monotonic
reader adapter and use absolute `setTrackPosition` when it owns the resolved
address. CP-AG-P adds atomic `offsetTrackPosition` for relative reconciliation
that must remain bound to one active generation, including while Roblox length
is unresolved. These are package operations only; this checkpoint adds no
consumer migration, hitstop, or VoxelMMO policy.

## Out of Scope Here

- editing VoxelMMO or Tempo;
- importing their types into AnimGraph;
- stable VoxelMMO playback handles or end-reason dispatch;
- presentation sequence and target-rematerialization implementation;
- package publication or pin updates.

# VoxelMMO Migration

This page is for migrating the current VoxelMMO animator to AnimGraph. It is not a
promise that AnimGraph should absorb every VoxelMMO-specific convenience API.

Use AnimGraph as the primitive animation controller. Put game-specific naming,
stable id resolution, hitstop policy, procedural solver stacks, and ability
semantics in a VoxelMMO adapter above it.

## Old Shape

The current VoxelMMO animator is category-oriented. It owns concepts like:

- `idle`;
- `locomotion`;
- `stance`;
- `block`;
- `transition`;
- `lowAction`;
- `action`;
- `reaction`.

It also provides helpers for:

- play by category;
- play by stable id/key;
- category stacks and release handles;
- category fades and priorities;
- hitstop;
- speed and time-position mutation;
- procedural selection;
- playback metadata queries.

## New Shape

In AnimGraph, categories become typed layers:

```luau
type Layer =
	"base"
	| "stance"
	| "block"
	| "transition"
	| "lowAction"
	| "action"
	| "reaction"
```

Clip keys stay game-owned:

```luau
type Clip =
	"idle"
	| "walk"
	| "run"
	| "slash_01"
	| "block_idle"
```

State names are authored/debug labels:

```luau
type State =
	"locomotion"
	| "stanceIdle"
	| "blocking"
	| "attacking"
	| "reacting"
```

Parameters are gameplay inputs:

```luau
type Param =
	"moveSpeed"
	| "moveX"
	| "moveY"
	| "grounded"
	| "attack"
	| "clearAction"
```

## Adapter Boundary

Create a VoxelMMO-owned adapter, for example `VoxelAnimationHost` or
`CharacterAnimationPresenter`, that owns the translation from old game language
to AnimGraph calls.

```text
Voxel character / visualizer
   |
   | playAction("slash_01"), setMoveSpeed(12), pushHitstop(...)
   v
Voxel animation adapter
   |
   | controller:setFloat, controller:play, controller:setLayerSpeed
   v
AnimGraph AnimationController
   |
   v
RobloxAnimatorBackend
```

AnimGraph should not learn what a sword slash, species variant, or combat reaction
means. The adapter should.

## Mapping Guide

| VoxelMMO concept | AnimGraph equivalent |
| --- | --- |
| category | layer |
| category priority | layer logical priority plus optional Roblox priority |
| category fade config | layer `defaultFadeIn` / `defaultFadeOut` |
| `playInCategory` | `controller:play(layer, motion, options?)` |
| stable animation key | caller-owned `ClipT` resolved by backend config |
| locomotion solver | blend node plus parameters, or adapter-selected motion |
| category speed | `controller:setLayerSpeed(layer, rate)` |
| category weight | `controller:setLayerWeight(layer, weight)` |
| stop category | `controller:stopLayer(layer, fadeTime?)` |
| playback snapshot | `controller:getDebugSnapshot()` |
| action trigger | parameter trigger into state machine |
| hitstop | adapter-level temporary speed modifier |

## What AnimGraph Already Covers

AnimGraph already covers the core replacement surface:

- typed layers;
- layer weights;
- layer playback rates;
- logical priority;
- Roblox priority override;
- layer default fades;
- clip playback;
- 1D/2D blend trees;
- state machines;
- transition conditions;
- trigger parameters;
- event dispatch;
- debug snapshots;
- backend abstraction.

That is enough to represent the old animator's main playback behavior with a new
call surface.

## What Should Stay Above AnimGraph

Keep these in the VoxelMMO adapter unless they become clearly game-agnostic:

- species/variant/local-key animation resolution;
- procedural locomotion/stance/block selection policies;
- category stack handles with VoxelMMO-specific rules;
- hitstop catch-up policy;
- combat timing markers;
- ability names and action ids;
- socket/anatomy integration;
- VFX and sound sequencing;
- damage and hitbox events.

## Potential Future AnimGraph Additions

These may be worth adding to AnimGraph after the first migration pass:

- marker forwarding through controller events;
- exit-time transition conditions;
- transition interruption policy;
- time-position query support in backend snapshots;
- a small reusable layer stack helper;
- backend-neutral layer masks for future custom solvers.

Avoid adding all of these before migration. Migrate one representative character
path first, then promote only the primitives that repeat cleanly.

## Suggested Migration Slice

1. Build a VoxelMMO adapter that constructs `RobloxAnimatorBackend` and
   `AnimationController`.
2. Map old categories to AnimGraph layers.
3. Port locomotion to a `Blend1DNode` or adapter-selected motion.
4. Port one action flow to an action state machine.
5. Replace old debug reads with `getDebugSnapshot()`.
6. Add only the missing adapter helpers needed by real gameplay.

This keeps the AnimGraph package generic while letting VoxelMMO keep its richer
character semantics.


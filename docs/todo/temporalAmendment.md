# Absolute-Time Evaluation Amendment

**Status:** implemented in the unreleased library contract. Deterministic and
static gates are covered by repository verification. Real Roblox behavior for
the `sampledPosition` strategy remains an explicit Studio gate.

This amendment replaces frame-delta accumulation with a caller-owned time
basis. It intentionally contains no discontinuity detector, revision counter,
source baseline, or automatic reader-replacement reconciliation.

## Ownership decision

The caller owns:

- scheduling `controller:update(sampleTime)`;
- constructing time and clock mappings;
- deciding whether jumps are preserved, filtered, or continuity-mapped;
- continuity offsets when changing readers;
- synchronous native seeks/offsets when physical playback must be re-addressed.

AnimGraph owns:

- selecting and sampling the effective time reader;
- graph evaluation on every accepted controller update;
- physical speed composition;
- native-rate or sampled-position execution;
- graph, generation, completion, and teardown lifecycle.

No VoxelMMO clock, timing service, discontinuity abstraction, or second
playback owner belongs in this package.

## Public time contract

```luau
export type TimeSample = {
	position: number,
	rate: number,
}

export type TimeReader = (sampleTime: number) -> TimeSample
```

`controller:update(sampleTime)` requires a finite, nondecreasing controller
coordinate. Equal values are legal and allow newly staged graph intent to be
evaluated without changing a reader position. Backward controller coordinates
are rejected.

Reader precedence is:

```text
controller default -> layer override -> active-play override
```

Every distinct selected reader is called exactly once per accepted update with
the exact controller coordinate. Position and rate are returned together so
they describe one source observation. Both must be finite. Invalid samples
reject the entire update before command commit or backend mutation.

There are no arbitrary motion-node or subtree readers. Runtime reader changes
use `setDefaultTimeReader`, `setLayerTimeReader`, and
`setActivePlayTimeReader` and take effect with other next-update graph intent.

## Literal evaluation

`TimeSample.position` is authoritative. The controller passes it through
`MotionEvaluateContext.timePosition` and `ClipRequest.timePosition` on every
evaluation. Blends and custom motions can evaluate curves against that literal
coordinate.

AnimGraph does not:

- integrate `dt`;
- derive rate from consecutive positions;
- classify a jump as a seek or ordinary progression;
- discard forward or backward jumps;
- make reader replacement continuous;
- maintain an address revision or source baseline.

If a consumer wants continuity, its reader must already return a continuous
mapping. A replacement reader's first position is observed directly.

## State-machine boundary

State-machine transitions remain forward-only discrete state. A transition
stores a time-position anchor and derives progress from the current literal
position. Equal or held positions hold progress. A forward jump advances
directly.

If an active transition observes a lower position, it shifts its start anchor
by the same difference. This preserves elapsed progress rather than reversing
state or stalling behind the old anchor. Replaying the same stateful runtime
does not inject a synthetic phase-zero sample, so replay cannot corrupt an
active transition.

Signed clip speed, reader rate, and explicit physical positioning do not rewind
the state machine.

## Commands and lifecycle

Graph-intent commands take effect on the next valid update:

- play and stop;
- parameters, weights, speeds, priorities, and layer backend data;
- time-reader changes.

`setTrackPosition` and `offsetTrackPosition` remain synchronous commands
against the current active physical generation. Their boolean reports whether
that generation accepted the command. `clear` and `destroy` remain immediate
lifecycle boundaries.

Borrowed readers and graph-event callbacks may call back into the controller.
A minimal lifecycle epoch invalidates the in-flight update if either callback
calls `clear` or `destroy`, preventing captured commands or requests from
restoring cleared state.

## Physical playback strategies

`BackendPositionMode` is fixed for a backend's lifetime:

```luau
export type BackendPositionMode = "nativeRate" | "sampledPosition"
```

It is a backend execution strategy, not a layer, play, or authored-content
option. Both modes share one generation/completion/lifecycle manager.

### nativeRate

The request's pre-clock signed speed contains authored clip speed, layer speed,
and ordinary playback modifiers. Native playback composes:

```luau
finalNativeSpeed = request.speed * request.timeRate
```

Roblox advances the track through `Play` and `AdjustSpeed`. Reverse-start
positioning and terminal direction use the final signed speed. An unchanged
effective speed is idempotent: controller updates do not rewrite
`TimePosition` or churn native properties every frame.

A position jump alone cannot tell native playback whether an already-running
track should seek. When physical re-addressing is intended, the caller uses
`setTrackPosition` or `offsetTrackPosition`. AnimGraph adds no tolerances,
prediction comparison, reconciliation, or retry loop.

### sampledPosition

Roblox runs the owned track at native speed zero. Physical phase is evaluated
from the supplied position:

```luau
physicalPosition = physicalAnchor
	+ request.speed * (request.timePosition - timeAnchor)
```

Speed or loop-policy changes first evaluate and rebase using the old values,
then adopt the new request. Forward, held, reverse, and nonlinear reader
positions are literal. `request.timeRate` does not advance sampled phase, but
the composed sign `request.speed * request.timeRate` supplies terminal
direction where a non-looping boundary needs it.

Derived arithmetic is preflighted for finiteness before accepted playback state
is poisoned. Backend apply depth is restored on every failure path so an error
cannot permanently suppress completion dispatch.

Roblox still owns asset loading, weight fades, pose application, markers, and
root motion. Deterministic position arithmetic does not prove those engine
behaviors under per-update `TimePosition` writes.

## Core implementation surface

| Concern | Main files |
| --- | --- |
| Canonical time types and package exports | `src/animGraph/types/def/animation/shared/animation.luau`, `src/init.luau` |
| Reader resolution and transaction | `src/animGraph/controller/animationController/shared/animationController/init.luau` |
| Layer propagation | `src/animGraph/runtime/layerRuntime/shared/layerRuntime.luau` |
| Motion/request contract | `src/animGraph/types/motions/motionNode/shared/motionNode.luau`, `src/animGraph/motions/clipNode/shared/clipNode.luau` |
| Forward-only transitions | `src/animGraph/runtime/transitionRuntime/shared/transitionRuntime.luau`, `src/animGraph/runtime/stateMachineRuntime/shared/stateMachineRuntime.luau` |
| Request validation | `src/animGraph/utils/requestValidation/shared/requestValidation.luau` |
| Native strategy | `src/animGraph/backends/robloxAnimatorBackend/shared/robloxAnimatorBackend/animPlayback.luau` |
| Sampled strategy | `src/animGraph/backends/robloxAnimatorBackend/shared/robloxAnimatorBackend/sampledAnimPlayback.luau` |
| Shared backend lifecycle | `src/animGraph/backends/robloxAnimatorBackend/shared/robloxAnimatorBackend/init.luau` |

## Deterministic proofs

The Lune suites cover:

- one atomic sample per distinct selected reader and precedence;
- literal position use, reader replacement, signed/zero rate, and invalid-batch
  rejection;
- native speed/rate composition and unchanged-request idempotence;
- sampled forward, held, reverse, nonlinear, and speed-rebase behavior;
- synchronous graph-neutral physical positioning;
- replay-safe transitions and callback-driven lifecycle invalidation;
- sampled numeric failure and apply-depth recovery.

See [Verification](/guides/verification) for commands and the current test
count.

## Remaining gate

The deterministic and static contract does not close the Roblox engine gate for
`sampledPosition`. Before production use, run the Studio checklist for actual
pose sampling, fade behavior, completion, markers/keyframes, root motion, and
cleanup. Historical CP-AG-R and CP-AG-P native operator records remain valid
and separate; this amendment does not claim a sampled-position Studio pass.

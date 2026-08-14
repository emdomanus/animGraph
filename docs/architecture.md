# Architecture

AnimGraph is an authored, sampled graph runtime. The caller schedules each
sample; the controller owns coherent logical-time sampling and graph evaluation;
the backend owns concrete animation materialization.

## Ownership

```text
Caller
  owns update phase and cadence
  owns TimeSource and LogicalTimeReader functions
  owns timing/discontinuity/rate policy
  owns AnimationController and injected backend
    AnimationController owns ParameterStore, EventBus, and LayerRuntime objects
      LayerRuntime owns one active play and its logical baseline
    RobloxAnimatorBackend owns materialized AnimationTrack state
```

AnimGraph never subscribes to the supplied functions and never destroys them.
It imports no Tempo, TemporalService, clock, timing-binding, or consumer types.

## Dependency Direction

```text
consumer policy -> AnimGraph controller -> motion/runtime types -> backend
                                                    |
                                                    v
                                             Roblox Animator
```

Runtime modules use script-relative requires. Public contracts are declared
under `src/animGraph/types`; the shared `AnimationPosition`, `TimeSource`, and
`LogicalTimeReader` definitions have one canonical declaration in
`src/animGraph/types/def/init.luau`. Implementation-only validation lives under
`src/animGraph/utils`.

## Sample Transaction

Every non-destroyed `controller:update()` performs this sequence:

1. Call the configured `TimeSource` exactly once and require a finite number.
2. For every layer with an active play, select its reader with play, layer, then
   controller-default precedence.
3. Call each distinct selected reader at most once with the same `frameNow`.
4. Validate every logical position and compare it with that activation's prior
   baseline. A non-finite, backward, or non-finite derived delta rejects the
   entire update.
5. After all samples pass, commit all new baselines.
6. Evaluate every configured layer with its derived logical delta, stamping that
   value onto each `ClipRequest.deltaTime`.
7. Validate the complete request batch, including unique `trackKey` values and
   valid initial positions.
8. Call `backend:apply(requests)`, including when all deltas are zero or no
   requests were produced.

No graph or backend mutation occurs during reader preflight. Rejected samples do
not change any prior baseline. Starting a replacement play clears only that
layer activation's baseline, even when the same reader function is selected.

## Logical Delta and Native Speed

`MotionEvaluateContext.dt` and `ClipRequest.deltaTime` are the reader-derived
logical delta. They advance graph transitions and provide custom backends with a
sampled integration value.

`ClipRequest.speed` is independently composed from authored request speed and
layer speed. AnimGraph never multiplies logical delta by native speed or native
speed by logical delta. A held reader can pause graph progression while a
non-zero native speed continues on the Roblox engine timeline.

## Layers and Motions

A `LayerRuntime` owns one active motion, state label, play overrides, reader
selection, and baseline. It applies layer weight and speed to emitted requests.
Motion nodes remain backend-neutral and return `ClipRequest` records; they never
load or mutate Roblox tracks.

Built-in nodes are `ClipNode`, `Blend1DNode`, `Blend2DNode`, and
`StateMachineRuntime`. Stateful motions such as state machines should be created
per independent graph activation.

## Backend Materialization

The `AnimationBackend` structural interface receives request batches without a
controller-wide delta argument. A custom backend can use each request's
`deltaTime`; the shipped Roblox backend intentionally ignores delta-only changes
when native desired state is unchanged.

The Roblox backend owns an internal playback materialization per track key. It
validates a whole batch before loading or mutating tracks. For one live
materialization it remembers effective weight, speed, loop flag, priority,
pending initial position, and completion state. That private state provides:

- one-shot initial positioning after `Play` and positive length resolution;
- exact non-looping clamp and looping wrap behavior;
- `forceRestart` as an explicit new internal generation;
- no redundant `Play`, position write, weight/speed adjustment, property write,
  or fade restart for unchanged desired state;
- an internal terminal latch that prevents a completed materialization from
  replaying while the same request remains present.

CP-TA1 intentionally exposes no completion event, live position operation,
completed tombstone, or physical fade-retirement lifecycle. Those are separate
CP-TA2 work.

## Hard Boundaries

`clear()` and `destroy()` remain physical lifecycle boundaries. The package does
not promise to retain backend tracks or a consumer playback handle across them.
The controller owns no `RunService` connection; consumers disconnect their own
scheduler before destruction when appropriate.

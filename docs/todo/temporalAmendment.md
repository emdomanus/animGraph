# Temporal Amendment

**Status:** CP-TA1, CP-TA2, and CP-TA3 are implemented, operator-reviewed, and complete. The
sampled-reader timing amendment below remains the binding contract. Discussion of the complete
per-layer delta-map shape is retained only as history of the superseded CP-TA1 draft. The stable
verification checklist and CP-TA3 Studio record live in the [Studio Verification guide](../guides/studio-verification.md).

**Implementation entrance:** passed. The project-local deterministic runner smoke described below
ran successfully before CP-TA1 production revision work resumed and remains part of the checkpoint
verification gate.

**Reviewed baselines:** AnimGraph `acd409b78ea87cdef15bb30b79f975229b219b32`, VoxelMMO
`ef2c40e4f6a06ea13d5559e074c6240563981a6e`, and Tempo
`7452b56cc65387ada9dcb9f8e8f90b5c25ad7992`. VoxelMMO currently pins the reviewed AnimGraph
commit exactly.

## Reason

VoxelMMO's TemporalService-backed character presentation stack needs graph advancement selected per
layer or active entry while preserving frame-sampled blend/state-machine evaluation. AnimGraph can
already express caller-defined layers and playback speed, but its baseline controller gives every
layer the same caller-supplied delta and its backend has no way to re-address or observe completion
of a live logical track. The current initial-position path is also not one-shot.

The amendment supplies only reusable graph and backend mechanics. AnimGraph never imports or models
Tempo, TemporalService, character presentation, timing bindings, or caller-owned duration policy.

## Scope and invariants

- Layers remain generic `LayerT` values declared by the caller. No character-specific layers enter
  the package.
- The caller schedules `update()` once for each graph sample. AnimGraph samples one borrowed
  `TimeSource` value, then samples caller-supplied structural logical-time readers selected per
  active layer. It derives layer delta from consecutive logical-position samples.
- The controller config requires one default logical-time reader. A layer definition and an active
  play may replace that default for their scope; play overrides layer, and layer overrides the
  controller default. Selection is replacement, never multiplication.
- A reader whose logical position is unchanged yields zero logical delta, pausing logical
  advancement for that layer while other layers can advance independently.
- The controller has no logical clock, mutable timeline, timescale, or position/rate setter. Its
  `TimeSource` is only a once-per-update sampling coordinate passed to readers; it is not a logical
  time value or multiplier.
- Layer/request speed remains an independent input. AnimGraph performs its documented authored
  layer/request speed composition, then forwards the resulting request speed to the backend without
  adding a temporal multiplier.
- Logical delta never multiplies native speed, and native speed never multiplies logical delta.
- A large forward logical sample produces its exact forward delta. AnimGraph does not infer or
  classify discontinuities. Explicit live positioning is the only native-track re-address operation.
- A backward logical sample rejects the whole update before graph or backend mutation. AnimGraph
  does not implement reverse graph traversal or silently rebase reader history.
- Initial playback position is one-shot. Live re-addressing is a distinct operation on an existing
  logical track.
- Backend `apply` is idempotent for an unchanged live generation, apart from resolving an explicitly
  pending position once its length becomes known.
- A request batch contains at most one request for each `trackKey`; duplicate keys reject the whole
  batch before backend mutation.
- Backend track completion is observable without exposing `AnimationTrack`.
- No aliases, parallel old/new methods, deprecated fields, or Tempo-shaped adapter types are added.
- `clear()` and `destroy()` remain hard physical-lifecycle boundaries; they do not promise to retain
  backend tracks across target rematerialization.

## Reviewed baseline and historical draft findings

### Package and public surface

- `pesde.toml` declares one private Roblox package whose entrypoint is `src/init.luau`. The root and
  `src/animGraph/init.luau` re-export the public constructors and types.
- At the reviewed package baseline, `AnimationController:update(dt)` evaluates every layer with the same `dt`, then calls
  `AnimationBackend:apply(requests, dt)`.
- `bindToPreAnimation()` supplies one `RunService.PreAnimation` delta to that shared update path. It
  cannot express caller-resolved independent layer deltas.
- `MotionEvaluateContext.dt` is the state-machine/transition delta. Layer speed is not applied to
  that field; `LayerRuntime` instead multiplies each emitted request's native `speed`.
- A superseded pre-implementation CP-TA1 draft replaced the shared delta with a complete
  `LayerDeltaTimes` map. That historical draft shape was superseded: the public map type and map
  argument had to be deleted, not moved or retained as an alias.
- `AnimationBackend` has `apply`, `stopLayer`, `clear`, `destroy`, capabilities, and debug state. It
  has no addressing or event port.
- The event bus declares state and transition events plus `motionRequested`. No implementation emits
  `motionRequested`, and the event payload is an optional-field record rather than a discriminated
  event union.
- The public surface returns no playback handle. `trackKey` is already the backend-neutral identity
  shared by `ClipRequest`, the Roblox backend cache, and VoxelMMO's playback-token adapter.

### Verified baseline defects and missing behavior

1. **Initial position is reapplied.** `LayerRuntime` only consumes `forceRestart`; it retains
   `timePosition` and `normalizedTime`. `ClipNode` emits its configured or overridden values on every
   evaluation, and `AnimPlayback:apply` writes `AnimationTrack.TimePosition` on every backend update.
   A later live position command would therefore snap back on the next evaluation.
2. **Pending normalized starts are accidental.** The Roblox backend skips normalized positioning
   while `AnimationTrack.Length == 0`. Repeated requests may eventually cause a write, but there is
   no explicit pending-once state and no guarantee that it is applied exactly once.
3. **Natural completion replays.** If a requested non-looping track naturally stops,
   `AnimPlayback:apply` sees `IsPlaying == false` on the next update and calls `Play` again. There is
   no completed latch or activation generation.
4. **Completion is not surfaced.** VoxelMMO's content-facing playback type includes the
   `"completed"` end reason, but `CharacterAnimator` cannot produce it from AnimGraph.
5. **Same-key clip replacement is wrong.** `_getOrLoadPlayback(trackKey, clip)` returns the cached
   playback without checking its clip. Reusing a key for a different clip keeps the old asset.
6. **Retired tracks are not retired.** Requests missing from an update are only adjusted to weight
   zero. They are not stopped, disconnected, or removed until `clear()`/`destroy()`, so looping and
   repeatedly replaced tracks can remain resident indefinitely.
7. **Repeated unchanged apply is not idempotent.** The Roblox playback issues `AdjustWeight` and
   `AdjustSpeed` on every apply and can reissue position or `Play`. Reapplying the same fade target
   can alter engine-time fade progression.
8. **Duplicate keys are order-dependent.** Multiple requests with the same `trackKey` are applied in
   array order to one cached playback and overwrite one debug state. No public invariant rejects or
   combines them.
9. **Position inputs are not fully validated.** The current backend clamps negative values to zero,
   accepts unbounded normalized values, and has no declared NaN/infinity or terminal-boundary rule.
10. **VoxelMMO's current layer-freeze policy is incomplete.** Its current hitstop implementation
    sets AnimGraph layer speed to zero but still supplies one shared graph delta, so logical
    transition advancement would continue. This is motivating consumer context, not package policy.
11. **The current VoxelMMO adapter is change-driven.** `CharacterAnimator:update(dt)` calls the graph
    only when its `_dirty` flag is set. Sampled graph weights, transitions, and backend request state
    require a frame update even when animation intent has not changed.
12. **Reverse graph integration is not implemented.** `TransitionRuntime` clamps negative delta to
    zero. State-machine history cannot be reconstructed by assigning an absolute clip position.
13. **There is no automated behavioral suite.** The repository has static checks and an interactive
    Roblox dev harness, but no checked-in deterministic test runner for these lifecycle contracts.

## Consumer inventory

| Consumer | Current ownership | What it needs from AnimGraph |
| --- | --- | --- |
| VoxelMMO `CharacterAnimator` | Creates the Roblox `AnimationController`/`Animator`, AnimGraph backend and controller; arbitrates one active entry per caller-defined layer; gives each entry a unique `character/<layer>/<token>` key. | A borrowed default structural logical-time reader plus optional entry/layer reader selection, independent resolved speed, one-shot initial position, live track positioning by key, and completion by the same key. |
| VoxelMMO `CharacterAnimationPlayback` | Content-facing stable handle with `stop`, `setSpeed`, snapshot, and `bindToEnded`; its end-reason union already contains `"completed"`. | VoxelMMO can map an AnimGraph completion event to the existing handle without exposing the Roblox track. A future VoxelMMO position operation can delegate to AnimGraph without replacing the handle. |
| VoxelMMO `CharacterProceduralAnimator` | Chooses base/stance/block/transition content and changes requested speed; owns gameplay-specific landing and locomotion policy. | No new package policy. `CharacterAnimator` selects the active logical reader and resolves the playback-speed basis before AnimGraph evaluates it. |
| VoxelMMO `CharacterVisualizer` | Owns frame stepping, target/profile changes, and construction order for animator, procedural animator, and presentation host. | It schedules `update()`, supplies the frame sampling source, and will eventually coordinate presentation timing and target rematerialization. AnimGraph must not import this owner. |
| VoxelMMO `CharacterPresentationHost` | Borrowed view exposing the simple `play(request)` content surface. The current view also exposes VoxelMMO's `pushHitstop` command; no production animation-command consumer exists yet. | Stable VoxelMMO playback handles and VoxelMMO-owned timing bindings; no new AnimGraph host type or policy command. |
| VoxelMMO future sequence/action/VFX consumers | Planned users of completion and possibly authored markers. | Completion is required now. Marker semantics are not sufficiently specified to freeze a package API. |
| Tempo / VoxelMMO `TemporalService` | Own clock samples, effective rates, revision/change classification, and discontinuity policy. | Nothing from AnimGraph. VoxelMMO adapts borrowed timing state to a plain structural logical-position reader, resolved speed, and explicit position commands. |

No other current VoxelMMO source module imports AnimGraph directly, and no current VoxelMMO source
consumer binds `CharacterAnimationPlayback:bindToEnded` or Roblox animation markers.

## Ownership and dependency direction

| Owner | Owns | Must not own |
| --- | --- | --- |
| AnimGraph controller/layer runtime | Once-per-update frame sampling, structural reader selection, per-layer sample baselines/delta derivation, motion evaluation, state-machine delta, request assembly, logical track identity, batch validation, and forwarding backend completion. | Clock objects, clock rate/effective-rate calculation, mutable timelines, discontinuity classification, caller duration policy, character layers, presentation generations, or sequence policy. |
| AnimGraph backend | Materialized track generations, initial/live positioning, resolved native speed/weight/priority, natural/terminal completion classification, fade retirement, and engine-signal lifetime. | Content-facing playback handles, clock selection, rate-basis selection, or discontinuity detection. |
| VoxelMMO `CharacterAnimator` | Entry arbitration, token-to-track-key mapping, content playback state/reasons, timing-binding adapters, selected structural readers, resolved native speeds, and physical target attachment. | Raw Roblox track access outside the AnimGraph backend. |
| VoxelMMO presentation owner | Default and override timing-binding choice, reactive adapter updates, native-speed basis, discontinuity response, VoxelMMO layer-freeze policy, and target rematerialization policy. | AnimGraph backend internals or graph-time mutation. |
| Tempo / TemporalService | Clock graph, synchronized positions, effective rates, and discontinuity classification. | Animation layers, tracks, clips, or completion. |

The dependency direction is therefore:

```text
Tempo <- TemporalService <- VoxelMMO presentation owner -> CharacterAnimator -> AnimGraph -> Roblox Animator
```

AnimGraph receives only plain structural functions and resolved request values and never imports
anything to the left of `CharacterAnimator`. Readers are borrowed and non-owning. VoxelMMO may back
one with cached reactive timing state plus extrapolation at the supplied frame sample; AnimGraph
does not subscribe to, mutate, or destroy that state.

## Proposed public contract

The names below are the sole public spelling. The old position fields and the self-bound update path
are deleted in the same contract checkpoint; there are no compatibility aliases.

```luau
export type AnimationPosition =
	{ kind: "seconds", value: number }
	| { kind: "normalized", value: number }

export type TimeSource = () -> number

export type LogicalTimeReader = (frameNow: number) -> number

export type TrackCompletedEvent<LayerT, StateT> = {
	name: "trackCompleted",
	trackKey: string,
	layer: LayerT,
	state: StateT?,
}
```

`TimeSource` and `LogicalTimeReader` return finite seconds. `frameNow` is only a shared sampling
coordinate; the logical reader's returned position is the state-machine/blend domain. That domain is
separate from `AnimationPosition`: `seconds` addresses native clip seconds, while `normalized`
addresses the inclusive clip fraction `[0, 1]`.

`MotionRequestOverrides`, `LayerPlayOptions`, `ClipNodeConfig`, and `ClipRequest` replace the pair
`timePosition`/`normalizedTime` with one field:

```luau
initialPosition: AnimationPosition?
```

`AnimationControllerConfig` requires the sampling coordinate and default logical reader:

```luau
timeSource: TimeSource,
logicalTimeReader: LogicalTimeReader,
```

`LayerDefinition` and `LayerPlayOptions` each add an optional persistent replacement:

```luau
logicalTimeReader: LogicalTimeReader?,
```

The active play option has highest precedence, then the layer definition, then the controller
default. An active play retains its reader until replacement or stop. Starting a new play creates a
fresh logical sample baseline even when it selects the same function identity.

`ClipRequest` carries the controller-derived logical delta for its layer so custom backends can
perform backend-specific sampled work:

```luau
deltaTime: number
```

The controller changes are:

```luau
controller:update()

controller:setTrackPosition(
	trackKey: string,
	position: AnimationPosition
): boolean
```

On each `update`, the controller calls `timeSource` exactly once and validates the finite result. It
selects a reader for every layer with an active logical play, calls each distinct selected reader at
most once with the same `frameNow`, validates every finite logical position, and computes all deltas
before any graph evaluation or backend mutation. Shared readers therefore produce one coherent
sample across their layers.

Each logical activation/binding has a per-layer baseline. Its first valid sample records the
baseline and yields delta zero. A later equal sample also yields zero; a larger sample yields the
exact difference. A new play, including one that selects the same reader, starts a fresh baseline.
A smaller sample rejects the entire update before package mutation. No reset/rebase method is added.

The derived layer value becomes `MotionEvaluateContext.dt` and every emitted request's
`ClipRequest.deltaTime`. Layer/request speed does not multiply either field. `bindToPreAnimation()` is
deleted without replacement; the caller owns the frame connection and invokes `update()` itself.

`AnimationBackend:apply` takes requests only; the former single `dt` argument is removed because it
cannot represent independent layer inputs. A custom backend reads each request's `deltaTime` if it
needs logical integration. The backend gains exactly these ports:

```luau
backend:apply(requests)

backend:setTrackPosition(
	trackKey: string,
	position: AnimationPosition
): boolean

backend:bindToTrackCompleted(
	callback: (event: TrackCompletedEvent<LayerT, StateT>) -> ()
): Release
```

The controller binds the backend completion port once, forwards it through the existing event bus,
and releases it during destruction. `AnimationEvent` becomes a discriminated union and
`AnimationEventName` adds `"trackCompleted"`; the unused `"motionRequested"` declaration is deleted
rather than retained as a dead compatibility surface.

Shared public definitions, including `AnimationPosition`, `TimeSource`, and `LogicalTimeReader`, are
declared once in `src/animGraph/types/def/init.luau` and re-exported through the existing type and
package barrels. `LayerDeltaTimes` is deleted. Small implementation-only validation helpers move
under `src/animGraph/utils/` rather than remaining at the package root. Runtime modules import the
canonical declarations; they do not redeclare structurally similar public types.

### Logical delta and resolved speed

- Logical delta advances graph/state-machine state. It is derived from reader positions, not passed
  by the update caller. A zero value pauses that layer's logical advancement while other layers use
  their own values.
- `ClipRequest.speed` is the resolved backend-native playback speed after AnimGraph's existing
  authored layer/request speed composition. The Roblox backend passes that value to `Play` or
  `AdjustSpeed` without adding any other multiplier.
- AnimGraph does not know whether a reader or speed was derived from a clock, motion, simulation,
  reactive cache, or authored constant.
- Changing only the logical reader's position cannot change request speed. Changing only
  request/layer speed cannot change the reader sample or derived logical delta.
- Zero logical delta does not implicitly stop native playback or native fades. Those continue from
  the independently resolved native request state.
- A large forward reader step advances graph transitions by that exact amount and may complete more
  than one graph-time-dependent operation according to existing graph semantics. AnimGraph does not
  guess whether it was a discontinuity.
- A backward reader sample is invalid. Forward and backward native live positions are supported,
  but assigning one does not change the graph baseline or reconstruct graph history.

### Sampled evaluation and backend neutrality

- AnimGraph remains a sampled graph runtime, not a lazy track-command orchestrator. Every caller
  `update()` evaluates active graph structure so state transitions and simultaneous layer, motion,
  clip, and future custom weight curves compose in one deterministic frame result.
- Independent native fades cannot generally replace that composition: multiplying two changing
  graph weights produces a different curve than launching separate engine fades, and a later custom
  backend may need to apply poses or transforms for every sample.
- The controller calls `backend:apply(requests)` on every successful update, including a frame whose
  reader-derived delta is zero. A custom backend may consume `ClipRequest.deltaTime` for sampled work.
  The Roblox backend remains idempotent and avoids redundant native calls when desired native state
  is unchanged.
- AnimGraph owns no `RunService` connection. The caller chooses the phase and cadence and calls
  `update()`; a non-frame caller may sample at another deterministic cadence if its graph/backend
  contract permits it.

### Position validation and terminal behavior

- Both the controller operation and a directly used backend validate `AnimationPosition` before
  mutation. `kind` must be exactly `"seconds"` or `"normalized"`; `value` must be finite; seconds
  must be non-negative; normalized values must be in the inclusive range `[0, 1]`.
- Invalid positions raise a contract error before changing pending or live state. The boolean return
  is reserved for whether a valid command found and was accepted by a live generation.
- Initial and live positions remain pending until the backend knows a positive track length. This
  gives both seconds and normalized addressing deterministic clamping/wrapping behavior.
- For a non-looping track, seconds clamp to `[0, Length]` and normalized values map to that same
  inclusive range. An accepted initial or live position at the exact terminal boundary, or a seconds
  value beyond it, places the track at `Length`, latches the generation completed, and emits exactly
  one `trackCompleted` after internal state is committed.
- For a looping track there is no terminal completion. Seconds wrap modulo `Length`; normalized `1`
  canonicalizes to `0`; addressing never emits `trackCompleted` merely because it crosses a loop
  boundary.
- A backward position command cannot revive a completed tombstone. A caller must establish a new
  activation with a new presence edge or explicit `forceRestart`.

### Initial position semantics

- `initialPosition` is applied once for each new materialized track generation, after the track has
  started and positive length is known. Repeated desired-state evaluations do not write it again.
- A layer-play override remains pending until that play call first emits at least one request, then
  is consumed. Every request in that first emitted batch may receive it; later evaluations do not.
- A `ClipNode`-configured initial position is declarative for each new materialization of its track
  key. The backend, not per-frame graph evaluation, enforces the one-write rule.
- A pending initial position is applied once when length becomes available unless superseded by a
  valid live position command or retirement.
- `forceRestart` remains an explicit one-shot activation command. It creates a new generation. When
  the request also contains `initialPosition`, that position is the new generation's starting
  position; otherwise the generation starts at zero. The explicit initial position therefore takes
  precedence over the restart default. `forceRestart` is not an alias for live positioning.

### Request-batch and apply invariants

- A valid batch has one request per `trackKey`. The controller validates the assembled batch before
  calling the backend; the shipped backend repeats the defensive validation for direct users.
- Any duplicate rejects the whole batch before backend mutation. There is no first-wins, last-wins,
  weight combination, partial apply, or order-dependent behavior.
- For the same live generation, a semantically unchanged request produces no new `Play`, position
  write, activation generation, signal subscription, `AdjustWeight`, or `AdjustSpeed` call. In
  particular, it cannot restart a fade. Polling positive length and applying one pending position is
  the sole allowed state change from an otherwise unchanged apply.
- A logical-delta-only change is available to a custom backend through `ClipRequest.deltaTime` but
  does not make the Roblox backend reapply native speed or weight.
- A changed effective Roblox weight, speed, loop flag, or priority updates only that property. It
  does not create a new generation.

### Live track positioning

- `setTrackPosition` addresses the currently live materialized generation identified by `trackKey`.
  It returns `true` when a valid command is accepted, including a command queued pending length, and
  `false` when the key is unknown, retiring, completed, or the controller/backend is destroyed.
- The command preserves the logical/content-facing playback identity, current loop setting, speed,
  weight target, priority, and completion subscription. Except for terminal handling, it does not
  call `Play`, recreate the `AnimationTrack`, emit state transitions, synthesize markers, or
  reconstruct state-machine history.
- A live command supersedes any unapplied initial position, and later evaluations cannot snap the
  track back to its initial position.
- Forward and backward discontinuities use the same operation. Detecting or classifying a
  discontinuity remains caller-owned.

### Completion, tombstones, and callback re-entrancy

- `trackCompleted` means that the current non-looping generation reached its terminal boundary by
  native forward playback or by an accepted initial/live terminal position. It fires once.
- Explicit `stopLayer`, disappearance from the desired request set, same-key clip replacement,
  `clear`, and `destroy` suppress completion for the retired generation.
- A looping track does not complete because it loops; `DidLoop` is not completion.
- Completion is latched before invoking subscribers. Repeated desired requests for the same
  `(trackKey, clip)` generation cannot call `Play` or emit completion again.
- After physical track cleanup, a lightweight completed tombstone retains the key, clip identity,
  layer/state identity, and generation token while that same request remains present. It does not
  retain the `AnimationTrack` or signal connections.
- A tombstone is removed when one fully validated applied batch omits its key, a different clip or
  explicit `forceRestart` establishes a new generation, or `clear`/`destroy` runs. If no later batch
  occurs, the lightweight tombstone lives until `clear`/`destroy` so an unchanged desired request can
  never auto-replay.
- Same-key/different-clip requests retire the old generation and create a new generation. Signals
  capture a generation token; callbacks from completed, retiring, replaced, cleared, or destroyed
  tokens cannot mutate or complete the current generation.
- Completion events accumulated during `apply` dispatch only after the entire batch and retirement
  state are committed. An engine-signal completion commits its tombstone before dispatch.
- Backend and controller event dispatch snapshot the current subscriber list. A completion callback
  may synchronously call `play`, `stopLayer`, `setTrackPosition`, `clear`, `destroy`, or release/add
  listeners. The emitter performs no post-callback mutation through a stale generation reference,
  and re-entry cannot cause a second completion.

### Fade-retirement ownership and cleanup

- The backend owns physical retirement once the controller/backend marks a generation retiring. It
  disconnects or invalidates completion classification first, calls `AnimationTrack:Stop(fadeTime)`,
  and holds only the retiring physical generation until cleanup.
- `stopLayer(layer, fadeTime?)` uses the explicit argument or the layer's resolved default fade-out.
  A request that disappears from a normal applied batch uses the backend's configured default
  fade-out. Same-key replacement and `forceRestart` use the incoming request's fade time for the old
  and new generation. `clear()` and `destroy()` are immediate zero-fade hard boundaries.
- The active-key map is released at retirement start, so a same-key request may create a new
  generation while the old one fades. Retiring generations are stored by generation token, not only
  by `trackKey`.
- `Stopped` from an explicitly retiring generation never emits completion. `Ended` owns final
  connection, `AnimationTrack`, and `Animation` cleanup after a non-zero fade. A zero-fade or already
  inactive generation cleans up immediately. Cleanup is idempotent.
- Natural completion uses `Ended` to release the physical objects but retains the lightweight
  completed tombstone described above.
- Graph-derived transition weights stop changing when their layer delta is zero. Roblox's native
  weight fade is engine-time behavior and may continue while logical delta is zero; AnimGraph does
  not promise timeline-controlled native fade suspension.

Roblox documents `Stopped` as covering both natural and explicit stops, while `Ended` occurs after
the track has finished affecting the world. The backend therefore needs explicit retirement flags
and generation guards: `Stopped` classifies a possible natural completion only after checking state;
`Ended` is the physical cleanup boundary. See the official
[AnimationTrack reference](https://create.roblox.com/docs/reference/engine/classes/AnimationTrack).

### Target rematerialization

AnimGraph does not own a content playback handle across `clear()`. In the VoxelMMO follow-on,
VoxelMMO retains its `CharacterAnimationPlayback` and logical entry, clears/rematerializes the
physical backend target, replays the same token-derived key with the current caller-derived
`initialPosition`, then continues live positioning. Physical Roblox tracks may be recreated; the
content-facing VoxelMMO playback must not be.

`clear()` must not emit `trackCompleted`. Generation guards reject delayed signals from the old
target. Roblox's `Animator:LoadAnimation()` creates a new track, so target rebuilds are bounded to
genuine materialization changes rather than per-frame positioning; see the official
[Animator reference](https://create.roblox.com/docs/reference/engine/classes/Animator).

## Required VoxelMMO follow-on composition

This section is a migration requirement and proof target, not AnimGraph implementation scope or an
AnimGraph API. The exact private VoxelMMO type names remain for that repository's migration review.

- `CharacterAnimator` receives a borrowed default character clock/reader. The MVP may inject the
  world clock as that default. VoxelMMO adapts it to AnimGraph's structural `LogicalTimeReader`;
  neither the raw clock nor the binding becomes an AnimGraph API value.
- Every active animation entry may carry an internal timing binding that overrides the default.
  Timing selection belongs to the active entry, not the AnimGraph controller instance.
- Ordinary character animation commands use the character timing binding.
- `PresentationSequence` animation commands retain the same simple `play(request)` content surface.
  `PresentationService` wraps that surface with the sequence's timing binding when it submits the
  entry to `CharacterAnimator`.
- Animation target and animation timeline are independent. Changing the target does not select a
  timeline, and selecting a timeline does not select or rematerialize a target.
- A melee sequence may borrow the attacker's character clock.
- A normal-speed two-character finisher may bind both characters' action animations to one world or
  sequence clock without changing either character clock.
- Normal advancement is represented by a monotonic logical reader built from consecutive
  selected-clock positions. Continuous rate changes update the affected active playback's resolved
  native speed under the hood. On a classified forward or backward discontinuity, VoxelMMO rebases
  its adapter without exposing a backward graph sample and issues `setTrackPosition`; it does not
  ask AnimGraph to reconstruct graph history.
- The authored `CharacterAnimationRequest` remains content-facing and does not need raw Tempo or
  TemporalService objects merely to achieve timing binding. A wrapper/internal entry configuration
  carries the borrowed binding.
- Native playback-rate basis is selectable per active playback or animation definition, not only
  per layer. Locomotion and discrete content may share a procedural layer:
  - a timeline-driven discrete animation resolves native speed as authored/request speed multiplied
    by the selected timing rate;
  - motion-derived locomotion resolves native speed from motion/velocity and does not multiply by
    the character-clock rate again.
- `CharacterAnimator` supplies the controller's default logical reader and any layer/active-play
  reader overrides from each selected binding, schedules `update()` per frame, and submits each
  already-resolved speed. It never applies a character-clock multiplier over the controller after
  per-entry/per-layer resolution.

### VoxelMMO follow-on proof matrix

These proofs belong to the VoxelMMO migration suite and Studio integration, not AnimGraph's package
suite:

| Scenario | Required proof |
| --- | --- |
| Character timing rate `0.5`, discrete attack | The attack layer's selected reader advances by `0.5` per unit frame time, its sampled logical delta follows `0.5`, and its authored/request native animation speed is resolved with rate `0.5` exactly once. No later AnimGraph or controller-instance multiplier is applied. |
| Character timing rate `0.5`, velocity already reduced to `0.5` | The locomotion playback's motion-derived native speed remains `0.5`; it never becomes `0.25`. Its logical layer delta comes independently from the selected reader. |
| Two characters each at `0.5`, finisher sequence timing rate `1` | Both finisher action animations select the sequence reader and resolved native rate `1`. Unrelated layers on each character retain their character readers/rates at `0.5`, and neither character clock is changed. |

## Rejected shapes

- Injecting Tempo clocks, TemporalService, revisions, timing-binding objects, or rate modifiers into
  AnimGraph. The generic `LogicalTimeReader` function is the dependency boundary; anything richer
  would reverse the dependency and make a reusable package game-specific.
- Passing a complete per-layer delta map, adding controller/layer timescale or logical-position
  setters, or applying a character-clock multiplier. AnimGraph samples selected logical positions
  and derives delta; it does not own mutable timing state.
- Retaining `bindToPreAnimation` or adding any self-bound frame connection. The caller owns update
  scheduling; the controller's `TimeSource` only makes every reader sample share one frame coordinate.
- Making the reader return position plus rate or having AnimGraph integrate a supplied rate. Readers
  expose resolved logical position only. Native request speed remains a separate discrete input.
- Adding an AnimGraph reset/rebase command for reader history. A new play/binding gets a fresh
  baseline; clock discontinuity classification and adapter rebasing remain consumer-owned.
- Returning a second package playback handle from `play`. VoxelMMO already owns the content-facing
  handle, while AnimGraph already has the narrower `trackKey` identity needed by the backend.
- Keeping `timePosition` and `normalizedTime` beside `initialPosition`, or adding separate
  seconds/normalized live methods. A discriminated position and one addressing operation prevent
  contradictory inputs.
- Exposing Roblox `AnimationTrack.Stopped`, `Ended`, or the raw track. The package reports one
  backend-neutral completion event.
- Silently accepting duplicate keys with first-wins, last-wins, or implicit weight merging.
- Treating a large delta jump as reversible state-machine history. Clip positioning and graph event
  history are different contracts.

## Migration and deletion order

1. Before CP-TA1 production source work is accepted or resumed, add the selected project-local Lune
   pin, package-owned module loader, suite entrypoint, and smoke proof; run it successfully from the
   AnimGraph root.
2. Consolidate `AnimationPosition`, `TimeSource`, and `LogicalTimeReader` in
   `src/animGraph/types/def/init.luau`, keep root re-exports, move implementation-only validation to
   `src/animGraph/utils/`, and delete the draft `LayerDeltaTimes` type/module/export.
3. Change controller/layer evaluation to `update()`: sample one finite frame coordinate, select
   play/layer/default readers, preflight reader results, derive per-layer delta and baselines, put the
   derived value on each request, remove the backend's ambiguous global `dt`, and delete
   `bindToPreAnimation`.
4. Replace `timePosition` and `normalizedTime` across motion overrides, layer play options, clip
   configuration, requests, docs, and dev code. Delete the old fields in that same commit; do not
   bridge both shapes.
5. Implement duplicate-batch rejection, one-shot layer override consumption, position validation,
   exact initial terminal behavior, unchanged-apply idempotence, and backend materialization state.
   Preserve `forceRestart` as the only restart command, with `initialPosition` taking precedence over
   its zero-position default.
6. Add canonical `TrackCompletedEvent`, controller/backend live positioning and completion binding,
   then implement Roblox generations, tombstones, fade retirement, re-entrant dispatch safety,
   stale-signal suppression, and pending-length ownership.
7. Update debug snapshots so live/completed/retiring state and generation identity are diagnosable
   without exposing the raw track. Remove the unused `motionRequested` event declaration and dead
   backend state.
8. Reorganize the documentation into the Tempo/Sovereign-style architecture, guides, filesystem-aligned
   API, type-definition/index, research, and TODO index structure. Update all examples and the dev
   harness to the sole new spellings. Do not add a compatibility layer.
9. Only after the AnimGraph checkpoints are reviewed may a separate VoxelMMO change update its exact
   pin and implement the follow-on composition/proofs above. This TODO does not authorize editing
   VoxelMMO or publishing a package.

## Implementation checkpoints and review pauses

### Deterministic-runner entrance gate

**Gate result: passed for CP-TA1.** The project-local loader smoke and suite entrypoint ran
successfully before production revision work resumed.

The selected runner is **Lune 0.8.9**, matching the currently pinned VoxelMMO runner. On 2026-08-13,
that executable was run from the AnimGraph root and successfully required the current canonical
event-bus type module; the temporary preflight file was removed. This proves executable availability
but is not the checked-in package test gate.

The gate required:

1. pin Lune 0.8.9 in AnimGraph's existing project tool manifest;
2. add `tests/lune/run.luau` and the minimal AnimGraph-owned transform/loader needed by Roblox-shaped
   modules;
3. add a smoke spec that loads a current package runtime module through that loader and exercises one
   observable behavior;
4. run `lune run tests/lune/run.luau` successfully from a clean AnimGraph root.

These tooling/test files are part of CP-TA1. The smoke passed before the superseded draft's
production edits were revised and passed again before sampled-reader revision work resumed. Missing
evidence or a later runner/loader failure blocks source work; the runner choice itself is no longer
open.

### CP-TA1 -- sampled logical timing and one-shot initial position

One coherent commit:

- land the canonical position/time-source/logical-reader types in `types/def`, their exports, and the
  `utils/` implementation-helper placement; delete `LayerDeltaTimes` rather than relocating it;
- replace `update(dt)` with `update()`, sample `timeSource` once, implement
  active-play/layer/controller reader precedence and per-activation baselines, add derived request
  `deltaTime`, remove backend global `dt`, and delete `bindToPreAnimation`;
- replace and delete the old position fields with no aliases;
- implement time-source/reader preflight validation, backward-sample rejection, position validation,
  duplicate-batch rejection, first-emitted-batch consumption, exact looping/non-looping
  initial-position boundaries, and one-write materialization behavior;
- make repeated backend apply idempotent for an unchanged live generation, including fade targets;
- retain an internal completed-materialization latch sufficient to prevent replay after an initial
  terminal position, without exposing `trackCompleted` or the CP-TA2 tombstone API early;
- add executable Lune specs for once-per-update coherent sampling, reader precedence/baselines,
  independently frozen logical layers, forward/backward sample rules, delta/speed independence,
  duplicate rejection before mutation, initial-position validation and terminal behavior,
  `forceRestart` with and without `initialPosition`, pending length, one-shot application, and
  unchanged apply;
- reorganize and update public documentation to the Tempo/Sovereign layout, including public types,
  controller, architecture, motions, state machine, backend, README examples, dev harness, consumer
  research/migration brief, TODO index, and changelog together.

Pause for public API, sampled-time semantics, deletion/file placement, deterministic-runner,
documentation structure, and behavior review. Do not begin CP-TA2 while CP-TA1 has type, tooling,
lifecycle, or documentation debt.

Checkpoint boundary: CP-TA1 retains an internal completed-materialization latch sufficient to
prevent replay; CP-TA2 adds outward `trackCompleted` dispatch, physical completion cleanup, and the
lightweight post-cleanup tombstone.

### CP-TA2 -- live position and backend-neutral completion

**Implementation status: complete, operator-reviewed, and committed.** The public contract, Roblox
generation/tombstone lifecycle, deterministic seams, dev harness, and documentation are present in
the CP-TA2 checkpoint. The later CP-TA3 operator record is captured in the [Studio Verification guide](../guides/studio-verification.md).

One coherent commit:

- add the one controller position operation, backend position/completion ports, canonical completion
  type, and discriminated controller event;
- extend CP-TA1's internal completed-materialization latch with outward `trackCompleted`
  dispatch, physical completion cleanup, and the lightweight post-cleanup completed tombstone;
- implement Roblox playback generations, terminal live positioning, same-key clip replacement,
  completed tombstones, tombstone retirement, explicit fade ownership, reappearance during fade,
  stale-signal suppression, connection/physical cleanup, and callback re-entrancy safety;
- ensure natural and explicitly addressed terminal completion dispatch once only after state commit,
  while explicit retirement never reports completion;
- add executable Lune backend-seam specs for every non-engine lifecycle rule, including tombstone
  lifetime, cleanup, stale callbacks, re-entrant `play`/`stopLayer`/`clear`/`destroy`, and live address
  superseding pending initial state;
- extend the dev harness with independent held/advancing logical-reader controls, live
  forward/back position, exact terminal position, natural completion, looping, replacement, and
  fade-retirement controls;
- update API/backend docs and changelog in the same commit.

Pause for lifecycle, cleanup, re-entrancy, and diff review. No package publishing occurs.

### CP-TA3 -- verification and consumer-readiness gate

**Closure status: complete and operator-reviewed.** No source tranche was required. The operator
connected to Place1 and personally completed all 12 Studio cases; the stable checklist and exact
observations are recorded in the [Studio Verification guide](../guides/studio-verification.md).
The deterministic/static baseline passed at 51/51 tests, the migration brief remained accurate,
Studio was returned to Edit mode, and documentation/navigation were brought into the final
checkpoint shape. Formatting, lint, Luau analysis, both sourcemaps, documentation build, and diff
checks passed. VoxelMMO timing-composition proofs remain a separate consumer follow-on, and package
publication/version decisions remain deferred.

## AnimGraph behavioral test matrix

| Area | Case | Required result | Venue |
| --- | --- | --- | --- |
| Sampling coordinate | Call `update()` with several active layers/readers | `timeSource` is called exactly once; every reader receives that same finite `frameNow`. | Lune spec |
| Shared reader coherence | Two layers select the same reader | The reader is called once for the update and both layers derive from the same position sample. | Lune spec |
| Reader precedence | Controller, layer, and active play provide different readers | Play replaces layer, layer replaces controller default, and no sampled value or rate is multiplied through the fallback chain. | Lune spec |
| Activation baseline | First update, a replacement play, or a new play that reuses the same reader | The selected position becomes a fresh baseline and logical delta is zero for that update; later forward samples use exact differences. | Lune spec |
| Independently frozen layer | One selected reader holds its position while another advances | The first layer receives zero logical delta and its graph state holds; the other receives its exact derived delta and advances. | Lune spec + Studio visual |
| Sample validation | Frame source or any reader returns NaN/infinity, or a reader moves backward | Whole update rejects before graph evaluation/backend mutation and preserves every prior baseline. | Lune spec |
| Large forward sample | A reader advances by a large finite amount | AnimGraph supplies the exact positive delta and existing graph semantics advance from it; no discontinuity or seek is inferred. | Lune spec |
| Delta/speed independence | Derive logical delta `0.25` while resolved request speed is `1.75`, then change each independently | Context/request delta remains exactly reader-derived `0.25`; backend speed remains exactly `1.75`; AnimGraph never multiplies or rewrites one with the other. | Lune spec + Studio visual |
| Backend-neutral sampling | Repeat a successful update with zero or unchanged native desired state | Backend `apply` still receives the sampled request/delta for custom per-frame work; the Roblox backend emits no redundant native operations. | Backend-seam Lune spec |
| Duplicate key | Two requests in one batch share a `trackKey` | Whole batch rejects before any backend mutation; request order cannot affect state. | Lune spec |
| Unchanged apply | Apply the same live-generation request repeatedly | No replay, seek, generation/signal churn, speed/weight reapply, or fade restart. | Backend-seam Lune spec + Studio |
| Initial seconds | Same request evaluated repeatedly | Position is validated and written once for the materialized generation. | Backend-seam Lune spec |
| Initial normalized | Length starts at zero, then becomes available | One pending position is applied once; no repeated writes. | Backend seam + Studio |
| Invalid position | Invalid kind/range/non-finite value through controller or direct backend | Contract error occurs before pending/live mutation. | Lune spec |
| Initial non-loop terminal | Exact normalized `1` or seconds at/beyond known length | Position clamps to `Length`, generation latches completed once, and later unchanged apply cannot replay it. | Backend seam + Studio |
| Initial loop terminal | Normalized `1` or seconds at a length multiple | Position canonicalizes/wraps to zero and does not complete. | Backend seam + Studio |
| Initial supersession | Live position arrives before pending initial resolves | Live position wins permanently. | Backend seam + Studio |
| Live position | Forward then backward position on an active key | Same logical/materialized generation remains; speed/weight/loop/priority are preserved. | Backend seam + Studio |
| Live non-loop terminal | Live position reaches exact/beyond terminal | One completion after state commit; completed tombstone refuses later positioning and unchanged apply. | Backend seam + Studio |
| Missing position | Unknown, retiring, completed, or destroyed key | Method returns `false` and creates nothing. | Lune spec |
| Natural completion | Non-looping track reaches its end while request remains | One `trackCompleted`; physical objects clean up; tombstone prevents automatic replay. | Backend seam + Studio |
| Tombstone lifetime | Same request remains, disappears, restarts, or changes clip | Tombstone remains only while needed to prevent replay and is removed by the specified presence/restart/clear boundaries. | Lune spec |
| Looping | Track crosses one or many loop boundaries | No `trackCompleted`; playback remains live. | Studio |
| Explicit stop | `stopLayer`, missing request, replacement, clear, or destroy | No `trackCompleted`; the selected fade and cleanup owner match the contract. | Backend seam + Studio |
| Same key/same clip | Desired native values change while live | No reload or activation change; only changed effective properties update. | Backend seam |
| Same key/different clip | Active entry is replaced | Old generation retires, new asset loads, stale old signals are ignored. | Backend seam + Studio |
| Reappearance during fade | Retired key returns before old `Ended` | New generation becomes active; old generation cannot affect or complete it; both physical lifetimes clean up. | Backend seam + Studio |
| Force restart default | Completed or live generation receives `forceRestart` without `initialPosition` | One new activation generation starts at zero; later evaluations do not restart again. | Backend seam + Studio |
| Force restart with initial position | Completed or live generation receives both `forceRestart` and a valid `initialPosition` | One new activation generation starts at the explicit position, not zero; the position is applied once and later evaluations neither reposition nor restart it. | Backend seam + Studio |
| Re-entrant completion callback | Callback plays/stops/positions/clears/destroys and mutates subscriptions | Internal state was committed first; no stale post-callback mutation, duplicate completion, or leaked connection occurs. | Lune spec |
| Native fade with zero logical delta | One layer's reader position is unchanged during a native fade | Logical transition values remain unchanged; observed native fade continues according to engine time and documented ownership. | Studio |
| Target rematerialization | Consumer retains handle but clears/rebuilds physical target | Old signals are suppressed; same logical entry starts at caller-derived position; no false completion. | VoxelMMO follow-on + Studio |
| Consumer-owned discontinuity | VoxelMMO classifies a forward/backward clock jump, rebases its monotonic graph reader, and issues live track positioning | AnimGraph sees no backward graph sample or synthetic history; the active native generation seeks without replacing the content playback. | VoxelMMO follow-on + Studio |

Immutable expectations are coherent once-per-update sampling, reader precedence/baselines,
delta/speed independence, backward-sample preflight rejection, duplicate rejection, one-shot
positioning, unchanged-apply idempotence, no auto-replay, completion suppression, tombstone lifetime,
and re-entrant callback safety. Tests for those behaviors must not be weakened to accommodate an
implementation.

## Marker and event assessment

Roblox exposes named marker signals through `AnimationTrack:GetMarkerReachedSignal(name)`, plus
`DidLoop`, `Stopped`, and `Ended`. A backend-neutral marker API would need at least a declared marker
subscription set, payload shape, loop identity, and a ruling for markers crossed by forward/backward
position changes. Neither the current VoxelMMO adapter nor production presentation host has a marker
consumer, and the engine reference does not establish position-crossing semantics.

Therefore this amendment adds completion only. It does not synthesize markers, keyframes, or loop
events. Marker forwarding is deferred until a concrete sequence/VFX consumer freezes the required
names and position policy. Studio observations from this work are recorded for that later contract,
but they do not leak into the completion event.

## Documentation and verification plan

CP-TA1 reorganized the reviewed flat/stale documentation into the same separation used by Tempo and
Sovereign. Stable pages, links, and VitePress navigation move together; old paths are deleted rather
than retained as duplicate contract pages:

```text
docs/
|-- .vitepress/
|   |-- config.mts
|   '-- theme/
|       |-- index.ts
|       |-- custom.css
|       '-- components/ZoomableDiagram.vue
|-- index.md
|-- architecture.md
|-- assets/
|   |-- animgraph-runtime.svg
|   '-- animgraph-completion.svg
|-- diagrams/
|   |-- animgraph-runtime.d2
|   |-- animgraph-completion.d2
|   '-- site-theme.d2
|-- guides/
|   |-- index.md
|   |-- getting-started.md
|   |-- motions.md
|   |-- state-machines.md
|   |-- dev-harness.md
|   |-- verification.md
|   '-- studio-verification.md
|-- api/
|   |-- index.md
|   |-- controllers/animationController.md
|   |-- motions/...
|   |-- runtimes/stateMachineRuntime.md
|   |-- backends/robloxAnimatorBackend.md
|   '-- types/
|       |-- index.md
|       '-- definitions.md
|-- research/voxelmmo-migration.md
'-- todo/
    |-- index.md
    |-- backlog.md
    '-- temporalAmendment.md
```

The API tree mirrors the public filesystem surface. `api/types/definitions.md` points to
`src/animGraph/types/def/init.luau`; `api/types/index.md` inventories every root-exported public type.
Private layer/backend lifecycle internals are explained in `architecture.md`, not promoted to API
pages. Guides own task-oriented usage. Consumer-specific requirements remain research/migration
material and never define package policy. `README.md` remains the package landing example and
`CHANGELOG.md` records each checkpoint.

Run the repository-supported gates from the AnimGraph root and save exact output:

```powershell
lune run tests/lune/run.luau
stylua --check src dev tests
selene src dev tests
.\scripts\check-luau.ps1
rojo sourcemap default.project.json --output sourcemap.json
npm run docs:build
git diff --check
```

Lune 0.8.9 is the decided deterministic runner. The project-local pin, loader, suite entrypoint, and
smoke must pass before CP-TA1 source work, then remain part of every checkpoint gate. Review generated
sourcemap diffs and do not commit generated caches or documentation build output.

## Studio-only verification

The stable Studio checklist and the operator-approved results are canonical in
the [Studio Verification guide](../guides/studio-verification.md). This completed amendment
retains the design intent and the distinction between engine evidence and deterministic/static
proof; it does not duplicate the 12-case record here.

## Explicitly deferred

- Any AnimGraph dependency on Tempo or TemporalService.
- Tempo clock/timing-binding objects, reader effective-rate APIs, rate modifiers, synchronization,
  discontinuity detection, adapter rebasing, duration-based freeze policy, and presentation
  scheduling. The generic logical-position function and frame sample are the complete package seam.
- Continuous signed reverse traversal of state machines or reconstruction of graph event history.
- Marker, keyframe, and loop event forwarding or synthesis.
- Timeline-controlled suspension of Roblox native weight fades.
- A package-owned content playback handle or target-rematerialization host.
- VoxelMMO sequence/action/VFX policy and consumer migration implementation.
- Custom pose-solver timelines, masks, and per-joint temporal behavior.
- Package publishing or a version/release decision.

## Finalized decisions and remaining gates

There are no open design blockers for CP-TA1, CP-TA2, or CP-TA3. The binding decisions are:

1. `trackKey` is the public logical/backend identity. AnimGraph adds only
   `setTrackPosition(trackKey, AnimationPosition)` and `trackCompleted`; it exposes no package
   playback handle or raw `AnimationTrack`.
2. `update()` takes no frame arguments. It samples one `TimeSource` coordinate and structural logical
   readers with play-over-layer-over-controller fallback, then derives each active layer's delta from
   a per-activation baseline. There is no AnimGraph clock, delta map, mutable timeline,
   controller-wide timescale, self-bound update, or temporal speed multiplier.
3. First/equal reader samples yield zero delta, forward samples yield their exact finite difference,
   and any backward/non-finite sample rejects the whole update before graph/backend mutation. Large
   forward steps are not classified; continuous reverse graph traversal is not claimed.
4. One `AnimationPosition` union serves initial and live positioning. Validation, looping rules, and
   exact non-loop terminal completion are fixed; the two numeric legacy fields are deleted without
   aliases. On `forceRestart`, an explicit `initialPosition` wins; zero is only the absent-position
   default.
5. Every request batch has unique `trackKey` values and rejects duplicates before mutation.
6. Repeated apply is idempotent for an unchanged live generation.
7. Natural or explicitly addressed non-loop terminal state emits one completion after state commit.
   Explicit retirement suppresses completion; completed tombstones prevent replay; `Ended` owns
   physical cleanup after fade. CP-TA1 implements only the internal completed-materialization latch
   required for no replay; CP-TA2 adds outward dispatch, physical completion cleanup, and the
   lightweight post-cleanup tombstone.
8. Completion dispatch is re-entrant-safe and stale engine signals are generation-guarded.
9. Named markers remain deferred until a concrete consumer defines subscription and position-crossing
   semantics.
10. VoxelMMO retains content playback handles and owns timing bindings, structural reader adapters,
    discontinuity rebasing, rate-basis selection, and target rematerialization composition. AnimGraph
    `clear()` remains a hard backend boundary.
11. Canonical shared types live in `types/def`, implementation helpers live in `utils`, and the docs
    use the Tempo/Sovereign architecture/guides/filesystem-aligned-API/types/research/TODO structure.
12. Lune 0.8.9 is the deterministic runner. The checked-in loader smoke is a mandatory execution
     entrance gate before source work, not an unresolved design decision.

The remaining work is the separate VoxelMMO timing-composition proof set and any later release
decision. The project-local Lune entrance gate, CP-TA1/CP-TA2 implementation, and CP-TA3 operator
review are complete. Package publication and version decisions remain deferred.

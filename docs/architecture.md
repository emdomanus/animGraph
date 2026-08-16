---
aside: false
sidebar: false
pageClass: architecture-page
---

# Architecture

AnimGraph is an authored, sampled graph runtime. A caller owns the cadence and
borrows plain timing functions; `AnimationController` owns one coherent graph
sample; and an injected backend owns concrete playback. The package never
owns a clock, scheduler connection, character policy, or consumer playback
handle.

<script setup>
import runtimeDiagram from "./assets/animgraph-runtime.svg";
import completionDiagram from "./assets/animgraph-completion.svg";
</script>

<ZoomableDiagram
  :src="runtimeDiagram"
  alt="AnimGraph runtime ownership, evaluation, materialization, and completion flow"
  height="min(78vh, 920px)"
/>

The graph is generated from `docs/diagrams/animgraph-runtime.d2` after auditing
the committed source under `src/animGraph`. Relationship labels state the
interaction directly: diamonds denote ownership, solid arrows denote calls,
dashed arrows carry data or structural conformance, and dotted arrows return
completion. Dashed node borders identify contracts; tightly dotted node borders
identify backend-private objects. `AnimPlayback`, `Animation`, and
`AnimationTrack` never cross the public boundary.

The cyclic completion route is generated separately so it remains legible
without routing a return edge across the forward evaluation graph. Its nodes
are short references to the same runtime objects, not additional instances.

<ZoomableDiagram
  :src="completionDiagram"
  alt="AnimGraph backend completion classification, tombstone, controller, and event flow"
  height="min(46vh, 420px)"
/>

Use the toolbar to fit either diagram or return to its native vector size.
Drag with a pointer, use the arrow keys after focusing the viewer, or hold
Control/Command while scrolling to zoom around the cursor. The default view
fits the complete diagram without clipping.

## Ownership and responsibilities

| Role | Constructed by | Lifecycle owner | Consumes | Produces or exposes |
| --- | --- | --- | --- | --- |
| Caller-owned scheduler | Consumer code | Consumer code | Its chosen phase/cadence | Calls `controller:update()`; disconnects its own connection |
| `TimeSource` and `LogicalPositionReader` | Consumer code | Consumer code | One sampled time supplied by the caller | A borrowed finite time and its converted logical positions; AnimGraph never subscribes to or destroys the functions |
| `AnimationController` | `AnimGraph.new` or `animationController.new` | Caller that created it | Scheduler calls, timing functions, layer definitions, parameters, and a backend | Coherent reader samples, graph evaluation, request validation, and controller events |
| `ParameterStore` | `AnimationController` | `AnimationController` | Raw, float, bool, and trigger parameter writes | Values and trigger consumption for motion evaluation |
| `EventBus` | `AnimationController` | `AnimationController` | State, transition, and backend completion events | Snapshot-dispatched public controller callbacks |
| `LayerRuntime` instances | `AnimationController:addLayer` | `AnimationController` | One active motion, selected reader, baseline, and layer settings | `MotionEvaluateContext`; layer-composed `ClipRequest` records |
| `MotionNode` contract | Caller-authored constructors | Caller-owned graph configuration | Evaluation context and parameters | One or more backend-neutral requests; `ClipNode`, blends, and state machines conform structurally |
| `StateMachineRuntime` | Caller through `stateMachine` | Caller-owned active graph, reached through its layer | Parameters, triggers, and logical `dt` | State/transition events and weighted child requests |
| `ClipRequest` batch | `LayerRuntime` evaluation | Held by the current update only | Motion output plus layer composition | Validated request batch passed to `AnimationBackend` |
| `AnimationBackend` contract | Caller supplies an implementation | Caller that owns the backend | Request batches and lifecycle commands | Materialization, atomic absolute/relative positioning, capabilities, debug state, and completion binding |
| `RobloxAnimatorBackend` | Caller through `robloxAnimatorBackend.new` | Caller that owns the backend | `ClipRequest` batches and an `Animator` | Roblox generations, priority mapping, native weight/speed changes, and completion events |
| `AnimPlayback` generations | `RobloxAnimatorBackend` | `RobloxAnimatorBackend` | A request and resolved asset id | Private physical generation state and guarded engine callbacks |
| Roblox `Animation` / `AnimationTrack` | `AnimPlayback` | `RobloxAnimatorBackend` through `AnimPlayback` | Asset id, play, fade, weight, speed, position, and priority commands | Physical playback and `Stopped`/`Ended` signals |

`StackModifier` is a public numeric utility, but the source audit shows no
runtime relationship to this update transaction. It is intentionally absent
from the graph and is documented separately in the
[components/stackModifier API page](/api/components/stackModifier).

## Dependency direction

The runtime dependency direction is one-way:

```text
consumer policy
    -> caller-owned scheduler
    -> AnimationController
    -> LayerRuntime / MotionNode evaluation
    -> AnimationBackend
    -> Roblox Animator implementation
```

Public contracts live below `src/animGraph/types`. Runtime implementations use
script-relative requires. The controller knows the backend contract, but the
motion nodes know neither Roblox instances nor backend implementation details.
The Roblox backend knows `Animation` and `AnimationTrack`, while those objects
never cross the package's public boundary.

## Sampled update transaction

`controller:update()` is a caller-invoked transaction:

1. The controller calls the borrowed `TimeSource` exactly once and validates one
   finite sample time.
2. Each active `LayerRuntime` selects its play reader, then layer reader, then
   controller default. Each distinct selected function is called at most once
   with that same sampled time.
3. All logical positions and forward deltas are preflighted against each
   layer activation's baseline. A non-finite or backward sample rejects before
   graph or backend mutation.
4. Baselines are committed, then layers evaluate their motion nodes with the
   derived logical `dt`. `StateMachineRuntime` advances transitions with that
   value; layer weight and native speed remain separate composition inputs.
5. Motion nodes produce `ClipRequest` records. `LayerRuntime` stamps the
   authoritative `deltaTime`, composes layer weight/speed, and consumes
   first-emitted play overrides.
6. The controller validates the complete batch, including unique `trackKey`
   values and valid positions, then calls `AnimationBackend:apply(requests)`.

The backend is called on every successful sample, including a zero-delta
sample. The Roblox implementation ignores delta-only changes when native
desired state is unchanged, while a custom backend may consume each request's
`deltaTime`.

## Logical and native domains

Logical time is the sampled graph domain. It advances state machines and blend
evaluation through `MotionEvaluateContext.dt` and `ClipRequest.deltaTime`.
Native speed is a separate request value composed from authored request speed
and layer speed, then passed to the backend. AnimGraph never multiplies logical
delta by native speed, and a held logical reader does not implicitly stop a
native Roblox fade.

Initial and live native positions use the public `AnimationPosition` union.
Initial placement is one-shot per materialized generation. `setTrackPosition`
addresses the current generation by `trackKey`, supersedes a pending initial
position, and does not replay graph history or replace the generation.
`offsetTrackPosition` is a separate atomic relative command: it accepts finite
signed seconds and binds the physical read/modify/write to that same active
generation without exposing a getter or backend-specific handle.

When length is unresolved, each `AnimPlayback` owns an optional absolute base
and an independent accumulated offset. Absolute set discards older offsets;
later offsets compose from the new base. Resolution uses that absolute base or,
when absent, the physical position observed at resolution, then wraps/clamps the
combined value into one write. Consumed offsets are never replayed by ordinary
request application.

At a non-looping boundary, completion is classified against desired signed native
speed: positive is outward only at `Length`, negative is outward only at `0`, and
zero holds either boundary active. Interior positions remain active. Looping
absolute and relative positions wrap and never complete from addressing.
Relative terminal classification uses desired signed speed rather than delta
sign or a temporary native hold. A known-length reverse start
activates negative speed through `Play` before the upper position write; an
unknown-length reverse start holds `Play` at zero until one resolved position
write of its absolute base plus queued offsets, then adopts the retained
negative speed without replay or generation change. Later sign pivots use only
`AdjustSpeed`.

## Backend generation lifecycle

`RobloxAnimatorBackend` validates a whole request batch before mutation. It
keeps one active generation per `trackKey`, retiring generations by monotonic
generation token, and lightweight completed tombstones by key. A same-key clip
replacement or `forceRestart` retires the old generation and creates a new
one; the generations may coexist while the old native fade runs.

`AnimPlayback` creates an `Animation`, loads its `AnimationTrack`, applies
initial native state, and tracks generation-local pending absolute/relative
positioning. Changed native
weight, speed, loop, or priority updates only that property. Unchanged desired
state does not replay, reposition, restart a fade, or create a generation. The
only pending-reverse exception is the ordered position write and retained-speed
application after positive length becomes available. Completion, retirement,
cleanup, and replacement clear pending address state before that generation can
affect another owner.

Retirement invalidates natural-completion classification before `Stop(fade)`.
`Ended` owns final physical cleanup for non-zero fades; zero-fade or already
inactive generations clean immediately. Generation tokens make stale engine
signals harmless to newer generations.

## Completion and teardown

Natural non-looping forward playback at the upper end, natural reverse playback
at the lower end, and accepted outward initial/live boundary positioning are
committed as completion exactly once. The backend stores a completed tombstone,
then forwards `trackCompleted` through the controller's bound callback into its
`EventBus`. Event dispatch snapshots listeners, so callbacks may re-enter
playback operations without mutating stale generation state.

Explicit stop, request disappearance, replacement, restart retirement, `clear`,
and `destroy` suppress completion. A looping track never completes merely by
crossing a loop boundary.

`clear()` stops layer intent, clears parameters, and establishes the backend's
immediate physical boundary. `destroy()` first releases the controller's one
backend completion binding, then clears the controller/event bus and destroys
the backend. The caller disconnects its scheduler before or alongside this
teardown. No package-owned object retains the caller's timing functions.

For task-oriented usage, start with the [guide overview](/guides/) or
[getting started](/guides/getting-started). For exact callable and type
contracts, use the [API index](/api/).

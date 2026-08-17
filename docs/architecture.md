---
aside: false
sidebar: false
pageClass: architecture-page
---

# Architecture

AnimGraph is a caller-scheduled graph runtime with absolute-time evaluation. A
caller supplies one explicit coordinate per update and borrowed time readers.
The controller owns a coherent transaction, layers pass literal time samples
through the graph, and the injected backend owns physical clip phase.

AnimGraph owns no clock, RunService connection, character policy, or consumer
playback handle.

<script setup>
import runtimeDiagram from "./assets/animgraph-runtime.svg";
import completionDiagram from "./assets/animgraph-completion.svg";
</script>

<ZoomableDiagram
  :src="runtimeDiagram"
  alt="AnimGraph explicit-time evaluation and backend strategy ownership"
  height="min(78vh, 920px)"
/>

<ZoomableDiagram
  :src="completionDiagram"
  alt="AnimGraph backend completion, tombstone, controller, and event flow"
  height="min(46vh, 420px)"
/>

The authored diagram sources are under `docs/diagrams`; generated SVGs are
checked in under `docs/assets`. Backend-private playback objects and Roblox
instances never cross the public boundary.

## Ownership

| Owner | Owns | Does not own |
| --- | --- | --- |
| Consumer scheduler | Sampling cadence, finite monotonic `sampleTime`, time mappings, continuity/discontinuity policy, native re-addressing | Graph state or backend generations |
| `AnimationController` | Command queue, reader cache, atomic sample preflight, layers, parameters, events, request transaction | A clock or physical clip phase |
| `LayerRuntime` | Reader precedence, literal sample propagation, layer composition | Time mapping, physical position, or Roblox timing |
| Motion graph | State selection, transition anchors, blend evaluation, backend-neutral requests | Reader selection, discontinuity policy, or concrete tracks |
| `AnimationBackend` | Physical generations, positioning, completion, teardown, fixed position strategy | State-machine progression or consumer clock mapping |
| `RobloxAnimatorBackend` | Native or sampled playback strategy, Roblox objects, priority mapping, fades, tombstones | Consumer scheduling or graph clocks |

`StackModifier` is a separate numeric utility and does not participate in this
transaction.

## Dependency direction

```text
consumer scheduler/readers
    -> AnimationController
    -> LayerRuntime / MotionNode evaluation
    -> AnimationBackend
    -> Roblox playback strategy
```

Public contracts live below `src/animGraph/types`. Motion nodes know no Roblox
types. The controller depends on the backend interface, not the Roblox
implementation.

## Update transaction

`controller:update(sampleTime)` performs one transaction:

1. Validate that `sampleTime` is finite and is not lower than the last accepted
   coordinate. Equal coordinates are valid.
2. Preview queued graph-intent commands to resolve the effective reader for
   every layer after those commands take effect.
3. Resolve controller-default, then layer, then active-play reader overrides.
   Call each distinct selected function once with the same `sampleTime`.
4. Validate every `TimeSample.position` and `TimeSample.rate` without mutation.
5. Commit queued play/stop, parameter, layer-property, and reader commands;
   retain the preflighted samples for evaluation.
6. Evaluate motion nodes with absolute `MotionEvaluateContext.timePosition` and
   `timeRate`. Transitions derive progress from their time-position anchor.
7. Validate the complete `ClipRequest` batch and call
   `backend:apply(sampleTime, requests)`.

An invalid coordinate or reader result rejects before step 5. Queued commands
remain pending. The backend is called on every successful update, including
equal-coordinate and empty-request updates.

The controller captures a lifecycle epoch before invoking borrowed code. A
reader or graph-event callback that calls `clear` or `destroy` changes that
epoch, aborting the old transaction before it can commit stale reader-preview
commands or apply stale requests. Commands issued after `clear` use the new
queue and remain available to the next update.

## Literal time basis

`TimeReader(sampleTime)` returns one atomic `{ position, rate }` sample.
AnimGraph uses `position` directly for graph, transition, custom-motion, and
sampled physical evaluation. It uses `rate` to compose optimized native
playback and final terminal direction. It never derives rate from consecutive
positions.

The graph does not accumulate frame `dt`, maintain a source baseline, classify
jumps, or make reader changes continuous. Pauses, reversals, seeks, and reader
replacement therefore mean exactly what the selected reader returns. A caller
that wants a continuous mapping supplies one; a caller that wants a native
track physically re-addressed also issues `setTrackPosition` or
`offsetTrackPosition`.

State machines retain forward-only discrete-state semantics. An active
transition stores a start-position anchor. If its supplied position moves
backward, the transition shifts the anchor by the same amount so progress holds
instead of rewinding or stalling. A forward jump remains literal. Replaying the
same stateful runtime does not synthesize a phase-zero sample.

## Command timing

Graph intent takes effect on the next valid update. This includes play, stop,
parameters/triggers, layer weight/speed/priority/backend data, and time-reader
changes. Getters expose committed state.

`setTrackPosition` and `offsetTrackPosition` are deliberately different: they
are synchronous physical-generation commands whose boolean reports acceptance
by the current active generation. `clear` and `destroy` are immediate lifecycle
boundaries.

## Graph and physical domains

```text
time-basis position != physical clip phase
```

Time-basis position drives transitions and graph events. Request speed and
explicit position commands affect physical playback only. Negative physical
speed never rewinds the state machine, and seeking a clip never replays graph
history.

`ClipRequest` therefore carries desired pre-clock physical speed plus the
atomic `timePosition` and `timeRate`, but no graph delta. The backend receives
the controller's shared sampling coordinate separately for apply ordering.

## Backend position strategies

`BackendPositionMode` is a fixed backend construction strategy and capability:

- `nativeRate` starts Roblox tracks at `request.speed * request.timeRate` and
  uses `AdjustSpeed` when that effective speed changes. It does not write
  `TimePosition` every update or churn unchanged native properties.
- `sampledPosition` starts tracks at native rate zero and derives physical
  position as `physicalAnchor + request.speed * (request.timePosition -
  timeAnchor)` on every apply. Speed and loop changes first evaluate/rebase
  with the old values. Final terminal direction includes `request.timeRate`.

Both strategies share the same manager for active/retiring/completed
generations, priority mapping, weight/fade operations, synchronous positioning,
completion dispatch, tombstones, and cleanup.

Sampled generations preflight anchor-derived elapsed and offset arithmetic
before the backend accepts a batch. This rejects finite inputs whose
derived arithmetic overflows without partially sampling the batch. Apply depth
is restored on every error path, keeping later completion dispatch live.

When sampled playback has no positive Roblox `Length`, its physical write is
deferred while anchor-relative phase continues to accrue. Once length resolves,
the generation wraps or clamps the complete address and samples it. Explicit
positioning rebases at the generation's last accepted request time position.

## Lifecycle and completion

The Roblox backend validates a request batch before materialization. It owns one
active generation per `trackKey`, any retiring physical generations, and
lightweight completed tombstones. Replacement or `forceRestart` can create a
new generation while old physics fades.

Native mode classifies natural Roblox completion signals. Sampled mode
classifies non-looping completion from sampled physical phase and ignores
native stop signals while an active zero-rate sampled generation remains
owned. Sampled completion immediately cleans the otherwise-frozen physical
track after committing its tombstone. Explicit stop, omission, replacement
retirement, clear, and destroy do not emit natural completion.

Completion is committed before `trackCompleted` dispatch. Listener snapshots
permit safe re-entry. `Ended` owns cleanup of non-zero retirement fades; zero
fade and inactive retirement clean immediately.

The backend also epochs its lifecycle around the borrowed asset resolver. A
resolver that calls `clear` or `destroy` invalidates the pending materialization
before any track is loaded, so the external lifecycle boundary cannot be undone
by the same apply.

See the [absolute-time amendment](/todo/temporalAmendment) for the full
contract, source inventory, edge cases, and migration record.

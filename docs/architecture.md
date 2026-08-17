---
aside: false
sidebar: false
pageClass: architecture-page
---

# Architecture

AnimGraph is a caller-scheduled graph runtime with absolute-time evaluation. A
caller supplies one explicit coordinate per update and borrowed logical-time
readers. The controller owns a coherent transaction, layers own monotonic graph
phase, and the injected backend owns physical clip phase.

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
| Consumer scheduler | Sampling cadence, finite monotonic `sampleTime`, reader construction and re-address policy | Graph state or backend generations |
| `AnimationController` | Command queue, reader cache, atomic sample preflight, layers, parameters, events, request transaction | A clock or physical clip phase |
| `LayerRuntime` | Reader precedence, source/revision baseline, monotonic logical graph phase, layer composition | Physical position or Roblox timing |
| Motion graph | State selection, transition anchors, blend evaluation, backend-neutral requests | Reader selection or concrete tracks |
| `AnimationBackend` | Physical generations, positioning, completion, teardown, fixed position strategy | Logical state-machine progression |
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
   Call each
   distinct selected function once with the same `sampleTime`.
4. Validate every `LogicalTimeSample` and prepare each layer's next source
   baseline and logical phase without mutation.
5. Commit queued play/stop, parameter, layer-property, and reader commands;
   commit the prepared layer samples.
6. Evaluate motion nodes with absolute `MotionEvaluateContext.logicalPosition`.
   Transitions derive progress from their start-position anchor.
7. Validate the complete `ClipRequest` batch and call
   `backend:apply(sampleTime, requests)`.

An invalid coordinate or reader result rejects before step 5. Queued commands
remain pending and prior baselines remain intact. The backend is called on every
successful update, including equal-coordinate and empty-request updates.

## Logical phase rebasing

A layer's source position may pause, reverse, or jump to a new address. Its
logical graph phase remains monotonic:

```text
same revision + forward source movement -> add exact positive difference
same revision + stationary/backward     -> hold phase, replace source baseline
new addressRevision                     -> hold phase, replace source baseline
reader replacement                      -> hold phase, establish new baseline
new play                                -> phase zero, establish first baseline
```

The graph does not accumulate frame `dt`. A transition stores its logical start
position and computes elapsed as `current - start`. Large forward jumps and
same-coordinate re-evaluation therefore have direct, deterministic semantics.

## Command timing

Graph intent takes effect on the next valid update. This includes play, stop,
parameters/triggers, layer weight/speed/priority/backend data, and logical-time
reader changes. Getters expose committed state.

`setTrackPosition` and `offsetTrackPosition` are deliberately different: they
are synchronous physical-generation commands whose boolean reports acceptance
by the current active generation. `clear` and `destroy` are immediate lifecycle
boundaries.

## Logical and physical domains

```text
logical graph phase != physical clip phase
```

Logical phase drives transitions and graph events. Request speed and explicit
position commands affect physical playback only. Negative physical speed never
rewinds the state machine, and seeking a clip never replays graph history.

`ClipRequest` therefore contains desired physical speed but no logical delta.
The backend receives the shared sample coordinate separately.

## Backend position strategies

`BackendPositionMode` is a fixed backend construction strategy and capability:

- `nativeRate` starts Roblox tracks at the desired signed rate and uses
  `AdjustSpeed` for changes. Unchanged requests do not reposition or churn
  native properties.
- `sampledPosition` starts tracks at native rate zero and derives physical
  position from `(positionAnchor, sampleTimeAnchor, speed)` on every apply.
  Speed and loop changes first evaluate/rebase with the old values.

Both strategies share the same manager for active/retiring/completed
generations, priority mapping, weight/fade operations, synchronous positioning,
completion dispatch, tombstones, and cleanup.

When sampled playback has no positive Roblox `Length`, its physical write is
deferred while anchor-relative phase continues to accrue. Once length resolves,
the generation wraps or clamps the complete address and samples it. Explicit
positioning rebases at the last accepted backend coordinate.

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

See the [absolute-time amendment](/todo/temporalAmendment) for the full
contract, source inventory, edge cases, and migration record.

# Absolute-Time Evaluation Amendment

**Status:** implemented in the unreleased library contract. Deterministic and
static verification is complete; real-Roblox verification of the new
`sampledPosition` strategy remains an explicit Studio gate.

This amendment replaces the former `TimeSource` plus scalar
`LogicalPositionReader` design. Temporal progression is now derived from an
explicit sampling coordinate and phase anchors. The graph is backend-neutral;
physical clip phase remains backend-owned.

## Feasibility conclusion

The migration is feasible without turning every motion node into a clock owner.
The source audit found one graph-time accumulator:
`TransitionRuntime._elapsed += dt`. Reader baselines and Roblox playback were
already centralized. The implementation therefore places time injection at
three graph ownership boundaries and phase rebasing at two runtime boundaries:

- `AnimationController` samples selected readers transactionally;
- `LayerRuntime` converts reader movement into a monotonic logical phase;
- `TransitionRuntime` evaluates progress from a start-position anchor;
- `nativeRate` playback leaves physical advancement to Roblox;
- `sampledPosition` playback owns physical phase anchors and writes sampled
  position every update.

Blends and clips do not need private clocks. They receive the layer's absolute
`logicalPosition`. This keeps reader scope out of arbitrary subtrees and avoids
duplicating cache/baseline state across motion nodes.

The result is pure with respect to temporal progression, not globally
stateless. State selection, triggers, one-shot play overrides, generations,
completion tombstones, and queued commands remain intentional runtime state.

## Frozen public contract

### Sampling coordinate

```luau
controller:update(sampleTime)
```

`sampleTime` is a finite, monotonic sampling coordinate. Equal values are
legal. A value lower than the controller's last accepted coordinate rejects the
update before reader sampling or graph mutation. Re-evaluating the same
coordinate after queuing new graph intent is supported.

The controller owns no clock and no scheduler connection. A usual Roblox call
site is:

```luau
local connection = RunService.PreAnimation:Connect(function()
	controller:update(os.clock())
end)
```

### LogicalTimeReader

```luau
export type LogicalTimeSample = {
	position: number,
	addressRevision: number,
}

export type LogicalTimeReader = (sampleTime: number) -> LogicalTimeSample
```

Both returned numbers must be finite. Each distinct reader selected by at least
one active layer is called once per update and receives the exact coordinate
passed to `update`.

Reader resolution starts with `AnimationControllerConfig.logicalTimeReader`,
then applies the `LayerDefinition.logicalTimeReader` override, then the
active-play `LayerPlayOptions.logicalTimeReader` override. The last present
reader wins.

There are no arbitrary motion-node or subtree readers. Runtime reader changes
use `setDefaultLogicalTimeReader`, `setLayerLogicalTimeReader`, and
`setActivePlayLogicalTimeReader` and take effect with the other queued graph
intent on the next valid update.

`addressRevision` changes only when the reader discontinuously re-addresses its
source. Ordinary continuous rate changes keep the revision stable.

### Logical phase rebasing

Each active layer stores a source baseline and a monotonic graph phase:

```luau
local sourceDelta = sample.position - sourcePosition

if sample.addressRevision ~= sourceAddressRevision then
	-- Discontinuous address: hold phase and replace the source baseline.
elseif sourceDelta <= 0 then
	-- Stationary or backward source: hold phase and replace the baseline.
else
	logicalPosition += sourceDelta
end

sourcePosition = sample.position
sourceAddressRevision = sample.addressRevision
```

A new play starts logical phase at zero and treats its first reader sample as a
baseline. A reader change preserves the current graph phase but establishes a
new source baseline. Forward movement with an unchanged revision advances by
the exact difference. Stationary movement, backward movement, and revision
changes hold phase and rebase the source baseline.

All selected samples are validated and all next phases are prepared before any
package state changes. If the coordinate or any sample is invalid, the whole
update rejects, prior baselines remain intact, the backend is not called, and
queued graph intent remains queued.

### Motion and transition evaluation

`MotionEvaluateContext` contains `logicalPosition`, not `dt`. `ClipRequest`
contains no graph delta. A transition stores the logical position at which it
started:

```luau
local elapsed = math.clamp(logicalPosition - startPosition, 0, duration)
local alpha = if duration <= 0 then 1 else elapsed / duration
```

This eliminates per-frame transition accumulation. Equal-coordinate
evaluation is idempotent for transition progress, and large forward samples are
evaluated directly from the anchor.

### Graph-intent transaction

The following calls enqueue intent for the next valid `update(sampleTime)`:

- `play` and `stopLayer`;
- parameter, float, bool, and trigger writes;
- layer weight, speed, priority, and backend-data changes;
- default, layer, and active-play logical-reader changes.

Getters expose committed state, not queued values. Commands issued during or
after one update are observed by the next update. `clear` and `destroy` remain
immediate lifecycle boundaries.

`setTrackPosition` and `offsetTrackPosition` remain synchronous physical-
generation commands. Their boolean still means that the currently active
generation accepted the command. They do not enter the graph-intent queue and
do not alter logical graph phase. A consumer such as `CharacterAnimator` may
retain a pre-materialization command and issue it after AnimGraph creates the
generation.

### Backend coordinate and position strategy

```luau
export type BackendPositionMode =
	"nativeRate"
	| "sampledPosition"

backend:apply(sampleTime, requests)
```

The backend receives the exact coordinate used for graph evaluation. The
Roblox backend validates finite monotonic coordinates even when used directly.
Its `positionMode` is fixed when the backend is constructed and reported in
`BackendCapabilities`; it is not authored content, a motion-node option, or a
per-layer switch.

`nativeRate` uses `AnimationTrack:Play` and `AdjustSpeed` for physical
advancement. It preserves the prior optimized behavior: unchanged requests do
not seek or churn native properties.

`sampledPosition` plays tracks at native speed zero, retains Roblox weight and
fade operations, and calculates physical phase from anchors:

```luau
local position = positionAnchor + speed * (sampleTime - sampleTimeAnchor)
```

Before a signed speed or loop-policy change, the backend evaluates this formula
with the old values, stores the result as the new position anchor, stores the
current coordinate as the new time anchor, and then applies the new values.
Every apply samples/writes the wrapped or clamped physical position. An
unresolved Roblox `Length` delays the write while the anchor-relative phase
continues to accrue.

Synchronous physical positioning in sampled mode rebases at the backend's last
accepted coordinate. A same-coordinate apply therefore preserves the explicit
position; later coordinates advance from that new anchor.

## Logical phase is not physical phase

This separation is binding:

```text
logical graph phase != physical clip phase
```

Logical phase drives state-transition progress. Physical phase belongs to the
backend and is affected by signed request speed and explicit physical
positioning. Negative native speed does not rewind the state machine. A
physical seek does not replay graph history. Layer/request speed is never
multiplied into logical phase.

## Core files changed

| Area | Files | Change |
| --- | --- | --- |
| Shared contract | `types/def/init.luau`, public barrels | Replace `TimeSource`/scalar reader with `LogicalTimeSample` and `LogicalTimeReader` |
| Controller transaction | `controller/animationController/init.luau`, controller types | Explicit coordinate, once-per-reader cache, atomic sample preflight, queued graph intent, reader setters |
| Layer phase | `runtime/layerRuntime/init.luau`, layer types | Source/revision baselines, monotonic logical phase, reader precedence, absolute evaluation context |
| Motion request | `types/motions/motionNode.luau`, `motions/clipNode/init.luau` | Add `logicalPosition`; remove `dt` and request `deltaTime` |
| Transition | `runtime/transitionRuntime/init.luau`, `runtime/stateMachineRuntime/init.luau` | Replace `_elapsed` accumulation with start-position sampling |
| Backend contract | backend types, `utils/requestValidation.luau` | `apply(sampleTime, requests)`, strategy capability, finite request validation |
| Roblox native strategy | `backends/robloxAnimatorBackend/animPlayback.luau` | Preserve native-rate lifecycle and signed-speed behavior under the new apply coordinate |
| Roblox sampled strategy | `backends/robloxAnimatorBackend/sampledAnimPlayback.luau` | Physical phase anchors, per-update position sampling, rebasing, unknown-length handling |
| Backend manager | `backends/robloxAnimatorBackend/init.luau` | Fixed strategy selection with shared generations, retirement, tombstones, completion, and positioning ports |

## Edge cases and policy

- **Equal coordinate:** legal; readers are sampled again and new graph intent is
  evaluated without temporal advancement.
- **Backward controller coordinate:** rejected. This is distinct from a reader
  returning a backward source position, which holds graph phase and rebases.
- **Revision change:** holds graph phase even if source position jumps forward.
- **Reader replacement:** holds existing graph phase; a replacement play starts
  a fresh zero phase.
- **Looping:** logical phase never wraps. Physical looping is backend-owned;
  sampled playback wraps modulo positive clip length.
- **Signed speed:** changes only physical playback. Sampled mode rebases before
  adopting the new speed; native mode delegates it to Roblox.
- **Completion:** non-looping sampled playback completes when sampled physical
  phase reaches the outward boundary. Native mode continues to classify Roblox
  signals and explicit boundary placement. Completed tombstones suppress
  unchanged replay in both modes.
- **Blending and fades:** blend weights are evaluated at the current logical
  coordinate. Roblox weight interpolation/fade timing remains engine-owned and
  is not made deterministic by `sampledPosition`.
- **Unknown length:** sampled phase accrues from its anchor while the physical
  write waits. Initial/explicit absolute position and ordered offsets remain
  generation-local.
- **Markers and root motion:** per-frame `TimePosition` writes may not reproduce
  native marker, keyframe-event, or root-motion behavior. These need explicit
  consumer semantics before sampled mode is used for such content.
- **Floating-point precision:** long-running/high-magnitude coordinates should
  be periodically re-addressed by the reader with a new `addressRevision`.
  Anchors avoid ordinary frame-by-frame accumulation but cannot remove IEEE-754
  precision limits.
- **Backend determinism:** sampled physical position is deterministic for a
  given coordinate/request history. Roblox asset loading, weight fades, and
  engine pose application remain engine behavior.

## Migration sequence

The library migration was executed in dependency order:

1. freeze public time, command, phase-separation, and backend-strategy contracts;
2. replace shared types and request shape;
3. implement controller preflight and queued graph intent;
4. migrate layers and transitions to absolute logical position;
5. add `sampleTime` to the backend contract while preserving native behavior;
6. add sampled physical playback behind the fixed backend strategy;
7. migrate the dev harness, tests, diagrams, and public documentation;
8. run deterministic, formatting, lint, Luau, require-graph, and docs gates;
9. perform the remaining Studio checklist for real sampled-pose, fade,
   completion, marker, and cleanup behavior.

VoxelMMO remains the owner of its RunService/TemporalService scheduling,
clock-domain selection, `addressRevision` policy, reader construction, and any
pre-materialization position command. AnimGraph imports none of those systems.

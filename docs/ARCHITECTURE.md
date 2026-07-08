# AnimGraph Architecture

AnimGraph is an authored animation controller runtime. It turns typed gameplay
intent into backend-neutral `ClipRequest` records, then delegates concrete
playback to an injected backend.

The package is not a character stack. It knows about layers, states, parameters,
clips, motion nodes, transitions, events, and backend calls. It does not know
about VoxelMMO, anatomy sockets, combat actions, abilities, or VFX.

## Lifecycle

```text
Backend             --construct first-->  RobloxAnimatorBackend / future backend
   | pass into config
   v
Controller          --owns--> layers, parameters, event bus
   | play(layer, motion)
   v
LayerRuntime        --evaluates--> active MotionNode
   | every update
   v
MotionNode          --returns--> ClipRequest[]
   | controller collects all layers
   v
AnimationBackend    --applies--> concrete runtime tracks / poses
```

## Controller

`AnimationController` is the public runtime facade. It owns:

- an injected `AnimationBackend`;
- a typed `ParameterStore`;
- one `LayerRuntime` per configured layer;
- an event bus;
- an optional `PreAnimation` update connection.

Controller update is intentionally simple:

1. Evaluate each layer in layer order.
2. Let the layer evaluate its current motion node.
3. Collect backend-neutral clip requests.
4. Pass all requests to `backend:apply(requests, dt)`.

The controller does not load Roblox animations and does not call
`AnimationTrack` directly.

## Layers

A layer is a logical animation lane controlled by the caller. Typical game
layers are `"base"`, `"upperBody"`, `"action"`, `"reaction"`, or a closed enum.

Each layer stores:

- `id`;
- `weight`;
- `speed`;
- `logicalPriority`;
- optional `layerBackend` data;
- default fade in/out;
- current state label;
- current motion node;
- per-play overrides.

Layer `speed` is playback rate. It multiplies clip/node/request speed before the
backend receives the request. It is not locomotion velocity. Locomotion velocity
should be represented as a parameter such as `"speed"` and fed into a blend node.

## Parameters

Parameters are caller-owned inputs read by motion nodes and transition
conditions. The controller supports:

- raw `setParameter`;
- float helpers;
- bool helpers;
- trigger helpers.

Triggers are consumed by transition evaluation. Use triggers for one-frame
intent such as `"attack"`, `"roll"`, or `"clearAction"`; use floats/bools for
continuous state such as movement speed or grounded state.

## Motions

A `MotionNode` is any object that implements:

```luau
evaluate(context) -> { ClipRequest }
getDebugSnapshot() -> MotionDebugSnapshot
```

Built-in motion nodes are:

- `ClipNode` for one clip;
- `Blend1DNode` for numeric one-axis blends;
- `Blend2DNode` for two-axis blends;
- `StateMachineRuntime` for authored states and transitions.

Motion nodes do not play tracks. They only produce requests.

## Requests

`ClipRequest` is the contract between controller logic and backend execution.
Requests carry:

- track identity;
- layer and state;
- clip identity;
- weight;
- speed;
- looped;
- logical priority;
- optional typed layer backend data;
- fade time;
- optional time position;
- restart behavior.

Backends should treat requests as the complete desired state for the current
frame or update step.

## Backend

`AnimationBackend` is a structural interface. A backend does not inherit from a
base class; it only needs to implement the required methods:

```luau
apply(requests, dt)
stopLayer(layer, fadeTime?)
clear()
destroy()
getCapabilities()
getDebugSnapshot()
```

The current backend is `RobloxAnimatorBackend`, which translates requests into
Roblox `AnimationTrack` operations.

## Events

State machines emit controller events through the evaluation context. Current
events are intended for state and transition observability:

- state enter;
- state exit;
- transition start;
- transition end.

Game code can subscribe through `controller:on(eventName, callback)`. Keep event
payloads descriptive and backend-neutral. Roblox marker forwarding should be a
future backend/controller slice, not a gameplay-specific event system.

## Ownership

```text
Caller
  owns Animator / rig / character stack
  owns RobloxAnimatorBackend or future backend
  owns AnimationController
    owns ParameterStore
    owns LayerRuntime(s)
    owns EventBus
    references MotionNode(s)
  owns higher-level gameplay adapters
```

Motion nodes can be shared by convention if game code treats them as authored
definitions. State machine runtimes have internal active state, so create one
runtime per controller/layer that needs independent state.

## Debugging

The main debug surface is `controller:getDebugSnapshot()`.

It contains:

- current parameters;
- layer state, weight, speed, priority, and active motion snapshot;
- backend capabilities, warnings, and track state.

Use this first when diagnosing migration issues. It tells you whether a bug is
in gameplay intent, motion evaluation, or backend playback.

## Extension Rules

When adding features, keep the layer clear:

- Controller features should stay backend-neutral.
- Backend features should not leak concrete runtime objects into public gameplay
  calls.
- VoxelMMO convenience methods should usually live in a VoxelMMO adapter, not
  inside AnimGraph.
- If a feature belongs to any game using authored animation control, it may
  belong in AnimGraph.
- If a feature names an ability, weapon, socket, hitbox, or damage event, it
  belongs above AnimGraph.

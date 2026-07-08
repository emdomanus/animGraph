# Types

AnimGraph exposes Luau types from the package entrypoint so consumers can type
layers, states, parameters, clips, backends, and motion graphs without requiring
implementation modules directly.

```luau
local AnimGraph = require(ReplicatedStorage.packages.animGraph)

type LayerBackend = AnimGraph.RobloxLayerBackend
type Controller = AnimGraph.AnimationController<Layer, State, Param, Clip, LayerBackend>
type Backend = AnimGraph.AnimationBackend<Layer, State, Clip, LayerBackend>
type Motion = AnimGraph.MotionNode<Layer, State, Param, Clip, LayerBackend>
```

The exact public surface is re-exported from
[`src/init.luau`](https://github.com/emdomanus/animGraph/blob/main/src/init.luau)
and backed by
[`src/animGraph/types/init.luau`](https://github.com/emdomanus/animGraph/blob/main/src/animGraph/types/init.luau).

## Type Index

### Controller

- [`AnimationControllerConfig`](#animationcontrollerconfig)
- [`AnimationController`](#animationcontroller)
- [`AnimationControllerDebugSnapshot`](#animationcontrollerdebugsnapshot)
- [`AnimationEventName`](#animationeventname)
- [`AnimationEvent`](#animationevent)
- [`AnimationEventCallback`](#animationeventcallback)

### Layers And Parameters

- [`LayerDefinition`](#layerdefinition)
- [`LayerPlayOptions`](#layerplayoptions)
- [`LayerDebugSnapshot`](#layerdebugsnapshot)
- [`ParameterValue`](#parametervalue)
- [`ParameterStore`](#parameterstore)

### Motions

- [`MotionNode`](#motionnode)
- [`MotionEvaluateContext`](#motionevaluatecontext)
- [`ClipRequest`](#cliprequest)
- [`MotionRequestOverrides`](#motionrequestoverrides)
- [`MotionDebugSnapshot`](#motiondebugsnapshot)
- [`ClipNodeConfig`](#clipnodeconfig)
- [`Blend1DSample`](#blend1dsample)
- [`Blend1DNodeConfig`](#blend1dnodeconfig)
- [`Blend2DSample`](#blend2dsample)
- [`Blend2DNodeConfig`](#blend2dnodeconfig)

### State Machines

- [`StateDefinition`](#statedefinition)
- [`StateMachineConfig`](#statemachineconfig)
- [`TransitionDefinition`](#transitiondefinition)
- [`TransitionCondition`](#transitioncondition)
- [`TransitionConditionOp`](#transitionconditionop)

### Backends

- [`AnimationBackend`](#animationbackend)
- [`BackendCapabilities`](#backendcapabilities)
- [`BackendDebugSnapshot`](#backenddebugsnapshot)
- [`RobloxAnimatorBackendConfig`](#robloxanimatorbackendconfig)
- [`RobloxLayerBackend`](#robloxlayerbackend)
- [`LogicalPriorityBand`](#logicalpriorityband)

### Components

- [`StackModifier`](#stackmodifier)
- [`Release`](#release)

## AnimationControllerConfig

Source:
[`src/animGraph/types/controller/animationController.luau`](https://github.com/emdomanus/animGraph/blob/main/src/animGraph/types/controller/animationController.luau)

Configuration passed to `AnimGraph.new` or `AnimGraph.animationController.new`.

```luau
export type AnimationControllerConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT> = {
	backend: AnimationBackend<LayerT, StateT, ClipT, LayerBackendT>,
	layers: { LayerDefinition<LayerT, LayerBackendT> }?,
}
```

The backend is required. Layers can be provided at construction or added later
with `controller:addLayer`.

## AnimationController

Source:
[`src/animGraph/types/controller/animationController.luau`](https://github.com/emdomanus/animGraph/blob/main/src/animGraph/types/controller/animationController.luau)

Main runtime API. It owns layers, parameters, events, update binding, and the
injected backend.

Important methods:

- `addLayer(definition)`
- `play(layer, motion, options?)`
- `stopLayer(layer, fadeTime?)`
- `setLayerWeight(layer, weight)`
- `setLayerSpeed(layer, speed)`
- `setLayerLogicalPriority(layer, logicalPriority)`
- `setLayerBackend(layer, layerBackend?)`
- `setFloat`, `setBool`, `setTrigger`
- `on(eventName, callback)`
- `update(dt)`
- `bindToPreAnimation()`
- `getDebugSnapshot()`
- `clear()`
- `destroy()`

Keep consumers on this interface instead of backend-specific track handles.

## AnimationControllerDebugSnapshot

Source:
[`src/animGraph/types/controller/animationController.luau`](https://github.com/emdomanus/animGraph/blob/main/src/animGraph/types/controller/animationController.luau)

Snapshot returned by `controller:getDebugSnapshot()`.

```luau
{
	parameters = ...,
	layers = ...,
	backend = ...,
}
```

Use this as the first debugging surface during migration.

## AnimationEventName

Source:
[`src/animGraph/types/controller/eventBus.luau`](https://github.com/emdomanus/animGraph/blob/main/src/animGraph/types/controller/eventBus.luau)

String union of controller event names. Events are emitted by controller-level
runtime behavior such as state machines and transitions.

## AnimationEvent

Source:
[`src/animGraph/types/controller/eventBus.luau`](https://github.com/emdomanus/animGraph/blob/main/src/animGraph/types/controller/eventBus.luau)

Backend-neutral event payload carrying layer and state context.

## AnimationEventCallback

Source:
[`src/animGraph/types/controller/eventBus.luau`](https://github.com/emdomanus/animGraph/blob/main/src/animGraph/types/controller/eventBus.luau)

Callback passed to `controller:on`.

## LayerDefinition

Source:
[`src/animGraph/types/runtime/layerRuntime.luau`](https://github.com/emdomanus/animGraph/blob/main/src/animGraph/types/runtime/layerRuntime.luau)

Layer construction config.

```luau
export type LayerDefinition<LayerT, LayerBackendT> = {
	id: LayerT,
	weight: number?,
	speed: number?,
	logicalPriority: number?,
	layerBackend: LayerBackendT?,
	defaultFadeIn: number?,
	defaultFadeOut: number?,
}
```

`speed` is playback rate. For movement velocity, use a parameter and feed it
into a blend node.

`layerBackend` is typed backend-specific layer data. For the Roblox backend, use
[`RobloxLayerBackend`](#robloxlayerbackend).

## LayerPlayOptions

Source:
[`src/animGraph/types/runtime/layerRuntime.luau`](https://github.com/emdomanus/animGraph/blob/main/src/animGraph/types/runtime/layerRuntime.luau)

Per-play options. These extend `MotionRequestOverrides`.

```luau
export type LayerPlayOptions<StateT, LayerBackendT> = MotionRequestOverrides<LayerBackendT> & {
	state: StateT?,
	fadeTime: number?,
	fadeIn: number?,
}
```

Use `state` as the authored/debug state label for the layer.

## LayerDebugSnapshot

Source:
[`src/animGraph/types/runtime/layerRuntime.luau`](https://github.com/emdomanus/animGraph/blob/main/src/animGraph/types/runtime/layerRuntime.luau)

Layer state returned in controller debug snapshots.

## ParameterValue

Source:
[`src/animGraph/types/controller/parameterStore.luau`](https://github.com/emdomanus/animGraph/blob/main/src/animGraph/types/controller/parameterStore.luau)

Supported parameter value union. Use the helper methods when possible:
`setFloat`, `setBool`, and `setTrigger`.

## ParameterStore

Source:
[`src/animGraph/types/controller/parameterStore.luau`](https://github.com/emdomanus/animGraph/blob/main/src/animGraph/types/controller/parameterStore.luau)

Internal parameter storage interface. Most consumers should use controller
parameter methods instead of constructing a store directly.

## MotionNode

Source:
[`src/animGraph/types/motions/motionNode.luau`](https://github.com/emdomanus/animGraph/blob/main/src/animGraph/types/motions/motionNode.luau)

Core authored motion interface.

```luau
export type MotionNode<LayerT, StateT, ParamT, ClipT, LayerBackendT> = {
	evaluate: (self, context) -> { ClipRequest<LayerT, StateT, ClipT, LayerBackendT> },
	getDebugSnapshot: (self) -> MotionDebugSnapshot,
}
```

Every built-in node implements this surface. Custom nodes should do the same.

## MotionEvaluateContext

Source:
[`src/animGraph/types/motions/motionNode.luau`](https://github.com/emdomanus/animGraph/blob/main/src/animGraph/types/motions/motionNode.luau)

Context passed into a motion node while a layer evaluates. It gives nodes access
to layer state, parameters, triggers, fade time, and event emission.

## ClipRequest

Source:
[`src/animGraph/types/motions/motionNode.luau`](https://github.com/emdomanus/animGraph/blob/main/src/animGraph/types/motions/motionNode.luau)

Backend-neutral playback request produced by motion nodes and consumed by
backends.

```luau
export type ClipRequest<LayerT, StateT, ClipT, LayerBackendT> = {
	trackKey: string,
	layer: LayerT,
	state: StateT?,
	clip: ClipT,
	weight: number,
	speed: number,
	looped: boolean,
	logicalPriority: number,
	layerBackend: LayerBackendT?,
	fadeTime: number,
	forceRestart: boolean,
}
```

## MotionRequestOverrides

Source:
[`src/animGraph/types/motions/motionNode.luau`](https://github.com/emdomanus/animGraph/blob/main/src/animGraph/types/motions/motionNode.luau)

Optional overrides for track key, weight, speed, looping, priority, layer backend
data, time position, and restart behavior.

## MotionDebugSnapshot

Source:
[`src/animGraph/types/motions/motionNode.luau`](https://github.com/emdomanus/animGraph/blob/main/src/animGraph/types/motions/motionNode.luau)

Small tree-shaped debug payload for motion nodes. Backends do not consume it.

## ClipNodeConfig

Source:
[`src/animGraph/types/motions/clipNode.luau`](https://github.com/emdomanus/animGraph/blob/main/src/animGraph/types/motions/clipNode.luau)

Configuration for `AnimGraph.clip` / `AnimGraph.clipNode.new`.

## Blend1DSample

Source:
[`src/animGraph/types/motions/blend1DNode.luau`](https://github.com/emdomanus/animGraph/blob/main/src/animGraph/types/motions/blend1DNode.luau)

One threshold sample in a 1D blend node.

## Blend1DNodeConfig

Source:
[`src/animGraph/types/motions/blend1DNode.luau`](https://github.com/emdomanus/animGraph/blob/main/src/animGraph/types/motions/blend1DNode.luau)

Configuration for `AnimGraph.blend1D`.

## Blend2DSample

Source:
[`src/animGraph/types/motions/blend2DNode.luau`](https://github.com/emdomanus/animGraph/blob/main/src/animGraph/types/motions/blend2DNode.luau)

One positioned sample in a 2D blend node.

## Blend2DNodeConfig

Source:
[`src/animGraph/types/motions/blend2DNode.luau`](https://github.com/emdomanus/animGraph/blob/main/src/animGraph/types/motions/blend2DNode.luau)

Configuration for `AnimGraph.blend2D`.

## StateDefinition

Source:
[`src/animGraph/types/runtime/stateMachineRuntime.luau`](https://github.com/emdomanus/animGraph/blob/main/src/animGraph/types/runtime/stateMachineRuntime.luau)

Authored state record. A state can be empty or have a motion node.

## StateMachineConfig

Source:
[`src/animGraph/types/runtime/stateMachineRuntime.luau`](https://github.com/emdomanus/animGraph/blob/main/src/animGraph/types/runtime/stateMachineRuntime.luau)

Configuration for `AnimGraph.stateMachine`.

## TransitionDefinition

Source:
[`src/animGraph/types/runtime/transitionRuntime.luau`](https://github.com/emdomanus/animGraph/blob/main/src/animGraph/types/runtime/transitionRuntime.luau)

Authored transition record.

```luau
export type TransitionDefinition<StateT, ParamT> = {
	name: string?,
	from: StateT?,
	to: StateT,
	duration: number?,
	priority: number?,
	conditions: { TransitionCondition<ParamT> }?,
}
```

`from = nil` means the transition may be considered from any state.

## TransitionCondition

Source:
[`src/animGraph/types/runtime/transitionRuntime.luau`](https://github.com/emdomanus/animGraph/blob/main/src/animGraph/types/runtime/transitionRuntime.luau)

Condition against one parameter.

## TransitionConditionOp

Source:
[`src/animGraph/types/runtime/transitionRuntime.luau`](https://github.com/emdomanus/animGraph/blob/main/src/animGraph/types/runtime/transitionRuntime.luau)

Supported operators:

```text
==, ~=, >, >=, <, <=, truthy, falsy, trigger
```

## AnimationBackend

Source:
[`src/animGraph/types/backends/animationBackend.luau`](https://github.com/emdomanus/animGraph/blob/main/src/animGraph/types/backends/animationBackend.luau)

Structural backend interface. Implement this to replace Roblox `Animator`
internals while keeping the public controller API.

```luau
export type AnimationBackend<LayerT, StateT, ClipT, LayerBackendT> = {
	apply: (
		self: AnimationBackend<LayerT, StateT, ClipT, LayerBackendT>,
		requests: { ClipRequest<LayerT, StateT, ClipT, LayerBackendT> },
		dt: number
	) -> (),
	stopLayer: (self, layer: LayerT, fadeTime: number?) -> (),
	clear: (self) -> (),
	destroy: (self) -> (),
	getCapabilities: (self) -> BackendCapabilities,
	getDebugSnapshot: (self) -> BackendDebugSnapshot,
}
```

## BackendCapabilities

Source:
[`src/animGraph/types/backends/animationBackend.luau`](https://github.com/emdomanus/animGraph/blob/main/src/animGraph/types/backends/animationBackend.luau)

Describes what the backend can solve, including unlimited priority, per-joint
fallback mode, and custom mask support.

## BackendDebugSnapshot

Source:
[`src/animGraph/types/backends/animationBackend.luau`](https://github.com/emdomanus/animGraph/blob/main/src/animGraph/types/backends/animationBackend.luau)

Backend-level debug state exposed through controller snapshots.

## RobloxAnimatorBackendConfig

Source:
[`src/animGraph/types/backends/robloxAnimatorBackend.luau`](https://github.com/emdomanus/animGraph/blob/main/src/animGraph/types/backends/robloxAnimatorBackend.luau)

Configuration for the shipped Roblox backend.

```luau
export type RobloxAnimatorBackendConfig<ClipT> = {
	animator: Animator,
	resolveAssetId: (clip: ClipT) -> number,
	defaultFadeOut: number?,
	defaultPriority: Enum.AnimationPriority?,
	priorityBands: { LogicalPriorityBand }?,
}
```

## RobloxLayerBackend

Source:
[`src/animGraph/types/backends/robloxAnimatorBackend.luau`](https://github.com/emdomanus/animGraph/blob/main/src/animGraph/types/backends/robloxAnimatorBackend.luau)

Roblox-specific layer extension data carried through generic AnimGraph requests.
This keeps `robloxPriority` out of the generic layer and motion types.

```luau
export type RobloxLayerBackend = {
	robloxPriority: Enum.AnimationPriority?,
}
```

Use it as the fifth controller generic when using `RobloxAnimatorBackend`:

```luau
type LayerBackend = AnimGraph.RobloxLayerBackend
type Controller = AnimGraph.AnimationController<Layer, State, Param, Clip, LayerBackend>
```

## LogicalPriorityBand

Source:
[`src/animGraph/types/backends/robloxAnimatorBackend.luau`](https://github.com/emdomanus/animGraph/blob/main/src/animGraph/types/backends/robloxAnimatorBackend.luau)

Mapping from backend-neutral numeric priorities to Roblox priority tiers.

## StackModifier

Source:
[`src/animGraph/types/components/stackModifier.luau`](https://github.com/emdomanus/animGraph/blob/main/src/animGraph/types/components/stackModifier.luau)

Small utility for stacking speed/weight-style modifiers. It is retained as a
shared component for future higher-level control helpers.

## Release

Source:
[`src/animGraph/types/components/stackModifier.luau`](https://github.com/emdomanus/animGraph/blob/main/src/animGraph/types/components/stackModifier.luau)

Callback used to release subscriptions or pushed modifiers.

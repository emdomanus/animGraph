# Motions

Motions are authored animation primitives. They evaluate into one or more
backend-neutral `ClipRequest` records. They do not load Roblox animations and do
not own tracks.

## MotionNode Contract

```luau
export type MotionNode<LayerT, StateT, ParamT, ClipT, LayerBackendT> = {
	evaluate: (
		self: MotionNode<LayerT, StateT, ParamT, ClipT, LayerBackendT>,
		context: MotionEvaluateContext<LayerT, StateT, ParamT, ClipT, LayerBackendT>
	) -> { ClipRequest<LayerT, StateT, ClipT, LayerBackendT> },

	getDebugSnapshot: (self: MotionNode<LayerT, StateT, ParamT, ClipT, LayerBackendT>) -> MotionDebugSnapshot,
}
```

The controller evaluates motions through the active layer. The backend receives
only the resulting requests.

## ClipNode

`AnimGraph.clip(clip, config?)` creates a one-clip motion node.

```luau
local idle = AnimGraph.clip("idle", {
	name = "Idle",
	looped = true,
	speed = 1,
})
```

Clip config can override:

- display/debug name;
- track key;
- weight;
- speed;
- looped;
- logical priority;
- Roblox priority;
- time position;
- normalized time.

Use explicit `trackKey` when the same clip identity may be played in multiple
independent ways and should not reuse one backend track slot.

## Blend1DNode

`AnimGraph.blend1D(parameter, config)` creates a one-axis blend tree.

```luau
local locomotion = AnimGraph.blend1D("speed", {
	name = "Locomotion",
	defaultValue = 0,
	samples = {
		{ threshold = 0, motion = AnimGraph.clip("idle") },
		{ threshold = 8, motion = AnimGraph.clip("walk") },
		{ threshold = 16, motion = AnimGraph.clip("run") },
	},
})
```

At evaluation time the node reads the named parameter, computes sample weights,
evaluates weighted child motions, and scales child request weights.

This is the right primitive for speed-based locomotion. Do not confuse the blend
parameter with layer playback speed:

- `controller:setFloat("speed", 8)` changes which locomotion samples are
  weighted.
- `controller:setLayerSpeed("base", 1.2)` changes playback rate.

## Blend2DNode

`AnimGraph.blend2D(parameterX, parameterY, config)` creates a two-axis blend tree.

```luau
local strafe = AnimGraph.blend2D("moveX", "moveY", {
	name = "Strafe",
	maxInfluences = 4,
	samples = {
		{ x = 0, y = 0, motion = AnimGraph.clip("idle") },
		{ x = 0, y = 1, motion = AnimGraph.clip("forward") },
		{ x = 0, y = -1, motion = AnimGraph.clip("back") },
		{ x = -1, y = 0, motion = AnimGraph.clip("left") },
		{ x = 1, y = 0, motion = AnimGraph.clip("right") },
	},
})
```

The current implementation computes nearest-sample style weighted influences and
limits participating samples with `maxInfluences`.

## Nesting

Motion nodes can be nested because every node returns the same request format.
For example:

```luau
local armedLocomotion = AnimGraph.blend1D("speed", {
	samples = {
		{ threshold = 0, motion = AnimGraph.clip("armedIdle") },
		{ threshold = 8, motion = AnimGraph.clip("armedWalk") },
	},
})

local baseStateMachine = AnimGraph.stateMachine({
	initialState = "locomotion",
	states = {
		{ id = "locomotion", motion = armedLocomotion },
		{ id = "jump", motion = AnimGraph.clip("jump") },
	},
})
```

Keep stateful nodes, especially state machines, per controller or per layer. A
plain clip node is effectively static authored data. A state machine has active
state and transition progress.

## ClipRequest Fields

Requests are the normalized output of all motions:

```luau
export type ClipRequest<LayerT, StateT, ClipT, LayerBackendT> = {
	trackKey: string,
	layer: LayerT,
	state: StateT?,
	clip: ClipT,
	weight: number,
	speed: number,
	timePosition: number?,
	normalizedTime: number?,
	looped: boolean,
	logicalPriority: number,
	layerBackend: LayerBackendT?,
	fadeTime: number,
	forceRestart: boolean,
}
```

If a future backend needs more data, prefer adding backend-neutral fields here
or a clearly optional metadata field rather than exposing backend objects to game
code.

## Custom Motion Nodes

A custom node should:

- implement the `MotionNode` interface;
- read parameters through `context.getParameter`;
- consume one-frame triggers through `context.consumeTrigger`;
- multiply by inherited layer/request weight instead of replacing it blindly;
- preserve or intentionally replace `context.layerBackend`;
- return stable track keys for clips that should persist;
- expose a useful `getDebugSnapshot`.

Custom nodes should not call Roblox `Animator` directly. They should return
requests and let the backend execute them.

# AnimGraph

AnimGraph is a Roblox Luau package for authored animation control. It sits above
Roblox `Animator`, keeps gameplay code away from raw `AnimationTrack` lifetime,
and exposes typed primitives for layers, parameters, motion nodes, state
machines, events, and backend-neutral clip requests.

The current backend uses Roblox `Animator`. The public API is intentionally
backend-shaped so a future Crunchyroll or custom pose-solver backend can be
added without changing gameplay-facing calls.

## Package Boundary

AnimGraph owns animation intent and playback orchestration:

- defining typed logical layers such as `"base"`, `"action"`, or `"upperBody"`;
- storing typed parameters and trigger parameters;
- evaluating motion nodes into clip requests;
- running authored state machines and transitions;
- dispatching controller events;
- passing evaluated requests into an injected animation backend;
- exposing debug snapshots for layers, parameters, motions, and backend tracks.

AnimGraph does not own character spawning, input, combat state, replication, socket
lookup, VFX lifetime, hitboxes, damage, inventory, ability routing, or rig
authoring. Those systems should call AnimGraph through a character or presentation
facade.

## Source Of Truth

The public package entrypoint is `src/init.luau`. It re-exports the package
constructors and public Luau types from `src/animGraph/types`.

- [Public entrypoint](https://github.com/emdomanus/animGraph/blob/main/src/init.luau)
- [Package implementation barrel](https://github.com/emdomanus/animGraph/blob/main/src/animGraph/init.luau)
- [Type barrel](https://github.com/emdomanus/animGraph/blob/main/src/animGraph/types/init.luau)
- [Architecture notes](/ARCHITECTURE)
- [Backend contract](/backends)

## Mental Model

```text
gameplay code
   |
   | set parameters, play layers, trigger actions
   v
AnimationController
   |
   | evaluate layers and motion nodes
   v
ClipRequest[]
   |
   | apply through injected backend
   v
Roblox Animator / future backend
```

The controller decides what should be playing. The backend decides how those
requests become runtime animation behavior.

## Minimal Flow

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimGraph = require(ReplicatedStorage.packages.animGraph)

type Layer = "base" | "action"
type State = "locomotion" | "empty" | "attack"
type Param = "speed" | "attack"
type Clip = "idle" | "walk" | "slash"
type LayerBackend = AnimGraph.RobloxLayerBackend

local backend = AnimGraph.robloxAnimatorBackend.new({
	animator = animator,
	resolveAssetId = function(clip: Clip): number
		return animationIds[clip]
	end,
})

local controller: AnimGraph.AnimationController<Layer, State, Param, Clip, LayerBackend> = AnimGraph.new({
	backend = backend,
	layers = {
		{
			id = "base",
			weight = 1,
			logicalPriority = 0,
			layerBackend = {
				robloxPriority = Enum.AnimationPriority.Movement,
			},
			defaultFadeIn = 0.15,
			defaultFadeOut = 0.15,
		},
		{
			id = "action",
			weight = 1,
			logicalPriority = 100,
			defaultFadeIn = 0.05,
			defaultFadeOut = 0.12,
		},
	},
})

controller:play("base", AnimGraph.blend1D("speed", {
	name = "Locomotion",
	samples = {
		{ threshold = 0, motion = AnimGraph.clip("idle") },
		{ threshold = 8, motion = AnimGraph.clip("walk") },
	},
}), {
	state = "locomotion",
	looped = true,
})

controller:setFloat("speed", 4)

local releaseUpdate = controller:bindToPreAnimation()
```

## Naming Semantics

`AnimGraph` is the package namespace and brand. `AnimationController` is the main
runtime object returned by `AnimGraph.new`.

Use this shape in consumers:

```luau
local AnimGraph = require(ReplicatedStorage.packages.animGraph)

local controller: AnimGraph.AnimationController<Layer, State, Param, Clip, LayerBackend> =
	AnimGraph.new(config)
```

Avoid renaming controller instances to `AnimGraph`. A controller is one live runtime
for one animator/backend pairing. The package namespace is the toolkit.

## Agent Notes

When modifying AnimGraph, preserve the boundary between generic controller logic and
backend execution. Gameplay code should talk to typed layers, parameters, clips,
and states. Backend code should be the only place that knows about Roblox
`AnimationTrack`, Crunchyroll pose binding, or any future solver-specific
objects.

Useful next reading:

- [Architecture](/ARCHITECTURE) for ownership and update flow.
- [Motions](/motions) for clip, 1D blend, and 2D blend behavior.
- [State Machines](/state-machines) for transition semantics.
- [Backends](/backends) for Roblox and future backend rules.
- [VoxelMMO Migration](/voxelmmo-migration) for adapting the older animator.

# Backends

Backends are the execution layer. The controller evaluates authored intent into
`ClipRequest` records, then the backend applies those requests to a concrete
runtime.

The current shipped backend is `RobloxAnimatorBackend`. A future Crunchyroll or
custom pose-solver backend should implement the same `AnimationBackend`
interface.

## Contract

Source:
[`src/animGraph/types/backends/animationBackend.luau`](https://github.com/emdomanus/animGraph/blob/main/src/animGraph/types/backends/animationBackend.luau)

```luau
export type AnimationBackend<LayerT, StateT, ClipT, LayerBackendT> = {
	apply: (
		self,
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

This is structural typing. A backend only needs to provide the methods; it does
not need to inherit from a base class.

## Controller Injection

Backends are manually constructed and passed into the controller:

```luau
local backend = AnimGraph.robloxAnimatorBackend.new({
	animator = animator,
	resolveAssetId = function(clip: Clip): number
		return animationIds[clip]
	end,
})

local controller = AnimGraph.new({
	backend = backend,
	layers = layers,
})
```

This keeps backend-specific setup outside the controller.

## Roblox Animator Backend

`RobloxAnimatorBackend` maps clip identities to Roblox asset ids through
`resolveAssetId`, loads `AnimationTrack`s through the provided `Animator`, and
applies each request by setting:

- `AnimationTrack.Priority`;
- `AnimationTrack.Looped`;
- `AnimationTrack:Play(fadeTime, weight, speed)` when a track starts;
- `AnimationTrack:AdjustWeight(weight, fadeTime)` while a track is live;
- `AnimationTrack:AdjustSpeed(speed)`;
- `AnimationTrack.TimePosition` when requested.

Roblox priority tiers still matter. Weights blend tracks that Roblox is willing
to solve together, but Roblox priority decides whether lower-priority joint
motion is suppressed by higher-priority tracks.

## Logical Priority Mapping

AnimGraph uses numeric logical priority. The Roblox backend maps it onto Roblox
priority tiers unless a request carries a `AnimGraph.RobloxLayerBackend` with an
explicit `robloxPriority`.

Default mapping:

```text
200+    -> Action4
100-199 -> Action3
50-99   -> Action2
10-49   -> Action
0-9     -> Movement
```

Override the bands when a game wants different semantics:

```luau
local backend = AnimGraph.robloxAnimatorBackend.new({
	animator = animator,
	resolveAssetId = resolveAssetId,
	priorityBands = {
		{ min = 300, priority = Enum.AnimationPriority.Action4 },
		{ min = 200, priority = Enum.AnimationPriority.Action3 },
		{ min = 100, priority = Enum.AnimationPriority.Action2 },
		{ min = 10, priority = Enum.AnimationPriority.Action },
		{ min = 0, priority = Enum.AnimationPriority.Movement },
	},
})
```

Override a single layer when Roblox's solver needs an explicit tier:

```luau
local layer: AnimGraph.LayerDefinition<Layer, AnimGraph.RobloxLayerBackend> = {
	id = "base",
	logicalPriority = 0,
	layerBackend = {
		robloxPriority = Enum.AnimationPriority.Movement,
	},
}
```

## Capabilities

Backends report capabilities for debugging and tooling:

```luau
export type BackendCapabilities = {
	unlimitedPriority: boolean,
	perJointFallback: "full" | "priorityTier" | "none",
	customMasks: boolean,
}
```

The Roblox backend is constrained by Roblox's solver. A future custom solver
could report stronger capabilities such as unlimited logical priority and custom
per-joint masks.

## Crunchyroll Or Custom Solver

A future custom backend should:

- implement `AnimationBackend`;
- accept the same `ClipRequest` records;
- resolve game clip identities into solver-specific animation assets;
- preserve the same debug snapshot shape;
- keep solver objects private to the backend;
- report capabilities honestly;
- degrade gracefully when a requested feature cannot be represented.

If Crunchyroll provides direct transform/pose control, it may eventually solve
limitations that Roblox priorities impose. It will likely cost more CPU than the
native Roblox animation path because more work moves into Luau/custom pose
application. Keep the Roblox backend as the default until a custom solver is
needed for concrete behavior.

## Backend Rules For Agents

When changing backend internals:

- do not expose `AnimationTrack` through controller APIs;
- do not make gameplay code know which backend is active;
- add debug warnings when backend constraints affect behavior;
- keep `ClipRequest` as the controller/backend boundary;
- prefer adding optional backend capabilities over adding special-case checks in
  gameplay code.

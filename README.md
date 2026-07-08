# animGraph

animGraph is a Roblox/pesde animation controller package built around typed
logical layers, motion nodes, and backend-neutral clip requests.

The current implementation provides the authored controller slice:

- typed `AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>`;
- logical layer playback with layer weight, speed, priority, and fade defaults;
- `ClipNode`, `Blend1DNode`, and `Blend2DNode` motion playback;
- authored state machines with trigger/parameter transition conditions;
- controller events for state enter/exit and transition start/end;
- controller parameters (`float`, `bool`, trigger, and raw values);
- a Roblox `Animator` backend that drives `AnimationTrack` weight, speed, and
  priority;
- debug snapshots for controller, layers, parameters, and backend tracks.

The public API intentionally talks in layers, states, parameters, clips, motion
nodes, and backends instead of raw Roblox `AnimationTrack`s. That keeps the API
usable with the current Roblox `Animator` backend while leaving room for a
future Crunchyroll/custom pose-solver backend.

## Install

```sh
pesde install
```

The package entrypoint is `src/init.luau`, which re-exports `src/animGraph`.

## Example

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimGraph = require(ReplicatedStorage.packages.animGraph)

type Layer = "base" | "action"
type State = "idle" | "attack"
type Param = "speed" | "attack"
type Clip = string
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

controller:play("action", AnimGraph.stateMachine({
	initialState = "empty",
	states = {
		{ id = "empty" },
		{ id = "attack", motion = AnimGraph.clip("slash_01") },
	},
	transitions = {
		{
			name = "attack",
			to = "attack",
			conditions = {
				{ parameter = "attack", op = "trigger" },
			},
		},
	},
}), { state = "empty" })

controller:setFloat("speed", 4)
controller:setTrigger("attack")

local releaseUpdate = controller:bindToPreAnimation()

-- later
releaseUpdate()
controller:destroy()
```

You can also drive updates manually:

```luau
controller:update(deltaTime)
```

## Concepts

- A layer is a caller-owned logical animation lane, such as `"base"`,
  `"upperBody"`, `"action"`, or a typed enum.
- A state is an authored/debug identity for the motion currently playing on a
  layer. Full transition/state-machine support will build on this.
- A clip is the caller's animation identity. It can be a string key, numeric
  asset id, enum value, or another stable key.
- A motion node evaluates to one or more clip requests. The package ships
  `ClipNode`, `Blend1DNode`, `Blend2DNode`, and `StateMachineRuntime`.
- A state machine owns authored states and transitions. Conditions can read
  normal parameters or consume trigger parameters.
- A backend receives clip requests and applies them to an animation runtime.
  The shipped backend uses Roblox `Animator` and `AnimationTrack`.
- Logical priorities are numeric and backend-neutral. The Roblox backend maps
  them onto Roblox's limited `Enum.AnimationPriority` tiers unless a request
  carries Roblox layer backend data with an explicit `robloxPriority`.
- `LayerBackendT` is the typed backend-specific data carried by a layer and its
  requests. Roblox uses `AnimGraph.RobloxLayerBackend`; custom backends can define
  their own layer extension type.

## Roblox Backend

The Roblox backend applies each evaluated clip request by setting:

- `AnimationTrack.Priority`;
- `AnimationTrack.Looped`;
- `AnimationTrack:AdjustWeight(weight, fadeTime)`;
- `AnimationTrack:AdjustSpeed(speed)`;
- `AnimationTrack.TimePosition` when requested.

It maps logical priority bands like this by default:

```text
200+    -> Action4
100-199 -> Action3
50-99   -> Action2
10-49   -> Action
0-9     -> Movement
```

Use explicit `layerBackend = { robloxPriority = ... }` on a layer or play
request when you need a specific Roblox priority tier.

## API

- `AnimGraph.new(config) -> AnimationController`
- `AnimGraph.clip(clip, config?) -> ClipNode`
- `AnimGraph.blend1D(parameter, config) -> Blend1DNode`
- `AnimGraph.blend2D(parameterX, parameterY, config) -> Blend2DNode`
- `AnimGraph.stateMachine(config) -> StateMachineRuntime`
- `AnimGraph.animationController.new(config)`
- `AnimGraph.clipNode.new(clip, config?)`
- `AnimGraph.blend1DNode.new(parameter, config)`
- `AnimGraph.blend2DNode.new(parameterX, parameterY, config)`
- `AnimGraph.stateMachineRuntime.new(config)`
- `AnimGraph.robloxAnimatorBackend.new(config)`
- `AnimGraph.stackModifier.new(config?)`

Controller methods:

- `controller:addLayer(definition)`
- `controller:hasLayer(layer)`
- `controller:play(layer, motionNode, options?)`
- `controller:stopLayer(layer, fadeTime?)`
- `controller:setLayerWeight(layer, weight)`
- `controller:getLayerWeight(layer) -> number?`
- `controller:setLayerSpeed(layer, speed)`
- `controller:getLayerSpeed(layer) -> number?`
- `controller:setLayerLogicalPriority(layer, logicalPriority)`
- `controller:getLayerLogicalPriority(layer) -> number?`
- `controller:setLayerBackend(layer, layerBackend?)`
- `controller:getLayerBackend(layer) -> layerBackend?`
- `controller:setParameter(parameter, value)`
- `controller:getParameter(parameter) -> value?`
- `controller:setFloat(parameter, value)`
- `controller:getFloat(parameter, fallback?) -> number`
- `controller:setBool(parameter, value)`
- `controller:getBool(parameter, fallback?) -> boolean`
- `controller:setTrigger(parameter)`
- `controller:consumeTrigger(parameter) -> boolean`
- `controller:on(eventName, callback) -> release`
- `controller:update(deltaTime)`
- `controller:bindToPreAnimation() -> release`
- `controller:getDebugSnapshot()`
- `controller:clear()`
- `controller:destroy()`

## Next Slices

The next implementation slices should be:

1. Roblox animation marker forwarding through the controller event bus.
2. Transition interruption policy and exit-time conditions.
3. Optional layer masks/per-joint blend metadata for a custom solver backend.
4. Optional Crunchyroll/custom pose-solver backend.
5. Focused tests around blend weights, transition conditions, and backend
   request application.

## Development

Run static and formatting checks when the local tools are available:

```sh
selene src
stylua --check src
rojo sourcemap default.project.json --output sourcemap.json
```

For Roblox-aware Luau analysis and Rojo require graph validation:

```powershell
.\scripts\check-luau.ps1
```

The script regenerates the dev sourcemap, downloads the Roblox `luau-lsp`
definitions into a temp cache when needed, runs `luau-lsp analyze`, and runs
`luau-lsp require-graph` against `src` and `dev`.

For the interactive dev harness:

```sh
rojo serve dev.project.json
```

Open a blank place, connect Rojo, and press Play. The harness mounts animGraph
under `ReplicatedStorage.packages`, creates an R6 dummy in `Workspace`, points the
camera at it, and provides UI buttons for layer playback, layer weights, action
priority mapping, authored state-machine triggers, blend parameters, and debug
snapshots. The control panel groups related controls into sections, keeps the
console collapsed by default, and includes scripted gameplay-like sequences for
testing chained locomotion/action operations.

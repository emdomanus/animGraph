# animGraph

animGraph is a Roblox/pesde animation controller package built around typed
logical layers, motion nodes, and backend-neutral clip requests.

Docs: https://emdomanus.github.io/animGraph/

The current implementation provides the authored controller slice:

- typed `AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>`;
- logical layer playback with layer weight, speed, priority, and fade defaults;
- `ClipNode`, `Blend1DNode`, and `Blend2DNode` motion playback;
- authored state machines with trigger/parameter transition conditions;
- controller events for state enter/exit, transition start/end, and backend-neutral track completion;
- controller parameters (`float`, `bool`, trigger, and raw values);
- coherent once-per-update sampling with controller, layer, and active-play logical readers;
- validated one-shot initial positions in seconds or normalized form;
- a Roblox `Animator` backend that drives `AnimationTrack` weight, speed, and
  priority without redundant unchanged operations;
- live backend-neutral track positioning by `trackKey`;
- generation-safe fade retirement, physical cleanup, and completed tombstones;
- debug snapshots for controller, layers, parameters, and active, retiring, or completed backend tracks.

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
local RunService = game:GetService("RunService")

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
	timeSource = os.clock,
	logicalTimeReader = function(frameNow: number): number
		return frameNow
	end,
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

local releaseCompletion = controller:on("trackCompleted", function(event)
	if event.name ~= "trackCompleted" then
		return
	end

	print("completed", event.trackKey, event.layer, event.state)
end)

local updateConnection = RunService.PreAnimation:Connect(function()
	controller:update()
end)

-- later
updateConnection:Disconnect()
releaseCompletion()
controller:destroy()
```

You can also drive updates from another caller-owned deterministic cadence:

```luau
controller:update()
```

## Concepts

- A layer is a caller-owned logical animation lane, such as `"base"`,
  `"upperBody"`, `"action"`, or a typed enum.
- A state is an authored/debug identity used by the package's authored
  state-machine and transition runtime.
- A clip is the caller's animation identity. It can be a string key, numeric
  asset id, enum value, or another stable key.
- A motion node evaluates to one or more clip requests. The package ships
  `ClipNode`, `Blend1DNode`, `Blend2DNode`, and `StateMachineRuntime`.
- A state machine owns authored states and transitions. Conditions can read
  normal parameters or consume trigger parameters.
- A backend receives clip requests and applies them to an animation runtime.
  The shipped backend uses Roblox `Animator` and `AnimationTrack`.
- `trackKey` is the backend-neutral identity used for live positioning and
  completion; AnimGraph does not expose a playback handle or raw Roblox track.
- Each update samples one finite `TimeSource` coordinate and each distinct
  selected `LogicalTimeReader` at most once. Play readers replace layer readers,
  which replace the controller default.
- Reader-derived logical delta and request speed remain independent inputs.
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
- `AnimationTrack:AdjustWeight(weight, fadeTime)` only when the effective target changes;
- `AnimationTrack:AdjustSpeed(speed)` only when the effective speed changes;
- `AnimationTrack.TimePosition` once per materialized generation when an
  `initialPosition` resolves against a positive length.

Repeated application of the same live request does not replay, reposition, or
restart an unchanged fade. `setTrackPosition` addresses the same live generation
forward or backward and permanently supersedes a pending initial position.
Non-looping terminal initial/live positions are clamped and complete once;
looping seconds wrap by length and normalized `1` canonicalizes to zero.

Natural and accepted terminal completion is forwarded as `trackCompleted` only
after state commit. Explicit stop, disappearance, replacement, restart, clear,
and destroy suppress completion. Non-zero retirement fades keep old physical
generations until `Ended`; completed tombstones retain no raw Roblox objects and
prevent unchanged desired requests from replaying.

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
- `controller:setTrackPosition(trackKey, position) -> boolean`
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
- `controller:update()`
- `controller:getDebugSnapshot()`
- `controller:clear()`
- `controller:destroy()`

## Next Slices

Further design history and consumer integration are tracked in the checkpointed
[temporal amendment](docs/todo/temporalAmendment.md) and
[backlog](docs/todo/backlog.md). CP-TA3 is operator-reviewed and complete;
package publishing, version decisions, and VoxelMMO migration remain separate
work.

## Development

Run the deterministic, formatting, lint, Luau-analysis, and documentation
checks from the repository root. The complete gate inventory and the 51-test
baseline are in the [verification guide](docs/guides/verification.md):

```sh
lune run tests/lune/run.luau
stylua --check src dev tests
selene src dev tests
npm run docs:build
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
testing chained locomotion/action operations. Its Temporal Lifecycle section
adds independent held/advancing readers, live forward/back positioning, exact
terminal and natural completion, looping, same-key replacement, reappearance
during fade, and cleanup visibility.

# animGraph

animGraph is a typed Roblox/Luau animation graph with explicit-time evaluation,
authored layers and motions, and backend-owned physical playback.

Docs: https://emdomanus.github.io/animGraph/

The package provides:

- `AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>`;
- controller, layer, and active-play `LogicalTimeReader` scopes;
- monotonic logical graph phase through source/revision rebasing;
- queued next-update graph intent and same-coordinate re-evaluation;
- clip, Blend1D, Blend2D, and authored state-machine motion nodes;
- backend-neutral requests, absolute/relative physical positioning, completion,
  and debug contracts;
- a Roblox backend with fixed `nativeRate` and `sampledPosition` strategies;
- generation-safe fade retirement, cleanup, and completion tombstones.

The caller owns scheduling and passes a finite monotonic coordinate to every
update. animGraph owns no clock or RunService connection.

## Install

```sh
pesde install
```

The package entry point is `src/init.luau`.

## Example

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimGraph = require(ReplicatedStorage.packages.animGraph)

type Layer = "base" | "action"
type State = "locomotion" | "empty" | "attack"
type Param = "speed" | "attack"
type Clip = "idle" | "walk" | "slash"
type LayerBackend = AnimGraph.RobloxLayerBackend

local backend = AnimGraph.robloxAnimatorBackend.new({
	animator = animator,
	positionMode = "nativeRate",
	resolveAssetId = function(clip: Clip): number
		return animationIds[clip]
	end,
})

local worldReader: AnimGraph.LogicalTimeReader = function(sampleTime: number): AnimGraph.LogicalTimeSample
	return {
		position = sampleTime,
		addressRevision = 0,
	}
end

local controller: AnimGraph.AnimationController<Layer, State, Param, Clip, LayerBackend> = AnimGraph.new({
	backend = backend,
	logicalTimeReader = worldReader,
	layers = {
		{ id = "base", logicalPriority = 0 },
		{ id = "action", logicalPriority = 100 },
	},
})

controller:play("base", AnimGraph.blend1D("speed", {
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
		{ id = "attack", motion = AnimGraph.clip("slash") },
	},
	transitions = {
		{
			from = "empty",
			to = "attack",
			conditions = {
				{ parameter = "attack", op = "trigger" },
			},
		},
	},
}))

controller:setFloat("speed", 4)
controller:setTrigger("attack")

local updateConnection = RunService.PreAnimation:Connect(function()
	controller:update(os.clock())
end)

-- later
updateConnection:Disconnect()
controller:destroy()
```

`play` and parameter writes take effect at the next valid update.

## Time model

```luau
export type LogicalTimeSample = {
	position: number,
	addressRevision: number,
}

export type LogicalTimeReader = (sampleTime: number) -> LogicalTimeSample
```

Reader precedence is controller default, then layer override, then active-play
override. Each distinct selected reader is sampled once per update.

A new play begins logical graph phase at zero. Forward source movement with an
unchanged revision advances phase by the exact difference. Stationary/backward
movement, a reader change, or a revision change holds phase and rebases the
source baseline. `addressRevision` is for discontinuous re-addressing, not
ordinary continuous rate changes.

`controller:update(sampleTime)` accepts finite nondecreasing coordinates. Equal
coordinates are legal; they allow newly queued commands to re-evaluate without
advancing transitions. Backward coordinates and invalid reader samples reject
the complete update before package mutation.

State-machine transitions store a logical start-position anchor and derive
progress from the current absolute phase. Motion requests contain no graph
`dt`.

## Graph intent and physical commands

Play, stop, parameters/triggers, layer weight/speed/priority/backend data, and
logical-reader changes are queued for the next valid update. Getters expose
committed state.

These remain synchronous:

- `setTrackPosition(trackKey, AnimationPosition) -> boolean`;
- `offsetTrackPosition(trackKey, deltaSeconds) -> boolean`;
- `clear()` and `destroy()` lifecycle boundaries.

The positioning boolean means the current active physical generation accepted
the command. Physical positioning never rewinds logical state-machine phase.

## Backend position modes

```luau
export type BackendPositionMode = "nativeRate" | "sampledPosition"
```

The mode is selected once when constructing a backend and is exposed through
its capabilities. It is not a layer, motion, or authored-content option.

- `nativeRate` lets Roblox advance physical playback through `Play` and
  `AdjustSpeed`. Unchanged requests do not seek or churn native properties.
- `sampledPosition` runs tracks at native speed zero and evaluates physical
  phase from `positionAnchor + speed * (sampleTime - sampleTimeAnchor)` on each
  apply. Speed/loop changes rebase before adopting the new values.

Both modes receive `backend:apply(sampleTime, requests)` and share generation,
fade, priority, positioning, completion, tombstone, and teardown behavior.

Logical graph phase and physical clip phase are separate. Signed physical speed
does not scale or reverse state-machine progress.

## Physical position and completion

`AnimationPosition` is either finite non-negative seconds or normalized
`[0, 1]`. Non-looping addresses clamp; looping addresses wrap. A non-looping
boundary completes only when desired signed speed points outward: positive at
the upper boundary or negative at the lower boundary. Zero/inward speed remains
active.

Unknown Roblox length delays physical writes. Position and ordered offsets stay
generation-local and resolve once length becomes positive. In sampled mode,
anchor-relative phase continues to accrue while length is unresolved.

The Roblox backend owns active, retiring, and completed generations. Completed
tombstones prevent unchanged desired requests from replaying. Explicit stop,
omission, replacement retirement, clear, and destroy do not emit natural
completion.

`sampledPosition` makes coordinate-to-position evaluation deterministic, but
Roblox still owns asset loading, weight fades, pose application, markers, and
root motion. Verify those behaviors in Studio before choosing sampled playback
for dependent content.

## Main API

Constructors:

- `AnimGraph.new(config)`
- `AnimGraph.clip(clip, config?)`
- `AnimGraph.blend1D(parameter, config)`
- `AnimGraph.blend2D(parameterX, parameterY, config)`
- `AnimGraph.stateMachine(config)`
- `AnimGraph.robloxAnimatorBackend.new(config)`
- `AnimGraph.stackModifier.new(config?)`

Controller operations:

- layers: `addLayer`, `hasLayer`, `play`, `stopLayer`;
- composition: layer weight/speed/logical-priority/backend setters and getters;
- readers: `setDefaultLogicalTimeReader`, `setLayerLogicalTimeReader`,
  `setActivePlayLogicalTimeReader`;
- parameters: raw, float, bool, trigger accessors;
- physical position: `setTrackPosition`, `offsetTrackPosition`;
- lifecycle/events: `on`, `update(sampleTime)`, `getDebugSnapshot`, `clear`,
  `destroy`.

See the [API reference](docs/api/index.md),
[architecture](docs/architecture.md), and
[absolute-time amendment](docs/todo/temporalAmendment.md).

## Development

```sh
lune run tests/lune/run.luau
stylua --check src dev tests
selene src dev tests
npm run docs:build
```

For Roblox-aware analysis and the require graph:

```powershell
.\scripts\check-luau.ps1
```

Run `rojo serve dev.project.json` for the Studio harness. Change its typed
`BACKEND_POSITION_MODE` constant to exercise either backend strategy. The
[Studio checklist](docs/guides/studio-verification.md) records the remaining
engine-only sampled-position gate.

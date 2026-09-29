# animGraph

animGraph is a typed Roblox/Luau animation graph with explicit-time evaluation,
authored layers and motions, and backend-owned physical playback.

Docs: https://emdomanus.github.io/animGraph/

The package provides:

- `AnimationController<LayerT, StateT, ParamT, ClipT, LayerBackendT>`;
- controller, layer, and active-play `TimeReader` scopes;
- literal time-basis position and rate sampling;
- queued next-update graph intent and same-coordinate re-evaluation;
- clip, Blend1D, Blend2D, and authored state-machine motion nodes;
- backend-neutral requests, absolute/relative physical positioning, completion,
  and debug contracts;
- a Roblox backend with fixed `nativeRate` and `sampledPosition` strategies;
- generation-safe fade retirement, cleanup, and completion tombstones.

The caller owns scheduling and passes a finite nondecreasing coordinate to every
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

local worldReader: AnimGraph.TimeReader = function(sampleTime: number): AnimGraph.TimeSample
	return {
		position = sampleTime,
		rate = 1,
	}
end

type Controller = AnimGraph.AnimationController<Layer, State, Param, Clip, LayerBackend>
type Config = AnimGraph.AnimationControllerConfig<Layer, State, Clip, LayerBackend>
local newController = AnimGraph.new :: (Config) -> Controller
local controller = newController({
	backend = backend,
	timeReader = worldReader,
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
export type TimeSample = {
	position: number,
	rate: number,
}

export type TimeReader = (sampleTime: number) -> TimeSample
```

Reader precedence is controller default, then layer override, then active-play
override. Each distinct selected reader is sampled once per update.

`position` is used literally for graph, transition, custom-motion, and sampled
physical evaluation. `rate` is supplied atomically with it and composes native
physical speed. AnimGraph does not derive rate, classify discontinuities, or
make reader changes continuous. A caller that needs continuity must provide an
already-mapped reader.

`controller:update(sampleTime)` accepts finite nondecreasing coordinates. Equal
coordinates are legal; they allow newly queued commands to re-evaluate without
advancing transitions. Backward controller coordinates and invalid reader
samples reject the complete update before package mutation.

State-machine transitions store a time-position anchor and derive progress from
the current sample. Backward time positions hold an active transition's
progress rather than traversing state backward. Motion requests contain no
graph `dt`.

## Graph intent and physical commands

Play, stop, parameters/triggers, layer weight/speed/priority/backend data, and
time-reader changes are queued for the next valid update. Getters expose
committed state.

These remain synchronous:

- `setTrackPosition(trackKey, AnimationPosition) -> boolean`;
- `offsetTrackPosition(trackKey, deltaSeconds) -> boolean`;
- `clear()` and `destroy()` lifecycle boundaries.

The positioning boolean means the current active physical generation accepted
the command. Physical positioning never rewinds state-machine progression.

## Backend position modes

```luau
export type BackendPositionMode = "nativeRate" | "sampledPosition"
```

The mode is selected once when constructing a backend and is exposed through
its capabilities. It is not a layer, motion, or authored-content option.

- `nativeRate` lets Roblox advance physical playback through `Play` and
  `AdjustSpeed` at `request.speed * request.timeRate`. Unchanged effective
  speed does not seek or churn native properties.
- `sampledPosition` runs tracks at native speed zero and evaluates physical
  phase from `physicalAnchor + request.speed * (request.timePosition -
  timeAnchor)` on each apply. Speed/loop changes rebase before adopting the new
  values.

Both modes receive `backend:apply(sampleTime, requests)` and share generation,
fade, priority, positioning, completion, tombstone, and teardown behavior.

Graph time position and physical clip phase are separate. Signed physical speed
does not scale or reverse state-machine progress. A time-position jump is
literal in sampled mode; in native mode the caller must issue
`setTrackPosition` or `offsetTrackPosition` when the physical generation must
be re-addressed.

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

`sampledPosition` makes time-position-to-physical-position evaluation
deterministic, but Roblox still owns asset loading, weight fades, pose
application, markers, and root motion. Verify those behaviors in Studio before
choosing sampled playback for dependent content.

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
- readers: `setDefaultTimeReader`, `setLayerTimeReader`,
  `setActivePlayTimeReader`;
- parameters: raw, float, bool, trigger accessors;
- physical position: `setTrackPosition`, `offsetTrackPosition`;
- lifecycle/events: `on`, `update(sampleTime)`, `getDebugSnapshot`, `clear`,
  `destroy`.

See the [API reference](docs/api/index.md),
[architecture](docs/architecture.md), and
[absolute-time amendment](docs/todo/temporalAmendment.md).

## Development

```sh
pwsh -NoProfile -File scripts/verify/tests.ps1
pwsh -NoProfile -File scripts/verify/stylua.ps1
pwsh -NoProfile -File scripts/verify/selene.ps1
npm run docs:build
```

Install pinned tools with `rokit install` and fetch definitions once with
`scripts/luau-lsp/fetch-roblox-types.ps1`. For Roblox-aware source/demo analysis
and accepted public contracts:

```powershell
.\scripts\check-luau.ps1
```

Run `rojo serve dev.project.json` for the Studio harness. Change its typed
`BACKEND_POSITION_MODE` constant to exercise either backend strategy. The
[Studio checklist](docs/guides/studio-verification.md) records the remaining
engine-only sampled-position gate.

The analyzer uses pinned Luau-LSP 1.70.1 and solver V2, retaining executable identity,
definitions hash, arguments, and raw diagnostics under ignored `.verification/`.
`LUAU_LSP_OVERRIDE` accepts an absolute executable of that pinned version; it does
not replace Rokit shims. Editor solver settings match the command line.

Run `scripts/verify/type-errors.ps1 -OutDir .verification/rejected-fresh` for rejected
public contracts and `scripts/verify/tooling-tests.ps1` for capture/override fixtures.
Public method fields are read-only; state-changing methods still work normally.
Dynamic Roblox doubles are exercised by the 87-case Lune suite rather than treated
as public type contracts. `scripts/verify/test-harness.ps1` verifies cleanup after
success/failure, abandoned run recovery, and concurrent isolation. Generated modules
belong to a unique `.animgraph-tests/<token>/runtime` directory; use the guarded
runner instead of calling Lune directly. `-KeepRuntime` explicitly retains a run.
